extends SceneTree
## The headless test runner, no downloads:
##   godot --headless --path <project> --import                 (once: registers the class_name scripts)
##   godot --headless --path <project> --script res://tests/run.gd [-- --filter=<substr>]
## Runs every res://tests/test_*.gd: each method named test_*, and each case a suite's get_cases() returns
## ([label, Callable] pairs). Every test gets a T and ends with t.done(): a script error abandons a function without
## failing anything, so a test that never reaches done() is counted as failed. A test may await (the live client
## test waits a frame: TLS is not ready inside a SceneTree's _init); each is awaited before the next.
## Exits 0 only when nothing failed; prints the total.

class T:
	var failures: PackedStringArray = []
	var checks := 0
	var reached_end := false
	var skipped := ""
	## The runner, for a test that waits a frame (Engine.get_main_loop() is null inside its _init).
	var tree: SceneTree
	func ok(cond: bool, msg: String = "") -> void:
		checks += 1
		if not cond:
			failures.append("not ok: " + msg)
	func eq(a, b, msg: String = "") -> void:
		checks += 1
		if typeof(a) != typeof(b) or a != b:
			failures.append("%s: expected %s (%s), got %s (%s)" % [msg, _show(b), type_string(typeof(b)), _show(a), type_string(typeof(a))])
	func fail(msg: String) -> void:
		checks += 1
		failures.append(msg)
	func skip(reason: String) -> void:
		skipped = reason
		reached_end = true
	func done() -> void:
		reached_end = true
	func _show(v) -> String:
		var s := var_to_str(v)
		return s if s.length() < 300 else s.substr(0, 300) + "..."

var passed := 0
var failed := 0
var skipped := 0
var checks := 0

func _run(label: String, fn: Callable) -> void:
	var t := T.new()
	t.tree = self
	var t0 := Time.get_ticks_msec()
	await fn.call(t)
	var ms := Time.get_ticks_msec() - t0
	checks += t.checks
	if not t.reached_end:
		t.failures.append("died before t.done() (a script error aborted the test)")
	if t.skipped != "" and t.failures.is_empty():
		skipped += 1
		print("SKIP %s: %s" % [label, t.skipped])
	elif t.failures.is_empty():
		passed += 1
		print("ok   %s (%d checks, %d ms)" % [label, t.checks, ms])
	else:
		failed += 1
		print("FAIL %s" % label)
		for x in t.failures:
			print("       " + x)

func _init() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var t_all := Time.get_ticks_msec()
	var files := Array(DirAccess.get_files_at("res://tests")).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("FAIL %s: does not load" % f)
			failed += 1
			continue
		var suite = script.new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var label: String = f + ":" + name
			if filter != "" and not label.contains(filter):
				continue
			await _run(label, Callable(suite, name))
		if suite.has_method("get_cases"):
			for c in suite.get_cases():
				var label: String = f + ":" + c[0]
				if filter != "" and not label.contains(filter):
					continue
				await _run(label, c[1])
	print("")
	print("TOTAL: %d tests, %d passed, %d failed, %d skipped (%d checks) in %.1f s" % [passed + failed + skipped, passed, failed, skipped, checks, (Time.get_ticks_msec() - t_all) / 1000.0])
	quit(1 if failed > 0 else 0)
