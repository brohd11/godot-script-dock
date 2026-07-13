extends "res://addons/script_outline/src/ui/overlay_item_list.gd"

## The Git section's Commits list — a read only `git log --oneline` view.
##
## Rows read:  <dimmed mono hash>  <tag, if any>  <subject>
##
## The row carries **no item text**: every part of it is an overlay segment. That is what lets the
## hash be mono. ItemList has one font for all of its text, so the only way to make the item text mono
## is to make the whole *list* mono — and ItemList also takes each row's height from that font, whose
## mono line box is taller. Doing it that way grew every row and left the list sitting visibly taller
## than the Changes list beside it, for no gain: the extra height is leading, not ink, so the hash did
## not even look any bigger for it. As an overlay the hash draws in whatever face it likes and
## ItemList's layout never hears about it.
##
## Every short hash is seven characters, so in a mono face they all come out the same width and the
## subject column lands on the same x on every row, with no column measuring anywhere. That is the
## whole reason the hash is mono, and it is why it needs no explicit width.
##
## The hash and the tag are fixed width so they never truncate; the subject is the segment that
## yields. Author and date, which have no room in a sidebar this narrow, live in the tooltip.

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")

## The mono face, for the hash and the hash alone. A mono subject is what made this read as too heavy
## back when the face was applied to the whole list.
var _mono_font:Font


func _ready() -> void:
	super()
	_ensure_fonts()


## Idempotent and called from add_commit as well as _ready, because a hot reload re-runs neither _init
## nor _ready on a live instance — it leaves newly declared members unset, and a null font would reach
## the segment as the list's own face, quietly costing the hash its mono.
func _ensure_fonts() -> void:
	if _mono_font != null:
		return
	_mono_font = EditorInterface.get_editor_theme().get_font(&"source", &"EditorFonts")


func clear_commits() -> void:
	clear_rows()


func add_commit(commit:Dictionary) -> void:
	_ensure_fonts()

	var full_hash = commit.get(GitUtil.Keys.FULL_HASH, "")
	var subject = commit.get(GitUtil.Keys.SUBJECT, "")
	var tags:Array = commit.get(GitUtil.Keys.TAGS, [])

	var tooltip = "%s\n\n%s\n%s  %s" % [
		subject,
		full_hash,
		commit.get(GitUtil.Keys.AUTHOR, ""),
		commit.get(GitUtil.Keys.DATE, ""),
	]
	var tags_str = "tag(%s)" % ", ".join(tags)
	if not tags.is_empty():
		tooltip += "\n\n%s" % tags_str

	# only the hash names a font; the tag and the subject take the list's own, which is the UI face
	var segments:Array = [
		segment({
			&"text": commit.get(GitUtil.Keys.HASH, ""),
			&"color": get_dim_color(), # dim, so the subject beside it reads as the primary
			&"font": _mono_font, # font_size stays the list's: as an overlay it cannot affect the row
			
		}),
	]
	# a commit usually has no tag, and an empty segment would still cost a gap — so leave it out
	if not tags.is_empty():
		segments.append(segment({
			&"text": tags_str,
			&"color": GitUtil.Colors.YELLOW,
		}))
	segments.append(segment({
		&"text": subject,
		&"color": get_theme_color(&"font_color"),
		&"flex": true,
	}))

	add_row(
		"", # no item text: the hash leads, and it can only be mono as an overlay — see the class doc
		segments,
		null,
		full_hash, # metadata: what a future "show this commit" would need
		tooltip,
	)


func get_selected_hash() -> String:
	var full_hash = get_selected_metadata()
	return full_hash if full_hash != null else ""
