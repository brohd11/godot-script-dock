extends VBoxContainer

const ScriptListManager = ALibEditor.Singletons.ScriptListManager
const SLKeys = ScriptListManager.Keys
const RightClickHandler = ClickHandlers.RightClickHandler
const Options = RightClickHandler.Options

const UFile = ALibRuntime.Utils.UFile
const UResource = ALibRuntime.Utils.UResource
const GDScriptFileAccess = UResource.GDScriptFileAccess

var right_click_handler:RightClickHandler

var script_list_manager:ScriptListManager

var filter_line_edit:LineEdit
var item_list:ItemList

var gdscript_icon = EditorInterface.get_editor_theme().get_icon(&"GDScript", &"EditorIcons")
var tool_color:Color

var current_filter_text:String = ""

var current_uids:PackedStringArray = []
var current_paths:PackedStringArray = []

func _init() -> void:
	name = "Collection"

func _ready() -> void:
	tool_color = EditorInterface.get_editor_theme().get_color(&"accent_color", &"Editor")
	tool_color.s = min(tool_color.s * 1.5, 1.0)
	
	
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
	item_list.item_clicked.connect(_on_item_clicked)
	item_list.select_mode = ItemList.SELECT_SINGLE
	item_list.set_drag_forwarding(_item_list_get_drag_data, _item_list_can_drop_data, _item_list_drop_data)


func _build_list():
	var filtering = current_filter_text != ""
	item_list.clear()
	
	#sort display names like script list
	var sorted_paths = sort_and_disambiguate_paths(current_paths)
	
	for data in sorted_paths:
		var display_name = data.get("display_name")
		if filtering:
			if not current_filter_text.is_subsequence_ofn(display_name):
				continue
		
		var path = data.get("path")
		var idx = item_list.item_count
		item_list.add_item(display_name, gdscript_icon)
		if GDScriptFileAccess.get_is_tool(path):
			item_list.set_item_icon_modulate(idx, tool_color)
		item_list.set_item_metadata(idx, data)
		item_list.set_item_tooltip(idx, path)

func _item_list_get_drag_data(at_pos:Vector2):
	if not Input.is_key_pressed(KEY_CTRL):
		return
	var item = item_list.get_item_at_position(at_pos)

func _item_list_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data.get("type", "") == "files":
		var files = data.get("files")
		for f in files:
			if not f in current_paths and f.get_extension() == "gd":
				return true
	return false

func _item_list_drop_data(_at_position: Vector2, data: Variant) -> void:
	var files = data.get("files")
	for f in files:
		if  f.get_extension() == "gd":
			add_path(f)
	_set_current_paths()
	_build_list()


func _on_item_clicked(idx:int, pos:Vector2, mouse_button:int):
	if mouse_button == MOUSE_BUTTON_LEFT:
		var path = get_item_path(idx)
		var script_idx = script_list_manager.get_script_index_or_open(path)
		if script_idx != -1:
			script_list_manager.activate_item_by_idx(script_idx)
	if mouse_button == MOUSE_BUTTON_RIGHT:
		if not Input.is_key_pressed(KEY_CTRL):
			_custom_right_click()
		else:
			var path = get_item_path(idx)
			var script_idx = script_list_manager.get_script_index_or_open(path)
			if script_idx != -1:
				script_list_manager.activate_item_by_idx(script_idx) # script tabs activates when tab changes, so this is needed here
				script_list_manager.right_click_by_idx(script_idx, pos)

func _on_filter_line_text_changed(new_text:String):
	current_filter_text = new_text
	_build_list()

func _custom_right_click():
	var options = Options.new()
	options.add_option("Remove", _remove_item.bind(item_list.get_selected_items()[0]), ["Close"])
	right_click_handler.display_popup(options)

func _remove_item(idx:int):
	var path = get_item_path(idx)
	item_list.remove_item(idx)
	var uid = UFile.path_to_uid(path)
	current_uids.erase(uid)
	_set_current_paths()

func get_item_path(idx:int):
	var data = item_list.get_item_metadata(idx)
	return data.get("path")

func _set_current_paths():
	var paths = []
	for uid in current_uids:
		paths.append(UFile.uid_to_path(uid))
	current_paths = paths

func add_path(path:String):
	var uid = UFile.path_to_uid(path)
	if not uid in current_uids:
		current_uids.append(uid)

	# Returns an Array of Dictionaries: {"path": String, "display_name": String}
func sort_and_disambiguate_paths(paths: Array[String], sort:=true) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var groups: Dictionary = {}
	
	for p in paths: # --- STEP 1: Parse paths and group by file name ---
		var parts = Array(p.split("/"))
		parts.reverse() # Split the path and reverse it so index 0 is always the file name
		var filename = parts[0]
		
		var item = {
			"path": p,
			"parts": parts,
			"display_name": filename # Default to just the filename
		}
		items.append(item)
		
		if not groups.has(filename):
			groups[filename] = []
		groups[filename].append(item)
	
	for filename in groups: # --- STEP 2: Resolve duplicates to the same directory level ---
		var group: Array = groups[filename]
		
		# If there are duplicates, we need to add parent directories
		if group.size() > 1:
			var depth = 1
			var max_possible_depth = 0
			
			# Find the longest path in this group to prevent infinite loops
			for item in group:
				max_possible_depth = max(max_possible_depth, item.parts.size())
			
			# Keep adding directory levels until all display names in the group are unique
			while depth <= max_possible_depth:
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
			
			# Apply this final depth to EVERY item in the group
			# (This satisfies your requirement: "All duplicated names show to the same dir level")
			for item in group:
				item.display_name = _get_name_at_depth(item.parts, depth)
	
	if sort:
		items.sort_custom(func(a, b):
			return a.display_name.naturalnocasecmp_to(b.display_name) < 0
		)
	
	return items

func _get_name_at_depth(parts: Array, depth: int) -> String:
	# Don't try to get more directories than the path actually has
	var actual_depth = min(depth, parts.size())
	var slice = parts.slice(0, actual_depth)
	slice.reverse() # Put it back in normal left-to-right order
	return "/".join(PackedStringArray(slice))
