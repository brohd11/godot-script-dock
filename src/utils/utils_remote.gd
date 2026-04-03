#! remote

const EditorGDScriptParser = preload("res://addons/addon_lib/brohd/alib_editor/misc/parser/editor_parser.gd")

const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

const TreeHelperBase = ALibRuntime.TreeHelperBase

const PluginButton = ALibEditor.UIHelpers.Buttons.PluginButton
const TabBarContainer = ALibEditor.UIHelpers.Tab.TabBarContainer

const UFile = ALibRuntime.Utils.UFile
const UResource = ALibRuntime.Utils.UResource
const GDScriptFileAccess = UResource.GDScriptFileAccess
const UString = ALibRuntime.Utils.UString
const UClassDetail = ALibEditor.Utils.UClassDetail

const EditorColors = ALibEditor.Colors
const EditorIcons = ALibEditor.Singletons.EditorIcons
const ScriptListManager = ALibEditor.Singletons.ScriptListManager

const RightClickHandler = ClickHandlers.RightClickHandler
const Options = ALibRuntime.Popups.Options
