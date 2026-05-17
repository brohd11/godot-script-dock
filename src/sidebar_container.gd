extends VSplitContainer

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const PluginButton = UtilsRemote.PluginButton
const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options
const EditorIcons = UtilsRemote.EditorIcons

const ScriptContainer = preload("res://addons/script_outline/src/script_container.gd")
const ScriptOutline = preload("res://addons/script_outline/src/outline.gd")

enum ViewMode {
	BOTH,
	SCRIPT_LIST,
	OUTLINE
}

var script_container:ScriptContainer
var script_outline:ScriptOutline

var _current_view_mode:ViewMode = ViewMode.BOTH

var _dock_data:Dictionary
var _in_script_editor_sidebar:bool = false

var right_click_handler:RightClickHandler

var dock_button:Button
var dock_manager:DockManager

var options_button:Button

var editor_side_bar_vsplit_parent:Control
var editor_side_bar_vsplit:VSplitContainer
var editor_script_list_vbox:VBoxContainer
var editor_outline_vbox:VBoxContainer

var _ui_controls := []

func get_dock_data() -> Dictionary:
	var data = {}
	data[Keys.IN_SCRIPT_EDITOR_SIDEBAR] = _in_script_editor_sidebar
	data[Keys.VIEW_MODE] = _current_view_mode
	
	for control:Control in _ui_controls:
		if control.has_method(&"get_dock_data"):
			data.merge(control.get_dock_data(), true)
	
	return data

func set_dock_data(data:Dictionary) -> void:
	#print("SETTING::", data)
	_dock_data = data
	_in_script_editor_sidebar = _dock_data.get(Keys.IN_SCRIPT_EDITOR_SIDEBAR, true)
	_current_view_mode = _dock_data.get(Keys.VIEW_MODE, ViewMode.BOTH) as ViewMode
	
	_ui_controls_call(&"set_dock_data", [data])

func _init():
	right_click_handler = RightClickHandler.new()
	add_child(right_click_handler)
	
	script_container = ScriptContainer.new()
	add_child(script_container)
	script_container.right_click_handler = right_click_handler
	
	script_outline = ScriptOutline.new()
	add_child(script_outline)
	script_outline.header_button_pressed.connect(_on_outline_header_button_pressed)
	script_outline.right_click_handler = right_click_handler
	
	_ui_controls = [script_container, script_outline]


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	dock_button = PluginButton.new().get_button()
	add_child(dock_button)
	dock_button.hide.call_deferred()
	
	options_button = PluginButton.new("TripleBar", _on_options_pressed).get_button()
	#_move_options_button()
	
	EditorNodeRef.call_on_ready.call_deferred(_on_enr_ready)


func _on_enr_ready():
	editor_side_bar_vsplit = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.SCRIPT_EDITOR_SIDEBAR_V_SPLIT)
	editor_side_bar_vsplit_parent = editor_side_bar_vsplit.get_parent()
	editor_script_list_vbox = editor_side_bar_vsplit.get_child(0)
	editor_outline_vbox = editor_side_bar_vsplit.get_child(1)
	
	if _in_script_editor_sidebar:
		_move_to_from_sidebar(true)
	else:
		set_margins(false)
	
	_set_view_mode(_current_view_mode)


func _set_view_mode(view_mode:ViewMode):
	_current_view_mode = view_mode
	if view_mode == ViewMode.BOTH:
		script_container.show()
		script_outline.show()
	elif view_mode == ViewMode.SCRIPT_LIST:
		script_container.show()
		script_outline.hide()
	elif view_mode == ViewMode.OUTLINE:
		script_container.hide()
		script_outline.show()
	
	_move_options_button()

func _move_options_button():
	var option_par = options_button.get_parent()
	if script_container.visible:
		var script_con_hbox = script_container.tab_bar_container.get_tab_bar_hbox()
		if option_par != script_con_hbox:
			if option_par == null:
				script_con_hbox.add_child(options_button)
			else:
				options_button.reparent(script_con_hbox)
	elif option_par != script_outline.toolbar:
		if option_par == null:
			script_outline.toolbar.add_child(options_button)
		else:
			options_button.reparent(script_outline.toolbar)



func _on_options_pressed():
	var options = Options.new()
	var in_docks = _is_in_docks()
	
	var move_message = "Move to ScriptEditor" if in_docks else "Move to Docks"
	var move_icon = "Script" if in_docks else "EditorDock"
	options.add_option(move_message, _move_to_from_sidebar.bind(in_docks), [move_icon])
	
	if in_docks:
		options.add_option("DockManager", func():dock_button.pressed.emit(), ["MakeFloating"])
	
	options.add_enum_radio("View Mode", _set_view_mode, ViewMode, _current_view_mode, ["Panels2", null])
	# this can be a view mode thing now, cycle script list outline etc
	#var script_vis = editor_script_list_vbox.visible
	#options.add_option("Toggle Script List", _toggle_script_list.bind(not script_vis), [EditorIcons.get_visibility_icon(script_vis)])
	
	if script_container.visible:
		
		var sc_options = script_container.get_options()
		if not sc_options.is_empty():
			options.add_separator("Script List")
			options.merge(sc_options)
		pass
	
	if script_outline.visible:
		var so_options = script_outline.get_options()
		if not so_options.is_empty():
			options.add_separator("Outline")
			options.merge(so_options)
	
	
	right_click_handler.display_on_control(options, options_button)

func _is_in_docks():
	var parent = get_parent()
	var par_class = parent.get_class()
	if par_class == "EditorDock":
		return true
	var parent_parent = parent.get_parent()
	if parent_parent is DockManager.PanelWindow:
		return true
	return false

func _move_to_from_sidebar(to_sidebar:bool, set_status:bool=true):
	if set_status:
		_in_script_editor_sidebar = to_sidebar
	
	if to_sidebar:
		dock_manager.remove_control_from_parent()
		editor_side_bar_vsplit.add_child(self)
		editor_side_bar_vsplit.remove_child(editor_outline_vbox)
		editor_script_list_vbox.hide()
	else:
		if get_parent() == editor_side_bar_vsplit:
			editor_side_bar_vsplit.remove_child(self)
		if editor_outline_vbox.get_parent() != editor_side_bar_vsplit:
			editor_side_bar_vsplit.add_child(editor_outline_vbox)
		editor_script_list_vbox.show()
		dock_manager.dock_instance(dock_manager.default_dock)
	
	
	set_margins(to_sidebar)

func _on_outline_header_button_pressed():
	var vis_state = script_outline.toggle_outline()
	collapsed = not vis_state
	dragging_enabled = vis_state

func set_margins(sidebar:bool):
	var val = -2
	if sidebar:
		val = 0
	
	val *= EditorInterface.get_editor_scale()
	
	var margins:Array = []
	var result = _ui_controls_call(&"get_margins")
	for arr in result.values():
		if arr is Array:
			margins.append_array(arr)
		elif arr is MarginContainer:
			margins.append(arr)
	
	for i in range(margins.size()):
		var marg = margins[i]
		if i == 0:
			marg.add_theme_constant_override("margin_top", val)
		else:
			marg.add_theme_constant_override("margin_top", 0)
		
		if i == margins.size() - 1:
			marg.add_theme_constant_override("margin_bottom", val)
		else:
			marg.add_theme_constant_override("margin_bottom", 0)
		
		marg.add_theme_constant_override("margin_left", val)
		marg.add_theme_constant_override("margin_right", val)


func clean_up():
	_ui_controls_call(&"clean_up")
	_move_to_from_sidebar(false, false)

func _ui_controls_call(callable_name:StringName, args:=[]):
	var results = {}
	for control:Control in _ui_controls:
		if control.has_method(callable_name):
			if args.is_empty():
				results[control] = control.call(callable_name)
			else:
				results[control] = control.callv(callable_name, args)
	return results


class Keys:
	const IN_SCRIPT_EDITOR_SIDEBAR = &"sidebar_container.in_script_editor_sidebar"
	const VIEW_MODE = &"sidebar_container.view_mode"
