
const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")
const UFile = UtilsRemote.UFile

const Options = UtilsRemote.Options

const UtilsLocal = preload("res://addons/script_outline/src/utils/utils_local.gd")

enum FileStatus {
	VALID,
	INVALID,
	MISSING
}


static func right_click(options:Options, path:String) -> FileStatus:
	if not FileAccess.file_exists(path):
		options.add_separator("Missing File")
		return FileStatus.MISSING
	elif not FileSystemSingleton.is_path_valid(path):
		options.add_separator("Invalid File")
		return FileStatus.INVALID
	
	var script_tabs = UtilsLocal.get_script_tabs_node()
	if is_instance_valid(script_tabs):
		var valid_containers = script_tabs.get_valid_containers_for_path(path, _open_in_split)
		options._dict.merge(valid_containers)
		options.add_separator()
	
	options.add_option("Copy Script Path", _copy_to_clipboard.bind(path), ["ActionCopy"])
	options.add_option("Copy Script UID", _copy_to_clipboard.bind(path, true))
	options.add_separator()
	options.add_option("Show in Tree", _navigate_to.bind(path), ["ShowInFileSystem"])
	options.add_option("Show in File Manager", _navigate_to.bind(path, true), ["Filesystem"])
	
	return FileStatus.VALID

static func _copy_to_clipboard(path:String, uid:=false):
	var to_clip = UFile.path_to_uid(path) if uid else path
	DisplayServer.clipboard_set(to_clip)


static func _open_in_split(path:String, target_tab:int):
	var script_tabs = UtilsLocal.get_script_tabs_node()
	if not is_instance_valid(script_tabs):
		printerr("No ScriptTab singleton found. How did you get here?")
		return
	script_tabs.open_script(path, target_tab, FileSystemSingleton.get_instance())



static func _navigate_to(path:String, os_file:=false):
	if os_file:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
	else:
		ScriptOutline.show_in_tree(path)
		pass
		#show_in_filesystem.emit(path) # this should be for the tree I think? need a better way to handle
		#EditorInterface.get_file_system_dock().navigate_to_path(path)
