extends SceneTree
## [v13goals] Planting is gone (owner, 26 Nov: the player only cleans, clean ground greens by
## itself). Turns the saves in user://saves_NAME into ones the planting game left: save version 5,
## 37 seeds, the seed tin found and the first sprout up, a compost press hopper, the card on "Plant
## the first seed", a Request to plant, a thirsty planted cell in the garden, a Drip and a Seedling
## in the crew. With --verify it checks that a later run cleaned all of it out and played on.
##   godot --headless --path . -s tools/planting_old_save.gd -- --save-dir=NAME [--verify]
## Used by tools/check_old_planting_save.sh.

## ORDER_V4's "seed" step (story/objectives.gd): the old card stood on it.
const OLD_SEED_STEP: int = 12
const SEEDS: float = 37.0


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
	_find(dir + "_round", files)  # the globe's saves
	var touched: int = 0
	var bad: int = 0
	for path: String in files:
		var d: Dictionary = _read(path)
		if not (d.get("flags") is Dictionary and d.get("stats") is Dictionary):
			continue  # not a world save (profile, settings)
		touched += 1
		if verify:
			bad += _verify(path, d)
			continue
		_write_old(d)
		_write(path, d)
		print("[old-planting] %s: planting state written (37 seeds, seed step, Drip and Seedling), version 5" % path.get_file())
	if touched == 0:
		print("[old-planting] FAIL no world save under %s" % dir)
		bad += 1
	print("[old-planting] %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(1 if bad > 0 else 0)


func _write_old(d: Dictionary) -> void:
	var fl: Dictionary = d["flags"]
	var cur: Dictionary = d.get("currencies", {}) if d.get("currencies") is Dictionary else {}
	cur["seeds"] = [SEEDS / 10.0, 1]  # BigNum serialized: mantissa, exponent
	d["currencies"] = cur
	fl["seeds_unlocked"] = true
	fl["seed_signal"] = true
	fl["first_sprout"] = true
	fl["press_hopper"] = 12.0
	fl["objective_step"] = OLD_SEED_STEP
	fl["objectives_v4"] = true
	fl.erase("objectives_v5")
	fl["old_plant_check_time"] = float((d["stats"] as Dictionary).get("time_played", 0.0))
	fl["contracts"] = {"slots": [{"state": "active", "tpl": "plant", "tier": 1, "n": 12, "left": 300.0, "base": 0.0}], "done_total": 0}
	(d["stats"] as Dictionary)["plants_planted"] = 3
	var orbit: Dictionary = d.get("orbit", {}) if d.get("orbit") is Dictionary else {}
	var at: Array = [0.0, 1.0, 0.0]
	var lumi: Variant = orbit.get("lumi", {})
	if lumi is Dictionary and (lumi as Dictionary).get("at") is Array and ((lumi as Dictionary)["at"] as Array).size() >= 3:
		var a: Array = (lumi as Dictionary)["at"]
		at = [float(a[0]), float(a[1]), float(a[2])]
	var rd: Dictionary = orbit.get("robots", {}) if orbit.get("robots") is Dictionary else {}
	var list: Array = rd.get("robots", []) if rd.get("robots") is Array else []
	list.append({"type": "drip", "tier": 1, "name": "Drip-07", "dir": at, "heading": [1, 0, 0], "hub": -1, "hopper": 0.0, "carry": []})
	list.append({"type": "seedling", "tier": 0, "name": "Sprig-12", "dir": at, "heading": [0, 0, 1], "hub": -1, "hopper": 0.0, "carry": []})
	rd["robots"] = list
	orbit["robots"] = rd
	# A planted, thirsty cell in the garden: one Lumi cleaned (hexes_paid), three plants, no water.
	var paid: Dictionary = orbit.get("hexes_paid", {}) if orbit.get("hexes_paid") is Dictionary else {}
	var w: Dictionary = d.get("world", {}) if d.get("world") is Dictionary else {}
	if not paid.is_empty():
		var hid: String = str(paid.keys()[0])
		var sp := PackedByteArray([2, 3, 1])
		var st := PackedByteArray([2, 1, 3])
		var wa := PackedFloat32Array([0.0, 0.0, 0.0])
		var g: Dictionary = w.get("garden", {}) if w.get("garden") is Dictionary else {}
		var cells: Dictionary = g.get("cells", {}) if g.get("cells") is Dictionary else {}
		cells[hid] = [Marshalls.raw_to_base64(sp), Marshalls.raw_to_base64(st), Marshalls.raw_to_base64(wa.to_byte_array())]
		g["cells"] = cells
		w["garden"] = g
		d["world"] = w
		fl["old_plant_cell"] = hid
	d["orbit"] = orbit
	d["version"] = 5


func _verify(path: String, d: Dictionary) -> int:
	var fails: Array[String] = []
	var fl: Dictionary = d["flags"]
	if int(d.get("version", 0)) < 6:
		fails.append("version %d" % int(d.get("version", 0)))
	if (d.get("currencies", {}) as Dictionary).has("seeds"):
		fails.append("a seed balance is left")
	if fl.has("press_hopper"):
		fails.append("the compost press hopper is left")
	if not bool(fl.get("planting_dropped", false)):
		fails.append("not migrated (flags.planting_dropped)")
	var text: String = JSON.stringify(d.get("orbit", {}))
	if text.contains("\"drip\"") or text.contains("\"seedling\""):
		fails.append("a Drip or Seedling robot is left")
	var cs: Variant = fl.get("contracts", {})
	if cs is Dictionary and JSON.stringify(cs).contains("\"plant\""):
		fails.append("the planting Request is left")
	if float((d["stats"] as Dictionary).get("time_played", 0.0)) <= float(fl.get("old_plant_check_time", 0.0)):
		fails.append("did not play on")
	var step: int = int(fl.get("objective_step", -1))
	if step < OLD_SEED_STEP - 2 or step > 40:  # "seed" was 12; the new chain has it gone: robot2 (10) or later
		fails.append("objective step %d" % step)
	var hid: String = str(fl.get("old_plant_cell", ""))
	if hid != "":
		var cells: Dictionary = ((d.get("world", {}) as Dictionary).get("garden", {}) as Dictionary).get("cells", {})
		var e: Variant = cells.get(hid)
		if not (e is Array and (e as Array).size() == 3):
			fails.append("the planted cell %s is gone from the garden" % hid)
		else:
			var wa: PackedFloat32Array = Marshalls.base64_to_raw(str(e[2])).to_float32_array()
			var sp: PackedByteArray = Marshalls.base64_to_raw(str(e[0]))
			var planted: int = 0
			var dry: int = 0
			for k: int in sp.size():
				if sp[k] > 0:
					planted += 1
					if k < wa.size() and wa[k] <= 0.0:
						dry += 1
			if planted < 3 or dry > 0:
				fails.append("the old plants: %d planted, %d thirsty" % [planted, dry])
	print("[old-planting] %s: version %d, step %d, %s" % [path.get_file(), int(d.get("version", 0)), step, "clean" if fails.is_empty() else "; ".join(fails)])
	return 0 if fails.is_empty() else 1


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
