extends MarginContainer

const UtilsRemote = preload("res://addons/script_dock/src/utils/utils_remote.gd")

const SettingHelperEditor = UtilsRemote.SettingHelperEditor
const PluginButton = UtilsRemote.PluginButton
const LineSubmit = UtilsRemote.LineSubmit
const TabBarContainer = UtilsRemote.TabBarContainer

const UFile = UtilsRemote.UFile
const UName = UtilsRemote.UName
const UResource = UtilsRemote.UResource
const UTexture = UtilsRemote.UTexture
const UWindow = UtilsRemote.UWindow

const EditorIcons = UtilsRemote.EditorIcons

const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const ScriptList = preload("res://addons/script_dock/src/file_tabs/script_list.gd")
const ScriptTree = preload("res://addons/script_dock/src/file_tabs/script_tree.gd")
const ScriptCollection = preload("res://addons/script_dock/src/file_tabs/script_collection.gd")

enum TitleMode {
	TITLES,
	BASE_ICONS,
	ALL_ICONS,
}

enum TabType {
	LIST,
	TREE,
	COLLECTION,
}

var setting_helper:SettingHelperEditor

var _dock_data:Dictionary
var _script_data_cache:Dictionary = {}

var _vbox:VBoxContainer

var tab_bar_container:TabBarContainer
var script_list:ScriptList
var script_tree:ScriptTree
var base_tabs:= []

var _tab_icon:Texture2D
var _tab_icon_list:PackedStringArray

var _title_mode:TitleMode = TitleMode.BASE_ICONS

func get_dock_data() -> Dictionary:
	_update_tabs_data()
	var data = {}
	data[Keys.CURRENT_TAB] = tab_bar_container.get_tab_bar().current_tab
	return data

func set_dock_data(data:Dictionary) -> void:
	_dock_data = data
	_build_nodes()
	tab_bar_container.set_current_tab(_dock_data.get(Keys.CURRENT_TAB, 0))


func _ready() -> void:
	_script_data_cache = ScriptDock.get_script_data_cache()
	_build_nodes()
	_tab_icon = EditorIcons.get_icon_white("TabBar")
	
	setting_helper = SettingHelperEditor.new()
	var default = PackedStringArray(["Node", "Node2D", "Node3D", "Folder"])
	setting_helper.subscribe_property(self, &"_tab_icon_list", EditorSet.DEFAULT_TAB_ICONS, default)
	setting_helper.initialize()

func _build_nodes():
	if is_instance_valid(_vbox):
		return
	
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	_vbox = VBoxContainer.new()
	add_child(_vbox)
	
	tab_bar_container = TabBarContainer.new()
	_vbox.add_child(tab_bar_container)
	
	_add_saved_tabs()
	if not is_instance_valid(script_list):
		script_list = _new_tab(TabType.LIST)
	if not is_instance_valid(script_tree):
		script_tree = _new_tab(TabType.TREE)
	
	script_tree.immutable = true
	
	base_tabs = [script_list, script_tree]
	
	var tab_bar = tab_bar_container.get_tab_bar()
	tab_bar.drag_to_rearrange_enabled = true
	tab_bar.select_with_rmb = true
	tab_bar.tab_close_pressed.connect(_on_tab_close_pressed)
	tab_bar_container.tab_changed.connect(_on_tab_changed)
	tab_bar.tab_rmb_clicked.connect(_on_tab_rmb_clicked)
	
	_set_title_mode(_title_mode)


func _add_saved_tabs():
	var tab_container_data = get_tabs_data()
	var tab_idxes = tab_container_data.keys()
	tab_idxes.sort()
	for key in tab_idxes:
		var data = tab_container_data[key]
		var base_tab = data.get(Keys.BASE_TAB, false)
		var tab_type = data.get(Keys.TAB_TYPE, TabType.TREE) as TabType
		var tab_data = data.get(Keys.TAB_DATA, {})
		tab_data[Keys.TAB_ICON] = data.get(Keys.TAB_ICON)
		tab_data[Keys.TAB_TITLE] = data.get(Keys.TAB_TITLE)
		
		var tab_control:Control = _new_tab(tab_type, tab_data)
		if base_tab:
			if tab_type == TabType.LIST:
				script_list = tab_control
			elif tab_type == TabType.TREE:
				script_tree = tab_control


func get_options():
	var options = Options.new()
	
	options.add_option("New/Collection", _new_collection, ["Add", "ThemeSelectAll"])
	options.add_option("New/Tree", _new_tree.bind("res://"), ["Add", "FileTree"])
	options.add_enum_radio("Titles", _set_title_mode, TitleMode, _title_mode, [_tab_icon, null])
	return options


func _on_tab_rmb_clicked(tab:int):
	var control = tab_bar_container.get_tab_control(tab)
	var options = Options.new()
	if not control in base_tabs:
		if _title_mode != TitleMode.ALL_ICONS:
			options.add_option("Rename", _on_tab_rename.bind(tab), ["Rename"])
		
		var icon_base_icon = EditorInterface.get_editor_theme().get_icon(&"Image", &"EditorIcons")
		for full_icon_name in _tab_icon_list:
			var icon_display = full_icon_name
			var icon_or_name = full_icon_name
			if icon_or_name.is_absolute_path():
				icon_display = full_icon_name.get_file()
				icon_or_name = load(full_icon_name)
				if not icon_or_name is Texture2D:
					icon_or_name = EditorInterface.get_editor_theme().get_icon(&"MissingNode", &"EditorIcons")
			
			options.add_option("Set Icon/" + icon_display, _on_tab_set_icon.bind(tab, full_icon_name), [icon_base_icon, icon_or_name])
		
		if not _tab_icon_list.is_empty():
			options.add_separator("", "Set Icon")
		options.add_option("Set Icon/Editor Icon..", _on_tab_set_custom_icon.bind(tab), [icon_base_icon, "Load"])
		options.add_option("Set Icon/Open..", _on_tab_set_custom_icon.bind(tab), [icon_base_icon, "Load"])
		options.add_option("Set Icon/Reset", _on_tab_set_icon.bind(tab, _tab_get_default_icon(tab_bar_container.get_tab_control(tab))), ["Reload"])
	
	if control.has_method(&"get_options"):
		options.merge(control.get_options())
	
	ScriptDock.get_right_click_handler().display_popup(options)


func _on_tab_rename(tab:int):
	var tab_bar = tab_bar_container.get_tab_bar()
	var tab_rect = _get_tab_rect(tab)
	var line_submit = LineSubmit.new(self, tab_rect, false)
	var resp:Dialogs.Response = await line_submit.handled
	if resp.cancelled or resp.payload == "":
		return
	
	var new_name = resp.payload
	tab_bar_container.set_tab_meta_value(tab, Keys.TAB_TITLE, new_name)
	tab_bar.set_tab_title(tab, new_name)
	
	_set_title_mode()
	update_tabs_data()

func _on_tab_set_custom_icon(tab:int):
	var tab_rect = _get_tab_rect(tab)
	var line_submit = LineSubmit.new(self, tab_rect, false)
	var resp:Dialogs.Response = await line_submit.handled
	if resp.cancelled or resp.payload == "":
		return
	var new_name = resp.payload
	
	var editor_thm = EditorInterface.get_editor_theme()
	if editor_thm.has_icon(new_name, &"EditorIcons"):
		_on_tab_set_icon(tab, new_name)
	elif FileAccess.file_exists(new_name):
		_on_tab_set_icon(tab, new_name)
	else:
		printerr("Could not find icon: ", new_name)

func _tab_get_default_icon(tab_control:Control):
	if tab_control is ScriptCollection:
		return &"ThemeSelectAll"
	elif tab_control is ScriptTree:
		if tab_control.root_dir == "res://":
			return "FileTree"
		else:
			return "Folder"
	return "Script"

func _on_tab_set_icon(tab:int, icon_name:String):
	_tab_set_icon(tab, icon_name)
	update_tabs_data()

func _tab_set_icon(tab:int, icon_name:String):
	var is_file = icon_name.is_absolute_path()
	var icon_texture = _get_icon(icon_name)
	if icon_texture is Texture2D:
		if is_file:
			icon_texture = UTexture.resize_texture(icon_texture, int(16 * EditorInterface.get_editor_scale()))
		tab_bar_container.get_tab_bar().set_tab_icon(tab, icon_texture)
		tab_bar_container.set_tab_meta_value(tab, Keys.TAB_ICON, icon_name)

func _get_icon(icon_name:String):
	var editor_theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(icon_name, &"EditorIcons"):
		return editor_theme.get_icon(icon_name, &"EditorIcons")
	elif FileAccess.file_exists(icon_name):
		return load(icon_name)


func _set_title_mode(title_mode:TitleMode=_title_mode):
	var tab_bar = tab_bar_container.get_tab_bar()
	for i in range(tab_bar.tab_count):
		if title_mode == TitleMode.ALL_ICONS:
			tab_bar.set_tab_title(i, "")
		elif title_mode == TitleMode.BASE_ICONS:
			var control = tab_bar_container.get_tab_control(i)
			var title = ""
			if not control in base_tabs:
				title = _get_tab_title(i)
			tab_bar.set_tab_title(i, title)
		elif title_mode == TitleMode.TITLES:
			tab_bar.set_tab_title(i, _get_tab_title(i))
	_title_mode = title_mode


func _on_tab_changed(_tab:int):
	var current_tab = tab_bar_container.get_current_tab_control()
	var tab_bar = tab_bar_container.get_tab_bar()
	if current_tab in base_tabs:
		tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER
	else:
		tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY

func _on_tab_close_pressed(tab:int):
	var control = tab_bar_container.get_tab_control(tab)
	control.queue_free()
	update_tabs_data()


func _new_collection():
	var new_collection = _new_tab(TabType.COLLECTION, {})
	_set_title_mode()
	update_tabs_data()
	return new_collection


func _new_tree(root_dir:String):
	var new_tab = _new_tab(TabType.TREE, {ScriptTree.PersistentData.ROOT_DIR: root_dir})
	_set_title_mode(_title_mode)
	update_tabs_data()
	return new_tab

func _new_tab(tab_type:TabType, tab_data:Dictionary={}):
	var tab_control:Control
	var icon = null
	var icon_str = tab_data.get(Keys.TAB_ICON)
	if icon_str != null:
		if icon_str is String:
			icon = _get_icon(icon_str)
	
	if tab_type == TabType.LIST:
		tab_control = ScriptList.new()
	elif tab_type == TabType.TREE:
		var root_dir = tab_data.get(ScriptTree.PersistentData.ROOT_DIR, "res://")
		tab_control = ScriptTree.new()
		if root_dir == "res://":
			tab_control.name = "Tree"
		else:
			tab_control.name = root_dir.trim_suffix("/").get_file()
		
		tab_control.create_new_tab.connect(_new_tree)
	
	elif tab_type == TabType.COLLECTION:
		tab_control = ScriptCollection.new()
		tab_control.collection_update.connect(_on_collection_update)
	
	if &"_script_data_cache" in tab_control:
		tab_control._script_data_cache = _script_data_cache
	
	if tab_control.has_method(&"set_tab_data"):
		tab_control.set_tab_data(tab_data)
	
	if icon == null:
		icon = EditorInterface.get_editor_theme().get_icon(_tab_get_default_icon(tab_control), &"EditorIcons")
	
	tab_control.name = UName.incremental_name_check_in_nodes(tab_control.name, tab_bar_container.get_tab_parent())
	tab_bar_container.add_tab(tab_control, icon)
	
	var current_idx = tab_bar_container.get_tab_count() - 1
	var tab_title = tab_data.get(Keys.TAB_TITLE)
	if tab_title != null:
		tab_bar_container.set_tab_meta_value(current_idx, Keys.TAB_TITLE, tab_title)
	if icon_str != null:
		tab_bar_container.set_tab_meta_value(current_idx, Keys.TAB_ICON, icon_str)
	return tab_control


func get_tabs_data():
	if not FileAccess.file_exists(Keys.CONTAINER_TABS_PATH):
		return {}
	else:
		return UFile.read_from_json(Keys.CONTAINER_TABS_PATH)

func update_tabs_data():
	await get_tree().process_frame
	_update_tabs_data()

func _update_tabs_data():
	var data = {}
	for i in range(tab_bar_container.get_tab_count()):
		var tab_meta = {}
		var control = tab_bar_container.get_tab_control(i)
		var title = _get_tab_title(i)
		tab_meta[Keys.TAB_TITLE] = title
		var icon = tab_bar_container.get_tab_meta_value(i, Keys.TAB_ICON)
		if icon != null:
			tab_meta[Keys.TAB_ICON] = icon
		
		if control in base_tabs:
			tab_meta[Keys.BASE_TAB] = true
		
		if control is ScriptList:
			tab_meta[Keys.TAB_TYPE] = TabType.LIST
		elif control is ScriptTree:
			tab_meta[Keys.TAB_TYPE] = TabType.TREE
		elif control is ScriptCollection:
			tab_meta[Keys.TAB_TYPE] = TabType.COLLECTION
		
		if control.has_method(&"get_tab_data"):
			tab_meta[Keys.TAB_DATA] = control.get_tab_data()
		
		data[i] = tab_meta
	
	DirAccess.make_dir_recursive_absolute(Keys.CONTAINER_TABS_PATH.get_base_dir())
	UFile.write_to_json(data, Keys.CONTAINER_TABS_PATH)

func _get_tab_title(tab:int):
	var title = tab_bar_container.get_tab_meta_value(tab, Keys.TAB_TITLE)
	if title == null:
		var control = tab_bar_container.get_tab_control(tab)
		title = control.name
	return title

func _get_tab_rect(tab:int):
	var tab_bar = tab_bar_container.get_tab_bar()
	var tab_pos = UWindow.get_control_absolute_position(tab_bar)
	var tab_rect = tab_bar.get_tab_rect(tab)
	tab_rect.position += tab_pos
	return tab_rect

func _on_collection_update(col_tab:ScriptCollection):
	var col_name = col_tab.current_collection.get_collection_name()
	col_tab.name = UName.incremental_name_check_in_nodes(col_name, tab_bar_container.get_tab_parent())
	var idx = col_tab.get_index()
	tab_bar_container.get_tab_bar().set_tab_title(idx, _get_tab_title(idx))

func _on_show_in_tree(path:String):
	show_in_tree(path)

func show_in_tree(path:String):
	tab_bar_container.set_current_tab(script_tree.get_index())
	script_tree.tree_helper.select_paths([path])
	script_tree.tree_helper.show_tree_item(script_tree.tree_helper.get_tree_item(path))

class Keys:
	const CURRENT_TAB = &"file_tabs.current_tab"
	const TAB_TITLE_MODE = &"file_tabs.tab_title_mode"
	
	const TAB_TITLE = &"tab_title"
	const TAB_ICON = &"tab_icon"
	const TAB_DATA = &"tab_data"
	
	const BASE_TAB = &"base_tab"
	const TAB_TYPE = &"tab_type"
	
	
	const CONTAINER_TABS_PATH = &"user://addons/script_dock/container_tabs.json"

class EditorSet:
	const DEFAULT_TAB_ICONS = &"plugin/script_dock/tab_icons"
	
	const DEFAULT_TAB_ICONS_PROP_INFO = {
		
	}
