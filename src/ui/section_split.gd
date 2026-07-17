extends SplitContainer

## A collapsible sidebar section.
##
## Sections form a nested chain: slot 0 holds this section's header + content,
## slot 1 holds the next SectionSplit. Each section therefore owns exactly one
## dragger — the boundary between itself and everything below it — which is what
## lets a collapsed section freeze its own dragger without touching the others.
## The 4.6 multi child SplitContainer cannot do this: its `dragging_enabled`,
## `collapsed` and `dragger_visibility` are container wide.
##
## Never parent a third visible Control here, it becomes a third split slot.

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const UControl = UtilsRemote.UControl
const EditorColors = UtilsRemote.EditorColors

const _ED_ICONS = &"EditorIcons"

signal collapse_toggled(section)
signal option_pressed(section_id:StringName)

var id:StringName

var content:Control
var main_vbox:VBoxContainer
var header_hbox:HBoxContainer
var title_button:Button
var option_button:Button
var option_hbox:HBoxContainer
var content_margin:MarginContainer


## The split position the user actually dragged to.
## `split_offset` cannot be used as storage: while `collapsed` is false the engine
## clamps it against the children's minimum sizes and writes the clamped value
## back, which happens whenever a neighbour is collapsed and on every reparent
## (the control's size is momentarily zero).
var offset_pref:int = 0

var collapsed_state:bool = false:
	set(value):
		if collapsed_state == value:
			return
		collapsed_state = value
		if is_instance_valid(content):
			content.visible = not value
		_update_fold_icon()
		collapse_toggled.emit(self)


func _init(section_id:StringName, title:String) -> void:
	id = section_id

	vertical = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	dragged.connect(_on_dragged)

	# the header lives inside the margin, so a negative margin pulls the section's
	# minimum height below the header button's own height and the collapsed row sits tight
	main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 0)
	UControl.expand(main_vbox)
	add_child(main_vbox)
	

	header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 0)
	main_vbox.add_child(header_hbox)

	title_button = Button.new()
	title_button.text = title
	title_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_button.theme_type_variation = &"FlatButton"
	title_button.focus_mode = Control.FOCUS_NONE
	title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_button.pressed.connect(toggle)
	header_hbox.add_child(title_button)
	
	option_hbox = HBoxContainer.new()
	option_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UControl.expand(option_hbox)
	title_button.add_child(option_hbox)
	
	option_hbox.add_spacer(true)
	
	option_button = Button.new()
	option_hbox.theme_type_variation = &"FlatButton"
	option_button.focus_mode = Control.FOCUS_NONE
	option_button.icon = EditorInterface.get_editor_theme().get_icon(&"TripleBar", &"EditorIcons")
	option_hbox.add_child(option_button)
	option_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option_button.flat = true
	option_button.pressed.connect(func(): option_pressed.emit(id))
	
	content_margin = MarginContainer.new()
	UControl.expand(content_margin)
	main_vbox.add_child(content_margin)


func _ready() -> void:
	_apply_header_theme()
	_update_fold_icon()


func set_content(control:Control) -> void:
	content = control
	UControl.expand(content)
	content.visible = not collapsed_state
	content_margin.add_child(content)

func get_content() -> Variant:
	if content_margin.get_child_count() > 0:
		return content_margin.get_child(0)
	return null

func add_header_button(button:Button) -> void:
	var parent:Node = button.get_parent()
	if parent == header_hbox:
		return
	if parent == null:
		header_hbox.add_child(button)
	else:
		button.reparent(header_hbox)


func set_title(title:String) -> void:
	title_button.text = title


func get_title() -> String:
	return title_button.text


func set_margins(left:int, right:int, top:int, bottom:int) -> void:
	content_margin.add_theme_constant_override("margin_left", left)
	content_margin.add_theme_constant_override("margin_right", right)
	content_margin.add_theme_constant_override("margin_top", top)
	content_margin.add_theme_constant_override("margin_bottom", bottom)


func set_content_stretch_ratio(ratio:float) -> void:
	# the split sorts its direct children, so the ratio belongs on the margin, not the vbox
	content_margin.size_flags_stretch_ratio = ratio


func toggle() -> void:
	collapsed_state = not collapsed_state


## Applies the layout rule for this section's place in the chain.
## `expanded_below` is true when any section deeper in the chain is expanded.
##
## Collapsed section with something expanded below: slot 0 does not expand, so it
## gets exactly its minimum (the header) and the rest of the chain takes the
## remainder — the freed space flows down. Expanded section with everything below
## collapsed: slot 1's minimum is the stack of headers beneath it, so slot 0 takes
## the remainder — the freed space flows up. Everything collapsed: the section's own
## SHRINK_BEGIN propagates up the chain and the headers stack at the top.
func apply_layout_state(expanded_below:bool) -> void:
	var expanded := not collapsed_state

	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL if expanded else Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_EXPAND_FILL if expanded or expanded_below else Control.SIZE_SHRINK_BEGIN
	
	# a drag is only meaningful when both sides of this boundary can actually resize
	var draggable := expanded and expanded_below
	dragging_enabled = draggable
	collapsed = not draggable # engine property, freezes the layout and the offset writeback
	# DRAGGER_HIDDEN still reserves the separation, it just stops drawing the grabber — that
	# is what keeps a visible gap between stacked collapsed headers. DRAGGER_HIDDEN_COLLAPSED
	# is the one value _get_separation() zeroes, which would leave them flush against each other
	dragger_visibility = DRAGGER_VISIBLE if draggable else DRAGGER_HIDDEN
	
	content_margin.visible = expanded
	option_button.visible = expanded
	
	if draggable:
		split_offset = offset_pref


func _on_dragged(offset:int) -> void:
	offset_pref = offset


func _update_fold_icon() -> void:
	var icon_name := &"GuiTreeArrowRight" if collapsed_state else &"GuiTreeArrowDown"
	title_button.icon = EditorInterface.get_editor_theme().get_icon(icon_name, _ED_ICONS)


func _apply_header_theme() -> void:
	var editor_theme = EditorInterface.get_editor_theme()
	# read the variation from the theme rather than the button, so this stays
	# idempotent once the override below is in place
	var flat = editor_theme.get_stylebox("normal", &"FlatButton")
	var sb = editor_theme.get_stylebox("normal", &"Button").duplicate() as StyleBoxFlat
	sb.content_margin_top = flat.content_margin_top
	sb.content_margin_bottom = flat.content_margin_bottom
	sb.content_margin_left = flat.content_margin_left
	sb.content_margin_right = flat.content_margin_right
	sb.bg_color = EditorColors.get_theme_color(EditorColors.ThemeColor.DARK_1)
	sb.border_color = sb.bg_color.lightened(0.15)
	title_button.add_theme_stylebox_override("normal", sb)
