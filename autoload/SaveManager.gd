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


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--save-dir="):
			dev_dir = a.get_slice("=", 1).validate_filename()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(save_dir())
	import_demo_save()  # [steam]


## [steam] The demo keeps its saves apart (Demo.SAVE_DIR) so a full-game save never opens in it.
func save_dir() -> String:
	if dev_dir != "":  # [beat]
		return "user://saves_" + dev_dir
	return Demo.SAVE_DIR if Demo.is_demo() else SAVE_DIR


## [steam] Full game, first run after the demo: carry the demo's slots over (never overwrites).
func import_demo_save() -> void:
	if Demo.is_demo() or not DirAccess.dir_exists_absolute(Demo.SAVE_DIR):
		return
	for nm: String in DirAccess.get_files_at(Demo.SAVE_DIR):
		var dst: String = SAVE_DIR.path_join(nm)
		if nm.ends_with(".save") and not FileAccess.file_exists(dst) and not FileAccess.file_exists(dst + ".demo_imported"):
			DirAccess.copy_absolute(Demo.SAVE_DIR.path_join(nm), dst)
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
	flags["money_migrated"] = true
	d["flags"] = flags
	return d
