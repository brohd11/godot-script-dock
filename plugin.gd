@tool
extends EditorPlugin

func _get_plugin_name() -> String:
	return "ScriptDock"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")

func _enter_tree() -> void:
	ScriptDock.register_node(self)

func _exit_tree() -> void:
	ScriptDock.unregister_node(self)
