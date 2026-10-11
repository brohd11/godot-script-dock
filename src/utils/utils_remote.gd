#! remote

const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve ALibEditor.Singleton.EditorGDScriptParser

const TreeHelperBase = preload("uid://bm6fl2iu4jew7") #! resolve ALibRuntime.TreeHelperBase

const PluginButton = preload("uid://redtm8tuamgm") #! resolve UIPlugin.PluginButton
const TabBarContainer = preload("uid://dhohyyr2xlven") #! resolve UIRuntime.Tabs.TabBarContainer
const PathBar = preload("uid://bw2knsytgo0vu") #! resolve ALibRuntime.UICustom.PathBar

const SettingHelperEditor = preload("uid://dnov6vp7pjnbb") #! resolve SettingHelper.Editor

const UFile = preload("uid://bl33psa06nv1e") #! resolve ALibRuntime.Utils.UFile.Methods
const UName = preload("uid://e2t8o184os5r") #! resolve ALibRuntime.Utils.UName
const UResource = preload("uid://brjrqxh2smivn") #! resolve ALibRuntime.Utils.UResource.Methods
const UTexture = preload("uid://ddu76iygjkxih") #! resolve ALibRuntime.Utils.UResource.UTexture
const UGDScript = preload("uid://bqwb564jwff43") #! resolve ALibRuntime.Utils.UGDScript
const UControl = preload("uid://brio73mirr5e6") #! resolve ALibRuntime.Utils.UControl
const VarInsertType = preload("uid://ci11vn1timw1r") #! resolve ALibEditor.Utils.UGDScript.VarInsertType
const UString = preload("uid://bbk1yedqm7a6a") #! resolve ALibRuntime.Utils.UString.Methods
const Pr = preload("uid://b7y5tr5s8mgri") #! resolve ALibRuntime.Utils.UString.PrintRich
const UWindow = preload("uid://d1yl3cuumcudy") #! resolve UtilR.Nodes.UWindow
const UVersion = preload("uid://dn156lc18d1vt") #! resolve UtilR.UVersion
const UClassDetail = preload("uid://gyx3o6jv751x") #! resolve ALibEditor.Utils.UClassDetail
const CacheHelper = preload("uid://1t7w412oon1j") #! resolve ALibRuntime.Utils.UMisc.CacheHelper
const TimeBudget = preload("uid://dq46888jea3a5") #! resolve ALibRuntime.Utils.UProfile.TimeBudget

const LineSubmit = preload("uid://vtkuh2gtwy1b") #! resolve Dialogs.Handlers.LineSubmit

const EditorColors = preload("uid://bhb1vgeh8ibjq") #! resolve ALibEditor.Colors
const EditorIcons = preload("uid://viocyrti6wce") #! resolve UIPlugin.EditorIcons
const ScriptListManager = preload("uid://d3o6grkkmk4qk") #! resolve ALibEditor.Singleton.ScriptListManager
const TagParser = preload("uid://gmbyxd0dnujb") #! resolve ALibEditor.Singleton.TagParser
const CollectionSingleton = preload("res://addons/_lib/brohd/collections/collection_singleton.gd")

const RightClickHandler = preload("uid://cs6pl78crcr0g") #! resolve UtilR.Nodes.PopupMenus.Placer
const Options = preload("uid://dxdxq2n3imf4q") #! resolve UtilR.Nodes.PopupMenus.Options

const FSTree = preload("uid://b7ydnvf8t32w3") #! resolve EditorFS.Components.FSTree
const FSSmallPopup = preload("uid://1gdu201y6jro") #! resolve EditorFS.Components.SmallPopup
