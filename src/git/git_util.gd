## Git repo discovery, status and diffs.
##
## Deliberately standalone — static, no node references, no panel coupling — so it can be
## lifted into a_lib whole once it settles.

const UtilsRemote = preload("res://addons/script_outline/src/utils/utils_remote.gd")

const UFile = UtilsRemote.UFile

const MAX_DEPTH = 5

const LOG_LIMIT = 100

## The fields of one `git log` record. `%D` is the ref names, which is where the tags come from; it
## goes last because it is the one field that is empty for most commits, and a trailing empty field
## still splits to the right size.
const LOG_FIELDS:PackedStringArray = ["%h", "%s", "%an", "%ar", "%H", "%D"]

## How git marks a tag inside `%D`, as opposed to a branch or HEAD.
const TAG_PREFIX = "tag: "

## ASCII unit separator, the field delimiter in the log format below. Safe where NUL was not: it is
## a valid single byte UTF-8 character, so it survives the Godot String that OS.execute pipes the
## process output through.
const LOG_SEP = "\u001f"

## Never descended into. `.git` holds thousands of object files and none of them are
## project files; the rest is build noise.
const PRUNE_DIRS:PackedStringArray = [".git", ".godot", ".import", "node_modules"]

## The v2 line type, which is what tells a conflict from an untracked file from an ordinary edit.
## v1 forced that distinction out of the XY pair; v2 states it outright.
enum Kind {
	ORDINARY,  ## "1"
	RENAMED,   ## "2", a rename or a copy
	UNMERGED,  ## "u"
	UNTRACKED, ## "?"
	IGNORED,   ## "!"
}

## One side of the XY pair. v2 writes an unmodified side as ".", which maps to NONE here — the
## raw character never escapes the parser.
enum Status {
	NONE,
	MODIFIED,
	ADDED,
	DELETED,
	RENAMED,
	COPIED,
	TYPE_CHANGED,
	UNMERGED,
}

const CHAR_STATUS = {
	".": Status.NONE,
	"M": Status.MODIFIED,
	"A": Status.ADDED,
	"D": Status.DELETED,
	"R": Status.RENAMED,
	"C": Status.COPIED,
	"T": Status.TYPE_CHANGED,
	"U": Status.UNMERGED,
}

const STATUS_LABELS = {
	Status.MODIFIED: "Modified",
	Status.ADDED: "Added",
	Status.DELETED: "Deleted",
	Status.RENAMED: "Renamed",
	Status.COPIED: "Copied",
	Status.TYPE_CHANGED: "Type Change",
	Status.UNMERGED: "Conflict",
}

## git's own short-format letters, for when a row is too narrow to spell the word out. "?" for
## untracked and "U" for a conflict are what `git status -s` prints; the two never collide, and the
## row colour tells them apart anyway (untracked light green, conflict red).
const STATUS_LETTERS = {
	Status.MODIFIED: "M",
	Status.ADDED: "A",
	Status.DELETED: "D",
	Status.RENAMED: "R",
	Status.COPIED: "C",
	Status.TYPE_CHANGED: "T",
	Status.UNMERGED: "U",
}


## The action a row should display, from an entry of the FILES dict.
##
## A display concern, so it is derived here rather than stored on the entry. The worktree side wins
## when the file is dirty on disk, so a staged-then-edited file reports what is still uncommitted.
static func get_status_label(file_data:Dictionary) -> String:
	return _status_display(file_data, STATUS_LABELS, "Untracked", "Conflict", "Unknown")


## The same, abbreviated to git's own single letter — what a row falls back to when the sidebar is
## too narrow to spell the word out.
static func get_status_letter(file_data:Dictionary) -> String:
	return _status_display(file_data, STATUS_LETTERS, "?", "U", "")


## Every character get_status_letter() can return. What a glyph cache has to bake to be able to
## answer for any file, whatever its status turns out to be.
static func get_letter_set() -> String:
	# "?" is the untracked row's letter and is not in the table, which is keyed by Status
	return "".join(STATUS_LETTERS.values()) + "?"


static func _status_display(file_data:Dictionary, table:Dictionary, untracked:String, conflict:String, unknown:String) -> String:
	match file_data.get(Keys.KIND, Kind.ORDINARY):
		Kind.UNTRACKED:
			return untracked
		Kind.UNMERGED:
			return conflict

	var worktree:Status = file_data.get(Keys.WORKTREE, Status.NONE)
	var index:Status = file_data.get(Keys.INDEX, Status.NONE)
	return table.get(worktree if worktree != Status.NONE else index, unknown)


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
## Porcelain v2, not v1: the branch state arrives as four `# branch.*` header lines instead of one
## line of bracket-and-ellipsis punctuation to unpick, a rename tab-separates its two paths instead
## of joining them with an ambiguous " -> ", and a conflict is its own line type rather than a pair
## of letters to look up in a table.
##
## Not `-z`: NUL delimited output would be more robust for pathological paths, but OS.execute
## funnels the pipe through a Godot String, where embedded NULs cannot be relied on. Newline
## delimited plus core.quotepath=false is the safe trade — git C-quotes the awkward paths and
## _unquote_path puts them back.
static func get_status(repo_dir:String) -> Dictionary:
	var result = run_git(repo_dir, [
		"-c", "core.quotepath=false",
		"status", "--porcelain=v2", "--branch", "--untracked-files=all",
	])

	var output:Array = result[Keys.OUTPUT]
	if result[Keys.EXIT] != 0 or output.is_empty():
		return parse_status("", repo_dir)

	return parse_status(String(output[0]), repo_dir)


## The parse half of get_status, split out so it can be exercised against captured git output
## without spawning anything. See tests/git/.
static func parse_status(text:String, repo_dir:String) -> Dictionary:
	var status = {
		Keys.REPO: repo_dir,
		Keys.BRANCH: _new_branch(),
		Keys.FILES: {},
	}

	for raw_line in text.split("\n", false):
		var line = raw_line.trim_suffix("\r")
		if line.begins_with("# branch."):
			_parse_branch_header(line, status[Keys.BRANCH])
		elif not line.begins_with("#"): # ignore headers we don't recognise, as git asks
			_parse_entry(line, repo_dir, status[Keys.FILES])

	return status


## Blocking, like get_status — run it off the main thread.
##
## Two spawns for the whole worktree, not one per file: `git diff` with no pathspec already emits
## the patch for every changed file, and splitting it up would only multiply git's ~11ms startup.
## Merges into an existing get_status() result so the panel's thread keeps its shape.
##
## Untracked files get no hunks: `git diff` excludes them by design. Their content is on disk and
## can just be read. (`git add -N` would pull them into the diff, but it writes to the index, which
## a passive auto-refreshing panel has no business doing.)
static func attach_diffs(repo_dir:String, status:Dictionary) -> void:
	var files:Dictionary = status.get(Keys.FILES, {})
	if files.is_empty():
		return

	_merge_patch(repo_dir, files, [], Keys.HUNKS_UNSTAGED)      # worktree vs index
	_merge_patch(repo_dir, files, ["--cached"], Keys.HUNKS_STAGED) # index vs HEAD


static func _merge_patch(repo_dir:String, files:Dictionary, extra_args:Array, hunks_key:StringName) -> void:
	var args = ["-c", "core.quotepath=false", "diff", "--patch"]
	args.append_array(extra_args)

	var result = run_git(repo_dir, args)
	if result[Keys.EXIT] != 0:
		return

	var output:Array = result[Keys.OUTPUT]
	if output.is_empty():
		return

	var patch = parse_patch(String(output[0]), repo_dir)
	for res_path:String in patch:
		if not files.has(res_path):
			continue # a path in the diff but not in the status: nothing to hang it off
		var parsed:Dictionary = patch[res_path]
		files[res_path][hunks_key] = parsed[Keys.HUNKS]
		if parsed[Keys.BINARY]:
			files[res_path][Keys.BINARY] = true


## Blocking, like get_status — run it off the main thread.
##
## Newest first, in git's own order. `%s` is the subject, i.e. the first line only, so a record can
## never contain a newline and one output line is exactly one commit. `%ar` is git's own relative
## date ("2 days ago"), so there is no date maths here.
static func get_log(repo_dir:String, limit:=LOG_LIMIT) -> Array[Dictionary]:
	var result = run_git(repo_dir, [
		"log",
		"--max-count=%s" % limit,
		"--pretty=format:" + LOG_SEP.join(LOG_FIELDS),
	])

	var output:Array = result[Keys.OUTPUT]
	# a repo with no commits yet exits non zero — that is not an error, it just has no history
	if result[Keys.EXIT] != 0 or output.is_empty():
		return [] as Array[Dictionary]

	return parse_log(String(output[0]))


## The parse half of get_log, split out so it can be exercised against captured git output without
## spawning anything. See tests/git/.
static func parse_log(text:String) -> Array[Dictionary]:
	var commits:Array[Dictionary] = []

	for raw_line in text.split("\n", false):
		var line = raw_line.trim_suffix("\r")
		var parts = line.split(LOG_SEP)
		if parts.size() < LOG_FIELDS.size():
			continue

		commits.append({
			Keys.HASH: parts[0],
			Keys.SUBJECT: parts[1],
			Keys.AUTHOR: parts[2],
			Keys.DATE: parts[3],
			Keys.FULL_HASH: parts[4],
			Keys.TAGS: _parse_refs(parts[5]),
		})

	return commits


## The tags out of a `%D` ref field: "HEAD -> main, origin/main, tag: v0.7.2, tag: v0.7.3".
##
## Branch and HEAD refs share the field with the tags, so the "tag: " prefix is the only thing that
## tells them apart — without this filter the Commits list would label every tip commit "main".
static func _parse_refs(field:String) -> Array[String]:
	var tags:Array[String] = []
	for ref in field.split(",", false):
		var name = ref.strip_edges()
		if name.begins_with(TAG_PREFIX):
			tags.append(name.substr(TAG_PREFIX.length()))
	return tags


static func _new_branch() -> Dictionary:
	return {
		Keys.BRANCH_NAME: "",
		Keys.BRANCH_UPSTREAM: "",
		Keys.BRANCH_AHEAD: 0,
		Keys.BRANCH_BEHIND: 0,
		Keys.BRANCH_DETACHED: false,
		Keys.BRANCH_INITIAL: false,
	}


## One of the four `# branch.*` headers --branch emits. Each states its field outright, so there is
## no punctuation to unpick here the way v1's single "## main...origin/main [ahead 1]" line needed.
static func _parse_branch_header(line:String, branch:Dictionary) -> void:
	var parts = line.split(" ", true, 2)
	if parts.size() < 3:
		return

	match parts[1]:
		"branch.oid":
			branch[Keys.BRANCH_INITIAL] = parts[2] == "(initial)"
		"branch.head":
			if parts[2] == "(detached)":
				branch[Keys.BRANCH_DETACHED] = true
			else:
				branch[Keys.BRANCH_NAME] = parts[2]
		"branch.upstream":
			branch[Keys.BRANCH_UPSTREAM] = parts[2]
		"branch.ab":
			# "+<ahead> -<behind>"
			for field in parts[2].split(" ", false):
				if field.begins_with("+"):
					branch[Keys.BRANCH_AHEAD] = field.substr(1).to_int()
				elif field.begins_with("-"):
					branch[Keys.BRANCH_BEHIND] = field.substr(1).to_int()


## A single tracked / untracked / ignored entry. The leading token is the line type.
##
## Every split below is bounded by an explicit maxsplit: a path may contain spaces, so it has to be
## taken as the whole remainder of the line rather than as one space-delimited field.
static func _parse_entry(line:String, repo_dir:String, files:Dictionary) -> void:
	match line.substr(0, 2):
		"1 ":
			# 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
			var parts = line.split(" ", true, 8)
			if parts.size() < 9:
				return
			var entry = _new_entry(Kind.ORDINARY, parts[1])
			entry[Keys.SUB] = parts[2]
			entry[Keys.OID_HEAD] = parts[6]
			entry[Keys.OID_INDEX] = parts[7]
			files[_to_res_path(repo_dir, parts[8])] = entry

		"2 ":
			# 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><TAB><origPath>
			var parts = line.split(" ", true, 9)
			if parts.size() < 10:
				return
			var paths = parts[9].split("\t")
			if paths.size() < 2:
				return
			var entry = _new_entry(Kind.RENAMED, parts[1])
			entry[Keys.SUB] = parts[2]
			entry[Keys.OID_HEAD] = parts[6]
			entry[Keys.OID_INDEX] = parts[7]
			entry[Keys.SCORE] = parts[8].substr(1).to_int() # drop the leading R / C
			entry[Keys.RENAMED_FROM] = _to_res_path(repo_dir, paths[1])
			files[_to_res_path(repo_dir, paths[0])] = entry

		"u ":
			# u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
			var parts = line.split(" ", true, 10)
			if parts.size() < 11:
				return
			var entry = _new_entry(Kind.UNMERGED, parts[1])
			entry[Keys.SUB] = parts[2]
			files[_to_res_path(repo_dir, parts[10])] = entry

		"? ":
			files[_to_res_path(repo_dir, line.substr(2))] = _new_entry(Kind.UNTRACKED, "..")

		"! ":
			files[_to_res_path(repo_dir, line.substr(2))] = _new_entry(Kind.IGNORED, "..")


static func _new_entry(kind:Kind, xy:String) -> Dictionary:
	var index:Status = CHAR_STATUS.get(xy.substr(0, 1), Status.NONE)
	var worktree:Status = CHAR_STATUS.get(xy.substr(1, 1), Status.NONE)

	return {
		Keys.KIND: kind,
		Keys.INDEX: index,
		Keys.WORKTREE: worktree,
		Keys.STAGED: index != Status.NONE,
		Keys.UNSTAGED: worktree != Status.NONE,
		Keys.RENAMED_FROM: "",
		Keys.SCORE: 0,
		Keys.SUB: "",
		Keys.OID_HEAD: "",
		Keys.OID_INDEX: "",
		Keys.BINARY: false,
		Keys.HUNKS_STAGED: [],
		Keys.HUNKS_UNSTAGED: [],
	}


## A unified diff, split into per-file hunks and keyed by res:// path so it merges straight into the
## FILES dict from get_status. Pure, like parse_status — see tests/git/.
static func parse_patch(text:String, repo_dir:String) -> Dictionary:
	var out = {}

	var res_path = ""
	var header = "" # the "a/x b/x" tail of the current `diff --git` line, kept for the binary case
	var file_data = {}
	var hunk = {}

	# `allow_empty` stays on: an empty context line in a hunk is " ", but a removed empty line is a
	# bare "-", and dropping empties would silently shift the line counts.
	for raw_line in text.split("\n"):
		var line = raw_line.trim_suffix("\r")

		if line.begins_with("diff --git "):
			res_path = ""
			header = line.substr(11)
			file_data = {Keys.HUNKS: [], Keys.BINARY: false}
			hunk = {}
			continue

		if file_data.is_empty():
			continue

		# The two path headers. `+++` names the file, except for a deletion, where it is /dev/null
		# and `---` is the only place the path survives.
		if line.begins_with("+++ ") and line != "+++ /dev/null":
			res_path = _patch_path(repo_dir, line.substr(4), "b/")
			out[res_path] = file_data
			continue
		if line.begins_with("--- ") and line != "--- /dev/null" and res_path.is_empty():
			res_path = _patch_path(repo_dir, line.substr(4), "a/")
			out[res_path] = file_data
			continue

		if line.begins_with("Binary files ") or line.begins_with("GIT binary patch"):
			file_data[Keys.BINARY] = true
			# a binary file has no +++/--- headers at all, so this is the only chance to learn its
			# path, and the `diff --git` line is the only place left to read it from
			if res_path.is_empty():
				res_path = _header_path(repo_dir, header)
				if not res_path.is_empty():
					out[res_path] = file_data
			continue

		if line.begins_with("@@"):
			hunk = _parse_hunk_header(line)
			file_data[Keys.HUNKS].append(hunk)
			continue

		if hunk.is_empty():
			continue # still in the file header (index / mode / rename lines)

		# Inside a hunk the first character is the origin. "\" is git's "\ No newline at end of
		# file" marker, which annotates the previous line rather than being one of its own.
		var origin = line.substr(0, 1)
		match origin:
			" ", "+", "-":
				hunk[Keys.LINES].append({
					Keys.ORIGIN: origin,
					Keys.TEXT: line.substr(1),
				})
			"":
				# a context line that is empty; git writes " " but be forgiving
				hunk[Keys.LINES].append({Keys.ORIGIN: " ", Keys.TEXT: ""})
			"\\":
				hunk[Keys.NO_NEWLINE] = true

	return out


## "@@ -<old_start>,<old_count> +<new_start>,<new_count> @@ <heading>"
##
## A count is omitted when it is 1, and the trailing heading is the enclosing function git guessed
## at — it is not diff content and must not be read as a line.
static func _parse_hunk_header(line:String) -> Dictionary:
	var hunk = {
		Keys.OLD_START: 0,
		Keys.OLD_COUNT: 0,
		Keys.NEW_START: 0,
		Keys.NEW_COUNT: 0,
		Keys.HEADING: "",
		Keys.NO_NEWLINE: false,
		Keys.LINES: [],
	}

	var close = line.find("@@", 2)
	if close < 0:
		return hunk

	hunk[Keys.HEADING] = line.substr(close + 2).strip_edges()

	for field in line.substr(2, close - 2).strip_edges().split(" ", false):
		var side = field.substr(0, 1)
		if side != "-" and side != "+":
			continue

		var nums = field.substr(1).split(",")
		var start = nums[0].to_int()
		var count = nums[1].to_int() if nums.size() > 1 else 1

		if side == "-":
			hunk[Keys.OLD_START] = start
			hunk[Keys.OLD_COUNT] = count
		else:
			hunk[Keys.NEW_START] = start
			hunk[Keys.NEW_COUNT] = count

	return hunk


## The path out of a `--- a/x` / `+++ b/x` diff header, which is quoted differently to a porcelain
## path and so cannot go through _to_res_path.
##
## Two traps, both of them silent — a mis-read path simply fails to match a status key and the
## file's hunks vanish:
##   - git terminates the field with a TAB when the path contains a space ("--- a/with space.txt\t")
##   - git C-quotes the *whole* field, `a/` prefix included ('--- "a/quo\"te.txt"'), so the tab must
##     come off and the quoting must come out before the prefix can be stripped
## Unquoting exactly once also matters: a filename that legitimately begins with a quote would be
## mangled by a second pass.
static func _patch_path(repo_dir:String, field:String, prefix:String) -> String:
	return repo_dir.path_join(_unquote_path(field.trim_suffix("\t")).trim_prefix(prefix))


## The path out of a `diff --git a/x b/x` line. A last resort, reached only for a binary file, which
## git gives no +++/--- headers to read.
##
## Ambiguous by construction: the two paths are space-joined and unquoted, so `a/one two.txt
## b/one two.txt` cannot be split by hunting for the space — which is precisely why git emits a +++
## header for everything else. It is recoverable at all only because the two halves are identical
## for anything but a rename, so the split can be found by length and then *checked*. Returns ""
## when that check fails: no hunks is a great deal better than a file's hunks silently attached to
## the wrong path.
static func _header_path(repo_dir:String, header:String) -> String:
	if header.begins_with("\""):
		var close = _find_closing_quote(header)
		if close < 0:
			return ""
		return repo_dir.path_join(_unquote_path(header.substr(0, close + 1)).trim_prefix("a/"))

	# "a/" + path + " " + "b/" + path, so the length is 2 * path + 5
	if header.length() < 7 or (header.length() - 5) % 2 != 0:
		return ""

	# exact, not truncating: the odd-length case already returned above
	@warning_ignore("integer_division")
	var path = header.substr(2, (header.length() - 5) / 2)
	if header != "a/%s b/%s" % [path, path]:
		return "" # a rename, or something else we cannot read back confidently
	return repo_dir.path_join(path)


## The index of the closing quote of a C-quoted field, honouring backslash escapes so an escaped
## quote inside the name does not end it early.
static func _find_closing_quote(text:String) -> int:
	var i = 1
	while i < text.length():
		match text[i]:
			"\\": i += 2
			"\"": return i
			_: i += 1
	return -1


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
	const BRANCH_INITIAL = &"initial"

	const KIND = &"kind"
	const INDEX = &"index"
	const WORKTREE = &"worktree"
	const STAGED = &"staged"
	const UNSTAGED = &"unstaged"
	const RENAMED_FROM = &"renamed_from"
	const SCORE = &"score"
	const SUB = &"sub"
	const OID_HEAD = &"oid_head"
	const OID_INDEX = &"oid_index"

	const BINARY = &"binary"
	const HUNKS = &"hunks"
	const HUNKS_STAGED = &"hunks_staged"
	const HUNKS_UNSTAGED = &"hunks_unstaged"

	const OLD_START = &"old_start"
	const OLD_COUNT = &"old_count"
	const NEW_START = &"new_start"
	const NEW_COUNT = &"new_count"
	const HEADING = &"heading"
	const NO_NEWLINE = &"no_newline"
	const LINES = &"lines"
	const ORIGIN = &"origin"
	const TEXT = &"text"

	const HASH = &"hash"
	const FULL_HASH = &"full_hash"
	const SUBJECT = &"subject"
	const AUTHOR = &"author"
	const DATE = &"date"
	const TAGS = &"tags"


class Colors:
	const L_GREEN = Color(0.57, 0.92, 0.57, 1.0)
	const GREEN = Color(0.0, 0.454, 0.0, 1.0)
	const L_YELLOW = Color(0.74, 0.69, 0.466, 1.0)
	const YELLOW = Color(0.741, 0.608, 0.0, 1.0)
	const RED = Color(0.573, 0.0, 0.0, 1.0)
