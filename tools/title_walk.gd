class_name TitleWalk
extends Node
## [v10ui] Owner, 2026-11-20: "Remove new game button if we have profiles thing." The title screen
## played with real mouse clicks, in its own save folder, through every state:
##   1. first launch: one big PLAY, no Profiles, no New Game;
##   2. one profile played: CONTINUE, NEW PROFILE, PROFILES;
##   3. three played: CONTINUE and one button per other profile, no NEW PROFILE (no slot free);
##   4. the Profiles page: Delete asks first (Cancel keeps the save, Delete erases only that
##      profile); Start over asks first (Cancel keeps it; "Erase and start" erases only that
##      profile and starts the game there);
##   5. another profile's button switches to it and continues; NEW PROFILE starts in the free slot;
##   6. PLAY on a first launch loads the game.
## `godot --headless --path . -- --menu --title-walk --save-dir=NAME`: [title-walk] lines, exit 1 on
## a failure. --title-walk-shots=/abs/dir (rendered) saves a frame of each state. In tools/check_exit.sh.

var _fails: Array[String] = []
var _shot_n: int = 0


static func attach(tree: SceneTree) -> void:
	if tree.root.has_node("TitleWalk"):
		return
	var r := TitleWalk.new()
	r.name = "TitleWalk"
	tree.root.add_child.call_deferred(r)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if SaveManager.dev_dir == "":
		print("[title-walk] FAIL: needs --save-dir=NAME (it erases profiles)")
		get_tree().quit(1)
		return
	for n: int in range(1, SaveManager.PROFILES + 1):
		SaveManager.delete_profile(n)
	SaveManager.set_profile(1)
	CradleMode.reload_for_profile()
	var m: Node = await _title()

	# 1. First launch.
	_check(_names(m) == ["Play", "Settings", "Quit"] or _names(m) == ["Play", "Wishlist on Steam", "Settings", "Quit"], "first launch: one PLAY button, then Settings and Quit (%s)" % str(_names(m)))
	_check(_focused(m) == m.get("_play") and m.get("_play") != null, "PLAY has the focus (a controller's A starts the game)")
	_check(not _has_text(m, "New Game"), "no New Game button")
	await _shot("first_launch")

	# 2. One profile played.
	_write_save(1, 3000.0)
	m = await _title()
	_check(_names(m).slice(0, 3) == ["Continue", "NewProfile", "Profiles"], "one profile played: CONTINUE, NEW PROFILE, PROFILES (%s)" % str(_names(m)))
	_check(_focused(m) == m.get("_continue"), "CONTINUE has the focus")
	_check(not _has_text(m, "New Game"), "no New Game button")
	await _shot("one_profile")

	# 3. All three played.
	_write_save(2, 5400.0)
	_write_save(3, 600.0)
	m = await _title()
	_check(_names(m).slice(0, 4) == ["Continue", "Profile2", "Profile3", "Profiles"], "three played: CONTINUE, a button for each other profile, PROFILES (%s)" % str(_names(m)))
	_check(_fits(m), "all the buttons are on the screen")
	await _shot("three_profiles")

	# 4. The Profiles page.
	await _click(m.get("_profiles_btn") as Button)
	var pk: ProfilePicker = m.get("_picker")
	_check(pk.visible, "PROFILES opens the page")
	_check(_row_texts(pk, 2) == [tr("Continue"), tr("Start over"), tr("Rename"), tr("Delete")], "a played profile: Continue, Start over, Rename, Delete (%s)" % str(_row_texts(pk, 2)))
	await _shot("profiles_page")
	await _click(_row_btn(pk, 3, tr("Delete")))
	_check(pk.get("_dialog") != null, "Delete asks first")
	await _shot("delete_confirm")
	await _click(_dialog_btn(pk, tr("Cancel")))
	_check(pk.get("_dialog") == null and _has_save(3), "Cancel keeps the profile")
	await _click(_row_btn(pk, 3, tr("Delete")))
	await _click(_dialog_btn(pk, tr("Delete")))
	_check(not _has_save(3) and _has_save(1) and _has_save(2), "Delete erases that profile and no other")
	_check(_row_texts(pk, 3) == [tr("Play"), tr("Rename")], "an empty profile: Play, Rename (%s)" % str(_row_texts(pk, 3)))
	await _click(_row_btn(pk, 2, tr("Start over")))
	_check(pk.get("_dialog") != null, "Start over asks first")
	await _shot("start_over_confirm")
	await _click(_dialog_btn(pk, tr("Cancel")))
	_check(pk.get("_dialog") == null and _has_save(2) and not bool(m.get("_leaving")), "Cancel keeps the save")
	await _click(_row_btn(pk, 2, tr("Start over")))
	await _click(_dialog_btn(pk, tr("Erase and start")), true)
	_check(bool(m.get("_leaving")) and SaveManager.profile_slot == 2 and not _has_save(2) and _has_save(1), "Erase and start: that profile starts over, the other keeps its save")
	_check(float(GameState.stats.get("time_played", 0.0)) == 0.0, "the game about to start is a new one")

	# 5. Another profile's button, and NEW PROFILE.
	m = await _title()  # (back before the game loads: profile 2 is the active one, and empty)
	_check(_names(m).slice(0, 3) == ["Profile1", "NewProfile", "Profiles"], "the active profile empty, another played: its button, NEW PROFILE, PROFILES (%s)" % str(_names(m)))
	await _click((m.get("_profile_btns") as Dictionary).get(1) as Button, true)
	_check(bool(m.get("_leaving")) and SaveManager.profile_slot == 1 and _has_save(1), "the other profile's button switches to it and continues")
	m = await _title()
	_check(_names(m).slice(0, 3) == ["Continue", "NewProfile", "Profiles"], "back at the title: CONTINUE is that profile (%s)" % str(_names(m)))
	await _click(m.get("_new_profile") as Button, true)
	_check(bool(m.get("_leaving")) and SaveManager.profile_slot == 2 and _has_save(1) and float(GameState.stats.get("time_played", 0.0)) == 0.0, "NEW PROFILE starts a new game in the free slot (profile %d), the played one untouched" % SaveManager.profile_slot)

	# 6. First launch again: PLAY loads the game.
	for n: int in range(1, SaveManager.PROFILES + 1):
		SaveManager.delete_profile(n)
	SaveManager.set_profile(1)
	CradleMode.reload_for_profile()
	m = await _title()
	_check(_names(m)[0] == "Play", "all profiles deleted: PLAY again")
	await _click(m.get("_play") as Button, true)
	_check(bool(m.get("_leaving")), "PLAY starts")
	var loaded: bool = false
	for k: int in 600:
		var cs: Node = get_tree().current_scene
		if cs != null and cs.scene_file_path == "res://scenes/slice.tscn":
			loaded = true
			break
		await _wait(0.1)
	_check(loaded and SaveManager.profile_slot == 1, "the game loads in profile 1")
	print("[title-walk] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


## The title screen built anew (as after a start), faded in.
func _title() -> Node:
	get_tree().change_scene_to_file(PauseMenu.TITLE_SCENE)
	for k: int in 1800:
		await _wait(0.1)
		var cs: Node = get_tree().current_scene
		if cs != null and cs.scene_file_path == PauseMenu.TITLE_SCENE and cs.get("_menu_box") != null and not bool(cs.get("_leaving")):
			var main: Control = cs.get("_main")
			if main != null and main.modulate.a > 0.95 and not Loader.busy():  # (the start-up loading screen is gone)
				await _wait(0.3)
				return cs
	_check(false, "the title screen comes up")
	return get_tree().current_scene


func _write_save(n: int, played: float) -> void:
	var d: Dictionary = GameState.to_dict()
	d["stats"] = {"time_played": played}
	d["saved_unix"] = Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(SaveManager.profile_dir(n))
	SaveManager.write_dict(SaveManager.profile_dir(n).path_join("slot_0.save"), d)


func _has_save(n: int) -> bool:
	return FileAccess.file_exists(SaveManager.profile_dir(n).path_join("slot_0.save"))


func _names(m: Node) -> Array:
	var out: Array = []
	for c: Node in (m.get("_menu_box") as Node).get_children():
		if c is Button and (c as Button).visible:
			out.append(str(c.name) if not str(c.name).begins_with("@") else {tr("Settings").to_upper(): "Settings", tr("Quit").to_upper(): "Quit"}.get((c as Button).text, (c as Button).text))
	return out


func _has_text(m: Node, t: String) -> bool:
	for b: Node in (m.get("_ui") as Node).find_children("*", "Button", true, false):
		if (b as Button).text.to_lower() == t.to_lower():
			return true
	return false


func _focused(m: Node) -> Control:
	return (m as Node).get_viewport().gui_get_focus_owner()


func _fits(m: Node) -> bool:
	var screen: Rect2 = (m.get("_ui") as Control).get_global_rect()
	for c: Node in (m.get("_menu_box") as Node).get_children():
		if c is Button and not screen.encloses((c as Button).get_global_rect()):
			return false
	return true


func _row(pk: ProfilePicker, n: int) -> Array:
	return (pk.get("_grid") as Array)[n - 1]


func _row_texts(pk: ProfilePicker, n: int) -> Array:
	return _row(pk, n).map(func(b: Button) -> String: return b.text)


func _row_btn(pk: ProfilePicker, n: int, text: String) -> Button:
	for b: Button in _row(pk, n):
		if b.text == text:
			return b
	_check(false, "profile %d has a %s button" % [n, text])
	return null


func _dialog_btn(pk: ProfilePicker, text: String) -> Button:
	var d: Node = pk.get("_dialog")
	if d != null:
		for b: Node in d.find_children("*", "Button", true, false):
			if (b as Button).text == text:
				return b as Button
	_check(false, "the question has a %s button" % text)
	return null


## A real click: the mouse moves there, the left button goes down and up, through the window.
## `leaving`: the click starts the game; come back the moment the title says so (the walk then
## rebuilds the title before its half-second fade ends and the game loads).
func _click(c: Control, leaving: bool = false) -> void:
	if c == null:
		return
	await _frames(3)
	var at: Vector2 = get_tree().root.get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5))
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	Input.parse_input_event(mv)
	Input.flush_buffered_events()
	await _frames(2)
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		if leaving and not down:
			for k: int in 30:
				if bool(get_tree().current_scene.get("_leaving")):
					return
				await get_tree().process_frame
			return
		await _frames(2)
	await _wait(0.3)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _check(ok: bool, what: String) -> void:
	print("[title-walk] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _shot(shot: String) -> void:
	var dir: String = DevHooks.get_s("title-walk-shots", "")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await _wait(1.5)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = "%s/%02d_%s.png" % [dir, _shot_n, shot]
	_shot_n += 1
	get_tree().root.get_texture().get_image().save_png(path)
	print("[title-walk] shot %s" % path)
