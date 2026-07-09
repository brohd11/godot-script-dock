extends FSTree

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const FSTree = UtilsRemote.FSTree
const UResource = UtilsRemote.UResource
const UGDScript = UtilsRemote.UGDScript

const ScriptListManager = UtilsRemote.ScriptListManager

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const EditorColors = UtilsRemote.EditorColors
const CacheHelper = UtilsRemote.CacheHelper


const NEW_TAB = "New Tab"

var script_list_manager:ScriptListManager

var right_click_handler:RightClickHandler

var immutable:bool = false
var script_tree:Tree

var _script_data_cache:= {}

signal create_new_tab(selected_path:String)

func _init() -> void:
	multi_select = false

func _on_fs_ready():
	filter_line_edit.placeholder_text = "Filter Scripts"
	
	filesystem_singleton.filesystem_changed.connect(_on_file_system_changed, 1)
	_on_file_system_changed()
	
	_build_tree()

func get_options():
	
	var options = Options.new()
	var flat_icon
	if _flat_view:
		flat_icon = "AnimationTrackList"
	else:
		flat_icon = "FileTree"
	
	options.add_option("Flat View (%s)" % _flat_view, _set_flat_view.bind(not _flat_view), [flat_icon])
	var show_all = file_extensions.is_empty()
	options.add_option("Show All Files Types (%s)" % show_all, _set_show_all_files.bind(not show_all), ["File"])
	options.add_option("Show Empty Dirs (%s)" % show_empty_dirs, _set_show_empty_dirs.bind(not show_empty_dirs), ["Folder"])
	options.add_option("Show Favorites (%s)" % show_favorites, _set_show_favorites.bind(not show_favorites), [FileSystemSingleton.get_favorites_icon()])
	return options


func set_tab_data(data:Dictionary):
	set_persistent_data(data)

func get_tab_data() -> Dictionary:
	return get_persistent_data()


func _set_show_all_files(state:bool):
	if state:
		file_extensions = []
	else:
		file_extensions = ScriptListManager.get_text_file_types()
	_refresh_files_and_tree()


func _custom_right_click_menu(items:Dictionary, selected_path:String, selected_paths:Array):
	if immutable:
		items["pre"].clear()
	
	if selected_path.ends_with("/"):
		items["pre"][NEW_TAB] = {
				PopupWrapper.ItemParams.ICON: ["TabContainer"],
				PopupWrapper.ItemParams.ICON_COLOR: [Color(5,5,5)],
				PopupWrapper.ItemParams.METADATA: {"selected": selected_path}
			}

func _handle_custom_popup_id(id, popup):
	var menu_path = PopupWrapper.PopupHelper.parse_menu_path(id, popup)
	var meta = PopupWrapper.PopupHelper.parse_metadata(id, popup)
	var selected = meta.get("selected")
	match menu_path:
		NEW_TAB: _on_new_tab_pressed(selected)


func _get_file_data(file_path:String):
	var data = CacheHelper.get_cached_data(file_path, _script_data_cache)
	
	if data == null:
		data = {}
	
	data[ItemKeys.PATH] = file_path
	data[ItemKeys.ICON_COLOR] = Color.WHITE
	
	
	if file_path.get_extension() == "gd":
		var is_tool = data.get(&"is_tool", UGDScript.FileRead.get_is_tool(file_path))
		if is_tool:
			data[ItemKeys.ICON_COLOR] = EditorColors.get_tool_script_color()
	
	#data.
	if not data.has(ItemKeys.ICON):
		data[ItemKeys.ICON] = filesystem_singleton.get_type_icon(file_path)
	if not data.has(ItemKeys.PREVIEW) and not file_path.get_extension() in ScriptListManager.get_text_file_types():
		var prev = FileSystemSingleton.get_preview(file_path)
		if prev is Dictionary:
			data[ItemKeys.PREVIEW] = prev.get(FileData.Preview.PREVIEW)
	
	#print(file_path,"::TOOL::", data[ScriptTreeKeys.SCRIPT_IS_TOOL] )
	CacheHelper.store_data(file_path, data, _script_data_cache, [file_path])
	return data

func _on_item_activated():
	_select_or_open_in_script_list()

func _on_item_left_clicked():
	return
	_select_or_open_in_script_list()

func _on_item_right_clicked():
	var selection = _get_selection()
	var selected = selection.selected
	if selected == null:
		return
	if selected == FileData.FAVORITES_META:
		return
	
	if Input.is_key_pressed(KEY_CTRL) and selected.get_extension() in ScriptListManager.get_text_file_types():
		_select_or_open_in_script_list(true)
	else: # ideally put a open in new script tab into fs menu
		FileSystemSingleton.show_right_click_menu(self, selected, [selected])


func _on_new_tab_pressed(selected_path:String):
	create_new_tab.emit(selected_path)



func _select_or_open_in_script_list(right_click:=false):
	var selected = tree_helper.get_selected_paths().duplicate().pop_front()
	#print(selected)
	if selected != null:
		if not selected.get_extension() in ScriptListManager.get_text_file_types():
			FileSystemSingleton.activate_path(selected)
		else:
			var sl_idx = script_list_manager.get_script_index_or_open(selected, filesystem_singleton)
			if sl_idx != -1:
				script_list_manager.activate_item_by_idx(sl_idx)
				if right_click:
					var location = DisplayServer.mouse_get_position()
					script_list_manager.right_click_by_idx(sl_idx, location)







class ScriptTreeKeys:
	const SCRIPT_DATA = &"script_data"
	
	const SCRIPT_PATH = &"script_path"
	const SCRIPT_IS_TOOL = &"script_is_tool"
	const SCRIPT_ICON = &"script_icon"
	
	const ROOT_DIR = &"script_tree.root_dir"
	const FLAT_VIEW = &"script_tree.flat_view"
	const SHOW_ALL_FILES = &"script_tree.show_all_files"
