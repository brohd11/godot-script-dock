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
## the leg of the right triangle marking a deletion
const WEDGE = 4

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



# clean_up added to remove section, should be ok after tests check out
#func _notification(what:int) -> void:
	#if what == NOTIFICATION_PREDELETE:
		#_teardown()


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
	_editors[id] = state

	# not ScriptEditorRef, background scripts (tabs) should update too
	if not code_edit.text_changed.is_connected(_on_text_changed):
		code_edit.text_changed.connect(_on_text_changed.bind(code_edit))

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

	if mask & (GitDiff.Marker.ADDED | GitDiff.Marker.MODIFIED):
		var color = COLOR_MODIFIED if mask & GitDiff.Marker.MODIFIED else COLOR_ADDED
		code_edit.draw_rect(Rect2(rect.position, Vector2(BAR_WIDTH * scale, rect.size.y)), color)

	# a deletion has no line of its own to occupy, so it is drawn as a wedge on the edge of the line
	# that closed over it rather than as a bar down the middle of a line that is still there
	var leg = WEDGE * scale
	if mask & GitDiff.Marker.DELETED_ABOVE:
		var top = rect.position
		code_edit.draw_colored_polygon(PackedVector2Array([
			top, top + Vector2(leg, 0), top + Vector2(0, leg)]), COLOR_DELETED)
	if mask & GitDiff.Marker.DELETED_BELOW:
		var bottom = rect.position + Vector2(0, rect.size.y)
		code_edit.draw_colored_polygon(PackedVector2Array([
			bottom, bottom + Vector2(leg, 0), bottom - Vector2(0, leg)]), COLOR_DELETED)

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
		_remove_gutter(code_edit)
		return

	# ABSENT arrives as an empty baseline, so a file git has never seen diffs as entirely added,
	# which is what it is
	var new_lines = GitDiff.to_lines(code_edit.text)
	var hunks = GitDiff.diff_lines(baseline[Keys.LINES], new_lines)

	state[Keys.HUNKS] = hunks
	state[Keys.MARKERS] = GitDiff.hunks_to_markers(hunks, new_lines.size())
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

	## one entry of _baselines, and REPO is on an _editors entry too
	const REPO = &"repo"
	const LINES = &"lines"
	const HEAD = &"head"
