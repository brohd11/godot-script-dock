#! remote

const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve ALibEditor.Singleton.EditorGDScriptParser

const TreeHelperBase = preload("uid://bm6fl2iu4jew7") #! resolve ALibRuntime.TreeHelperBase

const PluginButton = preload("uid://cwiqk1fttu0sy").PluginButton #! resolve ALibEditor.UIHelpers.Buttons.PluginButton
const TabBarContainer = preload("uid://b7cxw711vl1jd") #! resolve ALibEditor.UIHelpers.Tab.TabBarContainer
const PathBar = preload("uid://bw2knsytgo0vu") #! resolve ALibRuntime.UICustom.PathBar

const SettingHelperEditor = preload("uid://c4l4v4eufkmtx") #! resolve ALibEditor.Settings.SettingHelperEditor

const UFile = preload("uid://gs632l1nhxaf") #! resolve ALibRuntime.Utils.UFile
const UName = preload("uid://e2t8o184os5r") #! resolve ALibRuntime.Utils.UName
const UResource = preload("uid://72uu8yngsoht") #! resolve ALibRuntime.Utils.UResource
const UGDScript = preload("uid://bqwb564jwff43") #! resolve ALibRuntime.Utils.UGDScript
const UControl = preload("uid://brio73mirr5e6") #! resolve ALibRuntime.Utils.UControl
const VarInsertType = preload("uid://ci11vn1timw1r") #! resolve ALibEditor.Utils.UGDScript.VarInsertType
const UString = preload("uid://cwootkivqiwq1") #! resolve ALibRuntime.Utils.UString
const UWindow = preload("uid://q2lbynew21er") #! resolve ALibRuntime.Utils.UWindow
const UClassDetail = preload("uid://gyx3o6jv751x") #! resolve ALibEditor.Utils.UClassDetail
const CacheHelper = preload("uid://1t7w412oon1j") #! resolve ALibRuntime.Utils.UMisc.CacheHelper
const TimeBudget = preload("uid://dq46888jea3a5") #! resolve ALibRuntime.Utils.UProfile.TimeBudget

const LineSubmit = preload("uid://dmilkaqawd510") #! resolve ALibRuntime.Dialog.Handlers.LineSubmit

const EditorColors = preload("uid://bhb1vgeh8ibjq") #! resolve ALibEditor.Colors
const EditorIcons = preload("uid://viocyrti6wce") #! resolve ALibEditor.Singleton.EditorIcons
const ScriptListManager = preload("uid://d3o6grkkmk4qk") #! resolve ALibEditor.Singleton.ScriptListManager
const TagParser = preload("uid://gmbyxd0dnujb") #! resolve ALibEditor.Singleton.TagParser
const CollectionSingleton = preload("res://addons/addon_lib/brohd/collections/collection_singleton.gd")

const RightClickHandler = preload("uid://mmtkf4h8er3m") #! resolve ClickHandlers.RightClickHandler
const Options = preload("uid://c61qxuau2v0pb") #! resolve ALibRuntime.Popups.Options

const FSTree = preload("uid://b7ydnvf8t32w3") #! resolve ALibEditor.FileSystem.Component.FSTree

const GitUtil = preload("uid://cxdracckohh76") #! resolve GitService.GitUtil
const GlyphIcons = preload("uid://dvguymko6if63") #! resolve GitService.GlyphIcons
const GitDataDraw = preload("uid://c0xta2pji111r") #! resolve GitService.GitDataDraw
