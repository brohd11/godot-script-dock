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

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")
const GlyphIcons = preload("res://addons/script_outline/src/ui/glyph_icons.gd")

## unscaled px of list width below which the status word gives way to its letter
const COMPACT_BELOW = 200.0


func _ready() -> void:
	super()
	compact_below = COMPACT_BELOW * EditorInterface.get_editor_scale()


func clear_changes() -> void:
	clear_rows()


func add_change(res_path:String, repo_dir:String, file_data:Dictionary) -> void:
	var dir = res_path.get_base_dir().trim_prefix(repo_dir).trim_prefix("/")
	var letter = GitUtil.get_status_letter(file_data)

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
				&"compact_icon": GlyphIcons.get_letter(letter),
			}),
		],
		null, # the file name keeps ItemList's own colour: it is the primary here
		res_path, # metadata: what a click-to-open will read
		res_path,
	)


func get_selected_path() -> String:
	var path = get_selected_metadata()
	return path if path != null else ""


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
