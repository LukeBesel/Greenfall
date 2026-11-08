extends Node
## QA-only autoload: enable with an uncommitted override.cfg ([autoload] QAProbe="*res://tools/qa_probe.gd"). See docs/QA_REPORT.md.
## QA-only probe (untracked). Driven by --qa-seq="T:cmd;T:cmd" (wall-clock seconds).
## cmds: pause | cancel | action=NAME | click=TEXT | shot=PATH | dump | interact
## --qa-watch logs every change in the set of visible on-screen texts (message overlap check).

var _seq: Array = []
var _t0: int = Time.get_ticks_msec()
var _last_watch: String = ""
var _watch_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var s: String = DevHooks.get_s("qa-seq", "")
	for part: String in s.split(";", false):
		var kv: PackedStringArray = part.split(":", true, 1)
		_seq.append([float(kv[0]), kv[1]])
	if DevHooks.has("qa-seq") or DevHooks.has("qa-watch"):
		print("[qa] probe on, %d steps" % _seq.size())


func _process(delta: float) -> void:
	var t: float = (Time.get_ticks_msec() - _t0) / 1000.0
	while not _seq.is_empty() and t >= float(_seq[0][0]):
		var cmd: String = _seq.pop_front()[1]
		_run(cmd)
	if DevHooks.has("qa-watch"):
		_watch_t += delta / maxf(Engine.time_scale, 0.001)
		if _watch_t >= 0.5:
			_watch_t = 0.0
			_watch(t)


func _run(cmd: String) -> void:
	print("[qa] run ", cmd)
	if cmd == "pause" or cmd == "cancel" or cmd == "interact" or cmd.begins_with("action="):
		var a: String = cmd.trim_prefix("action=") if cmd.begins_with("action=") else ("ui_cancel" if cmd == "cancel" else cmd)
		var ev := InputEventAction.new()
		ev.action = a
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventAction.new()
		up.action = a
		up.pressed = false
		get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void: Input.parse_input_event(up))
	elif cmd.begins_with("click="):
		var want: String = cmd.trim_prefix("click=").to_lower()
		var b: BaseButton = _find_button(get_tree().root, want)
		print("[qa] click '%s' -> %s" % [want, str(b.get_path()) if b else "NOT FOUND"])
		if b:
			b.emit_signal("pressed")
	elif cmd.begins_with("shot="):
		DevHooks.save_viewport(cmd.trim_prefix("shot="))
	elif cmd.begins_with("near="):
		var r: float = float(cmd.trim_prefix("near="))
		_near(get_tree().current_scene, r, 0)
	elif cmd == "dump":
		print("[qa] dump:\n" + _texts(true))


func _find_button(n: Node, want: String) -> BaseButton:
	if n is BaseButton and (n as CanvasItem).is_visible_in_tree():
		var txt: String = str(n.get("text")).to_lower()
		if txt.contains(want) or str(n.get("tooltip_text")).to_lower().contains(want):
			return n
	for c: Node in n.get_children():
		var r: BaseButton = _find_button(c, want)
		if r:
			return r
	return null


func _texts(rects: bool) -> String:
	var out: PackedStringArray = []
	_collect(get_tree().root, out, rects)
	return "\n".join(out)


func _collect(n: Node, out: PackedStringArray, rects: bool) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if (n is Label or n is RichTextLabel) and (n as Control).is_visible_in_tree():
		var c: Control = n
		var txt: String = (c as Label).text if c is Label else (c as RichTextLabel).get_parsed_text()
		var a: float = c.modulate.a * c.self_modulate.a
		var p: Node = c.get_parent()
		while p:
			if p is CanvasItem:
				a *= (p as CanvasItem).modulate.a
			p = p.get_parent()
		if txt.strip_edges() != "" and a > 0.05:
			var line: String = txt.replace("\n", " / ").left(140)
			if rects:
				var r: Rect2 = c.get_global_rect()
				line = "  [%d,%d %dx%d a=%.2f] %s" % [r.position.x, r.position.y, r.size.x, r.size.y, a, line]
			out.append(line)
	for ch: Node in n.get_children():
		_collect(ch, out, rects)


func _watch(t: float) -> void:
	var s: String = _texts(true)
	# compare without alpha/rect noise
	var key: String = _texts(false)
	if key != _last_watch:
		_last_watch = key
		print("[qa-watch] t=%.1f game=%.1f\n%s" % [t, t * Engine.time_scale, s])


func _near(n: Node, r: float, depth: int) -> void:
	for c: Node in n.get_children():
		if c is Node3D and (c as Node3D).is_visible_in_tree():
			var p: Vector3 = (c as Node3D).global_position
			if Vector2(p.x, p.z).length() <= r and depth <= 2:
				print("[qa-near] %s%s (%s) at (%.1f, %.1f, %.1f)" % ["  ".repeat(depth), c.name, c.get_class(), p.x, p.y, p.z])
		if depth < 2:
			_near(c, r, depth + 1)
