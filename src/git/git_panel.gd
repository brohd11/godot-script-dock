extends VBoxContainer

## The sidebar's Git section.
##
## Owns the repo list, the current selection, and the per-file status dict. Status is gathered off
## the main thread and published through `status_updated`, which drives the Changes list. The
## Commits tab is not wired up yet.

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")
const UControl = UtilsRemote.UControl
const TabBarContainer = UtilsRemote.TabBarContainer
const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")
const GitChangeList = preload("res://addons/script_outline/src/git/git_change_list.gd")

const MAIN_REPO = "res://"
const MAIN_REPO_TITLE = "Project"
const REFRESH_DEBOUNCE = 1.0

var repo_option_button:OptionButton
var tab_container:TabBarContainer
var change_list:GitChangeList
var commit_list:ItemList


signal status_updated(repo_dir:String)
signal repos_updated

## res:// paths of every repo found under the project
var repos:Array[String] = []
var current_repo:String = MAIN_REPO
## the last GitUtil.get_status() result for current_repo
var status:Dictionary = {}

var _dock_data:Dictionary

var _thread:Thread
var _refresh_queued:bool = false
var _debounce_timer:Timer


func get_dock_data() -> Dictionary:
	return {Keys.CURRENT_REPO: current_repo}


func set_dock_data(data:Dictionary) -> void:
	_dock_data = data
	current_repo = _dock_data.get(Keys.CURRENT_REPO, MAIN_REPO)
	if is_node_ready():
		_apply_current_repo()


func _ready() -> void:
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = REFRESH_DEBOUNCE
	_debounce_timer.timeout.connect(refresh_status)
	add_child(_debounce_timer)

	repo_option_button = OptionButton.new()
	repo_option_button.item_selected.connect(_on_repo_selected)
	add_child(repo_option_button)

	tab_container = TabBarContainer.new()
	add_child(tab_container)
	UControl.expand(tab_container)

	change_list = GitChangeList.new()
	change_list.name = "Changes"
	tab_container.add_tab(change_list)

	commit_list = ItemList.new()
	commit_list.name = "Commits"
	tab_container.add_tab(commit_list)

	status_updated.connect(_on_status_updated)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed, 1)

	refresh_repos()
	# DockManager calls set_dock_data() after _ready(), so deferring means the restored repo is
	# already in place and exactly one status runs — against the right repo
	_apply_current_repo.call_deferred()


func clean_up() -> void:
	_join_thread()


func refresh_repos() -> void:
	repos = GitUtil.find_repos()

	repo_option_button.clear()
	for repo in repos:
		var repo_name = MAIN_REPO_TITLE if repo == MAIN_REPO else repo.trim_suffix("/").get_file()
		repo_option_button.add_item(repo_name)
		repo_option_button.set_item_metadata(repo_option_button.item_count - 1, repo)

	repos_updated.emit()


## Points the panel at current_repo: falls back to the main repo if it has gone away, syncs the
## option button to it, and pulls a fresh status.
func _apply_current_repo() -> void:
	if not current_repo in repos:
		current_repo = MAIN_REPO

	var idx = repos.find(current_repo)
	if idx > -1:
		repo_option_button.select(idx)

	change_list.clear_changes()
	refresh_status()


func _on_repo_selected(idx:int) -> void:
	set_repo(repo_option_button.get_item_metadata(idx))


func set_repo(repo_dir:String) -> void:
	if current_repo == repo_dir:
		return
	current_repo = repo_dir
	status = {}
	change_list.clear_changes() # don't leave the old repo's rows up while the new status runs
	refresh_status()


func _on_status_updated(_repo_dir:String) -> void:
	_rebuild_change_list()


func _rebuild_change_list() -> void:
	change_list.clear_changes()

	var files:Dictionary = status.get(GitUtil.Keys.FILES, {})
	var paths = files.keys()
	paths.sort()

	for path:String in paths:
		change_list.add_change(path, current_repo, files[path])


## The per-file lookup a tree — or the per-file cache in utils_local.gd — will call.
func get_file_status(file_path:String) -> Dictionary:
	return status.get(GitUtil.Keys.FILES, {}).get(file_path, {})


func get_branch() -> Dictionary:
	return status.get(GitUtil.Keys.BRANCH, {})


## Runs git off the main thread: a cold repo can take long enough to drop frames.
func refresh_status() -> void:
	if is_instance_valid(_thread) and _thread.is_alive():
		# coalesce rather than pile up threads — re-run once the in flight call lands
		_refresh_queued = true
		return

	_join_thread()
	_thread = Thread.new()
	_thread.start(_status_task.bind(current_repo))


func _status_task(repo_dir:String) -> void:
	var result = GitUtil.get_status(repo_dir)
	_on_status_ready.call_deferred(repo_dir, result)


func _on_status_ready(repo_dir:String, result:Dictionary) -> void:
	_join_thread()
	
	if repo_dir == current_repo: # a repo switch mid flight leaves this result stale
		status = result
		status_updated.emit(repo_dir)

	if _refresh_queued:
		_refresh_queued = false
		refresh_status()


func _join_thread() -> void:
	if not is_instance_valid(_thread):
		return
	_thread.wait_to_finish()
	_thread = null
	
	# status finished point
	#print(status)


func _on_filesystem_changed() -> void:
	_debounce_timer.start()


class Keys:
	const CURRENT_REPO = &"git_panel.current_repo"
