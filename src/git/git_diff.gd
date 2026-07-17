## Two versions of a file, as the hunks git would have printed for them.
##
## The one part of the git story that has nothing to do with git: it spawns nothing, parses nothing
## git produced, and would be just as correct on a machine with no git installed. That is why it is
## not in git_util.gd. It borrows that file's Keys so a hunk from here and a hunk from `git diff` are
## the same shape — duplicating the constants to shed the dependency would defeat the point.
##
## Static, no node references, so it lifts into a_lib alongside git_util.gd.
##
## The reason the shapes must match: `attach_diffs` already produces hunks from real patches, and the
## side-by-side preview will read hunks without caring which of the two made them. Anything here that
## drifts from parse_patch() is a bug, and tests/git/git_diff_tests.gd asserts it does not.
##
## One thing is not drift and is deliberate: the *line model*. git diffs "a\nb\n" as two lines, the
## final newline being a terminator; to_lines() calls it three, the last one empty, because that is
## what CodeEdit shows and marking the buffer is the entire job. The keys, the 1-based starts, the
## zero-count rule and the removals-before-additions ordering are all git's. Only a hunk reaching the
## end of a file that ends in a newline differs, by the one line of context git does not have.

const GitUtil = preload("res://addons/script_outline/src/git/git_util.gd")

## Lines of context around a change, and how far apart two changes must be to become two hunks.
## git's own default, and what the fixtures in tests/git/ were captured with.
const CONTEXT = 3

## Past this many edits, stop looking for the minimal diff and say so.
##
## Myers is O(ND) in time and, with the trace kept for backtracking, O(D²) in memory — nothing at all
## for the case this actually runs in (a keystroke, where the prefix/suffix trim leaves D at 1) and
## ruinous for a file that was rewritten wholesale. Blowing the budget is not answered with a wrong
## diff but with a coarser true one: everything old removed, everything new added. A gutter cannot
## draw the difference between that and the minimal edit script anyway.
const MAX_EDIT_DISTANCE = 1024

enum _Op {
	EQUAL,
	DELETE,
	INSERT,
}


## A blob or a buffer, as the array of lines to diff. Both sides must come through here or nothing
## below means anything.
##
## Two traps, and both of them show up as "every line changed":
##
## `git show` hands back the raw blob, filters and all — a file committed with CRLF arrives with a
## \r on the end of every line, where CodeEdit's buffer has none. Normalising the pair is the only
## thing keeping a CRLF repo from painting whole files yellow.
##
## "a\nb\n" splits to ["a", "b", ""]. That trailing empty string is not a wart to trim: it is exactly
## the empty last line CodeEdit shows for a file ending in a newline, and it is what `text` joins
## back. Keep it on both sides and it cancels; trim it on one and the last line lies.
static func to_lines(text:String) -> PackedStringArray:
	return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


## The hunks turning `old_lines` into `new_lines`, in parse_patch()'s shape.
##
## NO_NEWLINE is always false, and that is the one place these hunks differ in *meaning* from a
## parsed patch's. git tracks a missing final newline because it diffs bytes; this diffs an array of
## lines, and once a text is an array of lines there is no such thing as a newline at the end to
## miss — to_lines() has already spelled its absence as one fewer empty line, which a hunk then
## reports as an ordinary added or removed line. Same fact, said in the only vocabulary here.
static func diff_lines(old_lines:PackedStringArray, new_lines:PackedStringArray,
		context:=CONTEXT) -> Array[Dictionary]:
	if old_lines == new_lines:
		return []
	return _build_hunks(_diff_ops(old_lines, new_lines), old_lines, new_lines, context)


## The edit script, one op per line of output, as the ops that turn old into new.
##
## The trim is not an optimisation, it is the case this runs in: a keystroke inside a 2000 line
## script leaves one line differing, and everything Myers is asked to do happens on that one line.
## The trimmed context comes back as EQUAL ops, because the op list is O(N) either way and a hunk
## still needs real lines around the change to quote.
static func _diff_ops(old_lines:PackedStringArray, new_lines:PackedStringArray) -> PackedByteArray:
	var n = old_lines.size()
	var m = new_lines.size()

	var prefix = 0
	var min_len = mini(n, m)
	while prefix < min_len and old_lines[prefix] == new_lines[prefix]:
		prefix += 1

	var suffix = 0
	while suffix < min_len - prefix and old_lines[n - 1 - suffix] == new_lines[m - 1 - suffix]:
		suffix += 1

	var mid_old = old_lines.slice(prefix, n - suffix)
	var mid_new = new_lines.slice(prefix, m - suffix)

	var mid:PackedByteArray = PackedByteArray()
	if mid_old.is_empty():
		mid = _fill_ops(_Op.INSERT, mid_new.size())
	elif mid_new.is_empty():
		mid = _fill_ops(_Op.DELETE, mid_old.size())
	else:
		# both sides are non empty and differ, so a real edit script is never empty — an empty return
		# is the budget saying it gave up, and cannot be confused with a legitimate answer
		mid = _myers(mid_old, mid_new)
		if mid.is_empty():
			mid = _fill_ops(_Op.DELETE, mid_old.size())
			mid.append_array(_fill_ops(_Op.INSERT, mid_new.size()))

	var ops = _fill_ops(_Op.EQUAL, prefix)
	ops.append_array(mid)
	ops.append_array(_fill_ops(_Op.EQUAL, suffix))
	return ops


static func _fill_ops(op:_Op, count:int) -> PackedByteArray:
	var ops = PackedByteArray()
	ops.resize(count)
	ops.fill(op)
	return ops


## Myers' O(ND) shortest edit script, or an empty array if it would cost more than the budget allows.
##
## The lines are interned to ints first: the inner loop is a run of equality tests, and making them
## int compares rather than String compares costs eight lines and buys a large constant factor.
static func _myers(old_lines:PackedStringArray, new_lines:PackedStringArray) -> PackedByteArray:
	var ids = {}
	var a = _intern(old_lines, ids)
	var b = _intern(new_lines, ids)

	var n = a.size()
	var m = b.size()
	var budget = mini(n + m, MAX_EDIT_DISTANCE)

	# k runs [-d, d] and the frontier reads its neighbours at k±1, so the array has to hold one more
	# diagonal on each side than the deepest d can name
	var offset = budget + 1
	var v = PackedInt32Array()
	v.resize(2 * budget + 3)

	var trace:Array[PackedInt32Array] = []

	for d in budget + 1:
		trace.append(v.duplicate())
		for k in range(-d, d + 1, 2):
			# down (an insertion) when there is no diagonal to the left, or when the one to the right
			# has reached further; otherwise right (a deletion)
			var x:int
			if k == -d or (k != d and v[offset + k - 1] < v[offset + k + 1]):
				x = v[offset + k + 1]
			else:
				x = v[offset + k - 1] + 1

			var y = x - k
			while x < n and y < m and a[x] == b[y]: # the snake: free moves along equal lines
				x += 1
				y += 1

			v[offset + k] = x

			if x >= n and y >= m:
				return _backtrack(trace, a, b, d, offset)

	return PackedByteArray()


static func _intern(lines:PackedStringArray, ids:Dictionary) -> PackedInt32Array:
	var out = PackedInt32Array()
	out.resize(lines.size())
	for i in lines.size():
		var line = lines[i]
		var id = ids.get(line, -1)
		if id == -1:
			id = ids.size()
			ids[line] = id
		out[i] = id
	return out


## The op list, walked back out of the frontier each round left behind.
##
## Runs from the end to the start, because that is the direction the trace can be read in — each
## round's frontier says where the round before it had got to, and nothing says where the next one
## went. The ops come out reversed and are flipped at the end.
static func _backtrack(trace:Array[PackedInt32Array], a:PackedInt32Array, b:PackedInt32Array,
		d_final:int, offset:int) -> PackedByteArray:
	var ops = PackedByteArray()
	var x = a.size()
	var y = b.size()

	for d in range(d_final, -1, -1):
		var v = trace[d]
		var k = x - y

		var prev_k:int
		if k == -d or (k != d and v[offset + k - 1] < v[offset + k + 1]):
			prev_k = k + 1
		else:
			prev_k = k - 1

		var prev_x = v[offset + prev_k]
		var prev_y = prev_x - prev_k

		while x > prev_x and y > prev_y: # unwind the snake
			ops.append(_Op.EQUAL)
			x -= 1
			y -= 1

		if d > 0:
			ops.append(_Op.INSERT if prev_k == k + 1 else _Op.DELETE)

		x = prev_x
		y = prev_y

	ops.reverse()
	return ops


static func _build_hunks(ops:PackedByteArray, old_lines:PackedStringArray,
		new_lines:PackedStringArray, context:int) -> Array[Dictionary]:
	var hunks:Array[Dictionary] = []
	var n_ops = ops.size()

	# where each side's cursor stands *before* op i, so a hunk can name its starts and counts by
	# subtraction rather than by counting its own lines back up
	var old_at = PackedInt32Array()
	var new_at = PackedInt32Array()
	old_at.resize(n_ops + 1)
	new_at.resize(n_ops + 1)
	var oi = 0
	var ni = 0
	for i in n_ops:
		old_at[i] = oi
		new_at[i] = ni
		if ops[i] != _Op.INSERT:
			oi += 1
		if ops[i] != _Op.DELETE:
			ni += 1
	old_at[n_ops] = oi
	new_at[n_ops] = ni

	var i = 0
	while i < n_ops:
		if ops[i] == _Op.EQUAL:
			i += 1
			continue

		# one hunk swallows the next change along if their context would touch — which is what makes
		# two edits a line apart one hunk and two edits a page apart two
		var first = i
		var last = i
		var j = i
		while j < n_ops:
			if ops[j] != _Op.EQUAL:
				last = j
				j += 1
				continue
			var run = j
			while j < n_ops and ops[j] == _Op.EQUAL:
				j += 1
			if j >= n_ops or j - run > 2 * context:
				break

		hunks.append(_make_hunk(ops, old_lines, new_lines,
			maxi(0, first - context), mini(n_ops - 1, last + context), old_at, new_at))
		i = last + 1

	return hunks


static func _make_hunk(ops:PackedByteArray, old_lines:PackedStringArray,
		new_lines:PackedStringArray, start:int, end:int, old_at:PackedInt32Array,
		new_at:PackedInt32Array) -> Dictionary:
	var lines = []
	var i = start
	while i <= end:
		if ops[i] == _Op.EQUAL:
			lines.append({GitUtil.Keys.ORIGIN: " ", GitUtil.Keys.TEXT: old_lines[old_at[i]]})
			i += 1
			continue

		# a unified diff writes a change block as every removal and then every addition, whatever
		# order the edit script found them in — and a run with no context in it is exactly such a
		# block. Emitting them interleaved would be a patch git never writes, and the shape has to
		# match parse_patch's or the two are not interchangeable after all.
		var dels = []
		var adds = []
		while i <= end and ops[i] != _Op.EQUAL:
			if ops[i] == _Op.DELETE:
				dels.append({GitUtil.Keys.ORIGIN: "-", GitUtil.Keys.TEXT: old_lines[old_at[i]]})
			else:
				adds.append({GitUtil.Keys.ORIGIN: "+", GitUtil.Keys.TEXT: new_lines[new_at[i]]})
			i += 1
		lines.append_array(dels)
		lines.append_array(adds)

	var old_count = old_at[end + 1] - old_at[start]
	var new_count = new_at[end + 1] - new_at[start]

	# git's zero count rule: "@@ -0,0 +1,3 @@" for an insertion into an empty file. When a count is 0
	# the start names the line *before* the change and not the one at it, because there is no line at
	# it — and a 0 based cursor is already that number. _parse_hunk_header reads this back, so
	# breaking it here would break the shape both sides are supposed to share.
	return {
		GitUtil.Keys.OLD_START: old_at[start] if old_count == 0 else old_at[start] + 1,
		GitUtil.Keys.OLD_COUNT: old_count,
		GitUtil.Keys.NEW_START: new_at[start] if new_count == 0 else new_at[start] + 1,
		GitUtil.Keys.NEW_COUNT: new_count,
		GitUtil.Keys.HEADING: "", # git guesses the enclosing function; we do not, and it is optional
		GitUtil.Keys.NO_NEWLINE: false, # see diff_lines()
		GitUtil.Keys.LINES: lines,
	}


## What a line is, as a mask.
##
## A mask because the two things a line can say are independent — a bar for its own content, a wedge
## for what went missing next to it — and because hunks_to_markers() will resolve hunks from anywhere
## against any buffer, where nothing guarantees they do not overlap.
##
## A diff produced here will not in fact combine them: a removal and an addition that touch are one
## unbroken block and resolve to a single MODIFIED, so a wedge only ever lands on a context line. The
## mask costs a byte and does not have to rely on that staying true.
enum Marker {
	ADDED         = 1 << 0,
	MODIFIED      = 1 << 1,
	DELETED_ABOVE = 1 << 2, ## lines were removed immediately before this one
	DELETED_BELOW = 1 << 3, ## ...and this is what that looks like at the end of the file, where there
							## is no line after the deletion to hang the mark on
}


## Hunks, resolved to one byte per line of the new text — a lookup a draw callback can do without
## ever touching a hunk.
##
## The same split overlay_item_list.gd makes between _fit_texts and _draw, for the same reason: the
## paint runs per visible row per frame, and everything here can be decided once instead.
##
## Takes hunks, not a diff, so it works just as well on parse_patch()'s — which is the contract test
## in tests/git/git_diff_tests.gd, and the whole reason the shapes match.
static func hunks_to_markers(hunks:Array, line_count:int) -> PackedByteArray:
	var markers = PackedByteArray()
	if line_count <= 0:
		return markers
	markers.resize(line_count)
	markers.fill(0)

	for hunk:Dictionary in hunks:
		# 0 based, because that is what a CodeEdit line is — the off by one everything below turns
		# on. A zero count hunk's start already names the line before the change, so it needs no
		# adjusting; every other hunk's names the first line it describes.
		var new_i:int = hunk[GitUtil.Keys.NEW_START]
		if hunk[GitUtil.Keys.NEW_COUNT] != 0:
			new_i -= 1

		var lines:Array = hunk[GitUtil.Keys.LINES]
		var i = 0
		while i < lines.size():
			if lines[i][GitUtil.Keys.ORIGIN] == " ":
				new_i += 1
				i += 1
				continue

			var adds = 0
			var dels = 0
			var block = new_i # the first added line, or the line the removal sits in front of
			while i < lines.size() and lines[i][GitUtil.Keys.ORIGIN] != " ":
				if lines[i][GitUtil.Keys.ORIGIN] == "+":
					adds += 1
				else:
					dels += 1
				i += 1
			new_i += adds

			if adds > 0:
				# a replacement is one fact and not a removal next to an addition: the reader wants
				# to know the line changed, and drawing it as a deletion too would say the line
				# before it lost something, which is not what happened
				var mask = Marker.MODIFIED if dels > 0 else Marker.ADDED
				for line in range(block, block + adds):
					_mark(markers, line, mask)
			elif dels > 0:
				if block < line_count:
					_mark(markers, block, Marker.DELETED_ABOVE)
				else:
					_mark(markers, line_count - 1, Marker.DELETED_BELOW)

	return markers


## Bounds checked, because the hunks and the line count need not have come from the same place — the
## contract test feeds git's hunks against a different buffer on purpose, and a real one can arrive
## a keystroke stale.
static func _mark(markers:PackedByteArray, line:int, mask:int) -> void:
	if line < 0 or line >= markers.size():
		return
	markers[line] |= mask
