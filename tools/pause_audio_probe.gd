extends Node
## [v8pause] `--pause-audio-probe[=S]`: S seconds into the game (default 40, game time), lists the
## world sounds that play, opens the pause menu, and after a second lists what still plays (should
## be nothing: owner item 78), then closes it and lists what resumed. `[pause-audio]` lines.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _audible() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Node in Audio.world_players(get_tree().root):
		if bool(p.get("playing")) and not bool(p.get("stream_paused")):
			out.append("%s/%s[%s] %s" % [p.get_parent().name, p.name, p.get("bus"), _sound_name(p.get("stream"))])
	return out


## The Audio sound a stream belongs to, or its file.
func _sound_name(st: Resource) -> String:
	if st == null:
		return "-"
	for k: String in Audio._sounds:
		if st in (Audio._sounds[k] as Array):
			return k
	for k: String in Audio._loops:
		if Audio._loops[k] == st:
			return "loop " + k
	return st.resource_path.get_file() if st.resource_path != "" else "(generated)"


func _run() -> void:
	await get_tree().create_timer(DevHooks.get_f("pause-audio-probe", 40.0)).timeout
	var pm: Node = get_tree().current_scene.get("pause_menu") if get_tree().current_scene else null
	var t0: int = Time.get_ticks_usec()
	var n: int = Audio.world_players(get_tree().root).size()
	print("[pause-audio] the pause's player walk: %d players in %.1f ms" % [n, (Time.get_ticks_usec() - t0) / 1000.0])
	print("[pause-audio] before pause: %d playing: %s" % [_audible().size(), ", ".join(_audible())])
	if pm and pm.has_method("open_menu"):
		pm.call("open_menu")
	else:
		get_tree().paused = true
	for i: int in 30:
		await get_tree().process_frame
	await get_tree().create_timer(1.0, true).timeout
	var still: PackedStringArray = _audible()
	print("[pause-audio] paused (menu=%s): %d playing%s" % [pm != null, still.size(), (": " + ", ".join(still)) if not still.is_empty() else ""])
	if pm and pm.has_method("close_menu"):
		pm.call("close_menu")
	else:
		get_tree().paused = false
	for i: int in 10:
		await get_tree().process_frame
	print("[pause-audio] after unpause: %d playing" % _audible().size())
	print("[pause-audio] %s" % ("PASS" if still.is_empty() else "FAIL"))
