extends Control

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const GDScriptParser = EditorGDScriptParser.GDScriptParser
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const ParserKeys = GDScriptParser.Keys

const PluginButton = UtilsRemote.PluginButton

const UString = UtilsRemote.UString
const Pr = UString.PrintRich

const EditorColors = UtilsRemote.EditorColors
const UClassDetail = UtilsRemote.UClassDetail

var test:NewScript3.Test



const TreeHelperBase = UtilsRemote.TreeHelperBase
var tree_helper:TreeHelperBase # thinking I don't actually need this, not a ton of overlap

const MAIN_SCRIPT_LABEL = "Script.Main"

var _main_margin:MarginContainer
var _main_vbox:VBoxContainer

var toolbar:HBoxContainer
var dock_button:Button


var outline_tree:OutlineTree


enum MemberType {
	VAR,
	STATIC_VAR,
	FUNC,
	STATIC_FUNC,
	ENUM,
	CONST,
	CLASS,
	SIGNAL,
}


var _updated:=false


func _ready() -> void:
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.EDITOR_SCRIPT_CHANGED, _on_editor_script_changed)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.VALIDATE_SCRIPT, _on_validate)
	
	_main_margin = ALibEditor.UIHelpers.Margin.new_plugin_margin_container()
	add_child(_main_margin)
	_main_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_main_vbox = VBoxContainer.new()
	_main_margin.add_child(_main_vbox)
	
	
	toolbar = HBoxContainer.new()
	_main_vbox.add_child(toolbar)
	
	dock_button = PluginButton.new().get_button()
	toolbar.add_child(dock_button)
	
	
	outline_tree = OutlineTree.new()
	_main_vbox.add_child(outline_tree)
	outline_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline_tree.hide_root = true
	
	



func _on_editor_script_changed(script:GDScript):
	if not is_instance_valid(script):
		outline_tree.clear()
		return
	
	
	
	# if new script build tree



func _on_validate():
	outline_tree.build_tree.call_deferred()
	pass



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
	
	
	static func get_type_icon(type:String, gdscript_parser:GDScriptParser, is_instance:=false) -> Texture2D:
		var editor_theme = EditorInterface.get_editor_theme()
		if type.is_empty():
			return editor_theme.get_icon(&"Nil", &"EditorIcons")
		elif type == &"void":
			return editor_theme.get_icon(&"Nil", &"EditorIcons")
		elif type.begins_with("res://"):
			if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
				return editor_theme.get_icon(&"Enum", &"EditorIcons")
			else:
				var parser_data = gdscript_parser.get_parser_and_class_obj_for_script(type)
				var class_obj = parser_data.get(ParserKeys.GET_CLASS_OBJ) as ParserClass
				var icon_name:StringName
				if is_instance:
					icon_name = class_obj.script_base_type if class_obj.script_base_type != &"RefCounted" else &"Object"
				else:
					if class_obj.access_path == "":
						icon_name = &"GDScript"
					else:
						icon_name = &"GDScriptInternal"
				return editor_theme.get_icon(icon_name, &"EditorIcons")
		else:
			if editor_theme.has_icon(type, &"EditorIcons"):
				return editor_theme.get_icon(type, &"EditorIcons")
			else:
				return editor_theme.get_icon(&"Variant", &"EditorIcons")
	
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
		
		return EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")
	
	static func get_main_script_name():
		var gdscript_parser = EditorGDScriptParser.get_parser()
		if gdscript_parser.get_global_class_name() != "":
			return gdscript_parser.get_global_class_name()
		return gdscript_parser.get_script_path().get_file()
	
	static func trim_file_path(path:String):
		var trimmed = path.trim_prefix("res://")
		var slice_count = trimmed.get_slice_count("/")
		if slice_count < 3:
			return path
		var res_dir = trimmed.get_slice("/", 0)
		var file_name = trimmed.get_file()
		
		return "res://" + res_dir.path_join("...").path_join(file_name)

	
	static func get_class_data(gdscript_parser:GDScriptParser, class_obj:ParserClass, pr:Pr):
		if class_obj.access_path == "":
			pr.append("script ", keyword_color).append(trim_file_path(class_obj.main_script_path), global_function_color)
			var global_name = gdscript_parser.get_global_class_name()
			if global_name != "":
				pr.new_line().append("class_name ", keyword_color).append(global_name, user_type_color)
		else:
			pr.append("class ", keyword_color).append(class_obj.access_path, base_type_color)
		
		var inherited = class_obj.get_inherited_scripts()
		if not inherited.is_empty():
			pr.new_line().append("extends ", keyword_color)
			var inh_script = inherited[0]
			print(inh_script)
			var script_data = UString.get_script_path_and_suffix(inh_script)
			if not script_data.is_empty():
				var script = load(script_data[0]) as GDScript
				var class_path = script_data[1]
				print(script)
				if script.get_global_name() != "":
					pr.append(script.get_global_name(), user_type_color)
					if class_path != "":
						pr.append(".")
						pr.append(class_path, base_type_color)
				else:
					pr.append(MemberData.trim_file_path(inh_script), global_function_color)
			else:
				pr.append("Inner Class - Cannot Find")
			
		
		var script_base_type = class_obj.script_base_type
		pr.new_line().append("Base Type: ").append(script_base_type, base_type_color)
		return pr
	
	



class Nested extends NewScript2.InnerClass:
	pass
	
	
	static func test():
		return "" == ""
	
	class Nested:
		extends Node
		func _enter_tree() -> void:
			pass
		pass
	

class OutlineTree extends Tree:
	
	func _ready() -> void:
		item_mouse_selected.connect(_on_item_mouse_selected)
	
	
	
	func build_tree():
		MemberData.set_colors()
		
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("BUILD OUTLINE")
		clear()
		
		var class_items = {}
		print("BUILDING")
		
		var root = create_item()
		
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var classes = gdscript_parser.get_classes()
		print(classes)
		for access_path in classes:
			var class_obj = gdscript_parser.get_class_object(access_path) as ParserClass
			
			var item_parent:TreeItem
			item_parent = class_items.get(access_path)
			if not is_instance_valid(item_parent):
				var last_access = ""
				if access_path.contains("."):
					last_access = UString.trim_member_access_back(access_path)
				item_parent = create_item(class_items.get(last_access))
				var _c_name = MemberData.get_main_script_name() if access_path == "" else UString.get_member_access_back(access_path)
				item_parent.set_text(0, _c_name)
				item_parent.set_icon(0, MemberData.get_icon(MemberType.CLASS))
				var meta = {ParserKeys.ACCESS_PATH: last_access}
				item_parent.set_metadata(0, meta)
				if access_path != "":
					class_items[access_path] = item_parent
			
			print(item_parent, "::PATH::",access_path)
			var prop_parent = item_parent
			var const_parent = item_parent
			var func_parent = item_parent
			if true: # add categories
				prop_parent = create_item(item_parent)
				prop_parent.set_text(0, "Properties")
				prop_parent.set_icon(0, MemberData.get_icon(MemberType.VAR))
				const_parent = create_item(item_parent)
				const_parent.set_text(0, "Constants")
				const_parent.set_icon(0, MemberData.get_icon(MemberType.CONST))
				func_parent = create_item(item_parent)
				func_parent.set_text(0, "Methods")
				func_parent.set_icon(0, MemberData.get_icon(MemberType.FUNC))
			
			var class_base_type = class_obj.script_base_type
			
			for m in class_obj.members.keys():
				
				var member_data = class_obj.members[m]
				var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
				if member_type == ParserKeys.MEMBER_TYPE_FUNC or member_type == ParserKeys.MEMBER_TYPE_STATIC_FUNC:
					continue
				
				var item = create_item(prop_parent)
				item.set_text(0, m)
				
				var type = class_obj.get_member_type(m)
				var icon = MemberData.get_type_icon(type, gdscript_parser, true)
				item.set_icon(0, icon)
				
				#item.set_icon(0, MemberData.get_icon(MemberType.VAR))
				var meta = {ParserKeys.ACCESS_PATH: access_path}
				item.set_metadata(0, meta)
			
			
			for c in class_obj.constants.keys():
				var member_data = class_obj.constants.get(c)
				if not member_data.get(ParserKeys.ACCESS_PATH).begins_with(access_path):
					continue
				var item = create_item(const_parent)
				item.set_text(0, c)
				
				var type = class_obj.get_member_type(c)
				var icon = MemberData.get_type_icon(type, gdscript_parser)
				item.set_icon(0, icon)
				
				#item.set_icon(0, MemberData.get_icon(MemberType.CONST))
				var meta = {ParserKeys.ACCESS_PATH: access_path}
				item.set_metadata(0, meta)
			
			var virtual_methods = {}
			for method_data in ClassDB.class_get_method_list(class_base_type):
				if method_data.flags & METHOD_FLAG_VIRTUAL > 0:
					virtual_methods[method_data.name] = true
			
			for f in class_obj.functions.keys():
				var item = create_item(func_parent)
				item.set_text(0, f)
				var func_obj = class_obj.get_function(f) as ParserFunc
				var type = func_obj.get_return_type()
				var icon = MemberData.get_type_icon(type, gdscript_parser)
				item.set_icon(0, icon)
				
				if virtual_methods.has(f):
					item.set_custom_color(0, MemberData.function_def_color)
				
				#item.set_icon(0, MemberData.get_icon(MemberType.FUNC))
				var meta = {ParserKeys.ACCESS_PATH: access_path}
				item.set_metadata(0, meta)
			
			if true:
				if prop_parent.get_child_count() == 0:
					prop_parent.free()
				if const_parent.get_child_count() == 0:
					const_parent.free()
				if func_parent.get_child_count() == 0:
					func_parent.free()
		
		t.stop()





		#_updated = true # use this to build only when needed, so validate and script change don't double build
	
	func _on_item_mouse_selected(mouse_pos:Vector2, btn_idx:int):
		print("CLICKED ", btn_idx)
		var item = get_item_at_position(mouse_pos)
		var member_name = item.get_text(0)
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
			
			
	
	
	
	
	
	func _make_custom_tooltip(for_text: String) -> Object:
		var item = get_item_at_position(get_local_mouse_position())
		if not is_instance_valid(item):
			return
		MemberData.set_colors()
		var meta = item.get_metadata(0)
		if meta == null:
			return
		
		
		
		var panel = PanelContainer.new()
		
		
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)
		#vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		
		var label = RichTextLabel.new()
		vbox.add_child(label)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.bbcode_enabled = true
		label.scroll_active = false
		
		
		#vbox.add_child(label)
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		
		var gdscript_parser = EditorGDScriptParser.get_parser()
		var access_path = meta.get(ParserKeys.ACCESS_PATH)
		var class_obj = gdscript_parser.get_class_object(access_path) as ParserClass
		
		var pr = Pr.new()
		
		var member_name = item.get_text(0)
		if member_name == MemberData.get_main_script_name():
			var inner_class_obj = gdscript_parser.get_class_object()
			MemberData.get_class_data(gdscript_parser, inner_class_obj, pr)
			label.text = pr.get_string()
			label.custom_minimum_size = _get_panel_size(pr, label)
			return panel
		
		
		
		var display_text = ""
		var member_data = class_obj.get_member(member_name)
		if member_data is ParserFunc:
			pr.append("func" if not member_data.is_static() else "static func", EditorColors.get_syntax_color(EditorColors.SyntaxColor.KEYWORD))
			pr.append(" " + member_name, EditorColors.get_syntax_color(EditorColors.SyntaxColor.FUNCTION_DEFINITION))
			pr.append("()", EditorColors.get_syntax_color(EditorColors.SyntaxColor.SYMBOL))
			
			
			var function_data = member_data.get_function_data()
			var args = function_data.get(ParserKeys.FUNC_ARGS)
			var ret_type = function_data.get(ParserKeys.FUNC_RETURN, "void")
			if ret_type == "":
				ret_type = "void"
			if not args.is_empty():
				pr.new_line().append("Arguments:")
				
				var arg_names = args.keys()
				for i in range(arg_names.size()):
					var arg_name = arg_names[i]
					pr.new_line().append("\t- ").append(arg_name).append(":", MemberData.symbol_color)
					var type = args[arg_name].get(ParserKeys.TYPE, "Nil")
					if type == "":
						type = "Nil"
					pr.append(type, MemberData.base_type_color)
					if i < arg_names.size() - 1:
						pr.append(", ", MemberData.symbol_color)
			
		
			#pr.append(") -> ", EditorColors.get_syntax_color(EditorColors.SyntaxColor.SYMBOL))
			pr.new_line().append("Return: ")
			if ret_type.begins_with("res://"):
				ret_type = MemberData.trim_file_path(ret_type)
			pr.append(ret_type, MemberData.base_type_color)
		else:
			
			var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
			if member_type == ParserKeys.MEMBER_TYPE_CLASS:
				var inner_access_path = UString.dot_join(member_data.get(ParserKeys.ACCESS_PATH), member_name)
				var inner_class_obj = gdscript_parser.get_class_object(inner_access_path) as ParserClass
				MemberData.get_class_data(gdscript_parser, inner_class_obj, pr)
			else:
				pr.append(member_type, MemberData.keyword_color).append(" " + member_name, MemberData.member_var_color)
				pr.append(": ", MemberData.symbol_color)
				var type = class_obj.get_member_type(member_name)
				if not type.begins_with("res://"):
					pr.append(type, MemberData.base_type_color)
				else:
					#var script_parser = gdscript_parser.get_parser_for_path(type)
					var script_data = UString.get_script_path_and_suffix(type)
					
					var script = load(script_data[0]) as GDScript
					print("PATH TO LOAD::", script_data[0], "::IS SCRIPT::", script is GDScript)
					var class_access_path = script_data[1]
					if script.get_global_name() != "":
						pr.append(script.get_global_name(), MemberData.user_type_color)
						pr.append(".", MemberData.symbol_color)
						#if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX): #^r not sure about enum color
							#pr.append(class_access_path, MemberData.string_name_color)
						#else:
						pr.append(class_access_path, MemberData.base_type_color)
					else:
						#if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
							#pr.append(MemberData.trim_file_path(type), MemberData.string_name_color)
						#else:
						pr.append(MemberData.trim_file_path(type), MemberData.global_function_color)
					
		
		print("FOR ", for_text, "::PATH::", access_path)
		
		label.text = pr.get_string()
		label.custom_minimum_size = _get_panel_size(pr, label)
		
		return panel
	
	
	func _get_panel_size(pr:Pr, label:RichTextLabel):
		var largest_string = pr.get_longest_line()
		print(largest_string)
		var line_count = max(label.text.count("\n") + 1, 2) # minimum 2 lines otherwise single line is cut off
		var font = label.get_theme_font("font")
		var string_size = font.get_string_size(largest_string)
		var x_size = string_size.x * 1.1 # multiplier for small strings seems to be necessary for some reason
		var y_size = string_size.y * (line_count)
		var final_size = Vector2(x_size, y_size)
		print(final_size)
		return final_size
	
	
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
	
	pass
