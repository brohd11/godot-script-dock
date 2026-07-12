extends "res://addons/script_outline/src/ui/overlay_item_list.gd"

## The Git section's Commits list — a read only `git log --oneline` view.
##
## Rows read:  <dimmed short hash>  <subject>
##
## The hash leads, so it has to be the ItemList's own text (a dimmed leading string cannot be an
## overlay — ItemList always draws its text first, at a fixed left edge). The colours therefore run
## the opposite way to the Changes list: the item text is dimmed and the overlay is bright.
## The hash is fixed width so it never truncates; the subject ellipsizes. Author and date, which
## have no room in a sidebar this narrow, live in the tooltip.

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")


func _ready() -> void:
	super()
	text_color = get_dim_color()
	secondary_color = get_theme_color(&"font_color")


func clear_commits() -> void:
	clear_rows()


func add_commit(commit:Dictionary) -> void:
	var full_hash = commit.get(GitUtil.Keys.FULL_HASH, "")
	var subject = commit.get(GitUtil.Keys.SUBJECT, "")

	var tooltip = "%s\n\n%s\n%s  %s" % [
		subject,
		full_hash,
		commit.get(GitUtil.Keys.AUTHOR, ""),
		commit.get(GitUtil.Keys.DATE, ""),
	]

	add_row(
		commit.get(GitUtil.Keys.HASH, ""),
		subject,
		"",
		get_dim_color(), # unused: no trailing
		full_hash, # metadata: what a future "show this commit" would need
		tooltip,
	)


func get_selected_hash() -> String:
	var full_hash = get_selected_metadata()
	return full_hash if full_hash != null else ""
