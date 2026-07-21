extends VBoxContainer

const Self = preload("res://addons/script_dock/src/file_tabs/script_collection.gd")

const UtilsLocal = preload("res://addons/script_dock/src/utils/utils_local.gd")
const UtilsRemote = preload("res://addons/script_dock/src/utils/utils_remote.gd")

const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys
const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options

const UFile = UtilsRemote.UFile
const UName = UtilsRemote.UName
const UResource = UtilsRemote.UResource
const UGDScript = UtilsRemote.UGDScript

const CollectionSingleton = UtilsRemote.CollectionSingleton
const CollectionManager = CollectionSingleton.CollectionManager
const CollectionBase = CollectionManager.CollectionBase
const Form = CollectionSingleton.Form

const CacheHelper = UtilsRemote.CacheHelper
const FSTree = UtilsRemote.FSTree
const ItemKeys = FSTree.ItemKeys


const COL_MANAGER_NAME = &"script_outline"
var col_storage_dir:String = "res://.addons/script_dock/collections/"

var filesystem_singleton:FileSystemSingleton
var script_list_manager:ScriptListManager

var _script_data_cache:= {}

var filter_line_edit:LineEdit
var item_list:ItemList
var git_icon_overlay:UtilsRemote.GitDataDraw.GitItemHelper

var current_filter_text:String = ""

var collection_data:Dictionary = {}

var current_collection:CollectionBase

signal collection_update(collection_tab:Self)

func _init() -> void:
	name = "unsaved"

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
	
	UtilsLocal.set_item_list_sb(item_list)
	
	filesystem_singleton = FileSystemSingleton.get_instance()
	FileSystemSingleton.call_on_ready(_on_fs_ready)

func _on_fs_ready():
	filesystem_singleton.filesystem_changed.connect(_on_file_system_changed, 1)
	
	var man = _get_col_manager()
	man.collections_updated.connect(_on_collections_updated)
	if not is_instance_valid(current_collection):
		current_collection = man.new_collection(name, false) # name should be unsaved_x
	
	_build_list()

func _on_file_system_changed():
	_build_list()

func build_list():
	_build_list()

func _on_collections_updated():
	_build_list()

func _build_list():
	if not is_instance_valid(git_icon_overlay):
		git_icon_overlay = UtilsRemote.GitDataDraw.GitItemHelper.new(item_list)
	var selected_idxes = item_list.get_selected_items()
	var selected_idx = -1
	var selected_uid = ""
	if selected_idxes.size() > 0:
		selected_uid = get_item_uid(selected_idxes[0])
	
	var filtering = current_filter_text != ""
	item_list.clear()
	
	#print(current_collection, current_collection.get_uids())
	var uids = current_collection.get_uids(true)
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
		if not selected_uid.is_empty() and uid == selected_uid:
			selected_idx = idx
		
		var file_data = UtilsLocal.get_file_data(path, _script_data_cache)
		item_list.add_item(display_name, file_data.get(ItemKeys.ICON))
		item_list.set_item_icon_modulate(idx, file_data.get(ItemKeys.ICON_COLOR))
		item_list.set_item_metadata(idx, data)
		item_list.set_item_tooltip(idx, path)
		
		git_icon_overlay.set_item_fg_color(idx, path)
	
	if selected_idx > -1:
		item_list.select(selected_idx)


func get_options():
	var options = Options.new()
	var man = _get_col_manager()
	options.add_option("New Collection", _new_collection, ["New"])
	for col in man.get_collections():
		var col_name = col.get_collection_name()
		var label = "Load Collection".path_join(col_name)
		if col == current_collection:
			label += " (current)"
		options.add_option(label, _load_collection.bind(col_name), ["ThemeSelectAll", null])
	
	if not man.has_collection_object(current_collection):
		options.add_option("Save Collection", _save_collection, ["Save"])
	else:
		options.add_option("Rename Collection", _rename_collection, ["Edit"])
	return options


func set_tab_data(data:Dictionary):
	var man = _get_col_manager()
	var current_col_name = data.get(Keys.CURRENT_COLLECTION, "")
	var current_col_data = data.get(Keys.COLLECTION_DATA, {})
	if not current_col_data.is_empty() or not man.has_collection(current_col_name):
		current_collection = man.new_collection(current_col_name, false)
		current_collection.set_data(current_col_data)
	else:
		current_collection = man.get_collection(current_col_name)
	

func get_tab_data() -> Dictionary:
	var man = _get_col_manager()
	var data = {}
	data[Keys.CURRENT_COLLECTION] = current_collection.get_collection_name()
	if not man.has_collection_object(current_collection):
		data[Keys.COLLECTION_DATA] = current_collection.get_data()
	return data


#region Collection

func _new_collection():
	var man = _get_col_manager()
	current_collection = man.new_collection("", false)
	collection_update.emit(self)
	_build_list()

func _load_collection(col_name:String):
	var man = _get_col_manager()
	current_collection = man.get_collection(col_name)
	collection_update.emit(self)
	_build_list()

func _save_collection():
	var man = _get_col_manager()

	var new_name = await _name_collection_form("New Collection", "New Collection Name")
	if new_name.is_empty():
		return
	
	current_collection.set_collection_name(new_name)
	
	man.add_collection(current_collection)
	man.save_collection(current_collection)
	#man.save_collection()
	collection_update.emit(self)

func _rename_collection():
	var man = _get_col_manager()

	var new_name = await _name_collection_form("Rename Collection", "New Collection Name")
	if new_name.is_empty():
		return
	var success = man.rename_collection(current_collection, new_name)
	if success:
		collection_update.emit(self)

func _try_save_collection():
	var man = _get_col_manager()
	if man.has_collection_object(current_collection):
		man.save_collection(current_collection)

func _get_col_manager() -> CollectionManager:
	col_storage_dir = "res://.addons/script_dock/collections/"
	return CollectionSingleton.get_named_manager({
		&"manager_name": COL_MANAGER_NAME,
		&"storage_dir": col_storage_dir
	})

func _name_collection_form(title:String, field:String) -> String:
	var form_data = Form.Data.new_data({
		&"title": title,
		&"size": Vector2(400, 100) * EditorInterface.get_editor_scale(),
		field: Form.Data.line_edit({
			&"placeholder": "Enter name...",
		}),
	})
	
	var result = await Form.construct_and_display(form_data)
	if Form.was_cancelled(result) or (result is String and result.is_empty()):
		return ""
	
	var new_name = result.get(field, "")
	new_name = new_name.trim_prefix("/").trim_suffix("/")
	var man = _get_col_manager()
	if new_name in man.collections.keys():
		printerr("Collection already exists.")
		return ""
	return new_name

#endregion


#region Drag Data

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
	var file_types = ScriptListManager.get_text_file_types()
	if from is Self:
		var file_path = files[0]
		var from_idx = data.get(Keys.DROP_DATA_FROM_IDX)
		var item_data = from.item_list.get_item_metadata(from_idx)
		var uid = item_data.get(Keys.UID)
		var new_idx = min(item_list.get_item_at_position(at_position), item_list.item_count - 1)
		if from != self:
			from.current_collection.remove_file(uid)
			from.build_list()
		
		add_path(uid)
		_move_item(uid, new_idx)
	else:
		for f in files:
			if f.get_extension() in file_types:
				add_path(f)
	
	_try_save_collection()
	_build_list()

func _check_new_files_in_array(files:Array):
	var uids = current_collection.get_uids()
	var file_types = ScriptListManager.get_text_file_types()
	for f in files:
		var uid = UFile.path_to_uid(f)
		if not uid in uids and f.get_extension() in file_types:
			return true
	return false

#endregion


#region Click

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

func _custom_right_click():
	var options = Options.new()
	var idx = get_selected_item()
	var path = get_item_path(idx)
	
	var valid:UtilsRemote.FSSmallPopup.FileStatus = UtilsRemote.FSSmallPopup.right_click(options, path)
	if valid == UtilsRemote.FSSmallPopup.FileStatus.VALID:
		options.add_separator()
		options.add_option("Remove", _remove_item.bind(item_list.get_selected_items()[0]), ["Close"])
	
	ScriptDock.get_right_click_handler().display_popup(options)


func _open_or_activate_path(path:String, right_click:=false, click_pos:=Vector2()):
	if not FileAccess.file_exists(path):
		printerr("Script Outline - Collection - File does not exist: ", path)
		return
	var script_idx = script_list_manager.get_script_index_or_open(path, filesystem_singleton)
	if script_idx != -1:
		script_list_manager.activate_item_by_idx(script_idx) # script tabs activates when tab changes, so this is needed here
		if right_click:
			script_list_manager.right_click_by_idx(script_idx, click_pos)

#endregion


func _on_filter_line_text_changed(new_text:String):
	current_filter_text = new_text
	_build_list()

func get_selected_item():
	var items = item_list.get_selected_items()
	if items.is_empty():
		return
	return items[0]

func get_item_path(idx:int):
	var data = item_list.get_item_metadata(idx)
	return data.get(Keys.PATH)

func get_item_uid(idx:int):
	var data = item_list.get_item_metadata(idx)
	return data.get(Keys.UID)

#region List Items

func add_path(path:String):
	current_collection.new_file(path)

func _move_item(uid_to_move: String, new_idx: int):
	var file_data = current_collection.get_file_data(uid_to_move)
	var old_index = file_data.index
	print(file_data)
	current_collection.move_file(old_index, new_idx)

func _remove_item(idx:int):
	var metadata = item_list.get_item_metadata(idx)
	var uid = metadata.get(Keys.UID)
	current_collection.remove_file(uid)
	item_list.remove_item(idx)

#endregion




func _get_display_names(sort:=true) -> Dictionary:
	var item_data: Dictionary = {}
	var groups: Dictionary = {}
	
	var col_data = current_collection.get_data()
	for uid in current_collection.get_uids(true): # --- STEP 1: Parse paths and group by file name ---
		var data = col_data[uid]
		var p = UFile.uid_to_path(uid)
		if p == "":
			p = data.get(CollectionBase.Keys.PATH)
		
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


func _get_script_tabs_node():
	var root = Engine.get_main_loop().root
	var ed_node = root.get_child(0) as Node
	return ed_node.get_node_or_null("EditorSingletons/ScriptTabSingleton")

class Keys extends CollectionBase.Keys:
	# for display
	const PARTS = &"parts"
	const DISPLAY_NAME = &"display_name"
	
	const DROP_DATA_FROM_IDX = &"from_idx"
	
	# persistent
	const CURRENT_COLLECTION = &"collection.current_collection"
	const COLLECTION_DATA = &"collection.collection_data"
