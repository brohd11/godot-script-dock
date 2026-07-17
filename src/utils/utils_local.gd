const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const Options = UtilsRemote.Options

const ScriptListManager = UtilsRemote.ScriptListManager
const UGDScript = UtilsRemote.UGDScript
const EditorColors = UtilsRemote.EditorColors

const CacheHelper = UtilsRemote.CacheHelper
const ItemKeys = UtilsRemote.FSTree.ItemKeys

const FileData = FileSystemSingleton.FileData

const GenericFileContext = preload("res://addons/script_outline/src/utils/generic_file_context.gd")

static func get_file_data(file_path:String, script_data_cache:Dictionary):
	var data = CacheHelper.get_cached_data(file_path, script_data_cache)
	
	if data == null:
		data = {}
	
	var script_type_file = file_path.get_extension() in ScriptListManager.get_text_file_types()
	
	var has_icon = _has_icon(data, ItemKeys.ICON)
	var has_preview = _has_icon(data, ItemKeys.PREVIEW)
	
	if has_icon and (has_preview or script_type_file):
		return data
	
	data[ItemKeys.PATH] = file_path
	data[ItemKeys.ICON_COLOR] = Color.WHITE
	
	if file_path.get_extension() == "gd":
		if not data.has(&"is_tool"):
			data[&"is_tool"] = UGDScript.FileRead.get_is_tool(file_path)
		if data.get(&"is_tool", false):
			data[ItemKeys.ICON_COLOR] = EditorColors.get_tool_script_color()
	
	
	
	if not has_icon:
		var filesystem_singleton = FileSystemSingleton.get_instance()
		data[ItemKeys.ICON] = filesystem_singleton.get_type_icon(file_path)
	
	if not script_type_file and not has_preview:
		var prev = FileSystemSingleton.get_preview(file_path)
		if prev is Dictionary:
			data[ItemKeys.PREVIEW] = prev.get(FileData.Preview.PREVIEW)
	
	#print(file_path,"::TOOL::", data[ScriptTreeKeys.SCRIPT_IS_TOOL] )
	CacheHelper.store_data(file_path, data, script_data_cache, [file_path])
	return data

static func _has_icon(data:Dictionary, key:StringName) -> bool:
	return data.has(key) and data[key] is Texture


static func set_item_list_sb(item_list:ItemList):
	var sb:StyleBoxFlat = item_list.get_theme_stylebox("panel").duplicate()
	sb.content_margin_right = 0
	item_list.add_theme_stylebox_override("panel", sb)

static func get_script_tabs_node():
	return Singletons.CheckInstance.get_instance("ScriptTabSingleton")
