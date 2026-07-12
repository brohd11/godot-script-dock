class_name ScriptOutline
extends SingletonRefCount
const SingletonRefCount = Singletons.RefCount

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")
const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser

const SideBarContainer = preload("res://addons/script_outline/src/sidebar_container.gd")
const VarInsertContext = preload("res://addons/script_outline/src/editor_plugins/var_insert.gd")
const GlyphIcons = preload("res://addons/script_outline/src/ui/glyph_icons.gd")
const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")


#region SingletonAPI

const PE_STRIP_CAST_SCRIPT = preload("res://addons/script_outline/src/script_outline_singleton.gd")

static func get_singleton_name() -> String:
	return "ScriptOutlineSingleton"

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
var glyph_icons:GlyphIcons

func _get_plugin_name() -> String:
	return "Script Outline"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(&"Script", &"EditorIcons")


func _ready() -> void:
	FileSystemSingleton.register_node(initial_plugin)
	EditorGDScriptParser.register_node(initial_plugin)
	#ScriptEditorRef.subscribe()

	# Baking the status letters costs one rendered frame, so it starts here — the earliest point there
	# is a tree to render in, and a long way ahead of the first `git status`, which is a process spawn
	# on a worker thread. Nothing blocks on it: a row built before the bake lands draws its letter as
	# a string and is rebuilt when GlyphIcons reports in.
	glyph_icons = GlyphIcons.new()
	add_child(glyph_icons)
	glyph_icons.warm(GitUtil.get_letter_set())

	var_insert_context = VarInsertContext.new()
	initial_plugin.add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, var_insert_context)
	
	sidebar_container = SideBarContainer.new()
	
	dm_instance_manager = DockManager.InstanceManager.new(initial_plugin, false, true)
	var dm = dm_instance_manager.new_persistent_dock_manager(sidebar_container, DockManager.Slot.DOCK_SLOT_LEFT_UR)
	dm.allow_scene_reload = true


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
	
	if is_instance_valid(var_insert_context):
		plugin.remove_context_menu_plugin(var_insert_context)
	
	if is_instance_valid(sidebar_container):
		sidebar_container.clean_up()
	
	if is_instance_valid(dm_instance_manager):
		dm_instance_manager.clean_up()
	
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


static func test():
	remove_section("Test")
