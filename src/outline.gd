extends MarginContainer

const PLUGIN_EXPORTED = false

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const GDScriptParser = EditorGDScriptParser.GDScriptParser
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const ParserKeys = GDScriptParser.Keys

const UString = UtilsRemote.UString
const Pr = UString.PrintRich

const EditorColors = UtilsRemote.EditorColors
const UClassDetail = UtilsRemote.UClassDetail

const RightClickHandler = ClickHandlers.RightClickHandler
const Options = ALibRuntime.Popups.Options


const _ED_ICONS = &"EditorIcons"

const _CLASS = &"_class"
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

var _dock_data:Dictionary

var right_click_handler:RightClickHandler

var _vbox:VBoxContainer
var toolbar:HBoxContainer
var filter_line_edit:LineEdit

var outline_tree:OutlineTree
var _tree_script_item_data:= {}

var _current_script_path:String
var _current_script_file_mod_time:int=-1


var _updated:=false


func get_dock_data() -> Dictionary:
	var data = {}
	return data

func set_dock_data(data:Dictionary) -> void:
	_dock_data = data


func _ready() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_file_system_changed, 1)
	
	#ScriptEditorRef.subscribe(ScriptEditorRef.Event.EDITOR_SCRIPT_CHANGED, _on_editor_script_changed)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_editor_text_changed)
	
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
	
	outline_tree = OutlineTree.new()
	_vbox.add_child(outline_tree)
	outline_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline_tree.hide_root = true
	
	
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


func _on_parse_completed(): # move this here, ensures the build is after the parsing
	#print("ON PARSE COMPLETE")
	_build_tree()


func _build_tree():
	if _current_script_path == "" or not _current_script_path.ends_with(".gd"):
		outline_tree.clear()
		_set_cache_dirty()
		return
	outline_tree.build_tree.call_deferred()


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
	
	var last_filter_text:String = ""
	var current_filter_text:String = ""
	var is_filtering:bool = false
	
	var sort_mode:SortMode = SortMode.NONE
	
	func _ready() -> void:
		item_mouse_selected.connect(_on_item_mouse_selected)
		item_collapsed.connect(_on_item_collapsed)
		
		allow_rmb_select = true
	
	
	func build_tree():
		MemberData.set_colors()
		
		if not cache_dirty:
			return
		
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("BUILD OUTLINE")
		var editor_theme = EditorInterface.get_editor_theme()
		
		clear()
		var class_items = {}
		var _root = create_item()
		var gdscript_parser = EditorGDScriptParser.get_parser()
		#print("OUTLINE TREE")
		#print(gdscript_parser)
		#print(gdscript_parser._script_path)
		#print(gdscript_parser.get_classes())
		
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
				item_parent = create_item(class_items.get(last_access))
				var _c_name = MemberData.get_main_script_name() if access_path == "" else UString.get_member_access_back(access_path)
				item_parent.set_text(0, _c_name)
				var icon_name = class_base_type
				if not editor_theme.has_icon(icon_name, _ED_ICONS): # icon_name == "RefCounted" or not editor_theme.has_icon(icon_name, _ED_ICONS):
					icon_name = "Object"
				item_parent.set_icon(0, editor_theme.get_icon(icon_name, _ED_ICONS))
				var meta = {ParserKeys.ACCESS_PATH: last_access, _CLASS:true}
				item_parent.set_metadata(0, meta)
				_set_collapsed(item_parent, access_path != "")
				if access_path != "":
					class_items[access_path] = item_parent
			
			var prop_parent = item_parent
			var const_parent = item_parent
			var func_parent = item_parent
			if true: # add a flag for categories?
				const_parent = create_item(item_parent)
				const_parent.set_text(0, "Constants")
				const_parent.set_icon(0, MemberData.get_icon(MemberType.CONST))
				const_parent.set_metadata(0, {ParserKeys.ACCESS_PATH: access_path, _CATEGORY:true})
				_set_collapsed(const_parent)
				
				prop_parent = create_item(item_parent)
				prop_parent.set_text(0, "Properties")
				prop_parent.set_icon(0, MemberData.get_icon(MemberType.VAR))
				prop_parent.set_metadata(0, {ParserKeys.ACCESS_PATH: access_path, _CATEGORY:true})
				_set_collapsed(prop_parent)
				
				func_parent = create_item(item_parent)
				func_parent.set_text(0, "Methods")
				func_parent.set_icon(0, MemberData.get_icon(MemberType.FUNC))
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
				var item = create_item(const_parent)
				item.set_text(0, c)
				
				var type = class_obj.get_member_type(c)
				var icon = MemberData.get_type_icon(type, gdscript_parser, class_obj)
				item.set_icon(0, icon)
				
				#item.set_icon(0, MemberData.get_icon(MemberType.CONST))
				var meta = {ParserKeys.ACCESS_PATH: access_path}
				item.set_metadata(0, meta)
				_set_collapsed(item)
			
			
			
			var member_names = class_obj.members.keys()
			member_names.sort_custom(sort_by_line_index.bind(class_obj.members))
			if sort_mode == SortMode.ALPHA or sort_mode == SortMode.METHOD_TYPE_ALPHA:
				member_names.sort()
			
			for m in member_names:
				var member_data = class_obj.members[m]
				var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
				if member_type == ParserKeys.MEMBER_TYPE_FUNC or member_type == ParserKeys.MEMBER_TYPE_STATIC_FUNC:
					continue
				
				var item = create_item(prop_parent)
				item.set_expand_right(0, true)
				var item_text = m
				if member_type == ParserKeys.MEMBER_TYPE_STATIC_VAR:
					item_text += " [static]"
				item.set_text(0, item_text)
				
				var type = class_obj.get_member_type(m)
				var icon = MemberData.get_type_icon(type, gdscript_parser, class_obj, true)
				item.set_icon(0, icon)
				
				#item.set_icon(0, MemberData.get_icon(MemberType.VAR))
				var meta = {ParserKeys.ACCESS_PATH: access_path}
				item.set_metadata(0, meta)
				_set_collapsed(item)
			
			
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
				var item = create_item(func_parent)
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
				
				#item.set_icon(0, MemberData.get_icon(MemberType.FUNC))
				var type = func_obj.get_return_type()
				var icon = MemberData.get_type_icon(type, gdscript_parser, class_obj)
				item.set_icon(0, icon)
				item.set_text(0, f)
				if not item_tags.is_empty():
					item.set_suffix(0, "[%s]" % ", ".join(item_tags))
				
				var meta = {ParserKeys.ACCESS_PATH: access_path, _TAGS: item_tags}
				item.set_metadata(0, meta)
				_set_collapsed(item)
			
			if true: # add a flag for categories?
				if prop_parent.get_child_count() == 0:
					prop_parent.free()
				if const_parent.get_child_count() == 0:
					const_parent.free()
				if func_parent.get_child_count() == 0:
					func_parent.free()
		
		cache_dirty = false
		filter_items()
		
		if not PLUGIN_EXPORTED:
			t.stop()
			pass
	
	
	func get_sorted_methods(methods: Array, virtual: Dictionary, inherited: Dictionary, statics: Dictionary) -> Array:
		var arr_virtual = []
		var arr_inherited = []
		var arr_static = []
		var arr_other = []
		
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
		
		var result = []
		result.append_array(arr_virtual)
		result.append_array(arr_inherited)
		result.append_array(arr_static)
		result.append_array(arr_other)
		return result
	
	func sort_by_line_index(a:String, b:String, dict:Dictionary):
		var a_data = dict[a]
		var b_data = dict[b]
		return a_data.get(ParserKeys.LINE_INDEX) < b_data.get(ParserKeys.LINE_INDEX)
	
	
	func _on_item_mouse_selected(mouse_pos:Vector2, btn_idx:int):
		var item = get_item_at_position(mouse_pos)
		var valid_member = valid_member_item(item)
		if not valid_member:
			return
		
		var member_name = get_item_member_name(item)
		if member_name == MemberData.get_main_script_name():
			var code_edit = ScriptEditorRef.get_current_code_edit()
			code_edit.set_line_as_first_visible(0)
		
		var class_obj = get_class_object_from_item(item)
		if not is_instance_valid(class_obj):
			return
		
		var member_data = class_obj.get_member_data(member_name)
		if btn_idx == MOUSE_BUTTON_LEFT:
			var line_index = member_data.get(ParserKeys.LINE_INDEX)
			var code_edit = ScriptEditorRef.get_current_code_edit()
			var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
			if member_type.ends_with("func") or member_type == "class":
				code_edit.set_line_as_first_visible(line_index)
			else:
				code_edit.set_line_as_center_visible(line_index)
	
	
	func filter_items():
		is_filtering = current_filter_text != ""
		if current_filter_text == "" and last_filter_text == "":
			return
		last_filter_text = current_filter_text
		var item = get_root()
		if current_filter_text == "":
			while is_instance_valid(item):
				item.visible = true
				var meta = item.get_metadata(0)
				if meta != null:
					_set_collapsed(item)
				item = item.get_next_in_tree()
			return
		
		var class_items = []
		var cat_items = []
		while is_instance_valid(item):
			var meta = item.get_metadata(0)
			if meta == null:
				pass
			elif meta.get(_CLASS) == true:
				class_items.append(item)
			elif meta.get(_CATEGORY) == true:
				cat_items.append(item)
			else:
				var text = item.get_text(0)
				item.visible = current_filter_text.is_subsequence_ofn(text)
			
			item = item.get_next_in_tree()
		
		for cat_item in cat_items:
			cat_item.visible = false
			for c in cat_item.get_children():
				if c.visible:
					cat_item.collapsed = false
					cat_item.visible = true
					break
		
		for class_item in class_items:
			class_item.visible = false
			for c in class_item.get_children():
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
		
		var meta = item.get_metadata(0)
		
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
		var class_obj = gdscript_parser.get_class_object(access_path) as ParserClass
		
		var pr = Pr.new()
		
		var member_name = get_item_member_name(item)
		var member_data = class_obj.get_member(member_name)
		var member_type = member_data.get(ParserKeys.MEMBER_TYPE) if member_data is Dictionary else "func"
		
		var is_main_class = member_name == MemberData.get_main_script_name()
		
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
			var tags = meta.get(_TAGS, "")
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
			
			var function_data = member_data.get_function_data()
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
			#if ret_type.begins_with("res://"):
			if ret_type.is_absolute_path():
				ret_type = MemberData.trim_file_path(ret_type, gdscript_parser)
			pr.append(ret_type, MemberData.base_type_color)
			
		else: # non func and non class member
			pr.append(member_type, MemberData.keyword_color).append(" " + member_name, MemberData.member_var_color)
			
			var type = class_obj.get_member_type(member_name)
			if not type.is_empty():
				pr.append(": ", MemberData.symbol_color)
			if not type.is_absolute_path():
				pr.append(type, MemberData.base_type_color)
			else:
				var script_data = UString.get_script_path_and_suffix(type)
				var script = load(script_data[0]) as GDScript
				var class_access_path = script_data[1]
				if script.get_global_name() != "":
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
	
	func get_item_member_name(item:TreeItem):
		var text = item.get_text(0) # this is incase I want to add static or return to text
		text = text.substr(0, text.find("[")).strip_edges()
		return text
	
	func get_item_access_path(item:TreeItem):
		var meta = item.get_metadata(0)
		if meta == null:
			return null
		var access_path = meta.get(ParserKeys.ACCESS_PATH)
		return access_path
	
	func get_class_object_from_item(item) -> ParserClass:
		var access_path = get_item_access_path(item)
		if access_path == null:
			return null
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var class_obj = gdscript_parser.get_class_object(access_path)
		return class_obj
	
	func valid_member_item(item:TreeItem):
		var meta = item.get_metadata(0)
		if meta is Dictionary and meta.get(_CATEGORY, false) == false:
			return true # non category items with metadata are valid
		return false
	
	func _set_collapsed(item:TreeItem, default:=false):
		var access_path = get_item_access_path(item)
		var _name = get_item_member_name(item)
		var access_path_data = current_script_item_data.get_or_add(access_path, {})
		item.collapsed = access_path_data.get(_name, default)
	
	func _on_item_collapsed(item:TreeItem):
		if is_filtering:
			return
		var access_path = get_item_access_path(item)
		var _name = get_item_member_name(item)
		var access_path_data = current_script_item_data.get_or_add(access_path, {})
		access_path_data[_name] = item.collapsed


class MemberData:
	
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
	
	static func get_type_icon(type:String, gdscript_parser:GDScriptParser, current_class_obj:ParserClass, is_instance:=false) -> Texture2D:
		#print("GET ICON::", type)
		var editor_theme = EditorInterface.get_editor_theme()
		if type.is_empty():
			return editor_theme.get_icon(&"Nil", _ED_ICONS)
		elif type == &"void":
			return editor_theme.get_icon(&"Nil", _ED_ICONS)
		
		if type.is_absolute_path():
			if not is_a_gdscript_file(type):
				var ext = type.get_extension()
				match ext:
					"tscn": return editor_theme.get_icon(&"PackedScene", _ED_ICONS)
				return editor_theme.get_icon(&"Variant", _ED_ICONS)
			elif type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
				return editor_theme.get_icon(&"Enum", _ED_ICONS)
				
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
				return editor_theme.get_icon(icon_name, _ED_ICONS)
		else:
			if editor_theme.has_icon(type, _ED_ICONS):
				return editor_theme.get_icon(type, _ED_ICONS)
			
			var member_type = current_class_obj.get_class_member_type(type, true)
			if member_type == "" and type.contains("."):
				var dot = type.find(".")
				var front = type.substr(0, dot)
				var back = type.substr(dot + 1)
				member_type = GDScriptParser.TypeLookup.get_class_member_type(front, back, true)
			
			if member_type != "" and editor_theme.has_icon(member_type, _ED_ICONS):
				return editor_theme.get_icon(member_type, _ED_ICONS)
			
			return editor_theme.get_icon(&"Variant", _ED_ICONS)
	
	
	static func get_icon(member_type:MemberType):
		var icon_name:String
		match member_type:
			MemberType.VAR: icon_name = &"MemberProperty"
			MemberType.STATIC_VAR: icon_name = &"MemberProperty"
			MemberType.FUNC: icon_name = &"MemberMethod"
			MemberType.STATIC_FUNC: icon_name = &"MemberMethod"
			MemberType.CONST: icon_name = &"MemberConstant"
			MemberType.ENUM: icon_name = &"Enum"
			MemberType.CLASS: icon_name = &"Object"
			MemberType.SIGNAL: icon_name = &"MemberSignal"
		
		return EditorInterface.get_editor_theme().get_icon(icon_name, _ED_ICONS)
	
	
	static func get_main_script_name():
		var gdscript_parser = EditorGDScriptParser.get_parser()
		if gdscript_parser.get_global_class_name() != "":
			return gdscript_parser.get_global_class_name()
		return gdscript_parser.get_script_path().get_file()
	
	static func trim_file_path(path: String, parser: GDScriptParser) -> String:
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
		return pr
