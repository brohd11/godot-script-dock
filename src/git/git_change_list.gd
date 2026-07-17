extends "res://addons/script_outline/src/ui/overlay_item_list.gd"

## The Git section's Changes list.
##
## Rows read:  <file name>  <dimmed dir> ………………… <status>
##
## The dir is the segment that yields, so a deep path shortens rather than crowding the file name.
## Below COMPACT_BELOW the status word drops to git's own single letter, which hands its width back
## to the name — the whole point of the fallback, since "Untracked" is wider than most file names.
##
## That letter is drawn from a baked square rather than as a string, so that the letters line up
## with one another down the list — see glyph_icons.gd. Until the cache is warm GlyphIcons hands back
## null and the segment falls through to its `compact` string, which is what the list drew before the
## textures existed; nothing here has to wait on the bake.

const RightClickHandler = UtilsRemote.RightClickHandler
const Options = UtilsRemote.Options


const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")
const GlyphIcons = preload("res://addons/script_outline/src/ui/glyph_icons.gd")

## unscaled px of list width below which the status word gives way to its letter
const COMPACT_BELOW = 200.0

var glyph_icons:GlyphIcons

## res:// path -> the status entry that built its row. The menu needs it: what a command can be asked
## to do to a file is decided by what state that file is in, and the row alone does not say.
var _file_data:Dictionary = {}

signal changes_command(command:GitUtil.Command, paths:Array)

func _ready() -> void:
	super()
	compact_below = COMPACT_BELOW * EditorInterface.get_editor_scale()
	
	select_mode = ItemList.SELECT_MULTI
	allow_rmb_select = true
	item_clicked.connect(_on_item_clicked)
	glyph_icons = ScriptOutline.get_glyph_icons_node()


func clear_changes() -> void:
	clear_rows()
	_file_data.clear()


func add_change(res_path:String, repo_dir:String, file_data:Dictionary) -> void:
	var dir = res_path.get_base_dir().trim_prefix(repo_dir).trim_prefix("/")
	var letter = GitUtil.get_status_letter(file_data)
	_file_data[res_path] = file_data

	var compact_icon = glyph_icons.get_letter(letter) if is_instance_valid(glyph_icons) else null

	add_row(
		res_path.get_file(),
		[
			segment({
				&"text": dir,
				&"color": get_dim_color(),
				&"flex": true,
			}),
			segment({
				&"text": GitUtil.get_status_label(file_data),
				&"color": _get_status_color(file_data),
				&"align": Align.RIGHT,
				&"compact": letter,
				# null while the cache is cold; the letter above covers it
				&"compact_icon": compact_icon,
			}),
		],
		null, # the file name keeps ItemList's own colour: it is the primary here
		res_path, # metadata: what a click-to-open will read
		res_path,
	)


func get_selected_path() -> String:
	var path = get_selected_metadata()
	return path if path != null else ""

func get_selected_paths():
	var paths = []
	for i in get_selected_items():
		var meta = get_item_metadata(i)
		if meta:
			paths.append(meta)
	return paths


func _get_status_color(file_data:Dictionary) -> Color:
	# the line type settles conflicted and untracked outright, so neither can be shadowed by the
	# staged/unstaged pair below
	match file_data.get(GitUtil.Keys.KIND, GitUtil.Kind.ORDINARY):
		GitUtil.Kind.UNMERGED:
			return GitUtil.Colors.RED
		GitUtil.Kind.UNTRACKED:
			return GitUtil.Colors.L_GREEN

	# staged with nothing left dirty on disk: the change is already safely in the index
	var staged = file_data.get(GitUtil.Keys.STAGED, false)
	var unstaged = file_data.get(GitUtil.Keys.UNSTAGED, false)
	if staged and not unstaged:
		return GitUtil.Colors.GREEN

	if file_data.get(GitUtil.Keys.WORKTREE, GitUtil.Status.NONE) == GitUtil.Status.MODIFIED:
		return GitUtil.Colors.L_YELLOW

	return get_dim_color()

func _on_item_clicked(_index:int, _at_pos:Vector2, mouse_button:int):
	if mouse_button == MOUSE_BUTTON_RIGHT:
		_on_item_right_clicked()

func _on_item_right_clicked():

	var selected_paths = get_selected_paths()
	var options = Options.new()
	if selected_paths.size() == 1:
		var path = selected_paths[0]
		var valid = UtilsLocal.GenericFileContext.right_click(options, path)
		if valid != UtilsLocal.GenericFileContext.FileStatus.VALID:
			options = Options.new()

	_add_command_options(options, selected_paths)

	ScriptOutline.get_right_click_handler().display_popup(options)


## One entry per command that has something to do to the selection.
##
## A command is handed only the subset of the selection it accepts, not the whole thing: staging a
## mixed selection should stage what can be staged rather than fail on the rest. A command no
## selected file accepts is not offered at all — no "Unstage" over an untracked file.
func _add_command_options(options:Options, selected_paths:Array) -> void:
	var separated = false

	for command:GitUtil.Command in GitUtil.COMMANDS:
		var entry:Dictionary = GitUtil.COMMANDS[command]

		var paths = selected_paths.filter(
			func(path): return GitUtil.command_accepts(command, _file_data.get(path, {}))
		)
		if paths.is_empty():
			continue

		# the destructive pair is unrecoverable and one click away, so at least keep it away from the
		# ones that are not. Commenting out this add_option is all it takes to drop them entirely.
		if entry[GitUtil.Keys.CMD_DESTRUCTIVE] and not separated:
			options.add_separator()
			separated = true

		options.add_option(_command_label(entry, paths, selected_paths),
			_changes_command.bind(command, paths))


## Says so when a command is about to act on fewer files than are selected — otherwise "Unstage" over
## five rows of which two are staged gives no hint that the other three are being left alone.
func _command_label(entry:Dictionary, paths:Array, selected_paths:Array) -> String:
	var label:String = entry[GitUtil.Keys.CMD_LABEL]
	if paths.size() == selected_paths.size():
		return label
	return "%s (%d of %d)" % [label, paths.size(), selected_paths.size()]


func _changes_command(command:GitUtil.Command, paths:Array):
	changes_command.emit(command, paths)
