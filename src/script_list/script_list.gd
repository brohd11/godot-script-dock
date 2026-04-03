extends VBoxContainer


const ScriptListManager = ALibEditor.Singletons.ScriptListManager
const SLKeys = ScriptListManager.Keys

var filter_line_edit:LineEdit

var script_list_manager:ScriptListManager

var item_list:ItemList

var current_filter_text:String = ""

func _init() -> void:
	name = "Active"

func _ready() -> void:
	
	script_list_manager = ScriptListManager.get_instance()
	script_list_manager.cache_updated.connect(_on_cache_updated)
	
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
	
	_on_cache_updated()

func _on_cache_updated():
	_build_list()

func _build_list():
	var filtering = current_filter_text != ""
	if not is_instance_valid(script_list_manager.current_script_editor):
		return
	var selected_idx = script_list_manager.current_script_editor.get_index()
	item_list.clear()
	var item_cache = script_list_manager.item_cache
	var item_cache_keys = item_cache.keys()
	item_cache_keys.sort_custom(
		func(a, b):
			return item_cache[a].get(SLKeys.ITEM_IDX) < item_cache[b].get(SLKeys.ITEM_IDX)
	)
	
	for item_index in item_cache_keys:
		var data = item_cache[item_index]
		var item_name = data.get(SLKeys.NAME)
		if filtering:
			if not current_filter_text.is_subsequence_ofn(item_name):
				continue
		
		item_list.add_item(item_name, data.get(SLKeys.ICON))
		var idx = item_list.item_count - 1
		item_list.set_item_icon_modulate(idx, data.get(SLKeys.ICON_MOD))
		item_list.set_item_custom_fg_color(idx, data.get(SLKeys.FG_COLOR))
		item_list.set_item_tooltip(idx, data.get(SLKeys.TOOLTIP))
		var script_idx = data.get(SLKeys.SCRIPT_IDX)
		item_list.set_item_metadata(idx, script_idx)
		if script_idx == selected_idx:
			item_list.select(idx)

func _on_filter_line_text_changed(new_text:String):
	current_filter_text = new_text
	_build_list()

func _on_item_clicked(idx:int, pos:Vector2, mouse_button:int):
	if mouse_button == MOUSE_BUTTON_LEFT:
		var script_idx = item_list.get_item_metadata(idx)
		script_list_manager.activate_item_by_idx(script_idx)
	if mouse_button == MOUSE_BUTTON_RIGHT:
		var script_idx = item_list.get_item_metadata(idx)
		script_list_manager.activate_item_by_idx(script_idx) # script tabs activates when tab changes, so this is needed here
		script_list_manager.right_click_by_idx(script_idx, pos)
