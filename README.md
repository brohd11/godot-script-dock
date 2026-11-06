# Script Dock
Godot plugin that adds a dock to replace the left sidebar of the script editor.

Compatible with 4.4+, but the old theme does not really look great to be honest.
I recommend 4.6+, and the Script Outline's optional dependency requires 4.5+. See below.

The current panels it has:

### Script Tab Container
The first tab is a copy of the standard script list. The original one is hidden and used as a 
source of truth for script editor identity. This has the same right click menu and the script list.

The second tab is a file tree, with full context menu functionality. You can create and move files,
basically anything that you would do with the file system dock, plus a bit more. You can instance multiple tabs
pinned at different folders and you can create collections, that hold whatever scripts you drag in.

All of these can be used with [Git View](https://github.com/brohd11/godot-git-view) to provide info on git file status
within the lists and file trees. It also adds a panel that can display modified files in a flat list in repos, ands submodules
within your project.

The script panel also pairs well with [ScriptTabs](https://github.com/brohd11/Godot-Script-Tabs)
a plugin that adds splittable tabs to the editor. You can open in a new split from the script list and file system,
as git views panel.

### Script Outline

The second panel is a script outline in the form of a tree. It maps every class, member, local variable and infers
its type. It will turn items red when they have a condition that may not be ideal. Currently this is only no static type.
There is a correction button that can insert the inffered type for you. You can have the outline follow your cursor with an editor setting.

This uses a custom parser that can also make use of an implementation of Tree-sitter. [tree-sitter-gd](https://github.com/brohd11/godot-tree-sitter-gd)
This is **not** required. It simply offloads alot of the slow parsing into C++. Most of it is async anyway and I find it
acceptable without it personally.

It can be installed automatically using the gdaddon package manager below. It will read the plugin.cfg of *this* plugin
and install the dependency.

#### Notes on FileSystem

**a note:** The file system tab works in a similar way ot the script list. You are better off leaving
it both: in tree mode, and alone. [FileSystemInstances](https://github.com/brohd11/Godot-FileSystem-Instances)
plugin will be available eventually, it is a replacement file system for the dock, with added features.

**one more note:** Getting renaming files to work on this system was very tricky. It was actually 4.6's new
theme that really made it work consistently to where I am confident in using it. If you are on < 4.6, consider
using the standard file system dock for renaming files.

### The Dock

This dock can be used to add your own controls to.
```gdscript
# you can preload this or add class_name to.
# The release package has the class name stripped
const ScriptDock = preload("path/to/class.gd")

var script_dock = ScriptDock.get_instance()
# call on ready ensures the script dock is ready before it calls the add function
# if your class is located above the script_dock folder, you will probably want
# to await a frame here to ensure the script dock has been instanced.
script_dock.call_on_ready(script_dock.add_section.bind(&"YourID", your_control))
```


## Install
This plugin uses external dependencies packaged with [GDPackage]
(https://github.com/brohd11/godot-gdpackage), download the latest package
 from releases, it includes the required dependencies.

You can also use [gdaddon](https://github.com/brohd11/gdaddon) to manage the
 addon. It is a TUI package/repo manager that can install and update addons for
  you.
`curl -fsSL https://raw.githubusercontent.com/brohd11/gdaddon/main/install.sh | sh`