extends SceneTree
## Owner item 110: moves the time stamp of the saves in user://saves_NAME, as if the game had been
## closed for hours or days, or the computer's clock had been set back. Used by
## tools/check_clock_save.sh between a --clock-check=save and a --clock-check=load run.
##   godot --headless --path . -s tools/clock_save.gd -- --save-dir=NAME --shift=S [--old]
##     --shift=S   the save's stamp becomes "S seconds ago" (S < 0: a stamp in the future, which is
##                 what a clock set back looks like). The first call keeps a copy of each save
##                 (*.clocksrc); every call starts again from that copy.
##     --old       also turns the save into one from before item 110 (version 5): the away keys
##                 are written back (stats.welcome_backs, offline_best_s; offline_units and
##                 junk_left on every base), and the research and rocket timers are put back on
##                 the system clock with the same time left.

func _init() -> void:
	var dir: String = ""
	var shift: float = 0.0
	var old: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--save-dir="):
			dir = "user://saves_" + a.get_slice("=", 1).validate_filename()
		elif a.begins_with("--shift="):
			shift = float(a.get_slice("=", 1))
		elif a == "--old":
			old = true
	var files: Array[String] = []
	_find(dir, files)
	_find(dir + "_round", files)  # the globe's saves
	var touched: int = 0
	for path: String in files:
		if not FileAccess.file_exists(path + ".clocksrc"):
			DirAccess.copy_absolute(path, path + ".clocksrc")
		var d: Dictionary = _read(path + ".clocksrc")
		if d.is_empty():
			continue
		var now: float = Time.get_unix_time_from_system()
		var was: float = float(d.get("saved_unix", now))
		var world_save: bool = d.get("flags") is Dictionary and d.get("stats") is Dictionary
		if old and world_save:
			var st: Dictionary = d["stats"]
			var fl: Dictionary = d["flags"]
			var played: float = float(st.get("time_played", 0.0))
			st["welcome_backs"] = 3
			st["offline_best_s"] = 28800.0
			for w: Variant in [d.get("world"), (d.get("orbit", {}) as Dictionary).get("hub_worlds", {}).get("0")]:
				if w is Dictionary:
					(w as Dictionary)["offline_units"] = 55.0
					(w as Dictionary)["junk_left"] = 400.0
			var rs: Variant = fl.get("research")
			if rs is Dictionary and (rs as Dictionary).get("active") is Dictionary and ((rs as Dictionary)["active"] as Dictionary).has("start"):
				var a: Dictionary = (rs as Dictionary)["active"]
				a["start"] = was - (played - float(a["start"]))  # the same seconds done, by the system clock
			if fl.has("rocket_ready_at"):
				fl["rocket_ready_unix"] = was + (float(fl["rocket_ready_at"]) - played)
				fl.erase("rocket_ready_at")
			d["version"] = 5
		# Every stamp in the file moves together, as it would if the clock itself were moved.
		var move: float = (now - shift) - was
		d["saved_unix"] = was + move
		if old and world_save:
			var fl2: Dictionary = d["flags"]
			var rs2: Variant = fl2.get("research")
			if rs2 is Dictionary and (rs2 as Dictionary).get("active") is Dictionary and ((rs2 as Dictionary)["active"] as Dictionary).has("start"):
				((rs2 as Dictionary)["active"] as Dictionary)["start"] = float(((rs2 as Dictionary)["active"] as Dictionary)["start"]) + move
			if fl2.has("rocket_ready_unix"):
				fl2["rocket_ready_unix"] = float(fl2["rocket_ready_unix"]) + move
		_write(path, d)
		touched += 1
		print("[clock] %s: stamped %.1f h %s%s" % [path.get_file(), absf(shift) / 3600.0, "ago" if shift >= 0.0 else "in the FUTURE (clock set back)", ", as an old save (version 5, away keys written)" if old and world_save else ""])
	if touched == 0:
		print("[clock] FAIL no save under %s" % dir)
	quit(1 if touched == 0 else 0)


## As SaveManager.read_dict / write_dict (autoloads are not there for a -s script).
func _read(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
	return parsed if parsed is Dictionary else {}


func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_string(JSON.stringify(d))
	f.close()


func _find(dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".save"):
			out.append(dir.path_join(f))
	for sub: String in DirAccess.get_directories_at(dir):
		_find(dir.path_join(sub), out)
