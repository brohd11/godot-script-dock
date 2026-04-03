extends VBoxContainer

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const TreeHelperBase = UtilsRemote.TreeHelperBase
const UResource = UtilsRemote.UResource
const GDScriptFileAccess = UtilsRemote.GDScriptFileAccess

const ScriptListManager = UtilsRemote.ScriptListManager

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const CacheHelper = UtilsRemote.CacheHelper

const TEXT_FILE_TYPES = ["gd", "json", "cfg", "txt", "ini", "md"]

var script_list_manager:ScriptListManager
var filesystem_singleton:FileSystemSingleton

var right_click_handler:RightClickHandler

var script_tree:Tree
var tree_helper:ScriptTreeHelper

var filter_line_edit:LineEdit

var current_files:PackedStringArray = []

var root_dir = "res://"

var _flat_view:=false



var _script_data:= {}

signal create_new_tab(selected_path:String)


func _ready() -> void:
	
	filter_line_edit = LineEdit.new()
	add_child(filter_line_edit)
	filter_line_edit.text_changed.connect(_on_filter_line_text_changed)
	filter_line_edit.right_icon = EditorInterface.get_editor_theme().get_icon(&"Search", &"EditorIcons")
	filter_line_edit.clear_button_enabled = true
	filter_line_edit.placeholder_text = "Filter Scripts"
	
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	script_tree = Tree.new()
	script_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_tree.select_mode = Tree.SELECT_SINGLE
	script_tree.allow_rmb_select = true
	add_child(script_tree)
	
	script_list_manager = ScriptListManager.get_instance()
	
	filesystem_singleton = FileSystemSingleton.get_instance()
	filesystem_singleton.filesystem_changed.connect(_on_file_system_changed, 1)
	
	tree_helper = ScriptTreeHelper.new(script_tree, null, null, null, false)
	tree_helper.filesystem_singleton = filesystem_singleton
	tree_helper.script_list_manager = script_list_manager
	
	tree_helper.mouse_left_clicked.connect(_on_item_left_clicked)
	tree_helper.mouse_right_clicked.connect(_on_item_right_clicked)
	
	_on_file_system_changed()

func get_options():
	var options = Options.new()
	
	options.add_option("Flat View (%s)" % _flat_view, _set_flat_view.bind(not _flat_view), [])
	
	return options

func _set_flat_view(state:bool):
	_flat_view = state
	_build_tree()


func _on_file_system_changed():
	_script_data = {}
	
	_set_current_files()
	_build_tree()

func set_root_dir(root:String):
	root_dir = root
	_set_current_files()
	_build_tree()

func _set_current_files():
	if root_dir == "res://":
		current_files = filesystem_singleton.get_paths_of_ext(TEXT_FILE_TYPES)
	else:
		current_files.clear()
		var files = filesystem_singleton.get_files_in_dir(root_dir)
		for f in files:
			if f.get_extension() in TEXT_FILE_TYPES:
				current_files.append(f)


func _build_tree():
	tree_helper.clear_items()
	
	tree_helper.clear_items()
	
	var root = script_tree.create_item()
	var root_text = root_dir
	if root_text != "res://":
		root_text = root_text.trim_suffix("/").get_file()
	root.set_text(0, root_text)
	root.set_icon(0, tree_helper.folder_icon)
	root.set_icon_modulate(0, tree_helper.folder_color)
	#tree_helper.
	for f in current_files:
		var script_data = _get_script_data(f)
		if not _flat_view:
			var _last_item = tree_helper.new_file_path(f, root_dir, script_data)
		else:
			var item = script_tree.create_item(root)
			item.set_text(0, f.get_file())
			item.set_tooltip_text(0, f)
			item.set_metadata(0, {TreeHelperBase.Keys.METADATA_PATH: f})
			tree_helper.set_item_icon(item, script_data)
			
	
	_update_tree_items()


func _get_script_data(file_path:String):
	var cached = CacheHelper.get_cached_data(file_path, _script_data)
	if cached != null:
		return cached
	
	var data = {}
	data[ScriptTreeKeys.SCRIPT_PATH] = file_path
	data[ScriptTreeKeys.SCRIPT_IS_TOOL] = GDScriptFileAccess.get_is_tool(file_path)
	data[ScriptTreeKeys.SCRIPT_ICON] = filesystem_singleton.get_type_icon(file_path)
	#print(file_path,"::TOOL::", data[ScriptTreeKeys.SCRIPT_IS_TOOL] )
	CacheHelper.store_data(file_path, data, _script_data, [file_path])
	return data

func _on_item_left_clicked():
	var i = select_or_open_script()
	if i == -1: return
	script_list_manager.activate_item_by_idx(i)

func _on_item_right_clicked():
	var i = select_or_open_script()
	if i != -1:
		var location = DisplayServer.mouse_get_position()
		script_list_manager.activate_item_by_idx(i)
		script_list_manager.right_click_by_idx(i, location)
		return
	
	var selected = tree_helper.get_selected_paths().duplicate().pop_front()
	if selected == "res://" or selected == null:
		return
	print(selected)
	var options = Options.new()
	options.add_option("New Tab", _on_new_tab_pressed.bind(selected), ["TabContainer"])
	right_click_handler.display_popup(options)

func _on_new_tab_pressed(selected_path:String):
	create_new_tab.emit(selected_path)

func select_or_open_script():
	var selected = tree_helper.get_selected_paths().duplicate().pop_front()
	if selected == null: return -1
	return script_list_manager.get_script_index_or_open(selected)

func _on_filter_line_text_changed(new_text:String):
	_update_tree_items()
	pass

func _update_tree_items():
	tree_helper.update_tree_items(_is_filtering(), _filter_text)

func _filter_text(to_filter:String):
	return filter_line_edit.text.is_subsequence_of(to_filter)

func _is_filtering():
	return filter_line_edit.text != ""


class ScriptTreeHelper extends TreeHelperBase:
	
	var tool_color:Color
	
	var script_list_manager:ScriptListManager
	var filesystem_singleton:FileSystemSingleton
	var thumbnail_size:float = 16
	var show_files:bool = true

	func set_thumbnail_size():
		thumbnail_size = 16 * EditorInterface.get_editor_scale()


	func _set_folder_icon_img():
		var base_ctrl = EditorInterface.get_base_control()
		tool_color = base_ctrl.get_theme_color(&"accent_color", &"Editor")
		tool_color.s = min(tool_color.s * 1.5, 1.0)
		folder_icon = base_ctrl.get_theme_icon(&"Folder", &"EditorIcons")
		folder_color = base_ctrl.get_theme_color(&"folder_icon_color", &"FileDialog")

	func _set_folder_icon(file_path, slice_item):
		var icon = filesystem_singleton.get_type_icon(file_path)
		slice_item.set_icon(0, icon)
		var color = filesystem_singleton.get_folder_color(file_path)
		if color:
			slice_item.set_icon_modulate(0, color)
		var bg_color = filesystem_singleton.get_background_color(file_path)
		if bg_color:
			slice_item.set_custom_bg_color(0, bg_color)
	
	# for use with flat view
	func set_item_icon(item:TreeItem, file_data:Dictionary):
		_set_item_icon(item, file_data)
	
	func _set_item_icon(last_item:TreeItem, file_data:Dictionary):
		last_item.set_icon(0, file_data.get(ScriptTreeKeys.SCRIPT_ICON))
		if file_data.get(ScriptTreeKeys.SCRIPT_IS_TOOL, false) == true:
			last_item.set_icon_modulate(0, tool_color)
		else:
			last_item.set_icon_modulate(0, Color.WHITE)



class ScriptTreeKeys:
	const SCRIPT_DATA = &"script_data"
	
	const SCRIPT_PATH = &"script_path"
	const SCRIPT_IS_TOOL = &"script_is_tool"
	const SCRIPT_ICON = &"script_icon"
