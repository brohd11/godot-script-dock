extends "res://addons/script_outline/src/ui/overlay_item_list.gd"

## The Git section's Changes list.
##
## Rows read:  <file name>  <dimmed dir> ………………… <status>

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")


func clear_changes() -> void:
	clear_rows()


func add_change(res_path:String, repo_dir:String, file_data:Dictionary) -> void:
	add_row(
		res_path.get_file(),
		res_path.get_base_dir().trim_prefix(repo_dir).trim_prefix("/"),
		GitUtil.get_status_label(file_data),
		_get_status_color(file_data),
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
