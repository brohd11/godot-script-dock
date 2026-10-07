extends EditorContextMenuPlugin

const SLOT = CONTEXT_SLOT_SCRIPT_EDITOR_CODE


const PopupHelper = UtilR.Nodes.PopupMenus.PathHelper
const Param = PopupHelper.ParamKeys
const Options = preload("uid://dxdxq2n3imf4q") #! resolve UtilR.Nodes.PopupMenus.Options

const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve ALibEditor.Singleton.EditorGDScriptParser
const VarInsertType = preload("uid://ci11vn1timw1r") #! resolve ALibEditor.Utils.UGDScript.VarInsertType

const INFER_MENU_PATH = "Infer Type"

const PRIORITY = 10

var _var_line_data:= {}

func _popup_menu(paths: PackedStringArray) -> void:
	var script_edit:CodeEdit = Engine.get_main_loop().root.get_node(paths[0]);
	var items:Dictionary = get_valid_items(script_edit)
	if items.is_empty():
		return
	
	PopupWrapper.ContextPlugin.create_items(self, script_edit, items, _callback)


func get_valid_items(script_editor:CodeEdit) -> Dictionary:
	var sel:ContextMenuSingleton.Selection = ContextMenuSingleton.get_script_editor_selection(script_editor)
	var line_data:Dictionary = sel.get_line_data()
	if line_data.is_empty():
		return {}
	
	var parser:GDScriptParser = EditorGDScriptParser.get_parser()
	var code_edit_parser:GDScriptParser.CodeEditParser = parser.get_code_edit_parser()
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

func _callback(script_editor:CodeEdit, menu_path:String) -> void:
	if menu_path == INFER_MENU_PATH:
		_infer_type(script_editor, _var_line_data)

func _infer_type(script_editor:CodeEdit, untyped_line_data:Dictionary) -> void:
	var parser:GDScriptParser = EditorGDScriptParser.get_parser()
	VarInsertType.insert_types(parser, script_editor, untyped_line_data)
