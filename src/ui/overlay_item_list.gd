extends ItemList

## An ItemList whose rows read:  <text>  <secondary> ………………… <trailing>
##
##   text      the ItemList's own item text — bright, selectable
##   secondary dimmed, drawn immediately after the text, ellipsized to whatever room is left
##   trailing  drawn right aligned, in its own colour
##
## A stock ItemList gives one string and one colour per row, so it cannot express this. The primary
## text is therefore left to ItemList (which keeps selection and highlighting working) and the rest
## is drawn on top, the same way alib_editor/file_system/fs_tab/filesystem_item_list.gd overlays
## its rows.
##
## ItemList draws its text at full length and knows nothing about the overlay, so a long primary
## would run straight through the trailing. _fit_texts() therefore ellipsizes the item text itself,
## reserving room for the secondary and the trailing. The full string is kept in _rows.

const DIM_ALPHA = 0.5
## unscaled px between the text and the secondary, and between the secondary and the trailing
const GAP = 8
## unscaled px below which the secondary is dropped rather than trimmed — a one or two letter stub
## of a path ("n", "na") is noise, not information
const MIN_SECONDARY_WIDTH = 36
const ELLIPSIS = "…"

## Per list colours. Which of the two reads as "primary" is the caller's choice: the Changes list
## wants a bright name and a dim dir, the Commits list wants a dim hash and a bright subject.
## null leaves ItemList's own default / the dim colour respectively.
var text_color = null
var secondary_color = null

## overlay data, index aligned with the ItemList items. `text` is the full, unellipsized string.
var _rows:Array[Dictionary] = []

var _fit_queued:bool = false


func _ready() -> void:
	resized.connect(_queue_fit)


func clear_rows() -> void:
	clear()
	_rows.clear()
	queue_redraw()


func add_row(text:String, secondary:String, trailing:String, trailing_color:Color, metadata = null, tooltip:="") -> void:
	add_item(text)

	var idx = item_count - 1
	if tooltip != "":
		set_item_tooltip(idx, tooltip)
	if metadata != null:
		set_item_metadata(idx, metadata)
	if text_color != null:
		set_item_custom_fg_color(idx, text_color)

	_rows.append({
		&"text": text,
		&"secondary": secondary,
		&"trailing": trailing,
		&"trailing_color": trailing_color,
	})
	_queue_fit()


func get_selected_metadata():
	var selected = get_selected_items()
	if selected.is_empty():
		return null
	return get_item_metadata(selected[0])


func get_dim_color() -> Color:
	var color = get_theme_color(&"font_color")
	color.a = DIM_ALPHA
	return color


## Rows change in batches, so coalesce into one pass per frame rather than refitting every add.
func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit_texts.call_deferred()


## Shrink each item's text until the secondary and the trailing have room to its right.
func _fit_texts() -> void:
	_fit_queued = false
	queue_redraw()

	if _rows.is_empty() or size.x <= 0:
		return # no layout yet — the resized signal will bring us back

	var font = get_theme_font(&"font")
	var font_size = get_theme_font_size(&"font_size")
	var gap = GAP * EditorInterface.get_editor_scale()

	var text_x = _get_text_start_x()
	var right_edge = _get_right_edge()

	# only the trailing is reserved — the secondary is always the one that yields, so the primary is
	# never crushed to "ad…" in a narrow sidebar
	for i in range(min(item_count, _rows.size())):
		var row = _rows[i]
		var reserved = _string_width(font, font_size, row[&"trailing"]) + gap
		var available = right_edge - text_x - reserved
		set_item_text(i, _ellipsize(row[&"text"], available, font, font_size))


func _draw() -> void:
	if _rows.is_empty():
		return

	var font = get_theme_font(&"font")
	var font_size = get_theme_font_size(&"font_size")
	var overlay_color = secondary_color if secondary_color != null else get_dim_color()
	var gap = GAP * EditorInterface.get_editor_scale()

	# get_item_rect() is in unscrolled content space while the list draws itself shifted by the
	# scroll value — without this the overlay detaches from its rows the moment you scroll
	var scroll_offset = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
	var right_edge = _get_right_edge()

	for i in range(min(item_count, _rows.size())):
		var row = _rows[i]
		var rect = get_item_rect(i, false)
		rect.position -= scroll_offset

		# draw_string takes a baseline, and ItemList centres its text on the row
		var ascent = font.get_ascent(font_size)
		var baseline = rect.position.y + (rect.size.y + ascent - font.get_descent(font_size)) * 0.5

		var trailing:String = row[&"trailing"]
		var trailing_x = right_edge
		if not trailing.is_empty():
			trailing_x = right_edge - _string_width(font, font_size, trailing)
			draw_string(font, Vector2(trailing_x, baseline), trailing, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, row[&"trailing_color"])

		var secondary:String = row[&"secondary"]
		if secondary.is_empty():
			continue

		# measure what ItemList actually drew, not the full string — _fit_texts may have trimmed it
		var text_width = _string_width(font, font_size, get_item_text(i))
		var secondary_x = rect.position.x + _get_text_indent() + text_width + gap
		var secondary_width = trailing_x - gap - secondary_x
		if secondary_width < MIN_SECONDARY_WIDTH * EditorInterface.get_editor_scale():
			continue

		# draw_string can only hard clip, which chops text mid word and reads as a glitch.
		# TextLine is the only thing that will ellipsize.
		var line = TextLine.new()
		line.add_string(secondary, font, font_size)
		line.width = secondary_width
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var line_y = rect.position.y + (rect.size.y - line.get_size().y) * 0.5
		line.draw(get_canvas_item(), Vector2(secondary_x, line_y), overlay_color)


## ItemList lays its text out at the item rect plus the icon column; these rows carry no icon, so
## that column collapses to a single h_separation. Add icons and this must grow by the icon width.
func _get_text_indent() -> float:
	return get_theme_constant(&"h_separation")


func _get_text_start_x() -> float:
	return get_theme_stylebox(&"panel").get_margin(SIDE_LEFT) + _get_text_indent()


func _get_right_edge() -> float:
	var right_edge = size.x - get_theme_stylebox(&"panel").get_margin(SIDE_RIGHT)
	if get_v_scroll_bar().visible:
		right_edge -= get_v_scroll_bar().size.x
	return right_edge


func _string_width(font:Font, font_size:int, text:String) -> float:
	if text.is_empty():
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _ellipsize(text:String, max_width:float, font:Font, font_size:int) -> String:
	if max_width <= 0:
		return ""
	if _string_width(font, font_size, text) <= max_width:
		return text

	var budget = max_width - _string_width(font, font_size, ELLIPSIS)
	if budget <= 0:
		return ELLIPSIS

	# longest prefix that still fits
	var low = 0
	var high = text.length()
	while low < high:
		var mid = (low + high + 1) / 2
		if _string_width(font, font_size, text.substr(0, mid)) <= budget:
			low = mid
		else:
			high = mid - 1

	return text.substr(0, low).strip_edges(false, true) + ELLIPSIS
