@tool
extends EditorPlugin

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")
const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser

const SideBarContainer = preload("res://addons/script_outline/src/sidebar_container.gd")
const VarInsertContext = preload("res://addons/script_outline/src/editor_plugins/var_insert.gd")

var sidebar_container:SideBarContainer
var dm_instance_manager:DockManager.InstanceManager

var var_insert_context:VarInsertContext

func _get_plugin_name() -> String:
	return "Script Outline"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")

func _enter_tree() -> void:
	ScriptOutline.register_node(self)


func _exit_tree() -> void:
	ScriptOutline.unregister_node(self)


#func _enter_tree() -> void:
	#FileSystemSingleton.register_node(self)
	#EditorGDScriptParser.register_node(self)
	#
	#var_insert_context = VarInsertContext.new()
	#add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, var_insert_context)
	#
	#sidebar_container = SideBarContainer.new()
	#
	#dm_instance_manager = DockManager.InstanceManager.new(self, false, true)
	#var dm = dm_instance_manager.new_persistent_dock_manager(sidebar_container, DockManager.Slot.DOCK_SLOT_LEFT_UR)
	#dm.allow_scene_reload = true
#
#
#func _exit_tree() -> void:
	#FileSystemSingleton.unregister_node(self)
	#EditorGDScriptParser.unregister_node(self)
	#
	#if is_instance_valid(var_insert_context):
		#remove_context_menu_plugin(var_insert_context)
	#
	#if is_instance_valid(sidebar_container):
		#sidebar_container.clean_up()
	#
	#if is_instance_valid(dm_instance_manager):
		#dm_instance_manager.clean_up()
