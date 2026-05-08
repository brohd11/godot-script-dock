extends MarginContainer

const PLUGIN_EXPORTED = false

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")


const PathBar = ALibEditor.UIHelpers.Tab.PathBar

const TagParser = ALibEditor.Singletons.TagParser
const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const SettingHelperEditor = UtilsRemote.SettingHelperEditor
const GDScriptParser = EditorGDScriptParser.GDScriptParser
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const ParserKeys = GDScriptParser.Keys

const UString = UtilsRemote.UString
const Pr = UString.PrintRich

const EditorColors = UtilsRemote.EditorColors
const UClassDetail = UtilsRemote.UClassDetail

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const QUEUE_PER_FRAME = 5

const _ED_ICONS = &"EditorIcons"

const _CLASS = &"_class"
const _FUNC = &"_func"
const _CATEGORY = &"_category"
const _TAGS = &"_tags"
const _VIRTUAL = &"virtual"
const _STATIC = &"static"
const _OVERIDE = &"overide"

enum MemberType{
	VAR,
	STATIC_VAR,
	FUNC,
	STATIC_FUNC,
	ENUM,
	CONST,
	CLASS,
	SIGNAL,
}

enum SortMode {
	NONE,
	ALPHA,
	METHOD_TYPE,
	METHOD_TYPE_ALPHA,
}

var editor_setting_helper:SettingHelperEditor
var _dock_data:Dictionary

var right_click_handler:RightClickHandler

var _vbox:VBoxContainer
var toolbar:HBoxContainer
var filter_line_edit:LineEdit
var _bread_crumb_tabs:PathBar

var outline_tree:OutlineTree
var _tree_script_item_data:= {}

var _current_script_path:String
var _current_script_file_mod_time:int=-1

var _caret_changed_debounce:bool=false
var _last_caret_line:int = -1
var _follow_cursor:bool = false


func get_dock_data() -> Dictionary:
	var data = {}
	return data

func set_dock_data(data:Dictionary) -> void:
	_dock_data = data


func _ready() -> void:
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
	
	toolbar = HBoxContainer.new()
	_vbox.add_child(toolbar)
	
	filter_line_edit = LineEdit.new()
	toolbar.add_child(filter_line_edit)
	filter_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_line_edit.placeholder_text = "Filter Members"
	filter_line_edit.right_icon = EditorInterface.get_editor_theme().get_icon(&"Search", _ED_ICONS)
	filter_line_edit.clear_button_enabled = true
	filter_line_edit.text_changed.connect(_on_filter_text_changed)
	
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_vbox.add_child(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	_bread_crumb_tabs = PathBar.new()
	_bread_crumb_tabs.display_mode = PathBar.DisplayMode.OUTLINE
	_bread_crumb_tabs.drag_to_rearrange_enabled = false
	_bread_crumb_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER
	scroll.add_child(_bread_crumb_tabs)
	_bread_crumb_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#_bread_crumb_tabs.tab_selected.connect(_on_breadcrumb_selected)
	_bread_crumb_tabs.tab_clicked.connect(_on_breadcrumb_selected)
	
	outline_tree = OutlineTree.new()
	_vbox.add_child(outline_tree)
	outline_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline_tree.hide_root = true
	outline_tree.selected_changed.connect(_on_tree_selected_changed)
	outline_tree.tree_built.connect(_on_tree_built)
	outline_tree.infer_queue_finished.connect(_on_infer_queue_finished, 1)
	
	editor_setting_helper = SettingHelperEditor.new()
	editor_setting_helper.subscribe_property(self, &"_follow_cursor", EditorSet.FOLLOW_CURSOR, false)
	editor_setting_helper.initialize()
	
	var current_parser = EditorGDScriptParser.get_parser()
	if is_instance_valid(current_parser):
		_on_editor_script_changed(current_parser.get_current_script())
		_build_tree()


func clean_up():
	pass



func _on_editor_text_changed():
	_set_cache_dirty()

func _set_cache_dirty():
	outline_tree.cache_dirty = true


func _on_editor_script_changed(script:GDScript):
	if not is_instance_valid(script):
		outline_tree.clear()
		_current_script_path = ""
		outline_tree.current_script_item_data = {}
		return
	
	_set_cache_dirty()
	_current_script_path = script.resource_path
	if _current_script_path == "" or not _current_script_path.ends_with(".gd"):
		outline_tree.clear()
		return
	
	var current_script_data = _tree_script_item_data.get_or_add(_current_script_path, {})
	outline_tree.current_script_item_data = current_script_data


func _on_file_system_changed():
	if not FileAccess.file_exists(_current_script_path):
		return
	var current_mod_time = FileAccess.get_modified_time(_current_script_path)
	if current_mod_time != _current_script_file_mod_time:
		_current_script_file_mod_time = current_mod_time
		EditorGDScriptParser.queue_parse(true)
		_set_cache_dirty() # set cache to dirty so it will rebuild tree


func _on_parse_completed():
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
	
	if new_line:
		_set_current_access_path()

func _on_tree_built():
	_set_current_access_path(true)

func _on_infer_queue_finished():
	_build_breadcrumb()

func _build_breadcrumb(current_access_path:String="null"):
	if current_access_path == "null":
		current_access_path = MemberData.get_current_access_path(outline_tree._item_dict)
	
	var full_breadcrumb = _get_selected_breadcrumb(true)
	var current_tab = _bread_crumb_tabs.current_tab
	var keep_tabs =  full_breadcrumb.begins_with(current_access_path)
	#print("KEEP::", keep_tabs, "::CURR::", current_access_path, "::BREAD::", full_breadcrumb)
	if current_access_path == "null":
		return
	
	if keep_tabs:
		for i in range(_bread_crumb_tabs.tab_count):
			var ap = _bread_crumb_tabs.get_tab_metadata(i)
			if ap == current_access_path:
				_bread_crumb_tabs.current_tab = i
				break
		#_bread_crumb_tabs.current_tab = current_tab
	else:
		_bread_crumb_tabs.clear_tabs()
		
		_bread_crumb_tabs.add_tab(MemberData.get_main_script_name(), outline_tree.get_item_icon_for_path(""))
		_bread_crumb_tabs.set_tab_metadata(0, "")
		
		var working_path = ""
		for part in UString.split_member_access(current_access_path):
			working_path = UString.dot_join(working_path, part)
			_bread_crumb_tabs.add_tab(part, outline_tree.get_item_icon_for_path(working_path))
			_bread_crumb_tabs.set_tab_metadata(_bread_crumb_tabs.tab_count - 1, working_path)
		
		_bread_crumb_tabs.current_tab = _bread_crumb_tabs.tab_count - 1

func _on_breadcrumb_selected(sel:int) -> void:
	var access_path = _bread_crumb_tabs.get_tab_metadata(sel)
	if access_path == null:
		return
	outline_tree.select_path(access_path, true, true)

func _get_selected_breadcrumb(longest:bool=false) -> String:
	if _bread_crumb_tabs.tab_count == 0:
		return "null"
	var idx = _bread_crumb_tabs.current_tab if not longest else _bread_crumb_tabs.tab_count - 1
	var selected = _bread_crumb_tabs.get_tab_metadata(idx)
	if selected == null:
		selected = "null"
	return selected


func _set_current_access_path(build:=false):
	var selected = _get_selected_breadcrumb()
	var current_access_path = MemberData.get_current_access_path(outline_tree._item_dict)
	prints("SEL::", selected, "::CURR::", current_access_path)
	if build:
		_build_breadcrumb(current_access_path)
	if current_access_path == "null" or selected == current_access_path:
		return
	if _follow_cursor:
		
		outline_tree.select_path(current_access_path, true, false)



func get_margins():
	return [self]

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

func _on_filter_text_changed(new_text:String):
	outline_tree.current_filter_text = new_text.strip_edges()
	outline_tree.filter_items()



class OutlineTree extends Tree:
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
		
		allow_rmb_select = true
	
	
	func build_tree():
		if not cache_dirty:
			return
		
		_editor_theme = EditorInterface.get_editor_theme()
		MemberData.set_colors()
		
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("BUILD OUTLINE")
		
		var selected_path = "null"
		var selected = get_selected()
		if is_instance_valid(selected):
			selected_path = get_item_access_path(selected)
		
		_clear_infer_queue()
		clear()
		
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
				var meta = {ParserKeys.ACCESS_PATH: full_access_path, _CLASS:true}
				item_parent.set_metadata(0, meta)
				var icon_name = class_base_type
				if not _editor_theme.has_icon(icon_name, _ED_ICONS): # icon_name == "RefCounted" or not editor_theme.has_icon(icon_name, _ED_ICONS):
					icon_name = "Object"
				
				_set_item_icon(item_parent, full_access_path, icon_name)
				#item_parent.set_icon(0, _editor_theme.get_icon(icon_name, _ED_ICONS))
				
				_set_collapsed(item_parent, access_path != "")
				#if access_path != "":
				class_items[access_path] = item_parent
			
			var prop_parent = item_parent
			var const_parent = item_parent
			var func_parent = item_parent
			if true: # add a flag for categories?
				const_parent = create_item(item_parent)
				const_parent.set_text(0, "Constants")
				const_parent.set_icon(0, _editor_theme.get_icon(&"MemberConstant", _ED_ICONS))
				const_parent.set_metadata(0, {ParserKeys.ACCESS_PATH: access_path, _CATEGORY:true})
				_set_collapsed(const_parent)
				
				prop_parent = create_item(item_parent)
				prop_parent.set_text(0, "Properties")
				prop_parent.set_icon(0, _editor_theme.get_icon(&"MemberProperty", _ED_ICONS))
				prop_parent.set_metadata(0, {ParserKeys.ACCESS_PATH: access_path, _CATEGORY:true})
				_set_collapsed(prop_parent)
				
				func_parent = create_item(item_parent)
				func_parent.set_text(0, "Methods")
				func_parent.set_icon(0, _editor_theme.get_icon(&"MemberMethod", _ED_ICONS))
				func_parent.set_metadata(0, {ParserKeys.ACCESS_PATH: access_path, _CATEGORY:true})
				_set_collapsed(func_parent)
			
			
			var const_names = class_obj.constants.keys()
			const_names.sort_custom(sort_by_line_index.bind(class_obj.constants))
			if sort_mode == SortMode.ALPHA or sort_mode == SortMode.METHOD_TYPE_ALPHA:
				const_names.sort()
			
			for c in const_names:
				var member_data = class_obj.constants.get(c)
				if not member_data.get(ParserKeys.ACCESS_PATH).begins_with(access_path):
					continue
				var full_access_path = UString.dot_join(access_path, c)
				var item = create_item(const_parent)
				class_items[full_access_path] = item
				item.set_text(0, c)
				var meta = {ParserKeys.ACCESS_PATH: full_access_path}
				item.set_metadata(0, meta)
				
				_set_collapsed(item)
				item.set_icon(0, get_item_icon_for_path(full_access_path))
				_queue_infer_item(item, full_access_path, c, class_obj)
			
			
			var member_names = class_obj.members.keys()
			member_names.sort_custom(sort_by_line_index.bind(class_obj.members))
			if sort_mode == SortMode.ALPHA or sort_mode == SortMode.METHOD_TYPE_ALPHA:
				member_names.sort()
			
			for m in member_names:
				var member_data = class_obj.members[m]
				var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
				if member_type == ParserKeys.MEMBER_TYPE_FUNC or member_type == ParserKeys.MEMBER_TYPE_STATIC_FUNC:
					continue
				
				var full_access_path = UString.dot_join(access_path, m)
				var item = create_item(prop_parent)
				class_items[full_access_path] = item
				item.set_expand_right(0, true)
				var item_text = m
				if member_type == ParserKeys.MEMBER_TYPE_STATIC_VAR:
					item_text += " [static]"
				item.set_text(0, item_text)
				
				var meta = {ParserKeys.ACCESS_PATH: full_access_path}
				item.set_metadata(0, meta)
				_set_collapsed(item)
				item.set_icon(0, get_item_icon_for_path(full_access_path))
				_queue_infer_item(item, full_access_path, m, class_obj, true)
			
			
			var virtual_methods = MemberData.get_virtual_methods_of_class(class_base_type)
			var inherited_members = class_obj.get_inherited_members()
			#print("INH MEMBERS::FOR CLASS::", class_obj.get_name(),"::", inherited_members.keys())
			var static_methods = {}
			var func_names = class_obj.functions.keys()
			
			func_names.sort_custom(sort_by_line_index.bind(class_obj.members))
			if sort_mode == SortMode.ALPHA:
				func_names.sort()
			elif sort_mode != SortMode.NONE:
				for f in func_names: # only need static methods if sorting
					var func_obj = class_obj.get_function(f) as ParserFunc
					if func_obj.is_static():
						static_methods[f] = true
				func_names = get_sorted_methods(func_names, virtual_methods, inherited_members, static_methods)
			
			for f in func_names:
				var full_access_path = UString.dot_join(access_path, f)
				var item = create_item(func_parent)
				class_items[full_access_path] = item
				var func_obj = class_obj.get_function(f) as ParserFunc
				
				var item_tags = []
				if func_obj.is_static():
					item_tags.append(_STATIC)
				var virtual = virtual_methods.has(f)
				if virtual:
					item_tags.append(_VIRTUAL)
					item.set_custom_color(0, MemberData.function_def_color)
				if inherited_members.has(f):
					item_tags.append(_OVERIDE)
					if not virtual:
						item.set_custom_color(0, MemberData.member_var_color)
				
				item.set_text(0, f)
				if not item_tags.is_empty():
					item.set_suffix(0, "[%s]" % ", ".join(item_tags))
				
				var meta = {ParserKeys.ACCESS_PATH: full_access_path, _TAGS: item_tags, _FUNC:true}
				item.set_metadata(0, meta)
				_set_collapsed(item, true)
				item.set_icon(0, get_item_icon_for_path(full_access_path))
				_queue_infer_item(item, full_access_path, f, class_obj, false)
				
				var func_dec_line = func_obj.declaration_line
				func_obj.map_variables()
				for arg_name in func_obj.arguments.keys():
					var arg_data = func_obj.arguments[arg_name]
					var arg_access_path = MemberData.get_lv_access_path(class_items, UString.dot_join(full_access_path, arg_name))
					var arg_item = create_item(item)
					class_items[arg_access_path] = arg_item
					arg_item.set_text(0, arg_name + " [arg]")
					arg_item.set_icon(0, get_item_icon_for_path(arg_access_path))
					
					var arg_meta = {
						ParserKeys.ACCESS_PATH: arg_access_path,
						Keys.LINE_IDX: func_dec_line,
						Keys.IS_LOCAL: true,
						Keys.IS_ARG: true
					}
					arg_item.set_metadata(0, arg_meta)
					_queue_infer_item(arg_item, arg_access_path, arg_name, class_obj, true, func_dec_line)
				
				for lv_dec_line in func_obj.local_vars.keys():
					var lv_data:Dictionary = func_obj.local_vars[lv_dec_line]
					var lv_name:String = lv_data.get(ParserKeys.MEMBER_NAME)
					var lv_member_type:StringName = lv_data.get(ParserKeys.MEMBER_TYPE)
					var lv_access_path:String = MemberData.get_lv_access_path(class_items, UString.dot_join(full_access_path, lv_name))
					var lv_item:TreeItem = create_item(item)
					class_items[lv_access_path] = lv_item
					var display_name = lv_name
					if lv_member_type == ParserKeys.MEMBER_TYPE_FOR:
						display_name = lv_name + " [for loop]"
					lv_item.set_text(0, display_name)
					lv_item.set_icon(0, get_item_icon_for_path(lv_access_path))
					
					# this will need a column to if their are multiple in line?
					var lv_meta:Dictionary = {
						ParserKeys.ACCESS_PATH: lv_access_path,
						Keys.LINE_IDX: lv_dec_line,
						Keys.IS_LOCAL: true
						}
					lv_item.set_metadata(0, lv_meta)
					_queue_infer_item(lv_item, lv_access_path, lv_name, class_obj, true, lv_dec_line)
				
				
			
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
		if selected_path != "null":
			select_path(selected_path, false, false, false)
		
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
			arr_virtual.sort()
			arr_inherited.sort()
			arr_static.sort()
			arr_other.sort()
		
		var result:Array = []
		result.append_array(arr_virtual)
		result.append_array(arr_inherited)
		result.append_array(arr_static)
		result.append_array(arr_other)
		return result
	
	func sort_by_line_index(a:String, b:String, dict:Dictionary):
		var a_data = dict[a]
		var b_data = dict[b]
		return a_data.get(ParserKeys.LINE_INDEX) < b_data.get(ParserKeys.LINE_INDEX)
	
	func _queue_infer_item(item:TreeItem, access_path:String, member_name:StringName, class_obj:ParserClass, is_instance:bool=false, line_idx:int=-1):
		_infer_queue.append({
			ParserKeys.ACCESS_PATH: access_path,
			Keys.ITEM: item,
			Keys.NAME: member_name,
			Keys.CLASS_OBJ: class_obj,
			Keys.IS_INSTANCE: is_instance,
			Keys.LINE_IDX: line_idx
		})
	
	func _clear_infer_queue():
		_infer_queue_processing = false
		_infer_queue.clear()
	
	func _process_infer_queue():
		_infer_queue_processing = true
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("INFER QUEUE")
		var count:int = 0
		var gdscript_parser:GDScriptParser = EditorGDScriptParser.get_parser()
		gdscript_parser.parse()
		while not _infer_queue.is_empty():
			var item_data:Dictionary = _infer_queue.pop_front()
			var item = item_data.get(Keys.ITEM)
			if not is_instance_valid(item):
				continue
			
			var access_path:String = item_data.get(ParserKeys.ACCESS_PATH)
			var member_name:String = item_data.get(Keys.NAME)
			var class_obj:ParserClass = item_data.get(Keys.CLASS_OBJ)
			var is_instance:bool = item_data.get(Keys.IS_INSTANCE)
			var line_index:int = item_data.get(Keys.LINE_IDX, -1)
			var is_local = false
			var type:String
			if line_index == -1: # no line index means class member, only because I am not passing via item
				var member_data = class_obj.get_member_data(member_name)
				line_index = member_data.get(ParserKeys.LINE_INDEX)
				type = class_obj.get_member_type(member_name)
			else:
				is_local = true
				var func_obj:ParserFunc = MemberData.get_lv_func_obj_from_access_path(access_path, line_index) as ParserFunc
				if not func_obj:
					printerr("Outline-631--Could not get func obj::",access_path)
					continue
				type = func_obj.get_local_var_type(line_index, member_name)
			
			#var type_rich = gdscript_parser.resolve_expression_to_type_rich(member_name, line_index)
			#if GDScriptParser.Utils.is_absolute_path(type_rich.origin):
			
			var type_data = gdscript_parser.get_code_edit_parser().get_type_from_line(line_index)
			if type_data and type_data.get(ParserKeys.TYPE) == "var":
				var type_array = type_data.get("result")
				var assignment = type_array[2]
				var tag_parser = TagParser.get_tag_parser("keys")
				if not tag_parser:
					printerr("CAN NOT GET TAG PARSER")
				if tag_parser:
					var adjusted_string = tag_parser.resolve_tagged_expression(assignment, line_index)
					if adjusted_string:
						type = gdscript_parser.resolve_expression_to_type(adjusted_string, line_index)
						#print("ADJ STRING::TYPE", member_name, "::", adjusted_string, " -> ", type)
			
			
			
			
			
			#TEST
			var old_type = current_script_item_data.get(access_path).get("TEST_TYPE", "")
			if old_type and old_type != type:
				printerr("TYPECHANGED::", "L:", line_index, ":", access_path, " - ", old_type, " -> ", type)
			current_script_item_data[access_path]["TEST_TYPE"] = type
			#TEST
			#print("INFER::", member_name, ":: -> ::", type)
			var icon_name:StringName = MemberData.get_type_icon_name(type, gdscript_parser, class_obj, is_instance)
			_set_item_icon(item, access_path, icon_name)
			count += 1
			if count % QUEUE_PER_FRAME == 0: # every x amount, await a frame
				await get_tree().process_frame
		
		# clear erased members
		for access_path in current_script_item_data.keys():
			if not _item_dict.has(access_path):
				current_script_item_data.erase(access_path)
		
		print("ITEMS INFERRED::", count)
		t.stop()
		
		
		if _infer_queue_processing: # rebuilding the tree sets this to false, so that not rebuilding with an unfinished queue
			infer_queue_finished.emit()
	
	
	func _on_item_mouse_selected(mouse_pos:Vector2, btn_idx:int):
		var item = get_item_at_position(mouse_pos)
		#if btn_idx == MOUSE_BUTTON_LEFT: # both select?
		selected_changed.emit(true)
		set_caret_to_member_line(item)
	
	
	func filter_items():
		is_filtering = current_filter_text != ""
		if current_filter_text == "" and last_filter_text == "":
			return
		last_filter_text = current_filter_text
		var item:TreeItem = get_root()
		if current_filter_text == "":
			while is_instance_valid(item):
				item.visible = true
				var meta = item.get_metadata(0)
				if meta != null:
					_set_collapsed(item)
				item = item.get_next_in_tree()
			return
		
		var class_items := []
		var func_items := []
		var cat_items := []
		while is_instance_valid(item):
			var meta:Variant = item.get_metadata(0)
			if meta == null:
				pass
			elif meta.get(_CLASS) == true:
				class_items.append(item)
			elif meta.get(_CATEGORY) == true:
				cat_items.append(item)
			else:
				if meta.get(_FUNC) == true:
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
			pass
		
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
		var item = get_item_at_position(get_local_mouse_position())
		if not is_instance_valid(item):
			return
		if not valid_member_item(item):
			return
		
		MemberData.set_colors()
		
		var meta:Dictionary = item.get_metadata(0)
		
		var panel = PanelContainer.new()
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)
		
		var label = RichTextLabel.new()
		vbox.add_child(label)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.bbcode_enabled = true
		label.scroll_active = false
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var access_path = meta.get(ParserKeys.ACCESS_PATH)
		var is_local = meta.get(Keys.IS_LOCAL, false)
		var is_arg = meta.get(Keys.IS_ARG, false)
		var line_idx = meta.get(Keys.LINE_IDX, -1)
		
		var member_name = get_item_member_name(item)
		
		var type_data = gdscript_parser.get_code_edit_parser().get_type_from_line(line_idx)
		if type_data and type_data.get(ParserKeys.TYPE) == "var" and member_name == "my_color":
			var type_array = type_data.get("result")
			var assignment = type_array[2]
			print("ADJ STRING::ASSIGN::", assignment)
			var tag_parser = TagParser.get_tag_parser("keys")
			if not tag_parser:
				printerr("CAN NOT GET TAG PARSER")
			if tag_parser:
				var adjusted_string = tag_parser.resolve_tagged_expression(assignment, line_idx)
				if adjusted_string:
					var type = gdscript_parser.resolve_expression_to_type(adjusted_string, line_idx)
					printerr("ADJ STRING::TYPE", member_name, "::", adjusted_string, " -> ", type)
			
		
		var class_obj:ParserClass
		var member_data
		if not is_local:
			class_obj = MemberData.get_class_obj_from_access_path(access_path) as ParserClass
			member_data = class_obj.get_member(member_name)
		else:
			var func_obj = MemberData.get_lv_func_obj_from_access_path(access_path, line_idx)
			if not is_instance_valid(func_obj):
				print("NO FUNC FOR LOCAL??")
				return
			if is_arg:
				member_data = func_obj.arguments.get(member_name)
			else:
				member_data = func_obj.local_vars.get(line_idx)
			if member_data == null:
				print("Member data null - local var")
				return
		
		var pr = Pr.new()
		var member_type:String = member_data.get(ParserKeys.MEMBER_TYPE) if member_data is Dictionary else "func"
		var is_main_class = access_path == ""
		
		if is_main_class or member_type == ParserKeys.MEMBER_TYPE_CLASS:
			var inner_access_path = ""
			if not is_main_class:
				inner_access_path = UString.dot_join(member_data.get(ParserKeys.ACCESS_PATH), member_name)
			var inner_class_obj = gdscript_parser.get_class_object(inner_access_path) as ParserClass
			MemberData.get_class_data(gdscript_parser, inner_class_obj, pr)
			label.text = pr.get_string()
			label.custom_minimum_size = _get_panel_size(pr, label)
			return panel
		
		if member_data is ParserFunc:
			var tags = meta.get(_TAGS, [])
			if not tags.is_empty():
				pr.append("[ ")
				for i in range(tags.size()):
					var t = tags[i]
					var color = MemberData.function_def_color
					match t:
						_STATIC: color = MemberData.keyword_color
						_OVERIDE: color = MemberData.member_var_color
					pr.append(t, color)
					if i < tags.size() - 1:
						pr.append(", ", MemberData.symbol_color)
				pr.append(" ]").new_line()
			
			pr.append("func" if not member_data.is_static() else "static func", MemberData.keyword_color)
			pr.append(" " + member_name, MemberData.function_def_color).append("()", MemberData.symbol_color)
			
			var function_data = member_data.get_function_data() as Dictionary
			#print("FUNC DATA::", member_name, "::", function_data)
			
			var args = function_data.get(ParserKeys.FUNC_ARGS)
			var ret_type = function_data.get(ParserKeys.FUNC_RETURN, "void")
			if ret_type == "":
				ret_type = "void"
			if not args.is_empty():
				pr.new_line().append("Arguments:")
				var arg_names = args.keys()
				for i in range(arg_names.size()):
					var arg_name = arg_names[i]
					pr.new_line().append("\t- ").append(arg_name).append(": ", MemberData.symbol_color)
					var type = args[arg_name].get(ParserKeys.TYPE, "Nil")
					if type == "":
						type = "Nil"
					if type != "Nil":
						type = gdscript_parser.resolve_expression_to_type(type, member_data.declaration_line)
					
					if type.is_absolute_path(): # this will work on "strings", but strings should be resovled by now
						type = MemberData.trim_file_path(type, gdscript_parser)
					pr.append(type, MemberData.base_type_color)
					#if i < arg_names.size() - 1:
						#pr.append(", ", MemberData.symbol_color)
			
			
			pr.new_line().append("Return: ")
			
			if ret_type.is_absolute_path():
				ret_type = MemberData.trim_file_path(ret_type, gdscript_parser)
			pr.append(ret_type, MemberData.base_type_color)
			
			var f_line = member_data.declaration_line
			pr.new_line().append("Line", MemberData.keyword_color).append(": ", MemberData.symbol_color).append("%s" % f_line)
			
		else: # non func and non class member
			var member_color:=Color.TRANSPARENT
			if is_arg:
				member_type = &"argument"
			elif is_local:
				member_type = &"local var"
			else:
				member_color = MemberData.member_var_color
			pr.append(member_type, MemberData.keyword_color).append(" " + member_name, member_color)
			
			var type:String
			if not is_local:
				type = class_obj.get_member_type(member_name)
				
			else:
				var func_obj = MemberData.get_lv_func_obj_from_access_path(access_path, line_idx) as ParserFunc
				type = func_obj.get_local_var_type(line_idx, member_name)
			
			if not type.is_empty():
				pr.append(": ", MemberData.symbol_color)
			if not type.is_absolute_path():
				pr.append(type, MemberData.base_type_color)
			else:
				var script_data = GDScriptParser.Utils.type_path_get_script_data(type)
				var script = load(script_data[0]) as GDScript
				var class_access_path = script_data[1]
				if script.get_global_name() != "" and not true: #ALERT Temp flag
					pr.append(script.get_global_name(), MemberData.user_type_color)
					if class_access_path != "":
						pr.append(".", MemberData.symbol_color)
						#if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX): #^r not sure about enum color
							#pr.append(class_access_path, MemberData.string_name_color)
						#else:
						pr.append(class_access_path, MemberData.base_type_color)
				else:
					#if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
						#pr.append(MemberData.trim_file_path(type), MemberData.string_name_color)
					#else:
					pr.append(MemberData.trim_file_path(type, gdscript_parser), MemberData.global_function_color)
			
			if line_idx == -1:
				line_idx = member_data.get(ParserKeys.LINE_INDEX)
			pr.new_line().append("Line", MemberData.keyword_color).append(": ", MemberData.symbol_color).append("%s" % line_idx)
		
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
	
	func get_item_from_access_path(access_path:String):
		return _item_dict.get(access_path)
	
	func select_path(access_path:String, scroll_tree:=false, set_caret:=false, emit_sig:=true):
		var item = _item_dict.get(access_path)
		if not is_instance_valid(item):
			return false
		#if not item.visible:
			#return false
		
		deselect_all()
		if scroll_tree:
			var item_par = item.get_parent()
			while is_instance_valid(item_par):
				item_par.collapsed = false
				item_par = item_par.get_parent()
			scroll_to_item(item, false)
		
		set_selected(item, 0)
		
		if set_caret:
			set_caret_to_member_line(item)
		
		if emit_sig:
			selected_changed.emit(false)
		return true
	
	func set_caret_to_member_line(item:TreeItem, auto_scroll:=true):
		var valid_member = valid_member_item(item)
		print("VALID::", valid_member)
		if not valid_member:
			return
		var code_edit = ScriptEditorRef.get_current_code_edit()
		var full_access_path = get_item_access_path(item)
		if full_access_path == "":
			code_edit.deselect()
			code_edit.set_caret_line(0)
			code_edit.set_caret_column(code_edit.get_line(0).length(), false)
			if not code_edit.is_caret_visible() or not auto_scroll:
				code_edit.set_line_as_first_visible(0)
			return
		
		var member_name = get_item_member_name(item)
		var item_meta = item.get_metadata(0) as Dictionary
		var is_local = item_meta.get(Keys.IS_LOCAL, false)
		var is_arg = item_meta.get(Keys.IS_ARG, false)
		var line_index:int = item_meta.get(Keys.LINE_IDX, -1)
		var member_data
		if not is_local:
			var class_obj = get_class_object_from_item(item)
			if not is_instance_valid(class_obj):
				return
			member_data = class_obj.get_member_data(member_name)
			line_index = member_data.get(ParserKeys.LINE_INDEX)
		else:
			member_data = {}
			pass #^ just use the existing data seems fine
			#var access_path = get_item_access_path(item)
			#var line_idx = item_meta.get(Keys.LINE_IDX, -1)
			#var func_obj = MemberData.get_lv_func_obj_from_access_path(access_path, line_idx)
			#if is_arg:
				#member_data = func_obj.arguments.get(member_name)
				#line_index = func_obj.declaration_line
			#elif is_local:
				#member_data = func_obj.local_vars.get(line_idx)
				#line_index = member_data.get(ParserKeys.LINE_INDEX)
		
		if is_arg:
			print(member_data)
			print(line_index)
		
		code_edit.deselect()
		code_edit.set_caret_line(line_index)
		code_edit.set_caret_column(code_edit.get_line(line_index).length(), false)
		if auto_scroll and code_edit.is_caret_visible():
			return
		
		var member_type = member_data.get(ParserKeys.MEMBER_TYPE, "")
		if member_type.ends_with("func") or member_type == ParserKeys.MEMBER_TYPE_CLASS:
			var first_line_pos = code_edit.get_scroll_pos_for_line(line_index)
			# offset the func or class to 25% position of code edit rather than 'set_line_as_first_visible'
			# feels a bit more natural if the scroll is not centered or at the top
			first_line_pos -= (code_edit.size.y / code_edit.get_line_height()) * 0.25 
			code_edit.get_v_scroll_bar().value = first_line_pos
		else:
			code_edit.set_line_as_center_visible(line_index)
	
	
	func get_item_member_name(item:TreeItem):
		var text = item.get_text(0) # this is incase I want to add static or return to text
		text = text.substr(0, text.find("[")).strip_edges()
		return text
	
	func get_item_access_path(item:TreeItem):
		var meta = item.get_metadata(0)
		if meta == null:
			return null
		return meta.get(ParserKeys.ACCESS_PATH)
	
	func get_class_object_from_item(item) -> ParserClass:
		var access_path = get_item_access_path(item)
		if access_path == null:
			return null
		return MemberData.get_class_obj_from_access_path(access_path)
	
	func valid_member_item(item:TreeItem):
		var meta = item.get_metadata(0)
		if meta is Dictionary and meta.get(_CATEGORY, false) == false:
			return true # non category items with metadata are valid
		return false
	
	
	func _set_item_icon(item:TreeItem, access_path:String, icon_name:StringName):
		var access_path_data = current_script_item_data.get_or_add(access_path, {})
		access_path_data[MemberData.LAST_ICON] = icon_name
		item.set_icon(0, _editor_theme.get_icon(icon_name, _ED_ICONS))
	
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


class MemberData:
	
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
		#print("GET ICON::", type)
		var editor_theme = EditorInterface.get_editor_theme()
		
		is_instance = type.ends_with(ParserKeys.INS_DELIM) or GDScriptParser.BuiltInChecker.is_variant_type(type)
		
		var delim_check = GDScriptParser.Utils.type_path_get_type(type, true)
		if delim_check != "":
			type = delim_check
		else:
			type = type.trim_suffix(ParserKeys.INS_DELIM)
		
		if type.is_empty():
			return &"MissingNode"
			return &"Variant"
		elif type == &"void":
			return &"Nil"
		
		
		#if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
			#return &"Enum"
		#elif type.ends_with(GDScriptParser.Keys.CALLABLE_SUFFIX):
			#return &"Callable"
		#elif type.ends_with(GDScriptParser.Keys.SIGNAL_SUFFIX):
			#return &"Signal"
		
		
		if type.is_absolute_path():
			if not is_a_gdscript_file(type):
				var ext = type.get_extension()
				match ext:
					"tscn": return &"PackedScene"
				return &"Variant"
			
				
			else:
				#print("ERROR TYPE::", type)
				var parser_data = gdscript_parser.get_parser_and_class_obj_for_script(type)
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
			
			var member_type = current_class_obj.get_class_member_type(type, true)
			if member_type == "" and type.contains("."):
				var dot = type.find(".")
				var front = type.substr(0, dot)
				var back = type.substr(dot + 1)
				member_type = GDScriptParser.TypeLookup.get_class_member_type(front, back, true)
			
			if member_type == &"TreeItem":
				print("YU")
			if member_type != "":
				if editor_theme.has_icon(member_type, _ED_ICONS):
					return member_type
				return &"Object"
			
			return &"Variant"
	
	
	static func get_main_script_name():
		var gdscript_parser = EditorGDScriptParser.get_parser()
		if gdscript_parser.get_global_class_name() != "":
			return gdscript_parser.get_global_class_name()
		return gdscript_parser.get_script_path().get_file()
	
	static func get_lv_func_obj_from_access_path(access_path:String, line_idx:int):
		var class_obj = MemberData.get_class_obj_from_access_path(UString.trim_member_access_back(access_path)) as ParserClass
		if is_instance_valid(class_obj):
			var func_name = class_obj.get_function_at_line(line_idx)
			return class_obj.get_function(func_name)
	
	static func get_class_obj_from_access_path(access_path:String):
		var class_access = ""
		if access_path.contains("."):
			class_access = UString.trim_member_access_back(access_path)
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var class_obj = gdscript_parser.get_class_object(class_access)
		return class_obj
	
	static func trim_file_path(path: String, parser: GDScriptParser) -> String:
		return path
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
		if not inherited.is_empty():
			pr.new_line().append("extends ", keyword_color)
			var inh_script = inherited[0]
			var script_data = UString.get_script_path_and_suffix(inh_script)
			if script_data.is_empty():
				pr.append("Inner Class - Cannot Find")
			else:
				var script = load(script_data[0]) as GDScript
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
	
	#static func get_current_access_path(items_dict:Dictionary):
		#var code_edit = ScriptEditorRef.get_current_code_edit()
		#if not is_instance_valid(code_edit):
			#return "null"
		#var line = code_edit.get_caret_line()
		#var current_line_text = code_edit.get_line(line)
		#var current_parser = EditorGDScriptParser.get_parser()
		#
		#var caret_context = current_parser.get_caret_context()
		#var code_context_stripped = caret_context.code_context_stripped
		#
		#var my_dict = {
			#
			#
			#
		#}
		#
		#var current_class = caret_context.current_class
		#var class_obj = caret_context.get_current_class_object() as GDScriptParser.ParserClass
		#var current_func = caret_context.current_function
		#prints("CLS::", current_class, "::FUNC::", current_func)
		#var current_access_path = current_class
		#if current_func != GDScriptParser.Keys.CLASS_BODY:
			#current_access_path = UString.dot_join(current_class, current_func)
			#if GDScriptParser.Utils.line_has_any_declaration(code_context_stripped) or code_context_stripped.begins_with("for "):
				#if not is_instance_valid(class_obj):
					#return current_access_path
				#var func_obj = class_obj.get_function(current_func)
				#if is_instance_valid(func_obj):
					#var member_data = func_obj.local_vars.get(line)
					#if member_data:
						#var member_name = member_data.get(ParserKeys.MEMBER_NAME)
						#current_access_path = UString.dot_join(current_access_path, member_name)
						#var temp_ap = current_access_path
						#var found = false
						#var count = 1
						#while items_dict.has(current_access_path):
							#var item = items_dict[current_access_path]
							#var meta = item.get_metadata(0)
							#var line_idx = meta.get(Keys.LINE_IDX, -1)
							#if line_idx == line:
								#found = true
								#break
							#current_access_path = temp_ap + "%%" + str(count)
							#count += 1
						#
						#if not found:
							#return "null"
						#return current_access_path
			#print("HERER")
			#
		#else:
			#var found = false
			#for c in class_obj.constants:
				#var data = class_obj.constants[c]
				#var dec_line = data.get(ParserKeys.LINE_INDEX)
				#if dec_line == line:
					#current_access_path = UString.dot_join(current_class, c)
					#found = true
					#break
			#if not found:
				#for m in class_obj.members:
					#var data = class_obj.members[m]
					#var dec_line = data.get(ParserKeys.LINE_INDEX)
					#if dec_line == line:
						#current_access_path = UString.dot_join(current_class, m)
						#found = true
						#break
		#
		#prints("END AP::", current_access_path)
		#return current_access_path
	
	static func get_current_access_path(items_dict:Dictionary):
		var code_edit = ScriptEditorRef.get_current_code_edit()
		if not is_instance_valid(code_edit):
			return "null"
		var line = code_edit.get_caret_line()
		var current_line_text = code_edit.get_line(line)
		var current_parser = EditorGDScriptParser.get_parser()
		
		var current_class = current_parser.get_class_at_line(line)
		var class_obj = current_parser.get_class_object(current_class) as GDScriptParser.ParserClass
		var current_func = current_parser.get_function_at_line(line)
		prints("CLS::", current_class, "::FUNC::", current_func)
		var current_access_path = current_class
		if current_func != GDScriptParser.Keys.CLASS_BODY:
			current_access_path = UString.dot_join(current_class, current_func)
			if GDScriptParser.Utils.line_has_any_declaration(current_line_text.strip_edges()):
				if not is_instance_valid(class_obj):
					return current_access_path
				var func_obj = class_obj.get_function(current_func)
				if is_instance_valid(func_obj):
					var member_data = func_obj.local_vars.get(line)
					if member_data:
						var member_name = member_data.get(ParserKeys.MEMBER_NAME)
						current_access_path = UString.dot_join(current_access_path, member_name)
						var temp_ap = current_access_path
						var found = false
						var count = 1
						while items_dict.has(current_access_path):
							var item = items_dict[current_access_path]
							var meta = item.get_metadata(0)
							var line_idx = meta.get(Keys.LINE_IDX, -1)
							if line_idx == line:
								found = true
								break
							current_access_path = temp_ap + "%%" + str(count)
							count += 1
						
						if not found:
							return "null"
						return current_access_path
			print("HERER")
			
		else:
			var found = false
			for c in class_obj.constants:
				var data = class_obj.constants[c]
				var dec_line = data.get(ParserKeys.LINE_INDEX)
				if dec_line == line:
					current_access_path = UString.dot_join(current_class, c)
					found = true
					break
			if not found:
				for m in class_obj.members:
					var data = class_obj.members[m]
					var dec_line = data.get(ParserKeys.LINE_INDEX)
					if dec_line == line:
						current_access_path = UString.dot_join(current_class, m)
						found = true
						break
		
		prints("END AP::", current_access_path)
		return current_access_path
	
	static func get_lv_access_path(item_dict:Dictionary, item_access_path:String):
		var count = 1
		var temp = item_access_path
		while item_dict.has(item_access_path):
			item_access_path = temp + "%%" + str(count)
			count += 1
		return item_access_path
	

class Keys:
	const ITEM = &"item"
	const NAME = &"name"
	const CLASS_OBJ = &"class_obj"
	const IS_INSTANCE = &"is_instance"
	const IS_LOCAL = &"is_local"
	const IS_ARG = &"is_arg"
	const LINE_IDX = &"line_idx"
	

class EditorSet:
	const FOLLOW_CURSOR = &"plugin/script_outline/follow_cursor"
