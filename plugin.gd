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
