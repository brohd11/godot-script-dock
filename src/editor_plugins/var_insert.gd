extends "res://addons/_lib/popup_wrapper/src/context_menu.gd" #! ext PopupWrapper.ContextMenu
#! gdp-strip-cast GDScriptParser, CodeEditParser

const SLOT = CONTEXT_SLOT_SCRIPT_EDITOR_CODE


const PopupHelper = UtilR.Nodes.PopupMenus.PathHelper
const Param = PopupHelper.ParamKeys
const Options = UtilR.Nodes.PopupMenus.Options

const VarInsertType = EditorParser.Other.VarInsertType
const EditorGDScriptParser = EditorParser.EditorGDScriptParser
const CheckInstance = Singletons.CheckInstance
const Selection = UtilR.Nodes.CodeEdits.Selection

const INFER_MENU_PATH = "Infer Type"

const PRIORITY = 10
const CodeEditParser = GDScriptParser.CodeEditParser

var _var_line_data:= {}

func _get_menu_options(data) -> void:
	var script_edit:CodeEdit = PopupWrapper.Slots.code_edit(data)
	var items:Dictionary = get_valid_items(script_edit)
	if items.is_empty():
		return
	
	PopupWrapper.ContextPlugin.create_items(self, data, items, _callback)


func get_valid_items(script_editor:CodeEdit) -> Dictionary:
	var sel = _get_selection(script_editor)
	var line_data:Dictionary = sel.get_line_data()
	if line_data.is_empty():
		return {}
	
	var parser:GDScriptParser = EditorGDScriptParser.get_parser()
	var code_edit_parser:CodeEditParser = parser.get_code_edit_parser()
	var untyped_line_data:Dictionary = {}
	var line_idxes:Array = line_data.keys()
	for i:int in line_idxes:
		var line_type_data = VarInsertType.check_type_in_line(code_edit_parser, i)
		if line_type_data:
			untyped_line_data[i] = line_type_data
	
	#print(untyped_line_data)
	var options:Options = Options.new()
	if not untyped_line_data.is_empty():
		options.add_option(INFER_MENU_PATH, null, null, {Param.PRIORITY: PRIORITY})
		_var_line_data = untyped_line_data
	
	return options.get_options()

func _callback(data, menu_path:String) -> void:
	var script_editor:CodeEdit = PopupWrapper.Slots.code_edit(data)
	if menu_path == INFER_MENU_PATH:
		_infer_type(script_editor, _var_line_data)

func _infer_type(script_editor:CodeEdit, untyped_line_data:Dictionary) -> void:
	var parser:GDScriptParser = EditorGDScriptParser.get_parser()
	VarInsertType.insert_types(parser, script_editor, untyped_line_data)


# util
func _get_selection(script_editor:CodeEdit):
	if CheckInstance.check_valid("ContextMenuSingleton"):
		var sing = CheckInstance.get_instance("ContextMenuSingleton")
		return sing.get_script_editor_selection(script_editor)
	return Selection.new(script_editor)
