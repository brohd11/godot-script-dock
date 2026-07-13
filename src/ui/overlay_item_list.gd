extends ItemList

## An ItemList whose rows are an item text plus any number of overlay segments drawn on top of it.
##
## A stock ItemList gives one string and one colour per row, so it cannot express this. The item
## text is therefore left to ItemList (which keeps selection and highlighting working) and the rest
## is drawn on top, the same way alib_editor/file_system/fs_tab/filesystem_item_list.gd overlays its
## rows. That is also why the item text always leads: ItemList draws it first, at a fixed left edge.
##
## Each segment declares where it sits and what it does when the row runs out of room, so the layout
## policy belongs to the caller rather than to this file:
##
##   Changes:  <file name>  <dim dir, flexes> ……………………… <status, right, compacts to a letter>
##   Commits:  <mono hash>  <tag>  <subject, flexes>          — no item text at all
##
## ItemList draws its text at full length and knows nothing about the overlay, so a long item text
## would run straight through the segments. _fit_texts() therefore ellipsizes the item text itself.
## The full string is kept in _rows.
##
## A row may also have **no item text**, in which case every segment is an overlay and the row's
## content starts where the item text would have. That is the only way to give the leading string a
## face of its own: ItemList has one font for all of its text, and that font is also what it takes the
## row's height from — so the Commits list, whose hash has to be mono, cannot let the hash be the item
## text without the whole list growing to fit the mono line box. See ROW_SPACER.

const DIM_ALPHA = 0.5

## ItemList gives a row no height unless it has text to shape — the row size is `MAX(icon, text)` and
## an empty string contributes nothing, so a text-less row with no icon collapses to nothing. A space
## is text. It never reaches the overlay: segment 0's width is measured from the real, empty string
## and stays 0, so the space costs nothing but the row's height, which is the whole reason it is here.
const ROW_SPACER = " "
## unscaled px between one segment and the next
const GAP = 8
## unscaled px kept clear at the right, so a right aligned segment does not sit flush against the
## end of the row
const RIGHT_PAD = 4
## unscaled px below which a flex segment is dropped rather than trimmed — a one or two letter stub
## of a path ("n", "na") is noise, not information
const MIN_FLEX_WIDTH = 36
const ELLIPSIS = "…"

## Where the overlay's baseline sits between the top and the bottom of the row. 0.5 is true centre,
## but ItemList draws its own item text a shade below that — which is the better spot — so the
## overlay has to go there too or the two read as misaligned against each other. Tuned by eye, not
## derived: ItemList's own offset falls out of theme constants there is no way to query.
##
## It moves every segment together, so whatever it is set to, the segments stay level with one
## another; it can only raise or lower the row's text as a block.
const BASELINE_CENTER = 0.57

enum Align {
	LEFT,  ## flows immediately after whatever precedes it
	RIGHT, ## packed against the right edge
}

## unscaled px below which segments swap to their `compact` string. 0 disables.
var compact_below:float = 0.0

## overlay data, index aligned with the ItemList items. Each row is an Array of segment dicts, and
## each segment's `text` is the full, unellipsized string.
var _rows:Array[Array] = []

## the resolved geometry of each row, rebuilt by _fit_texts and only read by _draw, so the two can
## never disagree about where a segment went
var _layouts:Array[Array] = []

var _fit_queued:bool = false


## One overlay segment. Every key is optional; the #! keys tag above is what offers them at the call
## site, and an omitted one resolves to its default at the point it is read, not here — the fonts
## fall back to the *list's* theme, which a static func has no self to reach, so no other key can
## sensibly default here either.
##
##   text          ""            the string to draw
##   color         white         drawn colour, and an icon segment's modulate
##   align         Align.LEFT    LEFT flows on from the segment before it; RIGHT packs to the edge
##   flex          false         see below
##   compact       ""            see below
##   compact_icon  null          see below
##   font          the list's    see below
##   font_size     the list's
##
## `flex` marks the segment that yields: it ellipsizes to absorb whatever room is left over, while
## every other segment keeps its natural width. At most one per row — a second is ignored.
##
## `compact` and `compact_icon` are the shorter stand-ins, swapped in when the list is narrower than
## `compact_below`; the icon wins where both are given. A texture is the better compact form for
## anything that has to line up down the list, because a square is placed by its size and not by its
## advance width — every row's icon then lands on the same x, which no two proportional glyphs do.
## An icon segment is fixed width: it never flexes and never ellipsizes.
##
## A segment only needs its own face when it has to differ from the item text: the Commits list sets
## the *list* font to a mono one so that its hashes (the item text) all come out the same width, and
## then hands the tag and the subject the proportional UI font back, so only the hash is mono.

#! keys text:String color:Color align:Align flex:bool compact:String compact_icon:Texture2D
#! keys font:Font font_size:int
static func segment(params:={}) -> Dictionary:
	return params


func _ready() -> void:
	resized.connect(_queue_fit)

## A segment's own face, or the list's. Every measure and every draw goes through these two, so a
## segment can never be measured with one font and drawn with another.
func _seg_font(seg:Dictionary) -> Font:
	var font = seg.get(&"font")
	return font if font != null else get_theme_font(&"font")


func _seg_font_size(seg:Dictionary) -> int:
	var font_size:int = seg.get(&"font_size", 0)
	return font_size if font_size > 0 else get_theme_font_size(&"font_size")


func clear_rows() -> void:
	clear()
	_rows.clear()
	_layouts.clear()
	queue_redraw()


## What ItemList is given to shape, which is not always what the overlay lays out — see ROW_SPACER.
## Both of the places that hand ItemList a string go through here, so the two cannot drift.
func _shaped_text(text:String) -> String:
	return text if not text.is_empty() else ROW_SPACER


func add_row(text:String, segments:Array, text_color = null, metadata = null, tooltip:="") -> void:
	add_item(_shaped_text(text))

	var idx = item_count - 1
	if tooltip != "":
		set_item_tooltip(idx, tooltip)
	if metadata != null:
		set_item_metadata(idx, metadata)
	if text_color != null:
		set_item_custom_fg_color(idx, text_color)

	# the item text is segment zero in all but name: it leads, and it is the last thing to yield. It
	# goes through segment() like any other so that every entry in _rows has the one origin — nothing
	# added to the factory later can miss the item text by being hand built here.
	_rows.append([segment({&"text": text})] + segments)
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


## Resolve every row's geometry, and ellipsize each item's text so the segments to its right have
## room. _draw only reads what this leaves behind in _layouts.
func _fit_texts() -> void:
	_fit_queued = false
	_layouts.clear()
	queue_redraw()

	if _rows.is_empty() or size.x <= 0:
		return # no layout yet — the resized signal will bring us back

	# ItemList works its own layout out in its draw notification, and a hidden control never draws. So
	# on a background tab its scrollbar is still describing the row count of whatever the list held
	# before — and _get_right_edge() reads that flag. Measuring the segments against it while it is
	# stale is what leaves the right-most one sitting under the scrollbar once the tab is shown, with
	# nothing to correct it: a redraw re-reads _layouts rather than rebuilding them. Ask for the update
	# instead of waiting for a draw that may not come until the panel is looked at.
	force_update_list_size()

	var font = get_theme_font(&"font")
	var font_size = get_theme_font_size(&"font_size")

	for i in range(min(item_count, _rows.size())):
		var layout = _layout_row(_rows[i], font, font_size)
		_layouts.append(layout)
		set_item_text(i, _shaped_text(layout[0][&"draw_text"]))


## Resolve a row to a list of `{draw_text, x, width, color}`, index aligned with the row's segments.
## Segment 0 is the item text, whose x/width ItemList owns — only its `draw_text` is used.
##
## The item text keeps its natural width wherever it can: the flex segment absorbs the shortfall and
## vanishes entirely before the primary is crushed to "ad…" in a narrow sidebar.
func _layout_row(row:Array, font:Font, font_size:int) -> Array:
	var gap = GAP * EditorInterface.get_editor_scale()
	var text_x = _get_text_start_x()
	var right_edge = _get_right_edge()
	var compact = compact_below > 0.0 and size.x < compact_below * EditorInterface.get_editor_scale()

	var out:Array = []
	var flex_idx = -1

	# 1. resolve every segment's text and natural width, and find the one that yields.
	# Segment 0 is the item text, which ItemList draws from the list's own font — it never carries
	# a face of its own. The rest are drawn here, so each is measured with whatever face it will be
	# drawn with, and that face is carried through to _draw so the two cannot disagree.
	for i in row.size():
		var seg:Dictionary = row[i]
		var text:String = seg.get(&"text", "")
		var icon:Texture2D = null

		# the item text cannot become an icon: ItemList, not this file, draws it
		if compact and i > 0:
			icon = seg.get(&"compact_icon")
			if icon != null:
				text = "" # the icon *is* the segment now; nothing is drawn as a string
			elif not seg.get(&"compact", "").is_empty():
				text = seg[&"compact"]
		
		var seg_font = font if i == 0 else _seg_font(seg)
		var seg_font_size = font_size if i == 0 else _seg_font_size(seg)
		
		out.append({
			&"draw_text": text,
			&"icon": icon,
			&"x": 0.0,
			&"width": float(icon.get_width()) if icon != null else _string_width(seg_font, seg_font_size, text),
			&"color": seg.get(&"color", Color.WHITE),
			&"align": seg.get(&"align", Align.LEFT),
			&"font": seg_font,
			&"font_size": seg_font_size,
		})
		# an icon is a fixed size square — there is nothing in it to give up, so it cannot be the
		# segment that yields even if the caller marked it flex
		if i > 0 and seg.get(&"flex", false) and icon == null and flex_idx < 0:
			flex_idx = i

	# 2. every non-flex segment keeps its natural width; what is left over is the flex segment's.
	#
	# A gap is only charged for a segment that has something before it. Whatever comes first in the
	# row sits flush at text_x, and on a row with no item text that is the first *segment* — so this
	# cannot key off the index, or a text-less row would be billed for a gap that step 4 never places
	# and the flex segment would quietly pay for it out of its own width.
	var fixed = 0.0
	var leading = true
	for i in out.size():
		if i == flex_idx or _is_blank(out[i]):
			continue
		fixed += out[i][&"width"] + (0.0 if leading else gap)
		leading = false

	var total = right_edge - text_x
	var slack = total - fixed - (gap if flex_idx > 0 else 0.0)

	if flex_idx > 0:
		var natural = out[flex_idx][&"width"]
		if slack < MIN_FLEX_WIDTH * EditorInterface.get_editor_scale():
			out[flex_idx][&"draw_text"] = "" # dropped: a two letter stub of a path is not information
			out[flex_idx][&"width"] = 0.0
		elif natural > slack:
			out[flex_idx][&"width"] = slack

	# 3. only now, if the fixed content alone still does not fit, does the item text give way
	var overflow = fixed - total
	if overflow > 0:
		var room = maxf(out[0][&"width"] - overflow, 0.0)
		out[0][&"draw_text"] = _ellipsize(out[0][&"draw_text"], room, font, font_size)
		out[0][&"width"] = _string_width(font, font_size, out[0][&"draw_text"])

	# 4. place them: LEFT flows rightwards from the item text, RIGHT packs leftwards from the edge.
	# A row with no item text has nothing to flow from and nothing to be separated from, so the first
	# segment starts flush at text_x — otherwise it would sit a gap right of where the item text of
	# every other row begins, and the two kinds of row would not line up with one another.
	var left_x = text_x
	if not _is_blank(out[0]):
		left_x += out[0][&"width"] + gap

	var right_x = right_edge

	for i in range(1, out.size()):
		var placed:Dictionary = out[i]
		if _is_blank(placed):
			continue

		if placed[&"align"] == Align.RIGHT:
			right_x -= placed[&"width"]
			placed[&"x"] = right_x
			right_x -= gap
		else:
			placed[&"x"] = left_x
			left_x += placed[&"width"] + gap

	return out


func _draw() -> void:
	if _layouts.is_empty():
		return # _fit_texts is deferred and has not run yet; it will queue_redraw when it does

	# the list's own font, which is what ItemList draws the item text with. Segments may each carry a
	# different face, but they all sit on the baseline this one defines — mixed faces belong on a
	# shared baseline, and centring each of them in the row separately is what would make them jitter
	# against one another.
	var font = get_theme_font(&"font")
	var font_size = get_theme_font_size(&"font_size")

	# get_item_rect() is in unscrolled content space while the list draws itself shifted by the
	# scroll value — without this the overlay detaches from its rows the moment you scroll. The
	# segments' own x is likewise in that space, so it takes the same correction.
	var scroll_offset = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)

	for i in range(min(item_count, _layouts.size())):
		var layout:Array = _layouts[i]
		var rect = get_item_rect(i, false)
		rect.position -= scroll_offset

		# draw_string takes a baseline, and ItemList sits its text a shade below the row's centre
		var ascent = font.get_ascent(font_size)
		var baseline = rect.position.y \
			+ (rect.size.y + ascent - font.get_descent(font_size)) * BASELINE_CENTER

		for j in range(1, layout.size()):
			var seg:Dictionary = layout[j]
			if _is_blank(seg):
				continue

			var x = seg[&"x"] - scroll_offset.x
			var icon:Texture2D = seg[&"icon"]

			# a square, of one size, centred in the row. Every row's icon is the same width, so a
			# right aligned one lands on the same x on every row — which is the whole reason a letter
			# that has to line up down the list is a texture here and not a string. Centring it in the
			# row also keeps it clear of BASELINE_CENTER, which is a value tuned by eye.
			if icon != null:
				var side:float = seg[&"width"]
				var pos = Vector2(x, rect.position.y + (rect.size.y - side) * 0.5).round()
				draw_texture_rect(icon, Rect2(pos, Vector2(side, side)), false, seg[&"color"])
				continue

			var text:String = seg[&"draw_text"]
			var seg_font:Font = seg[&"font"]
			var seg_font_size:int = seg[&"font_size"]

			# a segment only needs TextLine when it is the one that had to give up width; anything
			# at its natural size draws straight, and draw_string is much the cheaper of the two
			if _string_width(seg_font, seg_font_size, text) <= seg[&"width"]:
				draw_string(seg_font, Vector2(x, baseline), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, seg_font_size, seg[&"color"])
				continue

			# draw_string can only hard clip, which chops text mid word and reads as a glitch.
			# TextLine is the only thing that will ellipsize.
			var line = TextLine.new()
			line.add_string(text, seg_font, seg_font_size)
			line.width = seg[&"width"]
			line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

			# draw_string takes a baseline but TextLine.draw takes the top of the line box. Sitting
			# it on the same baseline is what stops a segment jumping vertically at the moment it
			# becomes narrow enough to ellipsize and swaps from one call to the other.
			line.draw(get_canvas_item(), Vector2(x, baseline - line.get_line_ascent()), seg[&"color"])


## A resolved segment with nothing to draw — it has neither text nor an icon, so it takes no width
## and no gap. A dropped flex segment is the usual one.
func _is_blank(seg:Dictionary) -> bool:
	return seg[&"icon"] == null and seg[&"draw_text"].is_empty()


## ItemList lays its text out at the item rect plus the icon column; these rows carry no icon of
## ItemList's own (the overlay's icons are drawn here, and ItemList knows nothing about them), so
## that column collapses to a single h_separation. Call set_item_icon and this must grow by its width.
func _get_text_indent() -> float:
	return get_theme_constant(&"h_separation")


func _get_text_start_x() -> float:
	var indent = _get_text_indent() * 0.5 # appears half gives a the exact amount, not sure if this coincendence, or actual math(split on ends)
	return get_theme_stylebox(&"panel").get_margin(SIDE_LEFT) + indent


## The padding belongs here rather than at the point a right aligned segment is packed, so that the
## one value feeds both that position *and* the total width the flex segment is sized against —
## otherwise a long subject would simply grow into the padding and eat it straight back.
func _get_right_edge() -> float:
	var right_edge = size.x - get_theme_stylebox(&"panel").get_margin(SIDE_RIGHT)
	if get_v_scroll_bar().visible:
		right_edge -= get_v_scroll_bar().size.x
	return right_edge - RIGHT_PAD * EditorInterface.get_editor_scale()


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
		@warning_ignore("integer_division")
		var mid = (low + high + 1) / 2
		if _string_width(font, font_size, text.substr(0, mid)) <= budget:
			low = mid
		else:
			high = mid - 1

	return text.substr(0, low).strip_edges(false, true) + ELLIPSIS
