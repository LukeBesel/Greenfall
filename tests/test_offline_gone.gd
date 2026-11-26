extends GutTest
## Owner item 110 (20 Nov): "Also i think we remove the robots worked when I got off the game
## thing. They work when I am in different locations and on different planets but not when i log
## off type thing." Nothing is earned, grown or finished while the game is closed: no text
## promises it in the data or the six languages, no class or stat of it is left, nothing in the
## game reads the system clock to work out "time since", and an old save's away keys are dropped.
## (Played proof: tools/check_clock_save.sh.)

var _before: Dictionary
var _r_now: float
var _k_now: float


func before_each() -> void:
	_before = GameState.to_dict()
	_r_now = Research.now_override
	_k_now = RocketTiers.now_override
	Research.now_override = -1.0
	RocketTiers.now_override = -1.0


func after_each() -> void:
	GameState.from_dict(_before)
	Research.now_override = _r_now
	RocketTiers.now_override = _k_now


## Phrases that promise or report work done with the game closed. "While you were away, your
## robots HERE cleaned ..." stays: that is Lumi coming back to a base from another base.
const BANNED: Array[String] = ["offline", "while you were away, your robots earned", "welcome back\"", "while you're away",
	"or are away", "takes real time", "while you sleep", "remote pace", "research finished: %s", "\"away %s\"", "while you were away (%s)"]


func test_no_away_earnings_text_in_data_or_languages() -> void:
	var bad: Array[String] = []
	for f: String in DirAccess.get_files_at("res://data"):
		if not f.ends_with(".json"):
			continue
		var low: String = FileAccess.get_file_as_string("res://data/" + f).to_lower()
		for b: String in BANNED:
			if low.contains(b):
				bad.append("data/%s: \"%s\"" % [f, b])
	for f: String in DirAccess.get_files_at("res://locale"):
		if not (f.ends_with(".po") or f.ends_with(".pot")):
			continue
		for line: String in FileAccess.get_file_as_string("res://locale/" + f).split("\n"):
			if line.begins_with("#~"):
				continue  # an obsolete entry: never loaded
			var low: String = line.to_lower()
			for b: String in BANNED:
				if low.contains(b):
					bad.append("locale/%s: %s" % [f, line.strip_edges().left(90)])
	assert_eq(bad, [] as Array[String], "away / offline earnings text is back: %s" % "\n".join(bad))


func test_nothing_of_it_is_built() -> void:
	for cls: String in ["Offline", "SphereOffline", "WelcomeBack"]:
		var found: bool = false
		for c: Dictionary in ProjectSettings.get_global_class_list():
			found = found or str(c["class"]) == cls
		assert_false(found, "%s is gone" % cls)
	for path: String in ["res://core/offline.gd", "res://core/sphere_offline.gd", "res://systems/extras/welcome_back.gd"]:
		assert_false(FileAccess.file_exists(path), "%s is gone" % path)
	for a: Dictionary in Economy.read_json("res://data/achievements.json").get("achievements", []):
		var text: String = JSON.stringify(a).to_lower()
		assert_false(text.contains("welcome_backs") or text.contains("offline"), "no achievement counts away time: %s" % str(a.get("id", "")))


## Game code may read the system clock for a date to show, a file name, the week's seed or "which
## file is newer"; never to work out how long the game was closed. Every file that reads it is
## listed here with why; a new reader fails this test until someone has looked at it.
const CLOCK_READERS: Dictionary = {
	"res://autoload/GameState.gd": "stamps the save (created / saved): shown on the title, Steam Cloud picks the newer file",
	"res://autoload/SaveManager.gd": "a date in the import log",
	"res://systems/profile_slots.gd": "stamps a profile",
	"res://systems/cradle_mode.gd": "stamps the profile and a world's last visit (shown)",
	"res://systems/achievements.gd": "the date an achievement was unlocked (shown in the Codex)",
	"res://systems/extras/album.gd": "the date on a photo",
	"res://systems/extras/nursery.gd": "the date a robot retired",
	"res://systems/extras/weekly.gd": "Seed of the Week: the calendar week picks the seed (off on the round world)",
	"res://systems/remote_progress.gd": "the screenshot sample's 'last visit' stamp",
	"res://ui/main_menu.gd": "'last played' on the title screen",
	"res://ui/photo_mode.gd": "a photo's file name",
	"res://ui/telescope_view.gd": "'last visit N h ago' label",
}


func test_only_listed_files_read_the_system_clock() -> void:
	var found: Dictionary = {}
	_scan("res://", found)
	var extra: Array[String] = []
	for p: String in found:
		if not CLOCK_READERS.has(p):
			extra.append(p)
	assert_eq(extra, [] as Array[String], "these files read the system clock; nothing in play may depend on it (item 110): %s" % ", ".join(extra))
	for p: String in ["res://systems/research.gd", "res://automation/rocket_tiers.gd", "res://planet/orbit/orbit_crews.gd", "res://core/crew_rate.gd", "res://core/sphere_work.gd",
			"res://robots/sphere/sphere_crew.gd", "res://plants/garden.gd", "res://systems/contracts.gd", "res://systems/events.gd", "res://planet/sites/base_keepers.gd"]:
		assert_false(found.has(p), "%s must not read the system clock" % p)


func _scan(dir: String, found: Dictionary) -> void:
	for d: String in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in ["addons", "tests", "tools", "screenshots", "builds", "export"]:
			continue
		_scan(dir.path_join(d), found)
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var p: String = dir.path_join(f)
		var text: String = FileAccess.get_file_as_string(p)
		if text.contains("_from_system(") or text.contains("OS.get_unix_time"):
			found[p] = true


# --- Old saves ------------------------------------------------------------------------------------

## A version 5 save from a build with away earnings: its counters, a research 100 s into 300 s
## and a rocket with 120 s of refill left, both timed by the system clock, saved at unix 5000.
func _old_save() -> Dictionary:
	return {"version": 5, "saved_unix": 5000.0, "created_unix": 100.0,
		"currencies": {"cubes": BigNum.from_float(250).serialize(), "parts": BigNum.from_float(7).serialize(), "seeds": BigNum.from_float(3).serialize()},
		"stats": {"hexes_cleaned": 12, "time_played": 900.0, "welcome_backs": 4, "offline_best_s": 28800.0, "remote_cubes": 40.0},
		"flags": {"tutorial_step": 9, "rocket_ready_unix": 5120.0, "rocket_tier": 1,
			"research": {"done": ["scoop_beam"], "queue": ["soil_survey"], "active": {"id": "wide_beam", "start": 4900.0, "dur": 300.0}}},
		"world": {"hub_level": 2, "offline_units": 31.5, "junk_left": 410.0},
		"districts": {"1": {"hub_level": 1, "offline_units": 4.0}},
		"orbit": {"schema": 1, "hub_worlds": {"0": {"hub_level": 2, "offline_units": 31.5, "junk_left": 410.0, "garden": {"v": 1}}}}}


func test_old_save_drops_the_away_keys_and_keeps_its_timers() -> void:
	var m: Dictionary = SaveManager.migrate(_old_save())
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	var text: String = JSON.stringify(m)
	for key: String in ["welcome_backs", "offline_best_s", "offline_units", "junk_left", "rocket_ready_unix"]:
		assert_false(text.contains(key), "%s is dropped" % key)
	assert_eq(int(m["stats"]["hexes_cleaned"]), 12)
	assert_almost_eq(float(m["stats"]["remote_cubes"]), 40.0, 0.001, "what other planets' crews earned in play stays counted")
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["cubes"]).to_float(), 250.0, 0.001, "nothing is paid or taken")
	assert_eq(int(m["orbit"]["hub_worlds"]["0"]["hub_level"]), 2, "the base itself is untouched")
	assert_true((m["orbit"]["hub_worlds"]["0"] as Dictionary).has("garden"))
	# The timers keep what they had left when the game was saved, now on the play clock (900 s).
	var a: Dictionary = m["flags"]["research"]["active"]
	assert_almost_eq(float(a["start"]) + float(a["dur"]) - 900.0, 200.0, 0.001, "200 s of research left")
	assert_almost_eq(float(m["flags"]["rocket_ready_at"]) - 900.0, 120.0, 0.001, "120 s of refill left")
	var again: Dictionary = SaveManager.migrate(m.duplicate(true))
	assert_eq(JSON.stringify(again), JSON.stringify(m), "loading the migrated save again changes nothing")


## The same old save found today, in a year, or with the clock set back to 1999: the same world.
func test_a_save_loads_the_same_whatever_the_clock_says() -> void:
	var seen: Array[String] = []
	for stamp: float in [5000.0, Time.get_unix_time_from_system() - 7200.0, Time.get_unix_time_from_system() - 30.0 * 86400.0,
			Time.get_unix_time_from_system() + 7200.0, Time.get_unix_time_from_system() + 400.0 * 86400.0]:
		var d: Dictionary = _old_save()
		var move: float = stamp - 5000.0  # the whole file's stamps move together, as with a moved clock
		d["saved_unix"] = stamp
		d["flags"]["rocket_ready_unix"] = 5120.0 + move
		d["flags"]["research"]["active"]["start"] = 4900.0 + move
		GameState.from_dict(SaveManager.migrate(d))
		assert_almost_eq(Research.remaining(), 200.0, 0.001, "research left, stamp %.0f" % stamp)
		assert_almost_eq(RocketTiers.recharge_left(), 120.0, 0.001, "rocket refill left, stamp %.0f" % stamp)
		assert_eq(Research.update().size(), 0, "nothing finished while the game was closed")
		var out: Dictionary = GameState.to_dict()
		out.erase("saved_unix")
		seen.append(JSON.stringify(out))
	for i: int in range(1, seen.size()):
		assert_eq(seen[i], seen[0], "the loaded game is the same for every stamp")


## The timers run on the play clock: they move when play time does, and only then.
func test_research_and_rocket_run_on_play_time_only() -> void:
	GameState.new_game()
	GameState.stats["time_played"] = 50.0
	GameState.flags["research"] = {"done": [], "queue": [], "active": {"id": "scoop_beam", "start": 50.0, "dur": 60.0}}
	RocketTiers.mark_launched()
	var full: float = float(RocketTiers.def().get("recharge_s", 0.0))
	assert_gt(full, 0.0)
	assert_almost_eq(RocketTiers.recharge_left(), full, 0.001)
	assert_almost_eq(Research.remaining(), 60.0, 0.001)
	GameState.saved_unix = Time.get_unix_time_from_system() - 86400.0 * 3.0  # "three days later"
	assert_almost_eq(Research.remaining(), 60.0, 0.001, "no play, no progress")
	assert_almost_eq(RocketTiers.recharge_left(), full, 0.001)
	GameState.stats["time_played"] = 80.0  # 30 s of play
	assert_almost_eq(Research.remaining(), 30.0, 0.001)
	assert_almost_eq(RocketTiers.recharge_left(), full - 30.0, 0.001)
	GameState.stats["time_played"] = 111.0
	assert_eq(Research.update(), ["scoop_beam"] as Array[String])
