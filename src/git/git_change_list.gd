extends ItemList

## The Git section's Changes list.
##
## A stock ItemList gives one string and one colour per row, which cannot express "file name,
## dimmed dir, right aligned status". So the name is left to ItemList — it keeps selection,
## highlighting and ellipsis working — and the rest is drawn on top in _draw(), the same way
## alib_editor/file_system/fs_tab/filesystem_item_list.gd overlays its rows.

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")

const DIM_ALPHA = 0.5
## unscaled px between the file name and the dir, and between the dir and the status
const GAP = 8

## overlay data, index aligned with the ItemList items
var _rows:Array[Dictionary] = []


func clear_changes() -> void:
	clear()
	_rows.clear()
	queue_redraw()


func add_change(res_path:String, repo_dir:String, file_data:Dictionary) -> void:
	var file_name = res_path.get_file()
	add_item(file_name)

	var idx = item_count - 1
	set_item_tooltip(idx, res_path)
	set_item_metadata(idx, res_path) # what a click-to-open will read

	_rows.append({
		&"name": file_name,
		&"dir": res_path.get_base_dir().trim_prefix(repo_dir).trim_prefix("/"),
		&"label": GitUtil.get_status_label(file_data),
		&"color": _get_status_color(file_data),
	})
	queue_redraw()


func get_selected_path() -> String:
	var selected = get_selected_items()
	if selected.is_empty():
		return ""
	return get_item_metadata(selected[0])


func _get_status_color(file_data:Dictionary) -> Color:
	var editor_theme = EditorInterface.get_editor_theme()
	
	print(file_data)
	
	
	
	if file_data.get(GitUtil.Keys.CONFLICTED, false):
		return GitUtil.Colors.RED

	# staged with nothing left dirty on disk: the change is already safely in the index
	var staged = file_data.get(GitUtil.Keys.STAGED, false)
	var unstaged = file_data.get(GitUtil.Keys.UNSTAGED, false)
	if staged and not unstaged:
		return GitUtil.Colors.GREEN
	
	if file_data.get(GitUtil.Keys.UNTRACKED, false):
		return GitUtil.Colors.L_GREEN
	elif file_data.get(GitUtil.Keys.Y, "") == "M":
		return GitUtil.Colors.L_YELLOW
	
	
	return _dim_font_color()


func _dim_font_color() -> Color:
	var color = get_theme_color(&"font_color")
	color.a = DIM_ALPHA
	return color


func _draw() -> void:
	if _rows.is_empty():
		return

	var font = get_theme_font(&"font")
	var font_size = get_theme_font_size(&"font_size")
	# ItemList lays its text out at the item rect plus the icon column; there is no icon on these
	# rows, so that column collapses to a single h_separation
	var text_indent = get_theme_constant(&"h_separation")

	var dim_color = _dim_font_color()
	var gap = GAP * EditorInterface.get_editor_scale()

	# get_item_rect() is in unscrolled content space while the list draws itself shifted by the
	# scroll value — without this the overlay detaches from its rows the moment you scroll
	var scroll_offset = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)

	var right_edge = size.x - get_theme_stylebox(&"panel").get_margin(SIDE_RIGHT)
	if get_v_scroll_bar().visible:
		right_edge -= get_v_scroll_bar().size.x

	for i in range(min(item_count, _rows.size())):
		var row = _rows[i]
		var rect = get_item_rect(i, false)
		rect.position -= scroll_offset

		# draw_string takes a baseline, and ItemList centres its text on the row
		var ascent = font.get_ascent(font_size)
		var baseline = rect.position.y + (rect.size.y + ascent - font.get_descent(font_size)) * 0.5

		var label:String = row[&"label"]
		var label_width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_x = right_edge - label_width
		draw_string(font, Vector2(label_x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, row[&"color"])

		var dir:String = row[&"dir"]
		if dir.is_empty():
			continue

		var name_width = font.get_string_size(row[&"name"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var dir_x = rect.position.x + text_indent + name_width + gap
		# never run the dir under the status word
		var dir_width = label_x - gap - dir_x
		if dir_width <= 0:
			continue

		# draw_string can only hard clip, which chops the dir mid word and reads as a glitch.
		# TextLine is the only thing that will ellipsize.
		var dir_line = TextLine.new()
		dir_line.add_string(dir, font, font_size)
		dir_line.width = dir_width
		dir_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var dir_y = rect.position.y + (rect.size.y - dir_line.get_size().y) * 0.5
		dir_line.draw(get_canvas_item(), Vector2(dir_x, dir_y), dim_color)
