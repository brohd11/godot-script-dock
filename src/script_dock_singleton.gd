class_name ScriptDock
extends SingletonRefCount
const SingletonRefCount = Singletons.RefCount

const UtilsRemote = preload("res://addons/script_dock/src/utils/utils_remote.gd")
const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const RightClickHandler = UtilsRemote.RightClickHandler

const SideBarContainer = preload("res://addons/script_dock/src/sidebar_container.gd")
const VarInsertContext = preload("res://addons/script_dock/src/editor_plugins/var_insert.gd")
const GitUtil = preload("res://addons/script_dock/src/git/git_util.gd")
const DiffGutter = preload("res://addons/script_dock/src/git/git_diff_gutter.gd")

const _CACHE_BIN_PATH = "res://.godot/addons/script_dock/script_cache.bin"


#region SingletonAPI

const PE_STRIP_CAST_SCRIPT = preload("res://addons/script_dock/src/script_dock_singleton.gd")

static func get_singleton_name() -> String:
	return "ScriptDockSingleton"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func register_node(node:Node):
	return _register_node(PE_STRIP_CAST_SCRIPT, node)

static func unregister_node(node:Node):
	_unregister_node(PE_STRIP_CAST_SCRIPT, node)

static func call_on_ready(callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)

func _init(node):
	if not is_instance_valid(initial_plugin):
		initial_plugin = node

func _all_unregistered_callback():
	clean_up()

func _get_ready_bool() -> bool:
	return is_node_ready()

#endregion


var initial_plugin:EditorPlugin

var sidebar_container:SideBarContainer
var dm_instance_manager:DockManager.InstanceManager

var var_insert_context:VarInsertContext

# owned here, not by the git panel: the on-editor diff marks are independent of enable_git_panel and
# survive the panel being toggled off. Its data comes from GitService, its eventual home is a
# standalone line-diff plugin.
var diff_gutter:DiffGutter

var _script_data_cache:Dictionary = {}
var right_click_handler:RightClickHandler

func _get_plugin_name() -> String:
	return "Script Outline"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(&"Script", &"EditorIcons")


func _ready() -> void:
	FileSystemSingleton.register_node(initial_plugin)
	EditorGDScriptParser.register_node(initial_plugin)
	var git_service = GitService.register_node(initial_plugin)
	#ScriptEditorRef.subscribe()
	var script_cache = UFile.get_data_bin(_CACHE_BIN_PATH)
	if script_cache != null:
		_script_data_cache = script_cache
		# comment for now, need to work off of icon names, not icons for serialization
		pass
	
	right_click_handler = RightClickHandler.new()
	add_child(right_click_handler)

	# gutter setup runs before the sidebar exists, so diff marks work with the git panel off entirely.
	# GitService drives it: repo set on scan, baselines flushed when a repo's HEAD moves.
	diff_gutter = DiffGutter.new()
	add_child(diff_gutter)
	git_service.repos_updated.connect(_on_git_repos_updated)
	git_service.status_updated.connect(_on_git_status_updated)
	# repos_updated already fired during registration, above — sync the current list in
	diff_gutter.set_repos(git_service.repos)

	var_insert_context = VarInsertContext.new()
	initial_plugin.add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, var_insert_context)
	
	await get_tree().process_frame
	sidebar_container = SideBarContainer.new()
	
	dm_instance_manager = DockManager.InstanceManager.new(initial_plugin, false, true)
	var dm = dm_instance_manager.new_persistent_dock_manager(sidebar_container, DockManager.Slot.DOCK_SLOT_LEFT_UR)
	dm.allow_scene_reload = true


# Feeds the diff gutter from GitService (was the git panel's job before the split).
func _on_git_repos_updated() -> void:
	if is_instance_valid(diff_gutter):
		diff_gutter.set_repos(GitService.get_instance().repos)


# A commit is a new baseline for every script open under that repo, and the oid is what says one
# happened — the gutter flushes and re-reads baselines when HEAD moves.
func _on_git_status_updated(repo_dir:String) -> void:
	if is_instance_valid(diff_gutter):
		var branch = GitService.get_instance().get_branch()
		diff_gutter.head_moved(repo_dir, branch.get(GitUtil.Keys.BRANCH_OID, ""))


## This should be called by the inital plugin that called it before exiting the tree.
func clean_up() -> void:
	var plugin = initial_plugin
	var free_plug = false
	if not is_instance_valid(plugin):
		plugin = EditorPlugin.new()
		free_plug = true
	else:
		FileSystemSingleton.unregister_node(initial_plugin)
		EditorGDScriptParser.unregister_node(initial_plugin)
		GitService.unregister_node(initial_plugin)

	# the gutter added gutters into CodeEdits that outlive us — tear those out before we free
	if is_instance_valid(diff_gutter):
		diff_gutter.clean_up()

	if is_instance_valid(var_insert_context):
		plugin.remove_context_menu_plugin(var_insert_context)
	
	if is_instance_valid(sidebar_container):
		sidebar_container.clean_up()
	
	if is_instance_valid(dm_instance_manager):
		dm_instance_manager.clean_up()
	
	#UFile.store_data_bin(_script_data_cache, _CACHE_BIN_PATH)

	
	if free_plug:
		plugin.queue_free()


static func add_section(section_id:StringName, control:Control, title:=""):
	if title == "":
		title = section_id
	var ins = get_instance()
	ins.sidebar_container.add_section(section_id, title, control)

static func remove_section(section_id:StringName):
	var ins = get_instance()
	ins.sidebar_container.remove_section_by_id(section_id)

static func get_script_data_cache():
	return get_instance()._script_data_cache

static func get_right_click_handler():
	return get_instance().right_click_handler

static func show_in_tree(path:String):
	get_instance().sidebar_container.show_in_tree(path)

static func test():
	remove_section("Test")
