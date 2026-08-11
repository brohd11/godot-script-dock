extends VBoxContainer

const UtilsRemote = preload("res://addons/script_dock/src/utils/utils_remote.gd")

const PluginButton = UtilsRemote.PluginButton
const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options
const UFile = UtilsRemote.UFile
const UVersion = UtilsRemote.UVersion

const SectionSplit = preload("res://addons/script_dock/src/ui/section_split.gd")
const FileTabs = preload("res://addons/script_dock/src/file_tabs/file_tabs.gd")
const Outline = preload("res://addons/script_dock/src/outline/outline.gd")

const SECTION_FILE_TABS = &"file_tabs"
const SECTION_OUTLINE = &"outline"

var script_container:FileTabs
var script_outline:Outline

## the section chain, top to bottom. sections[i] is the parent of sections[i + 1]
var sections:Array[SectionSplit] = []

var _chain_margin:MarginContainer

var _dock_data:Dictionary
var _in_script_editor_sidebar:bool = true

var right_click_handler:RightClickHandler

var dock_button:Button
var dock_manager:DockManager

var editor_side_bar_vsplit_parent:Control
var editor_side_bar_vsplit:VSplitContainer
var editor_script_list_vbox:VBoxContainer
var editor_outline_vbox:VBoxContainer


# _dock_data is the persistent backing store: present sections are flushed into it here, while
# entries for sections that were removed (e.g. git_view disabled) are left untouched so they survive.
func get_dock_data() -> Dictionary:
	_dock_data[Keys.IN_SCRIPT_EDITOR_SIDEBAR] = _in_script_editor_sidebar
	for section in sections:
		_flush_section(section)
	return _dock_data

func set_dock_data(data:Dictionary) -> void:
	_dock_data = data
	_in_script_editor_sidebar = _dock_data.get(Keys.IN_SCRIPT_EDITOR_SIDEBAR, true)

	# built-in sections already exist by the time DockManager delivers the saved data; hand each
	# its own slice, then restore the chain order
	for section in sections:
		_apply_section(section)
	_apply_section_order(_dock_data.get(Keys.SECTIONS, {}))
	_set_stretch_ratios()
	# on this frame every size is still zero, so an offset applied now would just be
	# clamped away — wait until the containers have actually laid out
	_refresh_chain_state.call_deferred()

func _init():
	add_theme_constant_override("separation", 0)

	right_click_handler = RightClickHandler.new()
	add_child(right_click_handler)

	# held at zero: the per-section margins do the outset (see set_margins). This is a hook
	# for trimming the chain as a whole, and pinning it keeps it off the theme's defaults
	_chain_margin = MarginContainer.new()
	_chain_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_chain_margin)

	_add_builtin_section(SECTION_FILE_TABS)
	_add_builtin_section(SECTION_OUTLINE)


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
	var section:SectionSplit = SectionSplit.new(section_id, title)
	section.set_content(content)
	section.option_pressed.connect(_on_section_options_pressed)
	section.collapse_toggled.connect(_on_section_collapse_toggled)

	# each new section hangs off the deepest existing one, extending the chain
	var parent:Node = sections.back() if not sections.is_empty() else _chain_margin
	parent.add_child(section)
	sections.append(section)

	# restore this section's saved slice — for a section added late (git_view) _dock_data is already
	# populated; for a built-in added during _init it just applies defaults until set_dock_data arrives
	_apply_section(section)

	_set_stretch_ratios()
	_refresh_chain_state()
	set_margins(_in_script_editor_sidebar) # the chain grew, so which section is last moved
	return section

func remove_section_by_id(section_id:StringName):
	var section = _get_section(section_id)
	if is_instance_valid(section):
		# snapshot while the content is still live, so its state round-trips if the section returns
		_flush_section(section)
		remove_section(section)
	else:
		print("Could not get ScriptDock section ID: ", section_id)

func remove_section(section:SectionSplit) -> void:
	if not section in sections:
		return

	# the chain has to survive: whatever hung off this section takes its place
	var parent = section.get_parent()
	var child_section = _get_child_section(section)
	if is_instance_valid(child_section):
		child_section.reparent(parent)
	
	var section_content = section.remove_content()
	if is_instance_valid(section_content):
		if section_content.has_method("clean_up"):
			section_content.clean_up()
	
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

# Snapshot a live section into the backing store: its split state under SECTIONS, its content
# payload under SECTIONS_DATA. Keyed by String(id) so lookups stay consistent with persisted data.
func _flush_section(section:SectionSplit) -> void:
	var id = String(section.id)
	_get_section_split_data(id).merge({
		Keys.SECTION_INDEX: sections.find(section),
		Keys.SECTION_COLLAPSED: section.collapsed_state,
		Keys.SECTION_SPLIT_OFFSET: section.offset_pref,
	}, true)
	var content = section.get_content()
	if is_instance_valid(content) and content.has_method(Keys.GET_DOCK_DATA):
		_dock_data.get_or_add(Keys.SECTIONS_DATA, {})[id] = content.call(Keys.GET_DOCK_DATA)


# Push a section's saved slice from the backing store onto the live section.
func _apply_section(section:SectionSplit) -> void:
	var id = String(section.id)
	var split = _get_section_split_data(id)
	section.collapsed_state = bool(split.get(Keys.SECTION_COLLAPSED, false))
	section.offset_pref = int(split.get(Keys.SECTION_SPLIT_OFFSET, 0))

	var content = section.get_content()
	# only hand over real saved data — a first-ever section shouldn't be handed an empty dict
	var content_data = _dock_data.get(Keys.SECTIONS_DATA, {}).get(id)
	if content_data != null and is_instance_valid(content) and content.has_method(Keys.SET_DOCK_DATA):
		content.call(Keys.SET_DOCK_DATA, content_data)


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


func _merge_options(options:Options, section_id:StringName):
	var section = _get_section(section_id)
	if not is_instance_valid(section): return
	var content = section.get_content()
	if is_instance_valid(content) and content.has_method("get_options"):
		var opts = content.get_options()
		if not opts.is_empty():
			options.merge(opts)

func _merge_shared_options(options:Options) -> Options:
	options.add_separator()
	var in_docks = _is_in_docks()
	var move_message = "Move to ScriptEditor" if in_docks else "Move to Docks"
	var dock_icon = "EditorDock"
	if UVersion.get_minor_version() < 6:
		dock_icon = "TabContainer"
	
	var move_icon = "Script" if in_docks else dock_icon
	options.add_option(move_message, _move_to_from_sidebar.bind(in_docks), [move_icon])

	if in_docks:
		options.add_option("DockManager", func():dock_button.pressed.emit(), ["MakeFloating"])
	
	return options

func _is_in_docks():
	var parent = get_parent()
	var par_class = parent.get_class()
	if UVersion.get_minor_version() < 6:
		if par_class == "TabContainer":
			return true
	else:
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
		show() # necessary in 4.4 for some reason
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
	for i in range(sections.size()):
		sections[i].set_margins(val, val, val, 0)

func clean_up():
	_sections_call(&"clean_up")
	_move_to_from_sidebar(false, false)

func _sections_call(callable_name:StringName, args:=[]):
	var results = {}
	for section:SectionSplit in sections:
		var content = section.get_content()
		if content.has_method(callable_name):
			if args.is_empty():
				results[content] = content.call(callable_name)
			else:
				results[content] = content.callv(callable_name, args)
	return results

func _add_builtin_section(section_id:StringName):
	var control
	var title = ""
	if section_id == SECTION_FILE_TABS:
		control = FileTabs.new()
		title = "Files"
	elif section_id == SECTION_OUTLINE:
		control = Outline.new()
		title = "Outline"
	
	for prop in ["right_click_handler"]:
		if prop in control:
			control.set(prop, get(prop))
	
	add_section(section_id, title, control)

func _get_section(id:StringName):
	for s in sections:
		if s.id == id:
			return s


# tab specific
func show_in_tree(path:String):
	var file_tab = get_section(SECTION_FILE_TABS)
	if not is_instance_valid(file_tab):
		return
	if file_tab.collapsed_state:
		file_tab.toggle()
	file_tab.get_content().show_in_tree(path)


func _get_section_split_data(section_id) -> Dictionary:
	return _dock_data.get_or_add(Keys.SECTIONS, {}).get_or_add(String(section_id), {})


class Keys:
	const IN_SCRIPT_EDITOR_SIDEBAR = &"sidebar_container.in_script_editor_sidebar"
	const SECTIONS = &"sidebar_container.sections"
	const SECTIONS_DATA = &"sidebar_container.sections_data"

	const SECTION_INDEX = &"index"
	const SECTION_COLLAPSED = &"collapsed"
	const SECTION_SPLIT_OFFSET = &"split_offset"
	
	const GET_DOCK_DATA = &"get_dock_data"
	const SET_DOCK_DATA = &"set_dock_data"
