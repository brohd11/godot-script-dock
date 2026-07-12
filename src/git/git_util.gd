## Git repo discovery and status.
##
## Deliberately standalone — static, no node references, no panel coupling — so it can be
## lifted into a_lib whole once it settles.

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const UFile = UtilsRemote.UFile

const MAX_DEPTH = 5

## Never descended into. `.git` holds thousands of object files and none of them are
## project files; the rest is build noise.
const PRUNE_DIRS:PackedStringArray = [".git", ".godot", ".import", "node_modules"]

## The XY pairs git uses for an unmerged (conflicted) path.
const CONFLICT_CODES:PackedStringArray = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]

## Not real index/worktree states — they only ever appear as the "??" / "!!" pair.
const NON_STATES:PackedStringArray = [" ", "?", "!"]

const STATUS_LABELS = {
	"M": "Modified",
	"A": "Added",
	"D": "Deleted",
	"R": "Renamed",
	"C": "Copied",
	"T": "Type Change",
	"U": "Conflict",
	"?": "Untracked",
}


## The action a row should display, from an entry of the FILES dict.
## Reads the `letter` the parse already resolved: the worktree state when the file is dirty on
## disk, otherwise the index state — so a staged-then-edited file reports what is still uncommitted.
static func get_status_label(file_data:Dictionary) -> String:
	return STATUS_LABELS.get(file_data.get(Keys.LETTER, ""), "Unknown")


static func run_git(repo_dir:String, args:Array) -> Dictionary:
	# globalized, not project relative: `git -C` resolves a relative path against the editor
	# process's working directory, which is not the project root
	var final_args:Array = ["-C", ProjectSettings.globalize_path(repo_dir)]
	final_args.append_array(args)

	var output = []
	var exit_code = OS.execute("git", final_args, output)
	return {
		Keys.EXIT: exit_code,
		Keys.OUTPUT: output,
	}


static func is_repo(dir_path:String) -> bool:
	var git_path = dir_path.path_join(".git")
	# `.git` is a file, not a directory, when the repo is a worktree or a submodule gitlink
	return DirAccess.dir_exists_absolute(git_path) or FileAccess.file_exists(git_path)


## Every repo under `root`, not just the top level one — this project keeps each addon as its
## own standalone clone nested inside the project repo.
static func find_repos(root:="res://", max_depth:=MAX_DEPTH) -> Array[String]:
	var repos:Array[String] = []
	var queue = [[UFile.ensure_dir_slash(root), 0]]

	while not queue.is_empty():
		var entry = queue.pop_front()
		var dir_path:String = entry[0]
		var depth:int = entry[1]

		if is_repo(dir_path):
			repos.append(dir_path)
			# no early out — repos nest, so keep descending past one to find the rest

		if depth >= max_depth:
			continue

		# show_hidden must be on or `.git` is invisible to DirAccess
		var contents = UFile.get_dir_contents(dir_path, true, true)
		for sub_dir:String in contents.get("dirs", []):
			if sub_dir.trim_suffix("/").get_file() in PRUNE_DIRS:
				continue
			queue.append([sub_dir, depth + 1])

	return repos


## Blocking. Callers that care about the editor's frame rate should run this off the main thread.
##
## Porcelain v1 is the same format VSCode's git extension parses, so the derived flags line up
## with its Changes / Staged Changes / Merge Changes grouping and its M/A/D/R/C/U decorations.
## Not `-z`: NUL delimited output would be more robust for pathological paths, but OS.execute
## funnels the pipe through a Godot String, where embedded NULs cannot be relied on. Newline
## delimited plus core.quotepath=false is the safe trade — git C-quotes the awkward paths and
## _unquote_path puts them back.
static func get_status(repo_dir:String) -> Dictionary:
	var status = {
		Keys.REPO: repo_dir,
		Keys.BRANCH: {},
		Keys.FILES: {},
	}

	var result = run_git(repo_dir, [
		"-c", "core.quotepath=false",
		"status", "--porcelain=v1", "--branch", "--untracked-files=all",
	])
	if result[Keys.EXIT] != 0:
		return status

	var output:Array = result[Keys.OUTPUT]
	if output.is_empty():
		return status

	for raw_line in String(output[0]).split("\n", false):
		var line = raw_line.trim_suffix("\r")
		if line.begins_with("## "):
			status[Keys.BRANCH] = _parse_branch(line.substr(3))
		elif line.length() > 3:
			_parse_file(line, repo_dir, status[Keys.FILES])

	return status


static func _parse_branch(info:String) -> Dictionary:
	var branch = {
		Keys.BRANCH_NAME: "",
		Keys.BRANCH_UPSTREAM: "",
		Keys.BRANCH_AHEAD: 0,
		Keys.BRANCH_BEHIND: 0,
		Keys.BRANCH_DETACHED: false,
	}

	if info.begins_with("HEAD (no branch)"):
		branch[Keys.BRANCH_DETACHED] = true
		return branch

	# a fresh repo reports "No commits yet on main" — the branch is real, it just has no HEAD
	info = info.trim_prefix("No commits yet on ")

	# "[ahead 1, behind 2]" trails the branch, and only when an upstream is configured
	var bracket = info.find(" [")
	if bracket > -1:
		var tracking = info.substr(bracket + 2).trim_suffix("]")
		for part in tracking.split(",", false):
			part = part.strip_edges()
			if part.begins_with("ahead "):
				branch[Keys.BRANCH_AHEAD] = part.trim_prefix("ahead ").to_int()
			elif part.begins_with("behind "):
				branch[Keys.BRANCH_BEHIND] = part.trim_prefix("behind ").to_int()
		info = info.substr(0, bracket)

	var parts = info.split("...", true, 1)
	branch[Keys.BRANCH_NAME] = parts[0]
	if parts.size() > 1:
		branch[Keys.BRANCH_UPSTREAM] = parts[1]

	return branch


static func _parse_file(line:String, repo_dir:String, files:Dictionary) -> void:
	# fixed width: X at 0, Y at 1, space at 2, path from 3
	var x = line[0]
	var y = line[1]
	var path_field = line.substr(3)

	var renamed_from = ""
	var arrow = path_field.find(" -> ")
	if arrow > -1 and (x == "R" or x == "C"):
		# a rename or copy reports both sides, "old -> new"
		renamed_from = _to_res_path(repo_dir, path_field.substr(0, arrow))
		path_field = path_field.substr(arrow + 4)

	var xy = x + y
	var conflicted = xy in CONFLICT_CODES
	var untracked = xy == "??"
	var tracked_change = not conflicted and not untracked

	var staged = tracked_change and not x in NON_STATES
	var unstaged = tracked_change and not y in NON_STATES

	files[_to_res_path(repo_dir, path_field)] = {
		Keys.X: x,
		Keys.Y: y,
		Keys.STAGED: staged,
		Keys.UNSTAGED: unstaged,
		Keys.UNTRACKED: untracked,
		Keys.CONFLICTED: conflicted,
		Keys.RENAMED_FROM: renamed_from,
		# what a decoration shows: the worktree letter wins when the file is dirty on disk
		Keys.LETTER: y if unstaged else x,
	}


static func _to_res_path(repo_dir:String, rel_path:String) -> String:
	# porcelain paths are relative to the repo root, so this is what makes the keys mergeable
	# into the per-file cache in utils_local.gd
	return repo_dir.path_join(_unquote_path(rel_path))


## git C-quotes any path with a quote, a backslash or a control character in it.
static func _unquote_path(path:String) -> String:
	if not path.begins_with("\""):
		return path

	path = path.substr(1, path.length() - 2)

	var out = ""
	var i = 0
	while i < path.length():
		if path[i] != "\\":
			out += path[i]
			i += 1
			continue

		i += 1
		if i >= path.length():
			break

		var escaped = path[i]
		i += 1
		match escaped:
			"n": out += "\n"
			"t": out += "\t"
			"r": out += "\r"
			"\"": out += "\""
			"\\": out += "\\"
			_:
				if escaped >= "0" and escaped <= "7": # \nnn, an octal byte
					var code = 0
					for digit in escaped + path.substr(i, 2):
						code = code * 8 + (digit.unicode_at(0) - 48)
					i += 2
					out += char(code)
				else:
					out += escaped

	return out


class Keys:
	const EXIT = &"exit"
	const OUTPUT = &"output"

	const REPO = &"repo"
	const BRANCH = &"branch"
	const FILES = &"files"

	const BRANCH_NAME = &"name"
	const BRANCH_UPSTREAM = &"upstream"
	const BRANCH_AHEAD = &"ahead"
	const BRANCH_BEHIND = &"behind"
	const BRANCH_DETACHED = &"detached"

	const X = &"x"
	const Y = &"y"
	const STAGED = &"staged"
	const UNSTAGED = &"unstaged"
	const UNTRACKED = &"untracked"
	const CONFLICTED = &"conflicted"
	const RENAMED_FROM = &"renamed_from"
	const LETTER = &"letter"


class Colors:
	const L_GREEN = Color(0.57, 0.92, 0.57, 1.0)
	const GREEN = Color(0.0, 0.454, 0.0, 1.0)
	const L_YELLOW = Color(0.74, 0.69, 0.466, 1.0)
	const YELLOW = Color(0.741, 0.608, 0.0, 1.0)
	const RED = Color(0.573, 0.0, 0.0, 1.0)
