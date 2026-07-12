extends VBoxContainer

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const PluginButton = UtilsRemote.PluginButton
const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const SectionSplit = preload("res://addons/script_outline/src/ui/section_split.gd")
const FileTabs = preload("res://addons/script_outline/src/file_tabs/file_tabs.gd")
const ScriptOutline = preload("res://addons/script_outline/src/outline/outline.gd")
const GitPanel = preload("res://addons/script_outline/src/git/git_panel.gd")

const SECTION_FILE_TABS = &"file_tabs"
const SECTION_OUTLINE = &"outline"
const SECTION_GIT = &"git"

var script_container:FileTabs
var script_outline:ScriptOutline
var git_panel:GitPanel

## the section chain, top to bottom. sections[i] is the parent of sections[i + 1]
var sections:Array[SectionSplit] = []

var _chain_margin:MarginContainer

var _dock_data:Dictionary
var _in_script_editor_sidebar:bool = false

var right_click_handler:RightClickHandler

var dock_button:Button
var dock_manager:DockManager

var editor_side_bar_vsplit_parent:Control
var editor_side_bar_vsplit:VSplitContainer
var editor_script_list_vbox:VBoxContainer
var editor_outline_vbox:VBoxContainer

var _ui_controls := []

func get_dock_data() -> Dictionary:
	var data = {}
	data[Keys.IN_SCRIPT_EDITOR_SIDEBAR] = _in_script_editor_sidebar
	data[Keys.SECTIONS] = _get_sections_data()

	for control:Control in _ui_controls:
		if control.has_method(&"get_dock_data"):
			data.merge(control.get_dock_data(), true)

	return data

func set_dock_data(data:Dictionary) -> void:
	_dock_data = data
	_in_script_editor_sidebar = _dock_data.get(Keys.IN_SCRIPT_EDITOR_SIDEBAR, true)
	
	_set_sections_data(_dock_data.get(Keys.SECTIONS, {}))

	_ui_controls_call(&"set_dock_data", [data])

func _init():
	add_theme_constant_override("separation", 0)

	right_click_handler = RightClickHandler.new()
	add_child(right_click_handler)

	# held at zero: the per-section margins do the outset (see set_margins). This is a hook
	# for trimming the chain as a whole, and pinning it keeps it off the theme's defaults
	_chain_margin = MarginContainer.new()
	_chain_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_chain_margin)

	script_container = FileTabs.new()
	script_container.right_click_handler = right_click_handler
	add_section(SECTION_FILE_TABS, "Files", script_container)

	script_outline = ScriptOutline.new()
	script_outline.right_click_handler = right_click_handler
	add_section(SECTION_OUTLINE, "Outline", script_outline)

	git_panel = GitPanel.new()
	add_section(SECTION_GIT, "Git", git_panel)

	_ui_controls = [script_container, script_outline, git_panel]


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	dock_button = PluginButton.new().get_button()
	add_child(dock_button)
	dock_button.hide.call_deferred()

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


#region sections

func add_section(section_id:StringName, title:String, content:Control) -> SectionSplit:
	var section = SectionSplit.new(section_id, title)
	section.set_content(content)
	section.option_pressed.connect(_on_section_options_pressed)
	section.collapse_toggled.connect(_on_section_collapse_toggled)

	# each new section hangs off the deepest existing one, extending the chain
	var parent:Node = sections.back() if not sections.is_empty() else _chain_margin
	parent.add_child(section)
	sections.append(section)

	_set_stretch_ratios()
	_refresh_chain_state()
	set_margins(_in_script_editor_sidebar) # the chain grew, so which section is last moved
	return section


func remove_section(section:SectionSplit) -> void:
	if not section in sections:
		return

	# the chain has to survive: whatever hung off this section takes its place
	var parent = section.get_parent()
	var child_section = _get_child_section(section)
	if is_instance_valid(child_section):
		child_section.reparent(parent)

	parent.remove_child(section)
	section.queue_free()
	sections.erase(section)

	_set_stretch_ratios()
	_refresh_chain_state()
	set_margins(_in_script_editor_sidebar)


func get_section(section_id:StringName) -> SectionSplit:
	for section in sections:
		if section.id == section_id:
			return section
	return null


func _get_child_section(section:SectionSplit) -> SectionSplit:
	for child in section.get_children():
		if child is SectionSplit:
			return child
	return null


## Sets the base position of each dragger, which `split_offset` is then added to.
## Structural only — recomputing these on collapse would move the base out from
## under the user's saved offset and the sections would visibly jump.
func _set_stretch_ratios() -> void:
	var count = sections.size()
	for i in range(count):
		sections[i].set_content_stretch_ratio(1.0)
		if i < count - 1:
			# the subtree below section i holds this many sections, so weight it accordingly
			sections[i + 1].size_flags_stretch_ratio = float(count - 1 - i)


## Every section's layout depends on whether anything below it is expanded, so a
## single toggle has to be resolved against the whole chain. One bottom-up pass.
func _refresh_chain_state() -> void:
	var expanded_below := false
	for i in range(sections.size() - 1, -1, -1):
		var section = sections[i]
		section.apply_layout_state(expanded_below)
		expanded_below = expanded_below or not section.collapsed_state


func _on_section_collapse_toggled(_section:SectionSplit) -> void:
	_refresh_chain_state()


#endregion


#region dock data

func _get_sections_data() -> Dictionary:
	var data = {}
	for i in range(sections.size()):
		var section = sections[i]
		data[String(section.id)] = {
			Keys.SECTION_INDEX: i,
			Keys.SECTION_COLLAPSED: section.collapsed_state,
			Keys.SECTION_SPLIT_OFFSET: section.offset_pref,
		}
	return data


func _set_sections_data(data:Dictionary) -> void:
	if data.is_empty():
		_migrate_legacy_dock_data()
	else:
		for section in sections:
			var section_data = data.get(String(section.id))
			if section_data == null:
				continue
			section.collapsed_state = bool(section_data.get(Keys.SECTION_COLLAPSED, false))
			section.offset_pref = int(section_data.get(Keys.SECTION_SPLIT_OFFSET, 0))

		_apply_section_order(data)

	_set_stretch_ratios()
	# on this frame every size is still zero, so an offset applied now would just be
	# clamped away — wait until the containers have actually laid out
	_refresh_chain_state.call_deferred()


## Layouts saved before sections existed kept the outline's fold state on its own key.
func _migrate_legacy_dock_data() -> void:
	var outline_vis = _dock_data.get(ScriptOutline.OutlineKeys.DOCK_OUTLINE_VIS, true)
	var outline_section = get_section(SECTION_OUTLINE)
	if is_instance_valid(outline_section):
		outline_section.collapsed_state = not outline_vis


func _apply_section_order(data:Dictionary) -> void:
	var ordered := sections.duplicate()
	ordered.sort_custom(func(a, b): return _get_saved_index(data, a) < _get_saved_index(data, b))
	if ordered == sections:
		return

	# detach deepest first, so each section leaves the chain without taking the rest with it
	for i in range(sections.size() - 1, -1, -1):
		sections[i].get_parent().remove_child(sections[i])

	sections = ordered
	var parent:Node = _chain_margin
	for section in sections:
		parent.add_child(section)
		parent = section

	set_margins(_in_script_editor_sidebar) # first and last changed hands


func _get_saved_index(data:Dictionary, section:SectionSplit) -> int:
	var section_data = data.get(String(section.id))
	if section_data == null:
		return sections.size()
	return int(section_data.get(Keys.SECTION_INDEX, sections.size()))

#endregion

func _on_section_options_pressed(id:StringName):
	var options = Options.new()
	_merge_options(options, id)
	_merge_shared_options(options)
	var section = _get_section(id)
	right_click_handler.display_on_control(options, section.option_button)
	if id == SECTION_OUTLINE:
		
		pass
	elif id == SECTION_FILE_TABS:
		pass
	pass

func _merge_options(options:Options, section_id:StringName):
	if section_id == SECTION_OUTLINE:
		var so_options = script_outline.get_options()
		if not so_options.is_empty():
			#options.add_separator("Outline")
			options.merge(so_options)
	elif section_id == SECTION_FILE_TABS:
		var sc_options = script_container.get_options()
		if not sc_options.is_empty():
			#options.add_separator("Files")
			options.merge(sc_options)

func _merge_shared_options(options:Options) -> Options:
	options.add_separator()
	var in_docks = _is_in_docks()
	var move_message = "Move to ScriptEditor" if in_docks else "Move to Docks"
	var move_icon = "Script" if in_docks else "EditorDock"
	options.add_option(move_message, _move_to_from_sidebar.bind(in_docks), [move_icon])

	if in_docks:
		options.add_option("DockManager", func():dock_button.pressed.emit(), ["MakeFloating"])
	
	return options

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
	# the reparent drops our size to zero, which lets the engine clamp the live
	# split offsets away — push the saved ones back once we have a size again
	_refresh_chain_state.call_deferred()

## Each section carries its own margin: the negative value shrinks a section's minimum
## height below its header button, which is what keeps a collapsed header row tight.
## Only the outermost edges of the chain get the outset, interior edges stay flush.
func set_margins(sidebar:bool):
	var val = 0 if sidebar else -2
	val *= EditorInterface.get_editor_scale()
	# chain is main one that needs offsets for plugin appearance
	for margin in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		_chain_margin.add_theme_constant_override(margin, val)
	
	
	# these are just offset from the main container
	val = 2
	val *= EditorInterface.get_editor_scale()
	var last = sections.size() - 1
	for i in range(sections.size()):
		var top = val if i == 0 else 0
		var bottom = val if i == last else 0
		sections[i].set_margins(val, val, val, 0)


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

func _get_section(id:StringName):
	for s in sections:
		if s.id == id:
			return s

class Keys:
	const IN_SCRIPT_EDITOR_SIDEBAR = &"sidebar_container.in_script_editor_sidebar"
	const SECTIONS = &"sidebar_container.sections"

	const SECTION_INDEX = &"index"
	const SECTION_COLLAPSED = &"collapsed"
	const SECTION_SPLIT_OFFSET = &"split_offset"
