extends SceneTree
## Owner item 105 (the Ledger is gone): turns the saves in user://saves_NAME into ones an older
## build left in the middle of the Ledger arc (act 3: relay placed and not yet used, two jammers at
## the base, coupons, drone counts, an audit in the events' memory, its Codex pages and trinkets,
## save version 4), or with --verify checks that a later run cleaned all of it out and kept playing.
##   godot --headless --path . -s tools/ledger_old_save.gd -- --save-dir=NAME [--verify]
## Used by tools/check_old_ledger_save.sh.

func _init() -> void:
	var dir: String = ""
	var verify: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--save-dir="):
			dir = "user://saves_" + a.get_slice("=", 1).validate_filename()
		elif a == "--verify":
			verify = true
	var files: Array[String] = []
	_find(dir, files)
	var touched: int = 0
	var bad: int = 0
	for path: String in files:
		var d: Dictionary = SaveManager.read_dict(path)
		if not (d.get("flags") is Dictionary and d.get("stats") is Dictionary):
			continue  # not a world save (profile, settings)
		touched += 1
		if verify:
			var text: String = JSON.stringify(d).to_lower()
			var ok: bool = not text.contains("ledger") and int(d.get("version", 0)) >= 5
			var st: Dictionary = d["stats"]
			var moved: bool = float(st.get("time_played", 0.0)) > float((d["flags"] as Dictionary).get("ledger_check_time", 0.0))
			print("[old-ledger] %s: version %d, Ledger keys left: %s, played on: %s" % [path.get_file(), int(d.get("version", 0)), "none" if not text.contains("ledger") else "SOME", str(moved)])
			if not ok or not moved:
				bad += 1
			continue
		var fl: Dictionary = d["flags"]
		fl["ledger_act"] = 3
		fl["ledger_relay_hub"] = 0
		fl["ledger_coupons"] = [0, 2, 5]
		fl["ledger_check_time"] = float((d["stats"] as Dictionary).get("time_played", 0.0))
		var once: Dictionary = fl.get("once", {}) if fl.get("once") is Dictionary else {}
		once["toast_ledger_note"] = true
		once["wren_ledger_drop"] = true
		fl["once"] = once
		var cx: Array = fl.get("codex", []) if fl.get("codex") is Array else []
		cx.append_array(["shards:ledger_memo", "sightings:ledger_wreck", "homeward:ledger_system"])
		fl["codex"] = cx
		var sh: Array = fl.get("shards_found", []) if fl.get("shards_found") is Array else []
		sh.append("ledger_memo")
		fl["shards_found"] = sh
		var tk: Array = fl.get("trinkets", []) if fl.get("trinkets") is Array else []
		tk.append_array(["audit_stamp", "drone_propeller"])
		fl["trinkets"] = tk
		var ev: Dictionary = fl.get("events", {}) if fl.get("events") is Dictionary else {}
		ev["recent"] = ["ledger_audit"]
		ev["done"] = {"ledger_audit": 1}
		ev["next_in"] = 5.0
		fl["events"] = ev
		(d["stats"] as Dictionary)["ledger_drops"] = 4
		(d["stats"] as Dictionary)["ledger_jammed"] = 1
		if d.get("world") is Dictionary:
			(d["world"] as Dictionary)["ledger_jammers"] = 2
		d["version"] = 4
		SaveManager.write_dict(path, d)
		print("[old-ledger] %s: Ledger state written (act 3, 2 jammers), version 4" % path.get_file())
	if touched == 0:
		print("[old-ledger] FAIL no world save under %s" % dir)
		bad += 1
	print("[old-ledger] %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(1 if bad > 0 else 0)


func _find(dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".save"):
			out.append(dir.path_join(f))
	for sub: String in DirAccess.get_directories_at(dir):
		_find(dir.path_join(sub), out)
