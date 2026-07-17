extends VBoxContainer

## The sidebar's Git section.
##
## Owns the repo list, the current selection, the per-file status dict and the commit log. Both git
## calls run off the main thread and are published through `status_updated` / `commits_updated`,
## which drive the Changes and Commits lists.

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")
const UControl = UtilsRemote.UControl
const TabBarContainer = UtilsRemote.TabBarContainer

const UtilsLocal = preload("res://addons/script_outline/src/utils/utils_local.gd")

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")
const DiffGutter = preload("res://addons/script_outline/src/git/git_diff_gutter.gd")
const GitChangeList = preload("res://addons/script_outline/src/git/git_change_list.gd")
const GitCommitList = preload("res://addons/script_outline/src/git/git_commit_list.gd")

const MAIN_REPO = "res://"
const MAIN_REPO_TITLE = "Project"
const REFRESH_DEBOUNCE = 1.0

var diff_gutter:DiffGutter

var repo_option_button:OptionButton
var branch_row:HBoxContainer
var branch_label:Label
var divergence_label:Label
var tab_container:TabBarContainer
var change_list:GitChangeList
var commit_list:GitCommitList


signal status_updated(repo_dir:String)
signal commits_updated(repo_dir:String)
signal repos_updated

## res:// paths of every repo found under the project
var repos:Array[String] = []
var current_repo:String = MAIN_REPO
## the last GitUtil.get_status() result for current_repo
var status:Dictionary = {}
## the last GitUtil.get_log() result for current_repo, newest first
var commits:Array[Dictionary] = []

var _dock_data:Dictionary
var _initialized:=false

var _thread:Thread
var _refresh_queued:bool = false
var _debounce_timer:Timer

## commands waiting for the worker thread, as [command, paths] — see run_command()
var _pending_commands:Array = []


func get_dock_data() -> Dictionary:
	return {
		Keys.CURRENT_REPO: current_repo,
		Keys.CURRENT_TAB: tab_container.get_tab_bar().current_tab,
	}


## Arrives after _ready — the nodes already exist, so apply straight away.
func set_dock_data(data:Dictionary) -> void:
	_dock_data = data
	_apply_dock_data()


func _ready() -> void:
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = REFRESH_DEBOUNCE
	_debounce_timer.timeout.connect(refresh_status)
	add_child(_debounce_timer)
	
	diff_gutter = DiffGutter.new()
	add_child(diff_gutter)

	repo_option_button = OptionButton.new()
	repo_option_button.item_selected.connect(_on_repo_selected)
	add_child(repo_option_button)

	# The tooltip goes on the row, not on either Label: Label sets its own mouse_filter to IGNORE, so
	# a tooltip on one would never fire — and that same IGNORE is what lets the mouse fall through to
	# the row, which is what the tooltip describes anyway.
	branch_row = HBoxContainer.new()
	branch_row.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(branch_row)

	# the branch name is the one that gives way: an ellipsis eats the end of a string, so leaving the
	# divergence in here with it would truncate the half worth acting on first
	branch_label = Label.new()
	branch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branch_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	branch_row.add_child(branch_label)

	divergence_label = Label.new()
	branch_row.add_child(divergence_label)

	tab_container = TabBarContainer.new()
	add_child(tab_container)
	UControl.expand(tab_container)

	

	change_list = GitChangeList.new()
	change_list.name = "Changes"
	change_list.changes_command.connect(_on_changes_command)
	tab_container.add_tab(change_list)
	UtilsLocal.set_item_list_sb(change_list)
	
	commit_list = GitCommitList.new()
	commit_list.name = "Commits"
	tab_container.add_tab(commit_list)
	UtilsLocal.set_item_list_sb(commit_list)
	
	
	status_updated.connect(_on_status_updated)
	commits_updated.connect(_on_commits_updated)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed, 1)


	refresh_repos()
	
	#await get_tree().process_frame
	
	
	# The status letters are baked textures, and a row picks its texture up at the moment it is built.
	# The bake is a frame's work and is kicked off at plugin start, so it is all but certain to be
	# done before the first `git status` returns — but if it is not, or if it is redone because the
	# editor's font changed, the rows that missed it are still drawing the letter as a string. Rebuild
	# them and they take the texture.
	
	var glyph_icons = ScriptOutline.get_glyph_icons_node()
	if is_instance_valid(glyph_icons):
		glyph_icons.generated.connect(_rebuild_change_list)
	
	
	if not _initialized:
		_apply_dock_data()


func _apply_dock_data() -> void:
	current_repo = _dock_data.get(Keys.CURRENT_REPO, MAIN_REPO)
	tab_container.set_current_tab(int(_dock_data.get(Keys.CURRENT_TAB, 0)))
	_dock_data = {}
	
	_apply_current_repo()
	_initialized = true


func clean_up() -> void:
	_join_thread()
	# the gutter tears itself down on PREDELETE too, because remove_section() never calls this — but
	# on the shutdown path it should come out before the editor starts folding up around it
	if is_instance_valid(diff_gutter):
		diff_gutter.clean_up()


func refresh_repos() -> void:
	repos = GitUtil.find_repos()

	repo_option_button.clear()
	for repo in repos:
		var repo_name = MAIN_REPO_TITLE if repo == MAIN_REPO else repo.trim_suffix("/").get_file()
		repo_option_button.add_item(repo_name)
		repo_option_button.set_item_metadata(repo_option_button.item_count - 1, repo)
	
	if is_instance_valid(diff_gutter):
		diff_gutter.set_repos(repos)
	
	repos_updated.emit()


## Points the panel at current_repo: falls back to the main repo if it has gone away, syncs the
## option button to it, and pulls a fresh status.
func _apply_current_repo() -> void:
	if not current_repo in repos:
		current_repo = MAIN_REPO

	var idx = repos.find(current_repo)
	if idx > -1:
		repo_option_button.select(idx)

	_clear_lists()
	refresh_status()


func _on_repo_selected(idx:int) -> void:
	set_repo(repo_option_button.get_item_metadata(idx))


func set_repo(repo_dir:String) -> void:
	if current_repo == repo_dir:
		return
	current_repo = repo_dir
	status = {}
	commits = []
	# a command queued against the old repo must not drain against the new one: its paths are res://
	# paths under the *old* root, so they would not even resolve here
	_pending_commands.clear()
	_clear_lists() # don't leave the old repo's rows up while the new git calls run
	refresh_status()


## Don't leave one repo's rows on screen while another repo's data is in flight — the branch least of
## all, since the old one sitting under the new repo's name is a worse lie than showing nothing.
func _clear_lists() -> void:
	change_list.clear_changes()
	commit_list.clear_commits()

	branch_label.text = ""
	divergence_label.hide()
	branch_row.tooltip_text = ""


func _on_status_updated(repo_dir:String) -> void:
	_rebuild_change_list()
	_update_repo_info()

	# a commit is a new baseline for every script open under that repo, and the oid is what says one
	# happened — a save refreshes this panel but does not move HEAD, and re-reading every open
	# script's committed side on every save would spawn git for nothing.
	#
	# Only ever speaks for current_repo, because that is the only repo this panel reads. It is a
	# shortcut, not the guarantee: the gutter re-reads a script's baseline whenever it attaches, and
	# that is what actually covers a commit — which touches only .git, so it never reaches
	# filesystem_changed and never lands here on its own anyway.
	if is_instance_valid(diff_gutter):
		diff_gutter.head_moved(repo_dir, get_branch().get(GitUtil.Keys.BRANCH_OID, ""))


## Spawns nothing: the branch and the counts come out of the status we already have, the commit out of
## the log fetched on the same worker pass. Reading `commits` here is not a frame behind, because
## _on_status_ready assigns both members before it emits either signal.
func _update_repo_info() -> void:
	var info = GitUtil.get_repo_info(status, commits)
	var branch:Dictionary = info[GitUtil.Keys.BRANCH]

	branch_label.text = GitUtil.get_branch_label(branch)

	var divergence = GitUtil.get_divergence_label(branch)
	divergence_label.text = divergence
	divergence_label.visible = not divergence.is_empty()

	# behind means there is something to pull, which is the one that wants noticing
	if not divergence.is_empty():
		divergence_label.add_theme_color_override(&"font_color",
			GitUtil.Colors.L_YELLOW if branch[GitUtil.Keys.BRANCH_BEHIND] > 0
			else GitUtil.Colors.L_GREEN)

	branch_row.tooltip_text = GitUtil.format_repo_tooltip(info)


func _on_commits_updated(_repo_dir:String) -> void:
	_rebuild_commit_list()


func _rebuild_change_list() -> void:
	change_list.clear_changes()

	var files:Dictionary = status.get(GitUtil.Keys.FILES, {})
	var paths = files.keys()
	paths.sort()

	for path:String in paths:
		change_list.add_change(path, current_repo, files[path])


func _rebuild_commit_list() -> void:
	commit_list.clear_commits()
	# git already returned these newest first — do not sort
	for commit in commits:
		commit_list.add_commit(commit)


## The per-file lookup a tree — or the per-file cache in utils_local.gd — will call.
func get_file_status(file_path:String) -> Dictionary:
	return status.get(GitUtil.Keys.FILES, {}).get(file_path, {})


func get_branch() -> Dictionary:
	return status.get(GitUtil.Keys.BRANCH, {})


## Runs git off the main thread: a cold repo can take long enough to drop frames.
func refresh_status() -> void:
	_start_work()


## Queues a write for the worker thread, which then re-reads the repo in the same pass.
##
## Not run inline: a command on the main thread could interleave with an in-flight `git status`, and
## a status that read the repo *before* the write would land *after* it and repaint stale rows, with
## nothing scheduled to correct them. Sharing the one thread makes the write and the re-read
## unsplittable, and makes the refresh something a caller cannot forget.
func run_command(command:GitUtil.Command, paths:Array) -> void:
	if paths.is_empty():
		return

	# resolved against the status in hand, not on the worker: by the time the thread runs, `status`
	# may already be the *next* repo's
	var expanded = GitUtil.expand_paths(command, paths, status.get(GitUtil.Keys.FILES, {}))
	_pending_commands.append([command, expanded])
	_start_work()


func _start_work() -> void:
	if is_instance_valid(_thread) and _thread.is_alive():
		# coalesce rather than pile up threads — re-run once the in flight call lands. Queued commands
		# keep their place in _pending_commands and go out with that run.
		_refresh_queued = true
		return

	_join_thread()

	var queued = _pending_commands
	_pending_commands = []

	_thread = Thread.new()
	_thread.start(_status_task.bind(current_repo, queued, _is_initial()))


## Whether the repo has no commits yet, which changes how a file is unstaged — see GitUtil.
func _is_initial() -> bool:
	return get_branch().get(GitUtil.Keys.BRANCH_INITIAL, false)


func _status_task(repo_dir:String, queued:Array, initial:bool) -> void:
	# the writes go first and the read that follows is therefore never stale with respect to them
	var errors:Array = []
	var wrote_worktree = false

	for entry in queued:
		var command:GitUtil.Command = entry[0]
		var result = GitUtil.run_command(repo_dir, command, entry[1], initial)

		if result[GitUtil.Keys.EXIT] != 0:
			errors.append("git %s failed (%s): %s" % [
				GitUtil.COMMANDS[command][GitUtil.Keys.CMD_LABEL],
				result[GitUtil.Keys.EXIT],
				"\n".join(result[GitUtil.Keys.OUTPUT]).strip_edges(),
			])
		elif GitUtil.COMMANDS[command][GitUtil.Keys.CMD_WORKTREE]:
			wrote_worktree = true

	# every git call shares the one thread: the existing coalescing and stale-repo guard then cover
	# them for free, and a 100 commit log next to a status is a rounding error
	var status_result = GitUtil.get_status(repo_dir)
	# two more spawns for the whole worktree's diff, merged into status_result here on the worker
	# thread — so the handoff below keeps its shape and a row click costs no git call at all
	GitUtil.attach_diffs(repo_dir, status_result)
	var log_result = GitUtil.get_log(repo_dir)
	_on_status_ready.call_deferred(repo_dir, status_result, log_result, errors, wrote_worktree)


func _on_status_ready(repo_dir:String, status_result:Dictionary, log_result:Array, errors:Array,
		wrote_worktree:bool) -> void:
	_join_thread()

	# a failed command otherwise looks exactly like one that worked, because the list simply repaints
	# the rows it already had
	for error:String in errors:
		push_error(error)

	if repo_dir == current_repo: # a repo switch mid flight leaves this result stale
		status = status_result
		commits.assign(log_result)
		status_updated.emit(repo_dir)
		commits_updated.emit(repo_dir)

	# discard and delete rewrite or remove files behind the editor's back, and nothing else will tell
	# it: a script still open on the old contents would write them straight back on the next save
	if wrote_worktree:
		EditorInterface.get_resource_filesystem().scan()

	if _refresh_queued or not _pending_commands.is_empty():
		_refresh_queued = false
		_start_work()


func _join_thread() -> void:
	if not is_instance_valid(_thread):
		return
	_thread.wait_to_finish()
	_thread = null
	
	# status finished point
	#print(status)


func _on_changes_command(command:GitUtil.Command, paths:Array):
	run_command(command, paths)


func _on_filesystem_changed() -> void:
	_debounce_timer.start()


class Keys:
	const CURRENT_REPO = &"git_panel.current_repo"
	const CURRENT_TAB = &"git_panel.current_tab"
