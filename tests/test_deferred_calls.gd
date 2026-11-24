extends GutTest
## A deferred call must not outlive the node that asked for it. The engine checks a deferred
## METHOD (`_fit.call_deferred()`) against the node's id and drops it when the node is gone. A
## deferred LAMBDA that uses the node (`(func() -> void: _fit()).call_deferred()`) only keeps the
## node's address: when the node is freed before the frame ends, the lambda runs on whatever lies
## at that address by then. That crashed the test run on the build server (signal 11 one script
## after tests/test_first_seed_hint.gd, which frees a FirstSeed with such a call waiting).


## The fault itself, as it happened: a FirstSeed asks for its planting card and is freed in the
## same frame. Nodes made right after must not get that card.
func test_freed_first_seed_leaves_no_call_behind() -> void:
	var seeds0: BigNum = GameState.get_currency("seeds")
	var later: Array[FirstSeed] = []
	for round_i: int in 8:
		var fs := FirstSeed.new()
		add_child(fs)
		fs._resume_planting()
		fs.free()
		for k: int in 8:  # same size as the freed node: the allocator hands its memory out again
			later.append(FirstSeed.new())
	await wait_process_frames(2)
	var hit: int = 0
	for n: FirstSeed in later:
		if n._card != "" or n._waiting_sprout:
			hit += 1
		n.free()
	GameState.spend("seeds", GameState.get_currency("seeds"))
	GameState.add_currency("seeds", seeds0)
	assert_eq(hit, 0, "a freed node's deferred call ran on another node")


## The rule that keeps it out: in a node's own (non-static) function, call_deferred takes a method,
## never a lambda. Lambdas in static functions have no node to lose.
func test_no_deferred_lambda_in_a_node_function() -> void:
	var bad: Array[String] = []
	var files: Array[String] = []
	_gd_files("res://", files)
	assert_gt(files.size(), 200, "the scan found the game's scripts")
	for path: String in files:
		bad.append_array(deferred_lambdas(FileAccess.get_file_as_string(path), path))
	assert_eq(bad, [] as Array[String], "use a method: `_name.call_deferred()` (or .bind(args))")


func test_the_scan_sees_each_shape() -> void:
	var src: String = "\n".join([
		"func a() -> void:",
		"\t(func() -> void: _fit()).call_deferred()",
		"\tvar grow := func() -> void:",
		"\t\t_fit()",
		"\tgrow.call_deferred()",
		"\tvar late: Callable = func() -> void: _fit()",
		"\tlate.call_deferred()",
		"\t(func() -> void:",
		"\t\t_fit()).call_deferred()",
		"\t_fit.call_deferred()",
		"\t_btn.grab_focus.call_deferred()",
		"\t_btn.call_deferred(\"grab_focus\")",
		"\t_fit.bind(1).call_deferred()",
		"static func b() -> void:",
		"\t(func() -> void: print(1)).call_deferred()",
		"\tvar grow := func() -> void: print(2)",
		"\tgrow.call_deferred()",
	])
	var got: Array[String] = deferred_lambdas(src, "x.gd")
	assert_eq(got.size(), 4, str(got))
	for line: int in [2, 5, 7, 9]:
		assert_true(got.any(func(s: String) -> bool: return s.begins_with("x.gd:%d " % line)), "line %d in %s" % [line, str(got)])


func _gd_files(dir: String, out: Array[String]) -> void:
	for d: String in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or (dir == "res://" and d in ["addons", "build", "screenshots"]):
			continue
		_gd_files(dir.path_join(d), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


## "path:line text" for every lambda handed to call_deferred inside a non-static function.
static func deferred_lambdas(src: String, path: String) -> Array[String]:
	var out: Array[String] = []
	var lines: PackedStringArray = src.split("\n")
	var is_static: bool = true  # top-level code has no function
	var lambda_vars: Dictionary = {}
	var fn := RegEx.create_from_string("^\\s*(static\\s+)?func\\s+\\w+\\s*\\(")
	var lam_var := RegEx.create_from_string("(\\w+)\\s*(?::\\s*Callable\\s*)?:?=\\s*func\\b")
	var recv_var := RegEx.create_from_string("(^|[^\\w.])(\\w+)\\.call_deferred\\(")
	var open_at: Array[int] = []  # lines where a still-open "(func" began
	for i: int in lines.size():
		var l: String = lines[i]
		var m: RegExMatch = fn.search(l)
		if m:
			is_static = m.get_string(1) != ""
			lambda_vars.clear()
			open_at.clear()
		if is_static:
			continue
		var lv: RegExMatch = lam_var.search(l)
		if lv:
			lambda_vars[lv.get_string(1)] = true
		if "(func" in l.replace(" ", "") and not ").call_deferred(" in l:
			open_at.append(i)
		if ").call_deferred(" in l:
			var head: String = l.strip_edges()
			if head.begins_with("(func"):
				out.append("%s:%d %s" % [path, i + 1, head.left(60)])
			elif not open_at.is_empty() and lines[open_at.back()].strip_edges().begins_with("(func") and _closes(lines, open_at.back(), i):
				out.append("%s:%d %s" % [path, i + 1, lines[open_at.back()].strip_edges().left(60)])
		var rv: RegExMatch = recv_var.search(l)
		if rv and lambda_vars.has(rv.get_string(2)):
			out.append("%s:%d %s" % [path, i + 1, l.strip_edges().left(60)])
	return out


## True when the "(" that opens line `from` is closed by the ")" before ".call_deferred(" on line `to`.
static func _closes(lines: PackedStringArray, from: int, to: int) -> bool:
	var depth: int = 0
	for i: int in range(from, to + 1):
		var l: String = lines[i]
		var stop: int = l.find(").call_deferred(") + 1 if i == to else l.length()
		for c: int in stop:
			var ch: String = l[c]
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
				if depth == 0:
					return i == to and c == stop - 1
	return false
