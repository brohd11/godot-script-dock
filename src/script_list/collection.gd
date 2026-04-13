extends VBoxContainer

const Self = preload("res://addons/script_outline/src/script_list/collection.gd")

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys
const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const UFile = UtilsRemote.UFile
const UResource = UtilsRemote.UResource
const UGDScript = UtilsRemote.UGDScript

const TEXT_FILE_TYPES = ScriptListManager.TEXT_FILE_TYPES

var filesystem_singleton:FileSystemSingleton
var script_list_manager:ScriptListManager

var right_click_handler:RightClickHandler

var filter_line_edit:LineEdit
var item_list:ItemList

var current_filter_text:String = ""

var collection_data:Dictionary = {}


func _init() -> void:
	name = "Collection"

func _ready() -> void:
	script_list_manager = ScriptListManager.get_instance()
	
	filter_line_edit = LineEdit.new()
	filter_line_edit.text_changed.connect(_on_filter_line_text_changed)
	filter_line_edit.right_icon = EditorInterface.get_editor_theme().get_icon(&"Search", &"EditorIcons")
	filter_line_edit.clear_button_enabled = true
	filter_line_edit.placeholder_text = "Filter Scripts"
	
	add_child(filter_line_edit)
	
	item_list = ItemList.new()
	add_child(item_list)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.allow_rmb_select = true
	item_list.item_activated.connect(_on_item_activated)
	item_list.item_clicked.connect(_on_item_clicked)
	item_list.select_mode = ItemList.SELECT_SINGLE
	item_list.set_drag_forwarding(_item_list_get_drag_data, _item_list_can_drop_data, _item_list_drop_data)
	
	filesystem_singleton = FileSystemSingleton.get_instance()
	FileSystemSingleton.call_on_ready(_on_fs_ready)

func _on_fs_ready():
	filesystem_singleton.filesystem_changed.connect(_on_file_system_changed, 1)
	_build_list()

func _on_file_system_changed():
	_build_list()

func build_list():
	_build_list()

func _build_list():
	var filtering = current_filter_text != ""
	item_list.clear()
	
	var uids = collection_data.keys()
	uids.sort_custom(
		func(a,b):
			return collection_data[a].get(Keys.IDX) < collection_data[b].get(Keys.IDX)
	)
	
	#sort display names like script list
	var display_names = _get_display_names(false)
	for uid in uids:
		var data = display_names.get(uid)
		var display_name = data.get(Keys.DISPLAY_NAME)
		if filtering:
			if not current_filter_text.is_subsequence_ofn(display_name):
				continue
		
		data[Keys.UID] = uid
		var path = data.get(Keys.PATH)
		var idx = item_list.item_count
		var icon = filesystem_singleton.get_type_icon(path)
		item_list.add_item(display_name, icon)
		if UGDScript.FileRead.get_is_tool(path):
			item_list.set_item_icon_modulate(idx, script_list_manager.tool_color)
		item_list.set_item_metadata(idx, data)
		item_list.set_item_tooltip(idx, path)


func _item_list_get_drag_data(at_pos:Vector2):
	#if not Input.is_key_pressed(KEY_CTRL):
		#return
	var item = item_list.get_item_at_position(at_pos)
	var path = get_item_path(item)
	var data = {"type":"files", "files": [path], "from": self, Keys.DROP_DATA_FROM_IDX: item}
	return data

func _item_list_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data.get("type", "") != "files":
		return false
	var files = data.get("files")
	var from = data.get("from")
	if from is Self:
		if from == self:
			return true
	
	return _check_new_files_in_array(files)


func _item_list_drop_data(at_position: Vector2, data: Variant) -> void:
	var files = data.get("files")
	var from = data.get("from")
	if from is Self:
		var file_path = files[0]
		var from_idx = data.get(Keys.DROP_DATA_FROM_IDX)
		var item_data = from.item_list.get_item_metadata(from_idx)
		var uid = item_data.get(Keys.UID)
		var new_idx = min(item_list.get_item_at_position(at_position), item_list.item_count - 1)
		if from != self:
			from.collection_data.erase(uid)
			from.build_list()
			from.reindex_items()
		
		if not collection_data.has(uid):
			item_data[Keys.IDX] = collection_data.size()
			collection_data[uid] = item_data
		
		_move_item(uid, new_idx)
	else:
		for f in files:
			if f.get_extension() in TEXT_FILE_TYPES:
				add_path(f)
	
	_build_list()
	reindex_items()


func _check_new_files_in_array(files:Array):
	for f in files:
		var uid = UFile.path_to_uid(f)
		if not collection_data.has(uid) and f.get_extension() in TEXT_FILE_TYPES:
			return true
	return false

func _move_item(uid_to_move: String, new_idx: int):
	if not collection_data.has(uid_to_move): # check if item exists to avoid crashes
		printerr("UID not found: ", uid_to_move)
		return
	
	var uid_to_move_data = collection_data[uid_to_move]
	var old_idx = uid_to_move_data.get(Keys.IDX)
	new_idx = clamp(new_idx, 0, collection_data.size() - 1) # Prevent out-of-bounds indexes
	if old_idx == new_idx: # if the index didn't actually change, do nothing
		return
	uid_to_move_data[Keys.IDX] = new_idx # apply the new index to the target item
	
	for uid in collection_data: # shift all other affected items
		if uid == uid_to_move: # skip the item moved
			continue
		
		var item_data = collection_data[uid]
		var current_idx = item_data.get(Keys.IDX)
		if old_idx < new_idx: # moving the item "down" the list (e.g., Index 1 -> 4) ie. 2 -> 1, 3 -> 2
			if current_idx > old_idx and current_idx <= new_idx:
				item_data[Keys.IDX] = current_idx - 1
		
		elif old_idx > new_idx: # moving the item "up" the list (e.g., Index 4 -> 1) ie. 1 -> 2, 2 -> 3
			if current_idx >= new_idx and current_idx < old_idx:
				item_data[Keys.IDX] = current_idx + 1


func _on_item_activated(idx:int):
	var path = get_item_path(idx)
	_open_or_activate_path(path)

func _on_item_clicked(idx:int, pos:Vector2, mouse_button:int):
	var ctrl_pressed := Input.is_key_pressed(KEY_CTRL)
	var path = get_item_path(idx)
	if mouse_button == MOUSE_BUTTON_LEFT:
		return
		_open_or_activate_path(path)
	
	if mouse_button == MOUSE_BUTTON_RIGHT:
		if not ctrl_pressed:
			_custom_right_click()
		else:
			_open_or_activate_path(path, true, pos)

func _open_or_activate_path(path:String, right_click:=false, click_pos:=Vector2()):
	if not FileAccess.file_exists(path):
		printerr("Script Outline - Collection - File does not exist: ", path)
		return
	var script_idx = script_list_manager.get_script_index_or_open(path, filesystem_singleton)
	if script_idx != -1:
		script_list_manager.activate_item_by_idx(script_idx) # script tabs activates when tab changes, so this is needed here
		if right_click:
			script_list_manager.right_click_by_idx(script_idx, click_pos)

func _on_filter_line_text_changed(new_text:String):
	current_filter_text = new_text
	_build_list()

func _custom_right_click():
	var options = Options.new()
	options.add_option("Remove", _remove_item.bind(item_list.get_selected_items()[0]), ["Close"])
	right_click_handler.display_popup(options)


func _remove_item(idx:int):
	var metadata = item_list.get_item_metadata(idx)
	var uid = metadata.get(Keys.UID)
	item_list.remove_item(idx)
	collection_data.erase(uid)
	reindex_items()


func get_item_path(idx:int):
	var data = item_list.get_item_metadata(idx)
	return data.get(Keys.PATH)


func add_path(path:String):
	var uid = UFile.path_to_uid(path)
	if not collection_data.has(uid):
		var next_idx = collection_data.size()
		collection_data[uid] = {
			Keys.IDX: next_idx,
			Keys.PATH: path,
			}



func set_tab_data(data:Dictionary):
	collection_data.clear()
	var col_data = data.get(Keys.DATA, {})
	for uid in col_data.keys():
		var uid_data = col_data[uid]
		collection_data[uid] = {
			Keys.IDX: int(uid_data.get(Keys.IDX)),
			Keys.PATH: uid_data.get(Keys.PATH)
		}

func get_tab_data() -> Dictionary:
	var data = {
		Keys.DATA: collection_data
	}
	return data

func _get_display_names(sort:=true) -> Dictionary:
	var item_data: Dictionary = {}
	var groups: Dictionary = {}
	
	for uid in collection_data.keys(): # --- STEP 1: Parse paths and group by file name ---
		var data = collection_data[uid]
		var p = UFile.uid_to_path(uid)
		if p == "":
			p = data.get(Keys.PATH)
		
		var parts = Array(p.split("/"))
		parts.reverse() # Split the path and reverse it so index 0 is always the file name
		var filename = parts[0]
		var file_valid = FileAccess.file_exists(uid)
		if not file_valid:
			filename = filename + " [File not present]"
		
		var item = {
			Keys.PATH: p,
			Keys.PARTS: parts,
			Keys.DISPLAY_NAME: filename # Default to just the filename
		}
		
		item_data[uid] = item
		if not groups.has(filename):
			groups[filename] = []
		groups[filename].append(item)
	
	for filename in groups: # --- STEP 2: Resolve duplicates to the same directory level ---
		var group: Array = groups[filename]
		if group.size() > 1: # If there are duplicates, we need to add parent directories
			var depth = 1
			var max_possible_depth = 0
			for item in group: # Find the longest path in this group to prevent infinite loops
				max_possible_depth = max(max_possible_depth, item.parts.size())
			
			while depth <= max_possible_depth: # Keep adding directory levels until all display names in the group are unique
				var seen_names = {}
				var is_unique = true
				for item in group:
					var test_name = _get_name_at_depth(item.parts, depth)
					if seen_names.has(test_name):
						is_unique = false
						break
					seen_names[test_name] = true
				
				if is_unique:
					break # We found the required depth to make everything unique!
				
				depth += 1
			
			for item in group: # Apply this final depth to EVERY item in the group
				item.display_name = _get_name_at_depth(item.parts, depth)
	
	if sort:
		#items.sort_custom(func(a, b):
			#return a.display_name.naturalnocasecmp_to(b.display_name) < 0
		#)
		pass
	
	return item_data

func _get_name_at_depth(parts: Array, depth: int) -> String:
	var actual_depth = min(depth, parts.size()) # Don't try to get more directories than the path actually has
	var slice = parts.slice(0, actual_depth)
	slice.reverse() # Put it back in normal left-to-right order
	return "/".join(PackedStringArray(slice))

func reindex_items():
	for i in range(item_list.item_count):
		var data = item_list.get_item_metadata(i)
		var uid = data.get(Keys.UID)
		collection_data[uid][Keys.IDX] = i


class Keys:
	const IDX = &"idx"
	const UID = &"uid"
	const PATH = &"path"
	const PARTS = &"parts"
	const DISPLAY_NAME = &"display_name"
	
	const VALID_FILE = &"valid_file"
	
	const DATA = &"collection.keys.data"
	
	const DROP_DATA_FROM_IDX = &"from_idx"
