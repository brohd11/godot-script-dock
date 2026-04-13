#! remote

const EditorGDScriptParser = preload("res://addons/addon_lib/brohd/alib_editor/misc/parser/editor_parser.gd") #! resolve ALibEditor.Singletons.EditorGDScriptParser

const TreeHelperBase = preload("res://addons/addon_lib/brohd/alib_runtime/tree_helper/tree_helper_base.gd") #! resolve ALibRuntime.TreeHelperBase

const PluginButton = preload("res://addons/addon_lib/brohd/alib_editor/ui/button/button_helper.gd").PluginButton #! resolve ALibEditor.UIHelpers.Buttons.PluginButton
const TabBarContainer = preload("res://addons/addon_lib/brohd/alib_editor/ui/tab/tab_bar_container.gd") #! resolve ALibEditor.UIHelpers.Tab.TabBarContainer

const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd") #! resolve ALibRuntime.Utils.UFile
const UName = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_name.gd") #! resolve ALibRuntime.Utils.UName
const UResource = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_resource.gd") #! resolve ALibRuntime.Utils.UResource
const UGDScript = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_gdscript.gd") #! resolve ALibRuntime.Utils.UGDScript
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd") #! resolve ALibRuntime.Utils.UString
const UWindow = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_window.gd") #! resolve ALibRuntime.Utils.UWindow
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd") #! resolve ALibEditor.Utils.UClassDetail
const LineSubmit = preload("res://addons/addon_lib/brohd/alib_runtime/dialog/line_submit/line_submit.gd") #! resolve ALibRuntime.Dialog.Handlers.LineSubmit

const EditorColors = preload("res://addons/addon_lib/brohd/alib_editor/misc/colors/editor_colors.gd") #! resolve ALibEditor.Colors
const EditorIcons = preload("res://addons/addon_lib/brohd/alib_editor/misc/icons/editor_icons.gd") #! resolve ALibEditor.Singletons.EditorIcons
const ScriptListManager = preload("res://addons/addon_lib/brohd/alib_editor/misc/script_list/script_list_manager.gd") #! resolve ALibEditor.Singletons.ScriptListManager

const RightClickHandler = preload("res://addons/addon_lib/brohd/gui_click_handler/right_click_handler.gd") #! resolve ClickHandlers.RightClickHandler
const Options = preload("res://addons/addon_lib/brohd/alib_runtime/popup_menu/popup_options.gd") #! resolve ALibRuntime.Popups.Options

const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")


const TEXT_FILE_TYPES = ["gd", "json", "cfg", "txt", "ini", "md"]
