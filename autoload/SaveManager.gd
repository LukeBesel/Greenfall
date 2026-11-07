extends Node
## Versioned, compressed saves in user://. Autosaves every 60 s, on focus loss, on pause and on quit.
## Nodes in the "persist" group get `persist_save()` called before a save so they can write
## their state into GameState.world.

const SAVE_DIR: String = "user://saves"
const AUTOSAVE_INTERVAL: float = 60.0

var slot: int = 0
## Dev hooks and tests can turn saving off so runs don't touch the player's save.
var enabled: bool = true
var _timer: float = 0.0
## [beat] Dev: `--save-dir=NAME` keeps saves in user://saves_NAME and saves even with --fresh
## (staged autoplay runs chain through it without touching the player's save).
var dev_dir: String = ""
## [worlds2] Save profiles: three separate profile folders (user://saves/p1..p3), each with its own
## Cradle Mode profile (worlds, Heirlooms) and world slots. Settings stay shared. The chosen
## profile is remembered in user://saves/profiles.cfg. Saves from before profiles (slot files and
## profile.save directly in user://saves) move into p1 on first start.
const PROFILES: int = 3
const PROFILES_CFG: String = "profiles.cfg"
var profile_slot: int = 1


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--save-dir="):
			dev_dir = a.get_slice("=", 1).validate_filename()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	migrate_to_profiles(root_dir())  # [worlds2] before anything reads a save (CradleBoot, Steam Cloud)
	profile_slot = read_profile_choice()
	DirAccess.make_dir_recursive_absolute(save_dir())
	import_demo_save()  # [steam]


## [steam] The demo keeps its saves apart (Demo.SAVE_DIR) so a full-game save never opens in it.
## [worlds2] The folder that holds the profile folders.
func root_dir() -> String:
	if dev_dir != "":  # [beat]
		return "user://saves_" + dev_dir
	return Demo.SAVE_DIR if Demo.is_demo() else SAVE_DIR


## [worlds2] The current save profile's folder: world slots and profile.save live here.
func save_dir() -> String:
	return profile_dir(profile_slot)


func profile_dir(n: int) -> String:
	return root_dir().path_join("p%d" % clampi(n, 1, PROFILES))


## [worlds2] Moves pre-profile saves (slot_N.save, profile.save in `root`) into root/p1, unless p1
## already has saves. Returns how many files moved. Static so tests can run it on a scratch folder.
static func migrate_to_profiles(root: String) -> int:
	if not DirAccess.dir_exists_absolute(root):
		return 0
	var legacy: Array[String] = []
	for nm: String in DirAccess.get_files_at(root):
		if nm.ends_with(".save") or nm.ends_with(".save.tmp"):
			legacy.append(nm)
	if legacy.is_empty():
		return 0
	var p1: String = root.path_join("p1")
	DirAccess.make_dir_recursive_absolute(p1)
	for nm: String in DirAccess.get_files_at(p1):
		if nm.ends_with(".save"):
			return 0  # p1 is in use already: leave the old files where they are
	var moved: int = 0
	for nm: String in legacy:
		if DirAccess.rename_absolute(root.path_join(nm), p1.path_join(nm)) == OK:
			moved += 1
	print("[save] moved %d save files into the first profile (%s)" % [moved, p1])
	return moved


func read_profile_choice() -> int:
	var cf := ConfigFile.new()
	if cf.load(root_dir().path_join(PROFILES_CFG)) != OK:
		return 1
	return clampi(int(cf.get_value("profiles", "current", 1)), 1, PROFILES)


## [worlds2] Switch to save profile n (1..3) and remember it. The caller reloads the Cradle profile.
func set_profile(n: int) -> void:
	profile_slot = clampi(n, 1, PROFILES)
	DirAccess.make_dir_recursive_absolute(save_dir())
	if (DevHooks.has("fresh") or DevHooks.has("nosave")) and dev_dir == "":
		return  # dev runs never change which profile the player last used
	var cf := ConfigFile.new()
	cf.set_value("profiles", "current", profile_slot)
	DirAccess.make_dir_recursive_absolute(root_dir())
	cf.save(root_dir().path_join(PROFILES_CFG))


## [worlds2] Erase every save of profile n (its worlds and profile.save), locally and in the cloud.
func delete_profile(n: int) -> void:
	var dir: String = profile_dir(n)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for nm: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(nm))
		if nm.ends_with(".save"):
			SteamService.on_deleted(dir.path_join(nm))


## [steam] Full game, first run after the demo: carry the demo's slots over (never overwrites).
func import_demo_save() -> void:
	if Demo.is_demo() or not DirAccess.dir_exists_absolute(Demo.SAVE_DIR):
		return
	migrate_to_profiles(Demo.SAVE_DIR)  # [worlds2] the demo's saves are in its own p1 too
	var src_dir: String = Demo.SAVE_DIR.path_join("p1")
	if not DirAccess.dir_exists_absolute(src_dir):
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR.path_join("p1"))
	for nm: String in DirAccess.get_files_at(src_dir):
		var dst: String = SAVE_DIR.path_join("p1").path_join(nm)  # [worlds2] into the first profile
		if nm.ends_with(".save") and not FileAccess.file_exists(dst) and not FileAccess.file_exists(dst + ".demo_imported"):
			DirAccess.copy_absolute(src_dir.path_join(nm), dst)
			FileAccess.open(dst + ".demo_imported", FileAccess.WRITE)
			print("[save] imported demo save ", nm)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= AUTOSAVE_INTERVAL:
		_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game()


func slot_path(s: int = -1) -> String:
	return "%s/slot_%d.save" % [save_dir(), slot if s < 0 else s]  # [steam] save_dir()


func has_save(s: int = -1) -> bool:
	return FileAccess.file_exists(slot_path(s)) or FileAccess.file_exists(slot_path(s) + ".tmp")


func save_game(gather: bool = true) -> bool:
	if not (enabled or dev_dir != "") or not is_inside_tree():  # [beat] --save-dir saves even with --fresh
		return false
	if gather:
		# [beat] Not mid-launch: Lumi is on the lift with the cells already spent; the last autosave
		# (or the save travel_to writes on arrival) is the consistent one.
		var sc: Node = get_tree().current_scene
		if sc and sc.get("launching") == true:
			return false
		get_tree().call_group("persist", "persist_save")
	var ok: bool = write_dict(slot_path(), GameState.to_dict())
	if ok:
		SteamService.on_saved(slot_path())  # [steam] Steam Cloud upload (no-op without Steam)
		EventBus.game_saved.emit()
	return ok


func load_game() -> bool:
	if not has_save():
		return false
	var d: Dictionary = read_dict(slot_path())
	if d.is_empty():
		# [beat] A crash between removing the old save and renaming the new one leaves only the .tmp.
		d = read_dict(slot_path() + ".tmp")
	if d.is_empty():
		return false
	GameState.from_dict(migrate(d))
	EventBus.game_loaded.emit()
	return true


func delete_save(s: int = -1) -> void:
	if has_save(s):
		DirAccess.remove_absolute(slot_path(s))
		SteamService.on_deleted(slot_path(s))  # [steam]


static func write_dict(path: String, d: Dictionary) -> bool:
	var tmp: String = path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("Could not open save for writing: %s" % tmp)
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	# Write-then-rename so a crash mid-save never corrupts the previous save.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


static func read_dict(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Upgrades older save dictionaries to the current version, one step at a time.
static func migrate(d: Dictionary) -> Dictionary:
	var v: int = int(d.get("version", 0))
	if v < 1:
		# v0 (pre-release prototype) stored currency as a plain float.
		var cur: Dictionary = d.get("currencies", {})
		for k: String in cur:
			if not (cur[k] is Array):
				cur[k] = BigNum.from_float(float(cur[k])).serialize()
		d["currencies"] = cur
		v = 1
	if v < 2:
		d = migrate_v2(d)  # [money]
		v = 2
	if v < 3:
		d = migrate_v3(d)  # [ui2]
		v = 3
	d["version"] = v
	return d


## [money] v1 -> v2: fold the old currencies (bolts, sheet metal, plastic, glass, Data, compost,
## tokens, trinkets) into cubes / parts / seeds at data/currencies.json's rates; compost goes
## into the compost press hopper and Maker Fragments become Parts, so nothing earned is lost.
static func migrate_v2(d: Dictionary) -> Dictionary:
	var res: Dictionary = Currencies.migrate_serialized(d.get("currencies", {}))
	var cur: Dictionary = res["currencies"]
	var flags: Dictionary = d.get("flags", {})
	var into: Dictionary = res["into"]
	if into.has("press_hopper"):
		flags["press_hopper"] = float(flags.get("press_hopper", 0.0)) + float(into["press_hopper"])
	var rb: Variant = flags.get("builder")
	if rb is Dictionary and int((rb as Dictionary).get("fragments", 0)) > 0:
		var fr: int = int(rb["fragments"])
		rb["fragments"] = 0
		var p: BigNum = BigNum.from_serialized(cur["parts"]) if cur.has("parts") else BigNum.zero()
		cur["parts"] = p.add(BigNum.from_float(fr * Currencies.rate("fragments", true))).serialize()
	for id: String in Currencies.IDS:
		if not cur.has(id):
			cur[id] = BigNum.zero().serialize()
	d["currencies"] = cur
	# Contracts are Requests now: the "Handle world events" contract is gone (events count directly).
	var cs: Variant = flags.get("contracts")
	if cs is Dictionary and (cs as Dictionary).get("slots") is Array:
		var slots: Array = cs["slots"]
		for i: int in slots.size():
			if slots[i] is Dictionary and str((slots[i] as Dictionary).get("tpl", "")) == "events":
				slots[i] = {"state": "wait", "wait": 30.0}
	flags["money_migrated"] = true
	d["flags"] = flags
	return d


## [ui2] v2 -> v3: robot part items (the rarity-graded parts the old recipes, Mk tiers and the
## Builder used) become Parts at their rarity's value (data/parts.json rarities[].parts), so
## a Vintage core is 150 parts. Builder parts are cosmetics now: nothing to convert there.
static func migrate_v3(d: Dictionary) -> Dictionary:
	var items: Array = d.get("parts", []) if d.get("parts") is Array else []
	var add: float = RobotParts.items_value(items)
	var cur: Dictionary = d.get("currencies", {})
	var p: BigNum = BigNum.from_serialized(cur["parts"]) if cur.has("parts") else BigNum.zero()
	cur["parts"] = p.add(BigNum.from_float(add)).serialize()
	d["currencies"] = cur
	d["parts"] = []
	var flags: Dictionary = d.get("flags", {})
	flags["parts_migrated"] = add
	d["flags"] = flags
	return d
