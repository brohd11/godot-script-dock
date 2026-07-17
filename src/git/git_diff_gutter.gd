extends Node

## Marks the script editor's gutter with what has changed since the last commit.
##
## Diffs HEAD against the editor's *buffer*, not the file on disk. The baseline comes from
## `git show HEAD:<path>` and the diff from GitDiff
##
## The hunks are kept per editor even though only the markers are drawn: they are what the
## side-by-side diff preview will read, and it should not have to diff the same buffer twice.

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")
const GitDiff = preload("res://addons/script_outline/src/git/git_diff.gd")

const GUTTER_NAME = &"script_outline_git_diff"

## CodeEdit re-finds main_gutter / line_numbers / fold_gutter by name whenever a gutter is added, so
## it does not care where we land. ScriptTextEditor's connection_gutter is a plain int cached at
## construction and never revisited — insert at or before it and the editor quietly starts drawing
## its signal icons into this gutter. Going in ahead of the fold arrows clears it, and is where every
## other editor puts a diff gutter anyway.
const GUTTER_BEFORE = &"fold_gutter"

## unscaled px: the column, of which the bar is the leftmost part and the rest is air before the text
const GUTTER_WIDTH = 7
const BAR_WIDTH = 3

## unscaled px of the stub marking a deletion, which owns no line and so sits on the boundary between
## the two that closed over it.
##
## A rect and not the triangle this used to be. A triangle has to be clipped point by point to stay
## inside the control, so the honest cheap version of that is to skip it whenever it does not fit
## whole — and "does not fit whole" is a wrapped line half off the top, i.e. exactly when the mark
## disappears instead of being clipped. A rect intersects in one call and shows the part that fits.
const TICK_WIDTH = 4
const TICK_HEIGHT = 2

## unscaled px of the mark down the minimap's left edge. A bar and not a band across the whole
## minimap: the minimap is there to show the code, and a band would cover what it came to show.
const MINIMAP_BAR_WIDTH = 3

## The Changes list's palette, not the editor theme's success/warning/error. UtilsRemote.EditorColors if want to change
const COLOR_ADDED = GitUtil.Colors.L_GREEN
const COLOR_MODIFIED = GitUtil.Colors.L_YELLOW
const COLOR_DELETED = GitUtil.Colors.RED

## Time before checking current line on text changed
const RECOMPUTE_DEBOUNCE = 0.2

## CodeEdits with a gutter in, by instance id; see Keys for an entry's shape
var _editors:Dictionary = {}
## res:// path -> {repo, lines, head}, the committed side, cached across tab switches
var _baselines:Dictionary = {}
## repo -> the BRANCH_OID last seen, which is the only thing that can make a baseline stale
var _repo_oids:Dictionary = {}
var _repos:Array[String] = []

## instance ids whose buffer has moved since the last recompute
var _dirty:Dictionary = {}
var _debounce:Timer

var _thread:Thread
## the one queued baseline request, as [res_path, repo] — see _start_work()
var _pending:Array = []


func _ready() -> void:
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = RECOMPUTE_DEBOUNCE
	_debounce.timeout.connect(_on_debounce_timeout)
	add_child(_debounce)

	ScriptEditorRef.subscribe(ScriptEditorRef.Event.EDITOR_SCRIPT_CHANGED, _on_editor_script_changed)

	# initialize
	_attach_current()


#region lifecycle

## Project repos, set by git panel on refresh
func set_repos(repos:Array[String]) -> void:
	_repos = repos.duplicate()
	# which repo owns a path may have just changed, and with it every baseline read from one
	_baselines.clear()
	_attach_current()


## A commit is a new baseline, and nothing else about a repo can make one stale
## compare the oid and flush only when it actually moved
func head_moved(repo_dir:String, oid:String) -> void:
	if _repo_oids.get(repo_dir, "") == oid:
		return
	_repo_oids[repo_dir] = oid

	for path in _baselines.keys():
		if _baselines[path][Keys.REPO] == repo_dir:
			_baselines.erase(path)

	_refresh_all()


func clean_up() -> void:
	_teardown()


# fine to run twice if needed (clean_up + predelete)
func _teardown() -> void:
	_join_thread()
	for id in _editors:
		var code_edit:CodeEdit = _editors[id][Keys.CODE_EDIT]
		if not is_instance_valid(code_edit):
			continue # its tab was closed and the gutter went with it
		_remove_gutter(code_edit)
	_editors.clear()
	_dirty.clear()

#endregion


#region attaching

func _attach_current() -> void:
	_attach(ScriptEditorRef.get_current_code_edit(), ScriptEditorRef.get_current_script())


## null is docs
func _on_editor_script_changed(script) -> void:
	if script == null:
		return
	_attach(ScriptEditorRef.get_current_code_edit(), script)


func _attach(code_edit:CodeEdit, script) -> void:
	if not is_instance_valid(code_edit) or not is_instance_valid(script):
		return
	
	_prune()
	
	var path:String = script.resource_path
	if path.is_empty() or path.contains("::"): # "::" -> tscn script, nah
		return
	
	var repo = _repo_for(path)
	if repo.is_empty():
		# it can have moved out of the tracked set since it was attached — set_repos may have just
		# taken its repo away
		_detach(code_edit)
		return
	
	_ensure_gutter(code_edit)

	var id = code_edit.get_instance_id()
	var state:Dictionary = _editors.get(id, {})
	state[Keys.CODE_EDIT] = code_edit
	state[Keys.PATH] = path
	state[Keys.REPO] = repo
	if not state.has(Keys.MARKERS):
		state[Keys.MARKERS] = PackedByteArray()
		state[Keys.HUNKS] = []
		state[Keys.VERSION] = 0
		state[Keys.CACHE] = []
		state[Keys.CACHE_KEY] = null
	_editors[id] = state

	# not ScriptEditorRef, background scripts (tabs) should update too
	if not code_edit.text_changed.is_connected(_on_text_changed):
		code_edit.text_changed.connect(_on_text_changed.bind(code_edit))

	# the minimap draws glyphs and nothing else — it has no notion of a gutter, so the marks have to
	# be painted over it. The draw signal fires after TextEdit's own _draw, so this lands on top.
	if not code_edit.draw.is_connected(_draw_minimap):
		code_edit.draw.connect(_draw_minimap.bind(code_edit))

	# draw from the cache now so a tab switch does not flicker
	# refresh regardless: commit in terminal never reaches filesystem_changed
	if _baselines.has(path):
		_recompute(id)
	_request_baseline(path, repo)


func _detach(code_edit:CodeEdit) -> void:
	if not is_instance_valid(code_edit):
		return
	if code_edit.text_changed.is_connected(_on_text_changed):
		code_edit.text_changed.disconnect(_on_text_changed.bind(code_edit))
	if code_edit.draw.is_connected(_draw_minimap):
		code_edit.draw.disconnect(_draw_minimap.bind(code_edit))
	_remove_gutter(code_edit)
	_editors.erase(code_edit.get_instance_id())
	_dirty.erase(code_edit.get_instance_id())


# Editors whose tab has closed. Their CodeEdit is gone and took the gutter with it
func _prune() -> void:
	for id in _editors.keys():
		if not is_instance_valid(_editors[id][Keys.CODE_EDIT]):
			_editors.erase(id)
			_dirty.erase(id)


# The repo a script belongs to, in case of submodules/repos
func _repo_for(path:String) -> String:
	return GitUtil.find_repo_for(path, _repos)

#endregion


#region the gutter

func _ensure_gutter(code_edit:CodeEdit) -> void:
	var idx = _find_gutter(code_edit)
	if idx < 0:
		idx = _insert_index(code_edit)
		code_edit.add_gutter(idx)
		if idx < 0:
			idx = code_edit.get_gutter_count() - 1
		code_edit.set_gutter_name(idx, GUTTER_NAME)

	# re-pointed rather than added a second time when the gutter is already there, which is what
	# makes this survive an editor hot-reload: disable and re-enable the plugin and the CodeEdits
	# live on with our gutter still in them, holding a Callable into an object that no longer exists
	code_edit.set_gutter_type(idx, TextEdit.GUTTER_TYPE_CUSTOM)
	code_edit.set_gutter_custom_draw(idx, _draw_gutter.bind(code_edit))
	code_edit.set_gutter_width(idx, int(GUTTER_WIDTH * EditorInterface.get_editor_scale()))
	code_edit.set_gutter_draw(idx, true)
	code_edit.set_gutter_overwritable(idx, false)


## By name, add_gutter shifts every later index, and others add gutters
func _find_gutter(code_edit:CodeEdit) -> int:
	for i in code_edit.get_gutter_count():
		if code_edit.get_gutter_name(i) == GUTTER_NAME:
			return i
	return -1


## -1 to append, add_gutter's default.
func _insert_index(code_edit:CodeEdit) -> int:
	for i in code_edit.get_gutter_count():
		if code_edit.get_gutter_name(i) == GUTTER_BEFORE:
			return i
	return -1


func _remove_gutter(code_edit:CodeEdit) -> void:
	var idx = _find_gutter(code_edit)
	if idx > -1:
		code_edit.remove_gutter(idx)
		code_edit.queue_redraw()


## called from inside TextEdit's _draw, once per visible row
## _recompute resolved the hunks into one byte per line and this reads it
func _draw_gutter(line:int, _gutter:int, rect:Rect2, code_edit:CodeEdit) -> void:
	var state:Dictionary = _editors.get(code_edit.get_instance_id(), {})
	if state.is_empty():
		return

	var markers:PackedByteArray = state[Keys.MARKERS]
	# the buffer is edited on every keystroke and re-diffed on a debounce, so the markers are
	# routinely a line or two short of the text they describe. Draw what is known and nothing else.
	if line < 0 or line >= markers.size():
		return

	var mask = markers[line]
	if mask == 0:
		return

	var scale = EditorInterface.get_editor_scale()
	# the first and last rows on screen are half rows, and the rect handed to us is a whole one, so it
	# hangs over the edge — and clip_contents is false on the editor's CodeEdit, so nothing downstream
	# will save us. Anything drawn past the edge lands on the scrollbar and the panel below it.
	var bounds = Rect2(Vector2.ZERO, code_edit.size)

	if mask & (GitDiff.Marker.ADDED | GitDiff.Marker.MODIFIED):
		var color = COLOR_MODIFIED if mask & GitDiff.Marker.MODIFIED else COLOR_ADDED
		_draw_clamped(code_edit, Rect2(rect.position, Vector2(BAR_WIDTH * scale, rect.size.y)),
			color, bounds)

	# a deletion has no line of its own to occupy, so it sits on the boundary of the line that closed
	# over it rather than running down the middle of a line that is still there
	var tick = Vector2(TICK_WIDTH * scale, TICK_HEIGHT * scale)
	if mask & GitDiff.Marker.DELETED_ABOVE:
		_draw_clamped(code_edit, Rect2(rect.position, tick), COLOR_DELETED, bounds)
	if mask & GitDiff.Marker.DELETED_BELOW:
		var bottom = rect.position + Vector2(0, rect.size.y - tick.y)
		_draw_clamped(code_edit, Rect2(bottom, tick), COLOR_DELETED, bounds)


## Nothing reaches the CodeEdit's canvas except through here — a wrapped line half off the top hands
## us a rect that starts above zero, and there is no clipping downstream to catch it.
func _draw_clamped(code_edit:CodeEdit, rect:Rect2, color:Color, bounds:Rect2) -> void:
	var clipped = rect.intersection(bounds)
	if clipped.has_area():
		code_edit.draw_rect(clipped, color)


## The same markers again, down the minimap — where the gutter cannot reach, because a change that
## has scrolled off is exactly the one worth being told about.
##
## Runs on the CodeEdit's draw signal, which fires after TextEdit has drawn itself, so this paints
## over the minimap it just drew. Every other draw.connect in this repo targets a control the plugin
## owns and frees; this one does not, hence the disconnect in _detach().
##
## A caret blink is a redraw like any other, so this runs about twice a second on an editor nobody is
## touching. Hence the cache: the rects only move when the minimap does, and the minimap moves far
## less often than the control repaints.
func _draw_minimap(code_edit:CodeEdit) -> void:
	var state:Dictionary = _editors.get(code_edit.get_instance_id(), {})
	# hunks and not markers: an unmodified file is the common case and this is the whole cost of it
	if state.is_empty() or state[Keys.HUNKS].is_empty():
		return
	if not code_edit.is_drawing_minimap():
		return

	for entry in _minimap_rects(code_edit, state):
		code_edit.draw_rect(entry[0], entry[1])


## The marks as [Rect2, Color], from the cache when nothing that moves them has changed.
##
## The key is what the geometry is a function of, and nothing else. Notably the anchor line rather
## than get_v_scroll(): the minimap only moves in whole rows, so a smooth scroll that has not yet
## shifted it is a hit here where the raw float would miss every frame. get_total_visible_line_count()
## covers folding, wrapping and the line count in one cheap call.
func _minimap_rects(code_edit:CodeEdit, state:Dictionary) -> Array:
	var geometry = _minimap_geometry(code_edit)
	if geometry.is_empty():
		return []

	var key = [
		state[Keys.VERSION],
		code_edit.size,
		geometry[Keys.ANCHOR_LINE],
		code_edit.get_total_visible_line_count(),
	]
	if state.get(Keys.CACHE_KEY) == key:
		return state[Keys.CACHE]

	var rects = _build_minimap_rects(code_edit, state[Keys.MARKERS], geometry)
	state[Keys.CACHE_KEY] = key
	state[Keys.CACHE] = rects
	return rects


## What the minimap is currently showing, as a row height and one line whose position is known.
##
## The anchor is probed at an exact multiple of the row height, and that is the whole trick.
## get_minimap_line_at_pos() computes floor((y - margin) / row_height + the fractional part of
## get_v_scroll()) — so at a y that divides evenly, the fraction has nowhere to go and the answer is
## stable, while a y that does not divide evenly flips by a line as you scroll through it. Measured
## on a static minimap (first_visible_line pinned, so it cannot legitimately move): probing m+3, m+6,
## m+12 and m+300 never wavered, while m+25, m+50, m+100, m+200 and m+500 each flipped by one, at
## exactly the fraction their remainder predicts. The old walk stepped half a row, so every other
## probe landed on a non-multiple and jittered — that was the flicker.
#! keys h:int anchor_line:int anchor_row:int
func _minimap_geometry(code_edit:CodeEdit) -> Dictionary:
	var rows = code_edit.get_minimap_visible_lines()
	if rows <= 0 or code_edit.size.y <= 0.0:
		return {}

	# x is ignored by the mapping — pos(0, y) and pos(2000, y) answer the same — so it stays 0
	var margin = code_edit.get_theme_stylebox(&"normal").get_margin(SIDE_TOP)

	# Measured, not modelled. The margin and the scroll fraction are constant additions, so they
	# cancel in a difference — which is what makes this survive an engine whose internals do not agree
	# with the numbers it reports. The rough answer is then rounded because the row height is
	# minimap_char_size.y + line_spacing, two integers; a couple of lines of error over a couple of
	# hundred rows cannot reach the neighbouring whole number.
	var ya = int(margin + 100)
	var yb = int(margin + 400)
	var la = code_edit.get_minimap_line_at_pos(Vector2i(0, ya))
	var lb = code_edit.get_minimap_line_at_pos(Vector2i(0, yb))
	var between = code_edit.get_visible_line_count_in_range(la, lb) - 1
	if between <= 0:
		return {}
	var h = maxi(1, int(round((yb - ya) / float(between))))

	# row 1 and not row 0: at a scroll fraction of exactly 0 the top row answers one line low, which
	# is its own edge case and not worth understanding when the row below it is free of the whole
	# question
	var anchor_row = 1
	return {
		Keys.H: h,
		Keys.ANCHOR_ROW: anchor_row,
		Keys.ANCHOR_LINE: code_edit.get_minimap_line_at_pos(Vector2i(0, int(margin) + anchor_row * h)),
	}


func _build_minimap_rects(code_edit:CodeEdit, markers:PackedByteArray, geometry:Dictionary) -> Array:
	var rects:Array = []
	var h:int = geometry[Keys.H]
	var height = code_edit.size.y
	var scale = EditorInterface.get_editor_scale()

	var v_scroll = code_edit.get_v_scroll_bar()
	var x = code_edit.size.x - code_edit.get_minimap_width()
	if is_instance_valid(v_scroll) and v_scroll.visible:
		x -= v_scroll.size.x

	var bar_width = MINIMAP_BAR_WIDTH * scale
	var tick_height = TICK_HEIGHT * scale
	var bounds = Rect2(Vector2.ZERO, code_edit.size)

	# by run and not by row: at ~3px a line a per line rect is a stack of slivers, and a hunk is one
	# thing to look at anyway
	var i = 0
	while i < markers.size():
		var mask = markers[i]
		if mask == 0:
			i += 1
			continue

		var start = i
		while i < markers.size() and markers[i] == mask:
			i += 1

		var top = _minimap_y(code_edit, geometry, start)
		var bottom = _minimap_y(code_edit, geometry, i - 1) + h
		if bottom <= 0.0 or top >= height:
			continue # scrolled off the minimap

		var color = COLOR_DELETED
		var rect := Rect2(x, top, bar_width, tick_height)
		if mask & (GitDiff.Marker.ADDED | GitDiff.Marker.MODIFIED):
			color = COLOR_MODIFIED if mask & GitDiff.Marker.MODIFIED else COLOR_ADDED
			rect = Rect2(x, top, bar_width, bottom - top)

		rect = rect.intersection(bounds)
		if rect.has_area():
			rects.append([rect, color])

	return rects


## Where the minimap draws a line, counted in rows from the anchor.
##
## get_visible_line_count_in_range() is what makes this arithmetic rather than a search: it already
## knows how many rows sit between two lines, folds and wraps included, so a folded function above
## the mark shortens the gap without anything here having to notice.
func _minimap_y(code_edit:CodeEdit, geometry:Dictionary, line:int) -> float:
	var anchor:int = geometry[Keys.ANCHOR_LINE]
	var rows:int
	if line >= anchor:
		rows = code_edit.get_visible_line_count_in_range(anchor, line) - 1
	else:
		rows = -(code_edit.get_visible_line_count_in_range(line, anchor) - 1)
	return float((geometry[Keys.ANCHOR_ROW] + rows) * int(geometry[Keys.H]))

#endregion


#region recomputing

func _on_text_changed(code_edit:CodeEdit) -> void:
	if not is_instance_valid(code_edit):
		return
	_dirty[code_edit.get_instance_id()] = true
	_debounce.start()


func _on_debounce_timeout() -> void:
	for id in _dirty:
		_recompute(id)
	_dirty.clear()


func _refresh_all() -> void:
	_prune()
	for id in _editors:
		_recompute(id)


## Resolves editor's buffer against its baseline. Cheap enough to run on a keystroke's debounce:
## the trim in GitDiff means a one line edit costs a one line diff, whatever the file's size.
func _recompute(id:int) -> void:
	var state:Dictionary = _editors.get(id, {})
	if state.is_empty():
		return

	var code_edit:CodeEdit = state[Keys.CODE_EDIT]
	if not is_instance_valid(code_edit):
		_editors.erase(id)
		return

	var baseline:Dictionary = _baselines.get(state[Keys.PATH], {})
	if baseline.is_empty():
		return # still in flight — leave whatever is drawn rather than blank it and blink

	# the repo would not answer. Anything drawn now would be a guess, and a machine with no git on
	# PATH would light up every open script.
	if baseline[Keys.HEAD] == GitUtil.Head.ERROR:
		state[Keys.HUNKS] = []
		state[Keys.MARKERS] = PackedByteArray()
		state[Keys.VERSION] += 1
		_remove_gutter(code_edit)
		return

	# ABSENT arrives as an empty baseline, so a file git has never seen diffs as entirely added,
	# which is what it is
	var new_lines = GitDiff.to_lines(code_edit.text)
	var hunks = GitDiff.diff_lines(baseline[Keys.LINES], new_lines)

	state[Keys.HUNKS] = hunks
	state[Keys.MARKERS] = GitDiff.hunks_to_markers(hunks, new_lines.size())
	# what the minimap cache watches — an int to compare, rather than the marker array itself
	state[Keys.VERSION] += 1
	code_edit.queue_redraw()

#endregion


#region the baseline read

## `git show` off the main thread, on this object's own Thread rather than the panel's.
## Not the panel's worker: this is often not the selected repo in case of multi/submodules
## thread to avoid git spawn on main, concurrent with the panel is safe: `show` and `rev-parse` only read
func _request_baseline(res_path:String, repo_dir:String) -> void:
	if is_instance_valid(_thread) and _thread.is_alive():
		# only the newest request can matter, so replace rather than queue
		_pending = [res_path, repo_dir]
		return

	_join_thread()
	_pending = []
	_thread = Thread.new()
	_thread.start(_baseline_task.bind(res_path, repo_dir, _repo_oids.get(repo_dir, "")))


func _baseline_task(res_path:String, repo_dir:String, oid:String) -> void:
	_on_baseline_ready.call_deferred(res_path, repo_dir, oid, GitUtil.get_file_at_head(repo_dir, res_path))


func _on_baseline_ready(res_path:String, repo_dir:String, oid:String, result:Dictionary) -> void:
	_join_thread()

	# a commit that landed while the read was in flight makes this the *previous* baseline. Guarded
	# by oid and keyed per path rather than by "is this still the current tab" like the panel's
	# guard: a result for a tab the user has since left is not stale, it is a cache entry they are
	# about to want back.
	if _repo_oids.get(repo_dir, "") == oid:
		_baselines[res_path] = {
			Keys.REPO: repo_dir,
			Keys.LINES: GitDiff.to_lines(result[GitUtil.Keys.TEXT]),
			Keys.HEAD: result[GitUtil.Keys.HEAD],
		}

	if not _pending.is_empty():
		var next = _pending
		_pending = []
		_request_baseline(next[0], next[1])

	_refresh_all()


## Mandatory before this object is freed: Godot errors on a Thread that is still running.
func _join_thread() -> void:
	if not is_instance_valid(_thread):
		return
	_thread.wait_to_finish()
	_thread = null

#endregion


class Keys:
	## one entry of _editors
	const CODE_EDIT = &"code_edit"
	const PATH = &"path"
	const MARKERS = &"markers"
	## unread here — what the diff preview window will want, so it need not diff the buffer again
	const HUNKS = &"hunks"
	## bumped whenever MARKERS is rebuilt, so the minimap cache has an int to compare
	const VERSION = &"version"
	## the minimap marks as [Rect2, Color], and what they were computed for
	const CACHE = &"minimap_cache"
	const CACHE_KEY = &"minimap_cache_key"

	## one entry of _minimap_geometry()
	const H = &"row_height"
	const ANCHOR_LINE = &"anchor_line"
	const ANCHOR_ROW = &"anchor_row"

	## one entry of _baselines, and REPO is on an _editors entry too
	const REPO = &"repo"
	const LINES = &"lines"
	const HEAD = &"head"
