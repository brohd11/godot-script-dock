@tool
extends EditorPlugin

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser

const Outline = preload("res://addons/script_outline/src/outline.gd")

var outline:Outline

var dock_manager:DockManager



func _get_plugin_name() -> String:
	return "Script Outline"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")


func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree() -> void:
	EditorGDScriptParser.register_node(self)
	
	outline = Outline.new()
	dock_manager = DockManager.new(self, outline, DockManager.Slot.DOCK_SLOT_LEFT_UR)
	dock_manager.can_be_freed = true
	dock_manager.allow_scene_reload = true


func _exit_tree() -> void:
	EditorGDScriptParser.unregister_node(self)
	
	if is_instance_valid(outline):
		outline.clean_up()
	
	if is_instance_valid(dock_manager):
		dock_manager.clean_up()
	
	
