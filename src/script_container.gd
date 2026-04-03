extends MarginContainer

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")


const PluginButton = UtilsRemote.PluginButton

const UFile = UtilsRemote.UFile
const UResource = UtilsRemote.UResource
const GDScriptFileAccess = UtilsRemote.GDScriptFileAccess
const TabBarContainer = UtilsRemote.TabBarContainer

const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const ScriptList = preload("res://addons/script_outline/src/script_list/script_list.gd")
const ScriptTree = preload("res://addons/script_outline/src/script_list/script_tree.gd")
const ScriptCollection = preload("res://addons/script_outline/src/script_list/collection.gd")

enum TitleMode {
	TITLES,
	BASE_ICONS,
	ALL_ICONS,
}


var right_click_handler:RightClickHandler

var _vbox:VBoxContainer

var tab_bar_container:TabBarContainer
var script_list:ScriptList
var base_tabs:= []


var _title_mode:TitleMode = TitleMode.BASE_ICONS

func _ready() -> void:
	
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	_vbox = VBoxContainer.new()
	add_child(_vbox)
	
	tab_bar_container = TabBarContainer.new()
	_vbox.add_child(tab_bar_container)
	
	script_list = ScriptList.new()
	tab_bar_container.add_tab(script_list, EditorInterface.get_editor_theme().get_icon(&"Script", &"EditorIcons"))
	
	var base_tree = _new_tree("res://")
	
	base_tabs = [script_list, base_tree]
	
	var tab_bar = tab_bar_container.get_tab_bar()
	tab_bar.drag_to_rearrange_enabled = true
	tab_bar.tab_close_pressed.connect(_on_tab_close_pressed)
	tab_bar_container.tab_changed.connect(_on_tab_changed)
	tab_bar.tab_rmb_clicked.connect(_on_tab_rmb_clicked)
	
	tab_bar_container.set_current_tab(0)
	
	_set_title_mode(_title_mode)


func get_margins():
	return [self]

func get_options():
	var options = Options.new()
	
	options.add_option("Add Collection", _new_collection, ["ThemeSelectAll"])
	
	options.add_enum_radio("Titles", _set_title_mode, TitleMode, _title_mode, [])
	
	return options

func _on_tab_rmb_clicked(tab:int):
	var control = tab_bar_container.get_tab_control(tab)
	if control in base_tabs:
		return
	var options = Options.new()
	if _title_mode != TitleMode.ALL_ICONS:
		options.add_option("Rename", _on_tab_rename.bind(tab), ["Rename"])
	
	var icon_base_icon = EditorInterface.get_editor_theme().get_icon(&"Image", &"EditorIcons")
	for icon_name in ["Node", "Node2D", "Node3D", "Folder"]:
		options.add_option("Set Icon/" + icon_name, _on_tab_set_icon.bind(tab, icon_name), [icon_base_icon, icon_name])
	options.add_option("Set Icon/Editor Icon", _on_tab_set_custom_icon.bind(tab), [icon_base_icon, "Add"])
	options.add_option("Set Icon/Open..", _on_tab_set_custom_icon.bind(tab), [icon_base_icon, "Load"])
	
	if control.has_method(&"get_options"):
		options.merge(control.get_options())
	
	right_click_handler.display_popup(options)

func _on_tab_rename(tab:int):
	# line submit, add as tab_meta_value for saving
	pass

func _on_tab_set_custom_icon(tab:int):
	# get a path here or icon name?
	pass

func _on_tab_set_icon(tab:int, icon_name:String):
	var icon_texture
	var editor_theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(icon_name, &"EditorIcons"):
		icon_texture = editor_theme.get_icon(icon_name, &"EditorIcons")
	elif FileAccess.file_exists(icon_name):
		icon_texture = load(icon_name)
	if icon_texture is Texture2D:
		tab_bar_container.get_tab_bar().set_tab_icon(tab, icon_texture)
		tab_bar_container.set_tab_meta_value(tab, Keys.TAB_ICON, icon_name)
	

func _set_title_mode(title_mode:TitleMode=_title_mode):
	var tab_bar = tab_bar_container.get_tab_bar()
	for i in range(tab_bar.tab_count):
		if title_mode == TitleMode.ALL_ICONS:
			tab_bar.set_tab_title(i, "")
		elif title_mode == TitleMode.BASE_ICONS:
			var control = tab_bar_container.get_tab_control(i)
			var title = ""
			if not control in base_tabs:
				title = control.name
			tab_bar.set_tab_title(i, title)
		elif title_mode == TitleMode.TITLES:
			var control = tab_bar_container.get_tab_control(i)
			tab_bar.set_tab_title(i, control.name)
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



func _new_collection():
	var new_collection = ScriptCollection.new()
	new_collection.right_click_handler = right_click_handler
	var icon = EditorInterface.get_editor_theme().get_icon(&"ThemeSelectAll", &"EditorIcons")
	tab_bar_container.add_tab(new_collection, icon)
	_set_title_mode()
	return new_collection
	

func _new_tree(root_dir:String):
	var new_tree = ScriptTree.new()
	new_tree.root_dir = root_dir
	var icon
	if root_dir == "res://":
		new_tree.name = "Tree"
		icon = EditorInterface.get_editor_theme().get_icon(&"FileTree", &"EditorIcons")
	else:
		new_tree.name = root_dir.trim_suffix("/").get_file()
		icon = EditorInterface.get_editor_theme().get_icon(&"Folder", &"EditorIcons")
	new_tree.right_click_handler = right_click_handler
	new_tree.create_new_tab.connect(_new_tree)
	

	tab_bar_container.add_tab(new_tree, icon)
	_set_title_mode(_title_mode)
	return new_tree

class Keys:
	const TAB_ICON = &"tab_icon"
