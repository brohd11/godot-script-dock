extends MarginContainer

const PLUGIN_EXPORTED = false

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const VarInsertType = UtilsRemote.VarInsertType
const SettingHelperEditor = UtilsRemote.SettingHelperEditor
const GDScriptParser = EditorGDScriptParser.GDScriptParser

const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const ParserKeys = GDScriptParser.Keys

const UString = UtilsRemote.UString
const Pr = UString.PrintRich

const PathBar = UtilsRemote.PathBar

const EditorColors = UtilsRemote.EditorColors
const TagParser = UtilsRemote.TagParser
const UClassDetail = UtilsRemote.UClassDetail

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const QUEUE_PER_FRAME = 5

const _ED_ICONS = &"EditorIcons"


enum SortMode {
	NONE,
	ALPHA,
	METHOD_TYPE,
	METHOD_TYPE_ALPHA,
}

var editor_setting_helper:SettingHelperEditor
var _dock_data:Dictionary

var right_click_handler:RightClickHandler

var _debounce_timer:Timer

var _vbox:VBoxContainer
var header_button:Button
var toolbar:HBoxContainer
var filter_line_edit:LineEdit
var _bread_crumb_tabs:PathBar

var outline_tree:OutlineTree
var _tree_script_item_data:= {}

var _editor_script_changed_flag:=true
var _current_script_path:String
var _current_script_file_mod_time:int=-1

var _caret_changed_debounce:bool=false
var _last_caret_line:int = -1
var _follow_cursor:bool = false

signal header_button_pressed

func get_dock_data() -> Dictionary:
	var data = {}
	data[OutlineKeys.DOCK_OUTLINE_VIS] = outline_tree.visible
	return data

func set_dock_data(data:Dictionary) -> void:
	_dock_data = data
	var outline_vis = _dock_data.get(OutlineKeys.DOCK_OUTLINE_VIS, true)
	if not outline_vis: # emit the signal because the sidebar needs to set it's settings
		header_button_pressed.emit()

func _ready() -> void:
	print("READY IN OUTLINE")
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_file_system_changed, 1)
	
	#ScriptEditorRef.subscribe(ScriptEditorRef.Event.EDITOR_SCRIPT_CHANGED, _on_editor_script_changed)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_editor_text_changed)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.CARET_CHANGED, _on_caret_changed)
	
	var editor_parser = EditorGDScriptParser.get_instance()
	editor_parser.editor_script_changed.connect(_on_editor_script_changed, 1)
	editor_parser.parse_completed.connect(_on_parse_completed, 1)
	
	# build nodes
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	_vbox = VBoxContainer.new()
	add_child(_vbox)
	
	header_button = Button.new()
	header_button.text = "Outline"
	header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_button.theme_type_variation = &"FlatButton"
	header_button.pressed.connect(func():header_button_pressed.emit())
	header_button.icon = EditorInterface.get_editor_theme().get_icon(&"GuiTreeArrowDown", &"EditorIcons")
	_vbox.add_child(header_button)
	
	header_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var existing = header_button.get_theme_stylebox("normal")
	var sb = EditorInterface.get_editor_theme().get_stylebox("normal", "Button").duplicate() as StyleBoxFlat
	sb.content_margin_bottom = existing.content_margin_bottom
	sb.content_margin_left = existing.content_margin_left
	sb.content_margin_right = existing.content_margin_right
	sb.content_margin_top = existing.content_margin_top
	sb.bg_color = EditorColors.get_theme_color(EditorColors.ThemeColor.DARK_1)
	
	sb.border_color = sb.bg_color.lightened(0.15)
	header_button.add_theme_stylebox_override("normal", sb)
	
	
	_bread_crumb_tabs = PathBar.new()
	_vbox.add_child(_bread_crumb_tabs)
	_bread_crumb_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bread_crumb_tabs.custom_minimum_size.y = 24 * EditorInterface.get_editor_scale()
	_bread_crumb_tabs.section_pressed.connect(_on_breadcrumb_selected)
	_bread_crumb_tabs.show_arrows = true
	
	toolbar = HBoxContainer.new()
	_vbox.add_child(toolbar)
	
	filter_line_edit = LineEdit.new()
	toolbar.add_child(filter_line_edit)
	filter_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_line_edit.placeholder_text = "Filter Members"
	filter_line_edit.right_icon = EditorInterface.get_editor_theme().get_icon(&"Search", _ED_ICONS)
	filter_line_edit.clear_button_enabled = true
	filter_line_edit.text_changed.connect(_on_filter_text_changed)
	
	
	outline_tree = OutlineTree.new()
	_vbox.add_child(outline_tree)
	outline_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline_tree.hide_root = true
	outline_tree.selected_changed.connect(_on_tree_selected_changed)
	outline_tree.tree_built.connect(_on_tree_built)
	outline_tree.infer_queue_finished.connect(_on_infer_queue_finished, 1)
	
	outline_tree.right_click_handler = right_click_handler # this may need to be deferred?
	
	editor_setting_helper = SettingHelperEditor.new()
	editor_setting_helper.subscribe_property(self, &"_follow_cursor", EditorSet.FOLLOW_CURSOR, false)
	editor_setting_helper.initialize()
	
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = 2 # 2 may be a bit long
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)
	
	var current_parser = EditorGDScriptParser.get_parser()
	if is_instance_valid(current_parser):
		_on_editor_script_changed(current_parser.get_current_script())
		_build_tree()


func clean_up():
	pass

func get_margins():
	return [self]

func toggle_outline():
	var new_state = not outline_tree.visible
	_toggle_outline(new_state)
	return new_state

func _toggle_outline(state:bool):
	for cont in [toolbar, _bread_crumb_tabs, outline_tree]:
		cont.visible = state
	
	if state:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		header_button.icon = EditorInterface.get_editor_theme().get_icon(&"GuiTreeArrowDown", &"EditorIcons")
		_set_cache_dirty()
		_build_tree()
	else:
		size_flags_vertical = Control.SIZE_SHRINK_END
		header_button.icon = EditorInterface.get_editor_theme().get_icon(&"GuiTreeArrowRight", &"EditorIcons")


func get_options():
	var options = Options.new()
	options.add_enum_radio("Sort", _set_sort_mode, SortMode, outline_tree.sort_mode, ["Sort", null])
	return options


func _set_sort_mode(mode:SortMode):
	var rebuild = outline_tree.sort_mode != mode
	outline_tree.sort_mode = mode
	if rebuild:
		_set_cache_dirty()
		_build_tree()

func _on_editor_text_changed():
	_set_cache_dirty()

func _set_cache_dirty():
	outline_tree.cache_dirty = true
	_debounce_timer.stop()


func _on_editor_script_changed(script:GDScript):
	outline_tree.right_click_handler = right_click_handler # TEMP
	
	if not is_instance_valid(script):
		outline_tree.clear()
		_current_script_path = ""
		outline_tree.current_script_item_data = {}
		return
	
	_editor_script_changed_flag = true
	_set_cache_dirty()
	_current_script_path = script.resource_path
	if _current_script_path == "" or not _current_script_path.ends_with(".gd"):
		outline_tree.clear()
		return
	
	var current_script_data = _tree_script_item_data.get_or_add(_current_script_path, {})
	outline_tree.current_script_item_data = current_script_data
	_build_tree.call_deferred() # maybe set a flag? if deferred doesn't work


func _on_file_system_changed():
	if not FileAccess.file_exists(_current_script_path):
		return
	var current_mod_time = FileAccess.get_modified_time(_current_script_path)
	if current_mod_time != _current_script_file_mod_time:
		_current_script_file_mod_time = current_mod_time
		EditorGDScriptParser.queue_parse(true)
		_set_cache_dirty() # set cache to dirty so it will rebuild tree


func _on_parse_completed():
	#print("PARSE HAPPENED")
	if _editor_script_changed_flag:
		_editor_script_changed_flag = false
		_debounce_timer.stop()
		_build_tree()
	else:
		_debounce_timer.start()

func _on_debounce_timeout():
	_build_tree()

func _build_tree():
	if _current_script_path == "" or not _current_script_path.ends_with(".gd"):
		outline_tree.clear()
		_set_cache_dirty()
		return
	outline_tree.build_tree.call_deferred()


func _on_tree_selected_changed(clicked:bool):
	if clicked:
		_caret_changed_debounce = true
	_build_breadcrumb.call_deferred()

func _on_caret_changed():
	var caret_line = ScriptEditorRef.get_current_code_edit().get_caret_line()
	var new_line = caret_line != _last_caret_line
	_last_caret_line = caret_line
	
	if _caret_changed_debounce: # set when moving the caret in outline tree from a click
		_caret_changed_debounce = false
		return
	
	if outline_tree.is_filtering:
		return
	
	if new_line:
		if outline_tree.cache_dirty:
			# this will basically fire every time you new line, ideally this wouldn't...
			EditorGDScriptParser.queue_parse()
		_set_current_access_path.call_deferred()


func _on_tree_built():
	_set_current_access_path(true)

func _on_infer_queue_finished():
	_build_breadcrumb()



func _build_breadcrumb(current_access_path:String="null"):
	if current_access_path == "null":
		current_access_path = MemberData.get_current_access_path()
	
	var editor_theme:Theme = EditorInterface.get_editor_theme()
	
	var full_breadcrumb = _get_selected_breadcrumb(true)
	var keep_tabs =  full_breadcrumb.begins_with(current_access_path)
	#print("KEEP::", keep_tabs, "::CURR::", current_access_path, "::BREAD::", full_breadcrumb)
	if current_access_path == "null":
		return
	
	if keep_tabs:
		for i in range(_bread_crumb_tabs.get_section_count()):
			var ap = _bread_crumb_tabs.get_section_metadata(i)
			if ap == current_access_path:
				_bread_crumb_tabs.select_section(i)
				break
	else:
		_bread_crumb_tabs.clear()
		_bread_crumb_tabs.add_section(MemberData.get_main_script_name(), editor_theme.get_icon("Script", _ED_ICONS))
		_bread_crumb_tabs.set_section_metadata(0, "")
		var working_path = ""
		for part in UString.split_member_access(current_access_path):
			working_path = UString.dot_join(working_path, part)
			var icon_name = &"Object"
			var item = outline_tree.get_item_from_access_path(working_path)
			if is_instance_valid(item):
				var meta = item.get_metadata(0)
				var item_type = meta.get(OutlineKeys.ITEM_TYPE)
				if item_type == OutlineKeys.ITEM_TYPE_CLASS:
					pass
				elif item_type == OutlineKeys.ITEM_TYPE_CONST:
					icon_name = &"MemberConstant"
				elif item_type == OutlineKeys.ITEM_TYPE_FUNC:
					icon_name = &"MemberMethod"
				elif item_type == OutlineKeys.ITEM_TYPE_MEMBER:
					icon_name = &"MemberProperty"
				elif item_type == OutlineKeys.ITEM_TYPE_ARG or item_type == OutlineKeys.ITEM_TYPE_LOCAL_VAR:
					icon_name = &"LocalVariable"
			
			_bread_crumb_tabs.add_section(part, editor_theme.get_icon(icon_name, _ED_ICONS))
			_bread_crumb_tabs.set_section_metadata(_bread_crumb_tabs.get_section_count() - 1, working_path)
		
		_bread_crumb_tabs.select_section(_bread_crumb_tabs.get_section_count() - 1)

func _on_breadcrumb_selected(sel:int) -> void:
	var access_path = _bread_crumb_tabs.get_section_metadata(sel)
	if access_path == null:
		return
	outline_tree.select_path(access_path, {
		"scroll_tree": true,
		"set_caret": true,
	})

func _get_selected_breadcrumb(longest:bool=false) -> String:
	if _bread_crumb_tabs.get_section_count() == 0:
		return "null"
	var idx = _bread_crumb_tabs.get_selected() if not longest else _bread_crumb_tabs.get_section_count() - 1
	var selected = _bread_crumb_tabs.get_section_metadata(idx)
	if selected == null:
		selected = "null"
	return selected

func _set_current_access_path(build:=false):
	var selected = _get_selected_breadcrumb()
	var current_access_path = MemberData.get_current_access_path()
	if build:
		_build_breadcrumb(current_access_path)
	if current_access_path == "null" or selected == current_access_path:
		return
	if _follow_cursor:
		outline_tree.select_path(current_access_path, {
			"scroll_tree": true
		})



func _on_filter_text_changed(new_text:String):
	var selected_path = outline_tree.get_selected_path()
	outline_tree.current_filter_text = new_text.strip_edges()
	outline_tree.filter_items()
	if not outline_tree.is_filtering:
		outline_tree.select_path(selected_path, {
			"scroll_tree":true,
			"center_tree": true
		})


class OutlineTree extends Tree:
	var right_click_handler:RightClickHandler
	
	var cache_dirty:bool = true
	var current_script_item_data:= {}
	var _item_dict:= {}
	
	var last_filter_text:String = ""
	var current_filter_text:String = ""
	var is_filtering:bool = false
	
	var sort_mode:SortMode = SortMode.NONE
	
	var _editor_theme:Theme
	var _infer_queue:= []
	var _infer_queue_processing:=false
	
	signal selected_changed(clicked:bool)
	signal tree_built
	signal infer_queue_finished
	
	func _ready() -> void:
		item_mouse_selected.connect(_on_item_mouse_selected)
		item_collapsed.connect(_on_item_collapsed)
		button_clicked.connect(_on_item_button_pressed)
		allow_rmb_select = true
	
	
	func build_tree():
		if not visible:
			return
		if not cache_dirty:
			return
		
		_editor_theme = EditorInterface.get_editor_theme()
		MemberData.set_colors()
		
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("BUILD OUTLINE")
		
		var selected_path = get_selected_path()
		
		_clear_infer_queue()
		clear()
		
		# pseudo settings
		var display_line_numbers = false
		#
		
		var class_items = {}
		var _root = create_item()
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var classes = gdscript_parser.get_classes()
		if classes.is_empty():
			return
		for access_path in classes:
			var class_obj = gdscript_parser.get_class_object(access_path) as ParserClass
			var class_base_type = class_obj.script_base_type
			
			var item_parent:TreeItem
			item_parent = class_items.get(access_path)
			if not is_instance_valid(item_parent):
				var last_access = ""
				if access_path.contains("."):
					last_access = UString.trim_member_access_back(access_path)
				var last_access_item = null
				if last_access != "":
					last_access_item = class_items.get(last_access)
				
				var full_access_path = UString.dot_join(last_access, access_path)
				item_parent = create_item(last_access_item)
				var _c_name = MemberData.get_main_script_name() if access_path == "" else UString.get_member_access_back(access_path)
				item_parent.set_text(0, _c_name)
				var meta = {
					ParserKeys.ACCESS_PATH: full_access_path,
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_CLASS,
					}
				item_parent.set_metadata(0, meta)
				
				var icon_name = class_base_type
				if not _editor_theme.has_icon(icon_name, _ED_ICONS): # icon_name == "RefCounted" or not editor_theme.has_icon(icon_name, _ED_ICONS):
					icon_name = "Object"
				item_parent.set_icon(0, _editor_theme.get_icon(icon_name, _ED_ICONS))
				
				_set_collapsed(item_parent, access_path != "")
				class_items[access_path] = item_parent
			
			var prop_parent:TreeItem = item_parent
			var const_parent:TreeItem = item_parent
			var func_parent:TreeItem = item_parent
			if true: # add a flag for categories?
				const_parent = create_item(item_parent)
				const_parent.set_text(0, "Constants")
				const_parent.set_icon(0, _editor_theme.get_icon(&"MemberConstant", _ED_ICONS))
				const_parent.set_metadata(0, { # should these have different paths? to keep collapse state
					ParserKeys.ACCESS_PATH: UString.dot_join(access_path, "-consts"),
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_CATEGORY
					})
				_set_collapsed(const_parent)
				
				prop_parent = create_item(item_parent)
				prop_parent.set_text(0, "Properties")
				prop_parent.set_icon(0, _editor_theme.get_icon(&"MemberProperty", _ED_ICONS))
				prop_parent.set_metadata(0, {
					ParserKeys.ACCESS_PATH: UString.dot_join(access_path, "-props"),
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_CATEGORY
					})
				_set_collapsed(prop_parent)
				
				func_parent = create_item(item_parent)
				func_parent.set_text(0, "Methods")
				func_parent.set_icon(0, _editor_theme.get_icon(&"MemberMethod", _ED_ICONS))
				func_parent.set_metadata(0, {
					ParserKeys.ACCESS_PATH: UString.dot_join(access_path, "-funcs"), 
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_CATEGORY
					})
				_set_collapsed(func_parent)
			
			
			var const_names:Array = class_obj.constants.keys()
			if sort_mode == SortMode.ALPHA or sort_mode == SortMode.METHOD_TYPE_ALPHA:
				const_names.sort_custom(sort_alphabetic)
			else:
				const_names.sort_custom(sort_by_line_index.bind(class_obj.constants))
			for c in const_names:
				var member_data:Dictionary = class_obj.constants.get(c)
				if not member_data.get(ParserKeys.ACCESS_PATH).begins_with(access_path):
					continue
				var line_index = member_data.get(ParserKeys.LINE_INDEX)
				var full_access_path = UString.dot_join(access_path, c)
				var item:TreeItem = create_item(const_parent)
				class_items[full_access_path] = item
				var suffix:String = ""
				if display_line_numbers:
					suffix += MemberData.ITEM_LINE_STR % line_index
				if not suffix.is_empty():
					suffix = OutlineKeys.SUFFIX_SPACE + suffix
				
				item.set_text(0, c + suffix)
				var meta = {
					ParserKeys.ACCESS_PATH: full_access_path,
					ParserKeys.LINE_INDEX: line_index,
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_CONST,
					}
				item.set_metadata(0, meta)
				_set_collapsed(item)
				_set_item_params_from_persistent_data(item, full_access_path)
				_queue_infer_item(item, full_access_path, c, class_obj)
			
			
			var member_names = class_obj.members.keys()
			if sort_mode == SortMode.ALPHA or sort_mode == SortMode.METHOD_TYPE_ALPHA:
				member_names.sort_custom(sort_alphabetic)
			else:
				member_names.sort_custom(sort_by_line_index.bind(class_obj.members))
			
			for m in member_names:
				var member_data = class_obj.members[m]
				var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
				if member_type == ParserKeys.MEMBER_TYPE_FUNC or member_type == ParserKeys.MEMBER_TYPE_STATIC_FUNC:
					continue
				
				var full_access_path:String = UString.dot_join(access_path, m)
				var item:TreeItem = create_item(prop_parent)
				class_items[full_access_path] = item
				
				var line_index = member_data.get(ParserKeys.LINE_INDEX)
				var suffix = ""
				if member_type == ParserKeys.MEMBER_TYPE_STATIC_VAR:
					suffix += "[static]"
				#var line_text = "[l:%s] " % member_data.get(ParserKeys.LINE_INDEX)
				if display_line_numbers:
					suffix += MemberData.ITEM_LINE_STR % line_index
				if not suffix.is_empty():
					suffix = OutlineKeys.SUFFIX_SPACE + suffix
				
				item.set_text(0, m + suffix)
				var meta = {
					ParserKeys.ACCESS_PATH: full_access_path,
					ParserKeys.LINE_INDEX: line_index,
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_MEMBER,
					}
				item.set_metadata(0, meta)
				_set_collapsed(item)
				_set_item_params_from_persistent_data(item, full_access_path)
				_queue_infer_item(item, full_access_path, m, class_obj)
			
			
			var virtual_methods:Dictionary = MemberData.get_virtual_methods_of_class(class_base_type)
			var inherited_members:Dictionary = class_obj.get_inherited_members()
			#print("INH MEMBERS::FOR CLASS::", class_obj.get_name(),"::", inherited_members.keys())
			var static_methods:Dictionary = {}
			var func_names:Array = class_obj.functions.keys()
			if sort_mode == SortMode.NONE:
				func_names.sort_custom(sort_by_line_index.bind(class_obj.members))
			elif sort_mode == SortMode.ALPHA:
				func_names.sort_custom(sort_alphabetic)
			else:
				for f in func_names: # only need static methods if sorting
					var func_obj = class_obj.get_function(f) as ParserFunc
					if func_obj.is_static():
						static_methods[f] = true
				func_names = get_sorted_methods(func_names, virtual_methods, inherited_members, static_methods)
			
			for f in func_names:
				var full_access_path:String = UString.dot_join(access_path, f)
				var item:TreeItem = create_item(func_parent)
				
				class_items[full_access_path] = item
				var func_obj:ParserFunc = class_obj.get_function(f) as ParserFunc
				
				var item_tags:Array = []
				if func_obj.is_static():
					item_tags.append(OutlineKeys.STATIC)
				var virtual:bool = virtual_methods.has(f)
				if virtual:
					item_tags.append(OutlineKeys.VIRTUAL)
					item.set_custom_color(0, MemberData.function_def_color)
				if inherited_members.has(f):
					item_tags.append(OutlineKeys.OVERIDE)
					if not virtual:
						item.set_custom_color(0, MemberData.member_var_color)
				
				var func_dec_line:int = func_obj.declaration_line
				var suffix:String = ""
				if not item_tags.is_empty():
					suffix += "[%s]" % ", ".join(item_tags)
				if display_line_numbers:
					suffix += MemberData.ITEM_LINE_STR % func_dec_line
				if not suffix.is_empty():
					suffix = OutlineKeys.SUFFIX_SPACE + suffix
				
				item.set_text(0, f + suffix)
				var meta:Dictionary = {
					ParserKeys.ACCESS_PATH: full_access_path,
					ParserKeys.LINE_INDEX: func_dec_line,
					OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_FUNC,
					OutlineKeys.TAGS: item_tags,
					}
				item.set_metadata(0, meta)
				_set_collapsed(item, true)
				_set_item_params_from_persistent_data(item, full_access_path)
				_queue_infer_item(item, full_access_path, f, class_obj)
				
				func_obj.map_variables()
				for arg_name in func_obj.arguments.keys():
					var arg_access_path = MemberData.get_lv_access_path(class_items, UString.dot_join(full_access_path, arg_name))
					var arg_item = create_item(item)
					class_items[arg_access_path] = arg_item
					arg_item.set_text(0, arg_name + " [arg]")
					var arg_meta = {
						ParserKeys.ACCESS_PATH: arg_access_path,
						ParserKeys.LINE_INDEX: func_dec_line,
						OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_ARG,
					}
					arg_item.set_metadata(0, arg_meta)
					_set_item_params_from_persistent_data(arg_item, arg_access_path)
					_queue_infer_item(arg_item, arg_access_path, arg_name, class_obj)
				
				var lv_dec_line_idxes = func_obj.local_vars.keys()
				lv_dec_line_idxes.sort()
				for lv_dec_line in lv_dec_line_idxes:
					var lv_data:Dictionary = func_obj.local_vars[lv_dec_line]
					var lv_name:String = lv_data.get(ParserKeys.MEMBER_NAME)
					var lv_member_type:StringName = lv_data.get(ParserKeys.MEMBER_TYPE)
					var lv_access_path:String = MemberData.get_lv_access_path(class_items, UString.dot_join(full_access_path, lv_name))
					var lv_item:TreeItem = create_item(item)
					class_items[lv_access_path] = lv_item
					
					var lv_suffix = ""
					if lv_member_type == ParserKeys.MEMBER_TYPE_FOR:
						lv_suffix += "[for loop]"
					if display_line_numbers:
						lv_suffix += MemberData.ITEM_LINE_STR % lv_dec_line
					if not lv_suffix.is_empty():
						lv_suffix = OutlineKeys.SUFFIX_SPACE + lv_suffix
					
					lv_item.set_text(0, lv_name + lv_suffix)
					var lv_meta:Dictionary = { # this will need a column too if their are multiple in line?
						ParserKeys.ACCESS_PATH: lv_access_path,
						ParserKeys.LINE_INDEX: lv_dec_line,
						OutlineKeys.ITEM_TYPE: OutlineKeys.ITEM_TYPE_LOCAL_VAR,
						}
					lv_item.set_metadata(0, lv_meta)
					_set_item_params_from_persistent_data(lv_item, lv_access_path)
					_queue_infer_item(lv_item, lv_access_path, lv_name, class_obj)
			
			
			if true: # add a flag for categories?
				if prop_parent.get_child_count() == 0:
					prop_parent.free()
				if const_parent.get_child_count() == 0:
					const_parent.free()
				if func_parent.get_child_count() == 0:
					func_parent.free()
		
		_item_dict = class_items
		cache_dirty = false
		filter_items()
		select_path(selected_path, {
			"emit_sig": false,
		})
		
		tree_built.emit()
		
		if not PLUGIN_EXPORTED:
			t.stop()
			pass
		
		_process_infer_queue()
	
	func get_sorted_methods(methods: Array, virtual: Dictionary, inherited: Dictionary, statics: Dictionary) -> Array:
		var arr_virtual:Array = []
		var arr_inherited:Array = []
		var arr_static:Array = []
		var arr_other:Array = []
		
		for m in methods:
			if virtual.has(m):
				arr_virtual.append(m)
			elif inherited.has(m):
				arr_inherited.append(m)
			elif statics.has(m):
				arr_static.append(m)
			else:
				arr_other.append(m)
		
		if sort_mode == SortMode.METHOD_TYPE_ALPHA:
			arr_virtual.sort_custom(sort_alphabetic)
			arr_inherited.sort_custom(sort_alphabetic)
			arr_static.sort_custom(sort_alphabetic)
			arr_other.sort_custom(sort_alphabetic)
		
		var result:Array = []
		result.append_array(arr_virtual)
		result.append_array(arr_inherited)
		result.append_array(arr_static)
		result.append_array(arr_other)
		return result
	
	func sort_by_line_index(a:StringName, b:StringName, dict:Dictionary) -> bool:
		var a_data = dict[a]
		var b_data = dict[b]
		return a_data.get(ParserKeys.LINE_INDEX) < b_data.get(ParserKeys.LINE_INDEX)
	
	func sort_alphabetic(a:StringName, b:StringName):
		return a.nocasecmp_to(b) < 0
	
	
	func _queue_infer_item(item:TreeItem, access_path:String, member_name:StringName, class_obj:ParserClass) -> void:
		_infer_queue.append({
			ParserKeys.ACCESS_PATH: access_path,
			OutlineKeys.ITEM: item,
			OutlineKeys.NAME: member_name,
			OutlineKeys.CLASS_OBJ: class_obj,
		})
	
	func _clear_infer_queue():
		_infer_queue_processing = false
		_infer_queue.clear()
	
	func _process_infer_queue() -> void:
		_infer_queue_processing = true
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("INFER QUEUE TOTAL")
		
		#var tree_font_color:Color = _editor_theme.get_color("font_color", "Tree")
		
		var gdscript_parser:GDScriptParser = EditorGDScriptParser.get_parser()
		var count:int = 0
		
		# pseudo setting
		var show_suffixes = false
		#
		
		# TEST
		# should this go through editor parser so that signals are sent? Would retrigger build?
		if gdscript_parser.get_code_edit_parser().cache_dirty:
			_clear_infer_queue()
			EditorGDScriptParser.queue_parse()
			return
		
		#gdscript_parser.parse()
		# TEST
		
		var inc_t = ALibRuntime.Utils.UProfile.TimeFunction.new("Infer Queue", ALibRuntime.Utils.UProfile.TimeFunction.TimeScale.USEC, false)
		inc_t.iterations = 50
		inc_t.start()
		while not _infer_queue.is_empty():
			var item_data:Dictionary = _infer_queue.pop_front()
			var item:TreeItem = item_data.get(OutlineKeys.ITEM)
			if not is_instance_valid(item):
				continue
			
			var item_metadata:Dictionary = item.get_metadata(0)
			var item_type:StringName = item_metadata.get(OutlineKeys.ITEM_TYPE)
			var line_index:int = item_metadata.get(ParserKeys.LINE_INDEX, -1)
			
			var access_path:String = item_data.get(ParserKeys.ACCESS_PATH)
			var member_name:String = item_data.get(OutlineKeys.NAME)
			var class_obj:ParserClass = item_data.get(OutlineKeys.CLASS_OBJ)
			
			var fg_color:Color = Color.BLACK
			var bg_color:Color = Color.BLACK
			var suffix:String = ""
			var button_hints:Array = []
			var diag_hints:Array = []
			
			var type_rich:Dictionary
			var has_static_type:bool = false
			
			var member_data
			if item_type == OutlineKeys.ITEM_TYPE_ARG or item_type == OutlineKeys.ITEM_TYPE_LOCAL_VAR:
				var func_obj:ParserFunc = MemberData.get_lv_func_obj_from_access_path(access_path, line_index) as ParserFunc
				if not func_obj:
					printerr("Outline-657--Could not get func obj::",access_path)
					continue
				
				member_data = func_obj.get_local_var_member_data(member_name, line_index)
				type_rich = func_obj.get_local_var_type_rich(line_index, member_name)
				has_static_type = func_obj.is_local_var_static_typed(line_index, member_name)
			else:
				member_data = class_obj.get_member_data(member_name)
				type_rich = class_obj.get_member_type_rich(member_name)
				has_static_type = class_obj.is_member_static_typed(member_name)
			
			var type:String = type_rich.type
			
			if member_data == null:
				printerr("MemberData null in outline - %s" % member_name)
				continue
			
			var has_issue:=false
			
			var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
			if member_type == ParserKeys.MEMBER_TYPE_VAR or member_type == ParserKeys.MEMBER_TYPE_STATIC_VAR:
				var dict_key_meta = get_dict_key_meta(gdscript_parser, line_index)
				if not dict_key_meta.is_empty():
					if not dict_key_meta_valid_access(dict_key_meta):
						has_issue = true
						diag_hints.append(OutlineKeys.HINT_DICT_KEY_INVALID_ACCESS)
					
					var adj_type = get_dict_key_meta_adjusted_type(dict_key_meta, gdscript_parser, line_index)
					if adj_type != "":
						type = adj_type
			
			
			if not has_static_type:
				has_issue = true
				suffix = "[no type hint]"
				
				if type == "" or member_type == ParserKeys.MEMBER_TYPE_FUNC_ARG:
					diag_hints.append(OutlineKeys.HINT_NO_TYPE)
				else:
					button_hints.append(OutlineKeys.HINT_NO_TYPE_INFER)
			
			if member_type == ParserKeys.MEMBER_TYPE_FUNC or member_type == ParserKeys.MEMBER_TYPE_STATIC_FUNC:
				var tags = item_metadata.get(OutlineKeys.TAGS, [])
				if OutlineKeys.VIRTUAL in tags:
					fg_color = MemberData.function_def_color
				elif OutlineKeys.OVERIDE in tags:
					fg_color = MemberData.member_var_color
				elif OutlineKeys.STATIC in tags:
					pass
			
			if has_issue:
				bg_color = Color.DARK_RED
				bg_color.a = 0.1
				#fg_color = Color.DARK_RED.lightened(0.5)
			
			#TEST
			var old_type = current_script_item_data.get(access_path).get("TEST_TYPE", "")
			if old_type and old_type != type:
				printerr("TYPECHANGED::", "L:", line_index, ":", access_path, " - ", old_type, " -> ", type)
			current_script_item_data[access_path]["TEST_TYPE"] = type
			#TEST
			#print("INFER::", member_name, ":: -> ::", type)
			
			
			
			var is_instance = type.ends_with(ParserKeys.INS_DELIM)
			var icon_name:StringName = MemberData.get_type_icon_name(type, gdscript_parser, class_obj, is_instance)
			
			var params = get_item_persistent_data(access_path)
			params.icon = icon_name
			if show_suffixes:
				params.suffix = suffix
			else:
				params.suffix = ""
			
			if fg_color != Color.BLACK:
				params["fg_color"] = fg_color
			else:
				#item.set_custom_color(0, tree_font_color)
				params.erase("fg_color")
			
			if bg_color != Color.BLACK:
				params["bg_color"] = bg_color
			elif item.get_custom_bg_color(0) != Color.BLACK:
				item.set_custom_bg_color(0, Color.TRANSPARENT)
				params.erase("bg_color")
			
			params.button_hints = button_hints
			params.diagnostic_hints = diag_hints
			
			_set_item_persistent_data(access_path, params)
			_set_item_params_from_persistent_data(item, access_path)
			
			#inc_t.stop("", true)
			count += 1
			if count % QUEUE_PER_FRAME == 0: # every x amount, await a frame
				await get_tree().process_frame
		
		
		# clear erased members
		for access_path in current_script_item_data.keys():
			if not _item_dict.has(access_path):
				current_script_item_data.erase(access_path)
		
		#print("ITEMS INFERRED::", count)
		#t.stop()
		
		if _infer_queue_processing: # rebuilding the tree sets this to false, so that not rebuilding with an unfinished queue
			infer_queue_finished.emit()
	
	
	func _on_item_mouse_selected(mouse_pos:Vector2, btn_idx:int):
		var item:TreeItem = get_item_at_position(mouse_pos)
		#if btn_idx == MOUSE_BUTTON_LEFT: # both select?
		selected_changed.emit(true)
		set_caret_to_member_line(item)
	
	
	func _on_item_button_pressed(item:TreeItem, col:int, id:int, mouse_button_idx:int) -> void:
		var access_path = get_item_access_path(item)
		var persistent_data = get_item_persistent_data(access_path)
		
		var metadata:Dictionary = item.get_metadata(0)
		var line_index:int = metadata.get(ParserKeys.LINE_INDEX)
		
		var options:Options = Options.new()
		if OutlineKeys.HINT_NO_TYPE_INFER in persistent_data.button_hints:
			options.add_option("Add Type Hint", _infer_line.bind(line_index))
		
		right_click_handler.display_popup(options, true)
		
	
	func _infer_line(line_index:int) -> void:
		var gdscript_parser:GDScriptParser = EditorGDScriptParser.get_parser()
		var code_edit:CodeEdit = ScriptEditorRef.get_current_code_edit()
		VarInsertType.infer_single_line(gdscript_parser, code_edit, line_index)
		EditorGDScriptParser.queue_parse()
		#build_tree.call_deferred()
	
	
	func filter_items() -> void:
		var selected_path:String = get_selected_path()
		
		is_filtering = current_filter_text != ""
		if current_filter_text == "" and last_filter_text == "":
			return
		last_filter_text = current_filter_text
		var item:TreeItem = get_root()
		if current_filter_text == "":
			while is_instance_valid(item):
				item.visible = true
				var meta:Variant = item.get_metadata(0)
				if meta != null:
					_set_collapsed(item)
				item = item.get_next_in_tree()
			return
		
		var class_items:Array[TreeItem] = []
		var func_items:Array[TreeItem] = []
		var cat_items:Array[TreeItem] = []
		while is_instance_valid(item):
			var meta:Variant = item.get_metadata(0)
			if meta == null:
				item = item.get_next_in_tree()
				continue
			var item_type:StringName = meta.get(OutlineKeys.ITEM_TYPE)
			if item_type == OutlineKeys.ITEM_TYPE_CLASS:
				class_items.append(item)
			elif item_type == OutlineKeys.ITEM_TYPE_CATEGORY:
				cat_items.append(item)
			else:
				if item_type == OutlineKeys.ITEM_TYPE_FUNC:
					func_items.append(item)
				
				var text:String = item.get_text(0)
				item.visible = current_filter_text.is_subsequence_ofn(text)
			
			item = item.get_next_in_tree()
		
		for func_item:TreeItem in func_items:
			if func_item.visible:
				continue
			for c:TreeItem in func_item.get_children():
				if c.visible:
					func_item.collapsed = false
					func_item.visible = true
					break
		
		for cat_item:TreeItem in cat_items:
			cat_item.visible = false
			for c:TreeItem in cat_item.get_children():
				if c.visible:
					cat_item.collapsed = false
					cat_item.visible = true
					break
		
		for class_item:TreeItem in class_items:
			class_item.visible = false
			for c:TreeItem in class_item.get_children():
				if c.visible:
					class_item.collapsed = false
					class_item.visible = true
					break
	
	
	func _make_custom_tooltip(_for_text: String) -> Object:
		var item:TreeItem = get_item_at_position(get_local_mouse_position())
		if not is_instance_valid(item):
			return
		if not valid_member_item(item):
			return
		MemberData.set_colors()
		
		var meta:Dictionary = item.get_metadata(0)
		var member_name:String = get_item_member_name(item)
		
		var panel:PanelContainer = PanelContainer.new()
		var vbox:VBoxContainer = VBoxContainer.new()
		panel.add_child(vbox)
		
		var label:RichTextLabel = RichTextLabel.new()
		vbox.add_child(label)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.bbcode_enabled = true
		label.scroll_active = false
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var gdscript_parser:GDScriptParser = EditorGDScriptParser.get_parser()
		var access_path:String = meta.get(ParserKeys.ACCESS_PATH)
		var persisitent_data:Dictionary = get_item_persistent_data(access_path)
		
		var line_index = meta.get(ParserKeys.LINE_INDEX, -1)
		var item_type = meta.get(OutlineKeys.ITEM_TYPE)
		var is_arg = item_type == OutlineKeys.ITEM_TYPE_ARG
		var is_local = is_arg or item_type == OutlineKeys.ITEM_TYPE_LOCAL_VAR
		
		var class_obj:ParserClass
		var member_data
		if is_local:
			var func_obj = MemberData.get_lv_func_obj_from_access_path(access_path, line_index)
			if not is_instance_valid(func_obj):
				print("NO FUNC FOR LOCAL??")
				return
			if is_arg:
				member_data = func_obj.arguments.get(member_name)
			else:
				member_data = func_obj.local_vars.get(line_index)
			if member_data == null:
				print("Member data null - local var")
				return
		else:
			class_obj = MemberData.get_class_obj_from_access_path(access_path) as ParserClass
			member_data = class_obj.get_member_data(member_name)
		
		if member_data == null:
			print("Member data null - %s" % member_name)
			return
		
		var pr = Pr.new()
		var is_main_class = access_path == ""
		
		var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
		if is_main_class or member_type == ParserKeys.MEMBER_TYPE_CLASS:
			var inner_access_path = ""
			if not is_main_class:
				inner_access_path = UString.dot_join(member_data.get(ParserKeys.ACCESS_PATH), member_name)
			var inner_class_obj = gdscript_parser.get_class_object(inner_access_path) as ParserClass
			MemberData.get_class_data(gdscript_parser, inner_class_obj, pr)
			label.text = pr.get_string()
			label.custom_minimum_size = _get_panel_size(pr, label)
			return panel
		
		if member_type == ParserKeys.MEMBER_TYPE_STATIC_FUNC or member_type == ParserKeys.MEMBER_TYPE_FUNC:
			var func_obj:ParserFunc = class_obj.get_function(member_name)
			var tags = meta.get(OutlineKeys.TAGS, [])
			if not tags.is_empty():
				pr.append("[ ", MemberData.symbol_color)
				for i in range(tags.size()):
					var t = tags[i]
					var color = MemberData.function_def_color
					match t:
						OutlineKeys.STATIC: color = MemberData.keyword_color
						OutlineKeys.OVERIDE: color = MemberData.member_var_color
					pr.append(t, color)
					if i < tags.size() - 1:
						pr.append(", ", MemberData.symbol_color)
				pr.append(" ]", MemberData.symbol_color).new_line()
			
			pr.append("func" if not func_obj.is_static() else "static func", MemberData.keyword_color)
			pr.append(" " + member_name, MemberData.function_def_color).append("()", MemberData.symbol_color)
			
			var function_data = func_obj.get_function_data() as Dictionary
			var args = function_data.get(ParserKeys.FUNC_ARGS)
			var ret_type = function_data.get(ParserKeys.FUNC_RETURN, "void")
			if ret_type == "":
				ret_type = "void"
			if not args.is_empty():
				pr.new_line().append("arguments", MemberData.keyword_color).append(":", MemberData.symbol_color)
				for arg_name in args.keys():
					pr.new_line().append("\t").append(arg_name)
					var type = args[arg_name].get(ParserKeys.TYPE, "Variant")
					type = gdscript_parser.resolve_expression_to_type(type, func_obj.declaration_line)
					MemberData.parse_type_string(type, pr, gdscript_parser)
			
			pr.new_line().append("return", EditorColors.get_syntax_color(EditorColors.SyntaxColor.CONTROL_FLOW_KEYWORD))
			MemberData.parse_type_string(ret_type, pr, gdscript_parser)
			pr.new_line().append("line", MemberData.keyword_color).append(": ", MemberData.symbol_color)
			pr.append("%s" % func_obj.declaration_line)
			
		else: # non func and non class member
			var member_color:=Color.TRANSPARENT
			var member_type_display = member_type
			if is_arg:
				member_type_display = &"argument"
			elif is_local:
				member_type_display = &"local var"
			else:
				member_color = MemberData.member_var_color
			pr.append(member_type_display, MemberData.keyword_color).append(" " + member_name, member_color)
			
			var type:String
			if not is_local:
				type = class_obj.get_member_type(member_name)
			else:
				var func_obj = MemberData.get_lv_func_obj_from_access_path(access_path, line_index) as ParserFunc
				type = func_obj.get_local_var_type(line_index, member_name)
			
			if member_type == ParserKeys.MEMBER_TYPE_VAR or member_type == ParserKeys.MEMBER_TYPE_STATIC_VAR:
				var dict_key_meta = get_dict_key_meta(gdscript_parser, line_index)
				if not dict_key_meta.is_empty():
					var adj_type = get_dict_key_meta_adjusted_type(dict_key_meta, gdscript_parser, line_index)
					if adj_type != "":
						type = adj_type
			
			MemberData.parse_type_string(type, pr, gdscript_parser)
			
			if member_type == ParserKeys.MEMBER_TYPE_SIGNAL: # signal args
				var args = class_obj.get_script_signal_args(member_name, false)
				if not args.is_empty():
					pr.new_line().append("arguments:", MemberData.keyword_color)
					for sig_name in args.keys():
						pr.new_line().append("\t" + sig_name)
						var sig_type = args[sig_name]
						var type_check = gdscript_parser.resolve_expression_to_type(sig_type, line_index)
						if type_check != "":
							sig_type = type_check
						MemberData.parse_type_string(type_check, pr, gdscript_parser)
			elif member_type == ParserKeys.MEMBER_TYPE_CONST or member_type == ParserKeys.MEMBER_TYPE_ENUM: # const or enum
				var val = GDScriptParser.Utils.run_expression(member_name, class_obj.get_script_resource())
				if not val.contains("<GDScript"):
					pr.new_line().append("value", MemberData.keyword_color).append(": ", MemberData.symbol_color)
					if val.begins_with("{") and val.ends_with("}"):
						var dict_members = val.trim_prefix("{").trim_suffix("}").split(",", false)
						if dict_members.is_empty():
							pr.append("empty dictionary")
						else:
							for mem in dict_members:
								pr.new_line().append("\t" + mem, MemberData.member_var_color)
						
					else: # this would already be handled via my own
						pr.append(val, MemberData.member_var_color)
			
			pr.new_line().append("line", MemberData.keyword_color).append(": ", MemberData.symbol_color).append("%s" % line_index)
		
		
		var button_hints = persisitent_data.get("button_hints", [])
		if not button_hints.is_empty():
			pr.new_line().new_line().append("diagnostics", MemberData.keyword_color).append(":", MemberData.symbol_color)
		for hint in button_hints:
			if hint == OutlineKeys.HINT_NO_TYPE_INFER:
				pr.new_line().append("\tType Hint - no explicit hint, can infer")
		
		var diag_hints = persisitent_data.get("diagnostic_hints", [])
		if not diag_hints.is_empty():
			pr.new_line().new_line().append("diagnostics", MemberData.keyword_color).append(":", MemberData.symbol_color)
		for hint in diag_hints:
			if hint == OutlineKeys.HINT_NO_TYPE:
				pr.new_line().append("\tType Hint - no explicit hint")
			elif hint == OutlineKeys.HINT_DICT_KEY_INVALID_ACCESS:
				pr.new_line().append("\tDict Key - invalid access")
		
		label.text = pr.get_string()
		label.custom_minimum_size = _get_panel_size(pr, label)
		return panel
	
	
	func _get_panel_size(pr:Pr, label:RichTextLabel):
		var largest_string = pr.get_longest_line()
		#print(largest_string)
		var line_count = max(label.text.count("\n") + 1, 2) # minimum 2 lines otherwise single line is cut off
		var font = label.get_theme_font("font")
		var string_size = font.get_string_size(largest_string)
		var x_size = string_size.x * 1.1 # multiplier for small strings seems to be necessary for some reason
		var y_size = string_size.y * (line_count)
		var final_size = Vector2(x_size, y_size)
		#print(final_size)
		return final_size
	
	
	#^ item utils
	
	func get_selected_path() -> String:
		var selected_path:String = "null"
		var selected:TreeItem = get_selected()
		if is_instance_valid(selected):
			selected_path = get_item_access_path(selected)
		return selected_path
	
	#! keys scroll_tree:bool center_tree:bool set_caret:bool emit_sig:bool
	func select_path(access_path:String, params:={}):
		if access_path == "null":
			return false
		
		var item = _item_dict.get(access_path)
		if not is_instance_valid(item):
			return false
		#if not item.visible:
			#return false
		
		deselect_all()
		if params.get("scroll_tree", false):
			var item_par = item.get_parent()
			while is_instance_valid(item_par):
				item_par.collapsed = false
				item_par = item_par.get_parent()
			var center_on_item = params.get("center_tree", false)
			scroll_to_item(item, center_on_item)
		
		set_selected(item, 0)
		if params.get("set_caret", false):
			set_caret_to_member_line(item)
		if params.get("emit_sig", true):
			selected_changed.emit(false)
		return true
	
	
	func set_caret_to_member_line(item:TreeItem, auto_scroll:=true):
		if not valid_member_item(item):
			return
		
		var code_edit:CodeEdit = ScriptEditorRef.get_current_code_edit()
		var first_vis_line = code_edit.get_first_visible_line()
		var vis_line_count = code_edit.get_visible_line_count()
		
		var full_access_path = get_item_access_path(item)
		if full_access_path == "":
			code_edit.deselect()
			code_edit.set_caret_line(0)
			code_edit.set_caret_column(code_edit.get_line(0).length(), false)
			#if not caret_is_visible or not auto_scroll: # don't think this necessary
			code_edit.set_line_as_first_visible(0)
			return
		
		var member_name:String = get_item_member_name(item)
		var item_meta:Dictionary = item.get_metadata(0) as Dictionary
		var item_type:String = item_meta.get(OutlineKeys.ITEM_TYPE)
		var line_index:int = item_meta.get(ParserKeys.LINE_INDEX, -1)
		
		var member_data:Dictionary
		if item_type == OutlineKeys.ITEM_TYPE_LOCAL_VAR or item_type == OutlineKeys.ITEM_TYPE_ARG:
			member_data = {}
		else:
			var class_obj:ParserClass = get_class_object_from_item(item)
			if not is_instance_valid(class_obj):
				return
			member_data = class_obj.get_member_data(member_name)
			line_index = member_data.get(ParserKeys.LINE_INDEX)
		
		var target_line_vis:bool = line_index >= first_vis_line and line_index <= first_vis_line + vis_line_count
		
		code_edit.deselect()
		code_edit.set_caret_line(line_index)
		code_edit.set_caret_column(code_edit.get_line(line_index).length(), false)
		if auto_scroll and target_line_vis:
			return
		
		if item_type == OutlineKeys.ITEM_TYPE_FUNC or item_type == OutlineKeys.ITEM_TYPE_CLASS:
			var first_line_pos:float = code_edit.get_scroll_pos_for_line(line_index)
			# offset the func or class to 25% position of code edit rather than 'set_line_as_first_visible'
			# feels a bit more natural if the scroll is not centered or at the top
			first_line_pos -= (code_edit.size.y / code_edit.get_line_height()) * 0.25 
			code_edit.get_v_scroll_bar().value = first_line_pos
		else:
			code_edit.set_line_as_center_visible(line_index)
	
	
	func get_item_from_access_path(access_path:String):
		return _item_dict.get(access_path)
	
	func get_item_member_name(item:TreeItem):
		var text = item.get_text(0) # this is incase I want to add static or return to text
		text = text.substr(0, text.find("[")).strip_edges()
		return text
	
	func get_item_access_path(item:TreeItem) -> Variant:
		var meta = item.get_metadata(0)
		if meta == null:
			return null
		return meta.get(ParserKeys.ACCESS_PATH)
	
	func get_class_object_from_item(item:TreeItem) -> ParserClass:
		var access_path = get_item_access_path(item)
		if access_path == null:
			return null
		return MemberData.get_class_obj_from_access_path(access_path, local_var_item(item))
	
	func local_var_item(item:TreeItem):
		var metadata = item.get_metadata(0)
		return metadata and (metadata.get(OutlineKeys.ITEM_TYPE) == OutlineKeys.ITEM_TYPE_ARG or metadata.get(OutlineKeys.ITEM_TYPE) == OutlineKeys.ITEM_TYPE_LOCAL_VAR)
	
	func valid_member_item(item:TreeItem):
		var meta = item.get_metadata(0)
		if meta is Dictionary and meta.get(OutlineKeys.ITEM_TYPE) != OutlineKeys.ITEM_TYPE_CATEGORY:
			return true # non category items with metadata are valid
		return false
	
	#! keys icon:Texture2D suffix:String fg_color:Color bg_color:Color button_hints:Array diagnostic_hints:Array
	func _set_item_persistent_data(access_path:String, data:Dictionary={}):
		var access_path_data = current_script_item_data.get_or_add(access_path, {})
		access_path_data["persistent_data"] = data
	
	#! keys i-_set_item_persistent_data;
	func get_item_persistent_data(access_path:String) -> Dictionary:
		return current_script_item_data.get_or_add(access_path, {}).get("persistent_data", {})
	
	func _set_item_params_from_persistent_data(item:TreeItem, access_path:String):
		var data = get_item_persistent_data(access_path)
		if data.has("icon"):
			item.set_icon(0, _editor_theme.get_icon(data.icon, _ED_ICONS))
		else:
			item.set_icon(0, _editor_theme.get_icon(&"Nil", _ED_ICONS))
		if data.has("suffix"):
			item.set_suffix(0, data.suffix)
		if data.has("fg_color"):
			item.set_custom_color(0, data.fg_color)
		if data.has("bg_color"):
			item.set_custom_bg_color(0, data.bg_color)
		if data.has("button_hints"):
			var button_idx = item.get_button_by_id(0, 0)
			var has_hints = not data.button_hints.is_empty()
			if has_hints and button_idx == -1:
				item.add_button(0, _editor_theme.get_icon("Info", _ED_ICONS), 0, false, "Insert type hint")
			elif not has_hints and button_idx > -1:
				item.erase_button(0, button_idx)
	
	
	func get_item_icon_for_path(access_path:String):
		
		var icon_name = current_script_item_data.get_or_add(access_path, {}).get(MemberData.LAST_ICON, &"Nil")
		return _editor_theme.get_icon(icon_name, _ED_ICONS)
	
	func _set_collapsed(item:TreeItem, default:=false):
		var access_path = get_item_access_path(item)
		var access_path_data = current_script_item_data.get_or_add(access_path, {})
		item.collapsed = access_path_data.get(MemberData.COLLAPSED, default)
	
	func _on_item_collapsed(item:TreeItem):
		if is_filtering:
			return
		var access_path = get_item_access_path(item)
		var access_path_data = current_script_item_data.get_or_add(access_path, {})
		access_path_data[MemberData.COLLAPSED] = item.collapsed
	
	
	
	func get_dict_key_meta(gdscript_parser:GDScriptParser, line_idx:int):
		var type_data = gdscript_parser.get_code_edit_parser().get_type_from_line(line_idx)
		if type_data and type_data.get(ParserKeys.TYPE) == "var":
			var type_array = type_data.get("result")
			var assignment = type_array[2]
			#print("ADJ STRING::ASSIGN::", assignment)
			var keys_completion = TagParser.get_tag_parser("keys", false)
			if not keys_completion and not PLUGIN_EXPORTED:
				printerr("CAN NOT GET KEYS COMPLETION")
			if keys_completion:
				var tl = gdscript_parser.get_type_lookup()
				tl._initialize_op_regexes()
				var as_check:RegExMatch = tl._as_regex.search(assignment)
				if as_check: # trim type cast from the assignment, could be other things too to get rid of?
					assignment = assignment.substr(0, as_check.get_start(0)).strip_edges()
					
				return keys_completion.check_expression_for_meta(assignment, line_idx)
		return {}
	
	func dict_key_meta_valid_access(meta_dict:Dictionary):
		if meta_dict.is_empty():
			return true
		var sim_call = meta_dict.get("simulated_call", "-invalid_access")
		if sim_call == "": # this would be a direct assignment of the dict
			return true
		return sim_call != "-invalid_access" # in DictKeys script, INVALID_ACCESS
	
	func get_dict_key_meta_adjusted_type(meta_dict:Dictionary, gdscript_parser:GDScriptParser, line_idx:int):
		if meta_dict.is_empty():
			return ""
		var sim_call = meta_dict.get("simulated_call", "-invalid_access")
		if sim_call == "-invalid_access":
			return ""
		return gdscript_parser.resolve_expression_to_type(sim_call, line_idx)
		


class MemberData:
	const ITEM_LINE_STR = "[l:%s]"
	
	const COLLAPSED = &"collapsed"
	const LAST_ICON = &"last_icon"
	
	static var base_type_color:Color
	static var global_function_color:Color
	static var user_type_color:Color
	static var keyword_color:Color
	static var member_var_color:Color
	static var string_name_color:Color
	static var function_def_color:Color
	static var symbol_color:Color
	
	static func set_colors():
		base_type_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.BASE_TYPE)
		global_function_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.GLOBAL_FUNCTION)
		user_type_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.USER_TYPE)
		keyword_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.KEYWORD)
		member_var_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.MEMBER_VARIABLE)
		string_name_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING_NAME)
		function_def_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.FUNCTION_DEFINITION)
		symbol_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.SYMBOL)
	
	static func is_a_gdscript_file(file_path:String):
		return GDScriptParser.Utils.is_gdscript_path(file_path)
	
	static func get_type_icon_name(type:String, gdscript_parser:GDScriptParser, current_class_obj:ParserClass, is_instance:=false) -> StringName:
		var editor_theme = EditorInterface.get_editor_theme()
		
		is_instance = type.ends_with(ParserKeys.INS_DELIM) or GDScriptParser.BuiltInChecker.is_variant_type(type)
		var delim_check = GDScriptParser.Utils.type_path_get_type(type, true)
		if delim_check != "":
			type = delim_check
		else:
			type = type.trim_suffix(ParserKeys.INS_DELIM)
		
		if type.is_empty():
			#return &"MissingNode"
			return &"Variant"
		elif type == &"void":
			return &"Nil"
		
		if type.is_absolute_path():
			if not is_a_gdscript_file(type):
				var type_check = GDScriptParser.Utils.file_path_to_type(type)
				if editor_theme.has_icon(type_check, _ED_ICONS):
					return type_check
				return &"Variant"
			else:
				#print("ERROR TYPE::", type)
				var parser_data = gdscript_parser.get_parser_and_class_obj_for_script(type)
				if not parser_data:
					return &"MissingNode"
				var class_obj = parser_data.get(ParserKeys.GET_CLASS_OBJ) as ParserClass
				var base = class_obj.script_base_type
				var icon_name:StringName
				if is_instance:
					icon_name = base if editor_theme.has_icon(base, _ED_ICONS) else &"Object"
				else:
					if class_obj.access_path == "":
						icon_name = &"GDScript"
					else:
						icon_name = &"GDScriptInternal"
				return icon_name
		else:
			if type.begins_with("Array["):
				type = "Array"
			elif type.begins_with("Dictionary["):
				type = "Dictionary"
			if editor_theme.has_icon(type, _ED_ICONS):
				return type
			
			# classes that don't have their own icon
			if ClassDB.class_exists(type):
				return &"ObjectDisabled"
			
			if type.begins_with("enum::"):
				printerr("THIS IS COMING IN, ENUM enum::Type -> ", type)
				return &"Enum" # should this be handled in typelookup differently?
			
			# for things like enums in the base class
			var member_type:String = current_class_obj.get_class_member_type(type, true)
			if member_type == "" and type.contains("."):
				var dot = type.find(".")
				var front = type.substr(0, dot)
				var back = type.substr(dot + 1)
				member_type = GDScriptParser.TypeLookup.get_class_member_type(front, back)
			
			if member_type != "":
				if editor_theme.has_icon(member_type, _ED_ICONS):
					return member_type
				return &"Object"
			else:
				return &"Variant"
	
	static func parse_type_string(type_path:String, pr:Pr, gdscript_parser:GDScriptParser, empty_as_variant:=true) -> Pr:
		var display_static_tag = true
		if type_path.is_empty():
			if empty_as_variant:
				type_path = "Variant"
			display_static_tag = false
		
		if type_path.ends_with(ParserKeys.INS_DELIM):
			display_static_tag = false
			type_path = type_path.trim_suffix(ParserKeys.INS_DELIM)
		pr.append(": ", symbol_color)
		
		var type_check = GDScriptParser.Utils.type_path_get_type(type_path, true)
		if type_check != "":
			if type_check == "Enum": # perhaps handle the other uniques?
				display_static_tag = false
			else:
				type_path = type_check
		
		if GDScriptParser.BuiltInChecker.is_variant_type(type_path):
			display_static_tag = false
		
		var resolved_member_name = GDScriptParser.Utils.type_path_get_member(type_path)
		if not type_path.is_absolute_path():
			type_path = type_path.get_slice(ParserKeys.TYPE_DELIM, 0)
			if resolved_member_name == "":
				pr.append(type_path, base_type_color)
			else:
				pr.append(GDScriptParser.Utils.type_path_get_non_member(type_path), base_type_color)
		else:
			var script_data = GDScriptParser.Utils.type_path_get_script_data(type_path)
			var script_path = script_data[0]
			var class_access_path = script_data[1]
			
			var global_name = UClassDetail.get_global_class_name(script_path)
			if not FileAccess.file_exists(script_path):
				pr.new_line().append("Could not load script: ").append(trim_file_path(script_path, gdscript_parser))
			elif not global_name.is_empty():
				pr.append(global_name, user_type_color)
			else:
				pr.append(trim_file_path(script_path, gdscript_parser), global_function_color)
			
			if class_access_path != "":
				pr.append(".", symbol_color)
				pr.append(class_access_path, base_type_color)
				# unsure about this, this keeps inner classes green between types, path is purple for preload
				#if not global_name.is_empty():
					#pr.append(class_access_path, base_type_color)
				#else:
					#pr.append(class_access_path, global_function_color)
		
		if resolved_member_name != "":
			pr.append(".", symbol_color)
			pr.append(resolved_member_name, base_type_color)
			
		if type_check in ["Enum"]:
			bracket_pr(pr, type_check)
		
		if display_static_tag and not GDScriptParser.BuiltInChecker.is_variant_type(type_path):
			bracket_pr(pr, "Static Class Ref", keyword_color, true)
		return pr
	
	static func bracket_pr(pr:Pr, text:String, color:Color=string_name_color, leading_space:=true, bracket:String="["):
		if leading_space:
			pr.append(" ")
		var close_bracket = "]"
		if bracket == "[":
			pass
		elif bracket == "(":
			close_bracket = ")"
		elif bracket == "{":
			close_bracket = "}"
		pr.append(bracket + " ", symbol_color).append(text, color).append(" " + close_bracket, symbol_color)
		return pr
	
	static func get_main_script_name():
		var gdscript_parser = EditorGDScriptParser.get_parser()
		if gdscript_parser.get_global_class_name() != "":
			return gdscript_parser.get_global_class_name()
		return gdscript_parser.get_script_path().get_file()
	
	static func get_lv_func_obj_from_access_path(access_path:String, line_idx:int):
		var class_obj = MemberData.get_class_obj_from_access_path(access_path, true) as ParserClass
		if is_instance_valid(class_obj):
			var func_name = class_obj.get_function_at_line(line_idx)
			return class_obj.get_function(func_name)
	
	static func get_class_obj_from_access_path(access_path:String, is_local:bool=false):
		var class_access = ""
		if access_path.contains("."):
			class_access = UString.trim_member_access_back(access_path)
		if is_local: # trim one more for local vars
			if class_access.contains("."):
				class_access = UString.trim_member_access_back(class_access)
			else:
				class_access = ""
		
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var class_obj = gdscript_parser.get_class_object(class_access)
		return class_obj
	
	static func trim_file_path(path: String, parser: GDScriptParser) -> String:
		# simplified version
		return path.get_file()
		
		var main_script_path = parser.get_script_path()
		if path.begins_with(main_script_path):
			var access_path = path.trim_prefix(main_script_path).trim_prefix(".")
			if access_path != "":
				return access_path
		
		var prefix = ""
		var trimmed = path
		if path.find("://") != -1: # GD
			var split_idx = path.find("://") + 3
			prefix = path.substr(0, split_idx)
			trimmed = path.substr(split_idx)
		elif path.find(":/") != -1: # Windoze
			var split_idx = path.find(":/") + 2
			prefix = path.substr(0, split_idx)
			trimmed = path.substr(split_idx)
		elif path.begins_with("/"): # Linux/MacOS
			prefix = "/"
			trimmed = path.substr(1)
		else: # no recognizable root
			pass 
		
		var slice_count = trimmed.get_slice_count("/")
		if slice_count < 3:
			return path
		var first_dir = trimmed.get_slice("/", 0)
		var file_name = trimmed.get_file()
		return prefix + first_dir.path_join("...").path_join(file_name)
	
	
	static func get_virtual_methods_of_class(class_type:String):
		var virtual_methods:= {}
		for method_data in ClassDB.class_get_method_list(class_type):
			if method_data.flags && METHOD_FLAG_VIRTUAL:
				virtual_methods[method_data.name] = true
		return virtual_methods
	
	
	static func get_class_data(gdscript_parser:GDScriptParser, class_obj:ParserClass, pr:Pr):
		if class_obj.access_path != "": # inner classes
			pr.append("class ", keyword_color).append(class_obj.access_path, base_type_color)
		elif gdscript_parser.get_global_class_name() != "": # main script is global
			pr.append("class_name ", keyword_color).append(gdscript_parser.get_global_class_name(), user_type_color)
		else: # non global
			pr.append("script ", keyword_color).append(trim_file_path(class_obj.main_script_path, gdscript_parser), global_function_color)
		
		var inherited = class_obj.get_inherited_scripts()
		for i in range(1): # single loop early break
			if inherited.is_empty():
				break
			pr.new_line().append("extends ", keyword_color)
			var inh_script = inherited[0]
			var script_data = UString.get_script_path_and_suffix(inh_script)
			if script_data.is_empty():
				pr.append("Inner Class - Cannot Find")
				break
			var script_path = script_data[0]
			if not FileAccess.file_exists(script_path):
				pr.append("Could not load script: ")
				pr.append(MemberData.trim_file_path(script_path, gdscript_parser), Color.FIREBRICK)
				break
			var script = load(script_path) as GDScript
			var class_path = script_data[1]
			if script.get_global_name() == "":
				pr.append(MemberData.trim_file_path(inh_script, gdscript_parser), global_function_color)
			else:
				pr.append(script.get_global_name(), user_type_color)
				if class_path != "":
					pr.append(".").append(class_path, base_type_color)
		
		var script_base_type = class_obj.script_base_type
		if script_base_type == "":
			script_base_type = "Could not find"
		pr.new_line().append("Base Type: ").append(script_base_type, base_type_color)
		
		var c_line = class_obj.declaration_line
		pr.new_line().append("Line", MemberData.keyword_color).append(": ", MemberData.symbol_color).append("%s" % c_line)
		return pr
	
	
	static func get_current_access_path():
		var code_edit = ScriptEditorRef.get_current_code_edit()
		if not is_instance_valid(code_edit):
			#print("ACCESS NO CODE EDIT")
			return "null"
		
		var line = code_edit.get_caret_line()
		var current_parser = EditorGDScriptParser.get_parser()
		if not is_instance_valid(current_parser):
			return "null"
		var code_edit_parser = current_parser.get_code_edit_parser()
		if not is_instance_valid(code_edit_parser.code_edit):
			#print("ACCESS NO CODE EDIT PARSER")
			return "null"
		
		var current_class = current_parser.get_class_at_line(line)
		var class_obj = current_parser.get_class_object(current_class) as GDScriptParser.ParserClass
		var current_func = current_parser.get_function_at_line(line)
		var in_class_body = current_func == ParserKeys.CLASS_BODY
		
		var line_context_start = code_edit_parser.get_line_context_start_simple(line)
		var line_context_data = code_edit_parser.get_line_context(line, 0, false, line_context_start)
		var context_text = line_context_data.get(ParserKeys.CONTEXT_TEXT).strip_edges()
		var start_idx = line_context_data.get(ParserKeys.CONTEXT_START)
		
		if start_idx == class_obj.declaration_line:
			return current_class
		
		var member_name = code_edit_parser.get_member_name_from_line(start_idx)
		if member_name == "":
			if not context_text.begins_with("for "):
				if in_class_body:
					return current_class
				else:
					return UString.dot_join(current_class, current_func)
			
			var for_info = GDScriptParser.Utils.get_for_loop_info(context_text)
			if for_info.is_empty():
				return UString.dot_join(current_class, current_func)
			else:
				member_name = for_info[0]
		
		if in_class_body:
			if class_obj.has_script_member(member_name):
				
				return UString.dot_join(current_class, member_name)
			
		else:
			if class_obj.has_function(member_name):
				return UString.dot_join(current_class, member_name)
			
			var func_obj = class_obj.get_function(current_func) as ParserFunc
			var local_var_data = func_obj.get_local_var_member_data(member_name, start_idx)
			if local_var_data:
				return UString.dot_joinv([current_class, current_func, member_name])
			
			return UString.dot_join(current_class, current_func)
		
		return "null"
	
	static func get_lv_access_path(item_dict:Dictionary, item_access_path:String):
		var count = 1
		var temp = item_access_path
		while item_dict.has(item_access_path):
			item_access_path = temp + "%%" + str(count)
			count += 1
		return item_access_path
	

class OutlineKeys:
	const ITEM = &"item"
	const NAME = &"name"
	const CLASS_OBJ = &"class_obj"
	const IS_INSTANCE = &"is_instance"
	
	const SUFFIX_SPACE = "   "
	
	const HINT_NO_TYPE = &"hint_no_type"
	const HINT_NO_TYPE_INFER = &"hint_no_type_infer"
	const HINT_DICT_KEY_INVALID_ACCESS = &"hint_dict_key_invalid_access"
	
	const TAGS = &"tags"
	const VIRTUAL = &"virtual"
	const STATIC = &"static"
	const OVERIDE = &"overide"
	
	const ITEM_TYPE = &"item_type"
	const ITEM_TYPE_CLASS = &"class"
	const ITEM_TYPE_CONST = &"const"
	const ITEM_TYPE_MEMBER = &"member"
	const ITEM_TYPE_FUNC = &"func"
	const ITEM_TYPE_ARG = &"arg"
	const ITEM_TYPE_LOCAL_VAR = &"local_var"
	const ITEM_TYPE_CATEGORY = &"category"
	
	const DOCK_OUTLINE_VIS = &"dock_outline_vis"
	

class EditorSet:
	const FOLLOW_CURSOR = &"plugin/script_outline/follow_cursor"
