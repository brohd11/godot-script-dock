extends FSTree

const UtilsLocal = preload("res://addons/script_outline/src/utils/utils_local.gd")
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

var immutable:bool = false
var script_tree:Tree

var _script_data_cache:= {}

signal create_new_tab(selected_path:String)

func _init() -> void:
	#multi_select = false # maybe leave multi select on?
	pass

func _on_fs_ready():
	filter_line_edit.placeholder_text = "Filter Scripts"
	
	filesystem_singleton.filesystem_changed.connect(_on_file_system_changed, 1)
	_on_file_system_changed()
	
	_build_tree()

func get_options():
	var options = Options.new()
	var flat_icon = "FileTree" if _flat_view else "AnimationTrackList"
	options.add_option("Settings/Flat View (%s)" % _flat_view, _set_flat_view.bind(not _flat_view), ["Tools", flat_icon])
	
	var show_all = file_extensions.is_empty()
	options.add_option("Settings/Show All Files Types (%s)" % show_all, _set_show_all_files.bind(not show_all), ["File"])
	options.add_option("Settings/Show Empty Dirs (%s)" % show_empty_dirs, _set_show_empty_dirs.bind(not show_empty_dirs), ["Folder"])
	if root_dir == "res://":
		options.add_option("Settings/Show Favorites (%s)" % show_favorites, _set_show_favorites.bind(not show_favorites), [FileSystemSingleton.get_favorites_icon()])
	
	options.add_option("Settings/Filter Full Path (%s)" % filter_full_path, _set_filter_full_paths.bind(not filter_full_path), ["RegEx"])
	options.add_option("Settings/Draw Line Color (%s)" % draw_alternate_line_colors, _set_alt_line_color.bind(not draw_alternate_line_colors), ["TripleBar"])
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
	if selected_paths.size() > 1:
		items["pre"].clear()
		return
	
	if selected_path.ends_with("/"):
		var copy = items["pre"].duplicate()
		items["pre"].clear() # place new tab at top, allows clearing above
		
		items["pre"][NEW_TAB] = {
				PopupWrapper.ItemParams.ICON: ["TabContainer"],
				PopupWrapper.ItemParams.ICON_COLOR: [Color(5,5,5)],
				PopupWrapper.ItemParams.METADATA: {"selected": selected_path}
			}
		for key in copy.keys():
			items["pre"][key] = copy[key]
		

func _handle_custom_popup_id(id, popup):
	var menu_path = PopupWrapper.PopupHelper.parse_menu_path(id, popup)
	var meta = PopupWrapper.PopupHelper.parse_metadata(id, popup)
	var selected = meta.get("selected")
	match menu_path:
		NEW_TAB: _on_new_tab_pressed(selected)


func _get_file_data(file_path:String):
	return UtilsLocal.get_file_data(file_path, _script_data_cache)


#func _on_item_activated():
	#_select_or_open_in_script_list()

func _on_item_left_clicked():
	return # overide so it deosn't select for import
	#_select_or_open_in_script_list()


func _on_new_tab_pressed(selected_path:String):
	create_new_tab.emit(selected_path)



func _select_or_open_in_script_list(right_click:=false):
	var selected = tree_helper.get_selected_paths().duplicate().pop_front()
	if not right_click:
		FileSystemSingleton.activate_path(selected)
		return
	
	# should be dead logic now...no more script menu in this tab
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
