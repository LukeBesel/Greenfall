extends Node
## SteamService autoload: the only place that talks to Steam (GodotSteam GDExtension, the "Steam"
## engine singleton). Everything degrades gracefully: with the extension missing, Steam not
## running, headless runs (tests, CI) or `-- --no-steam`, `active` stays false and every call
## below is a no-op (open_store_page falls back to the browser).
##
## What it does when Steam is up:
##   - initialises Steam with the app id from project settings (greenfall/steam/app_id, or
##     greenfall/steam/demo_app_id in the demo); in the editor steam_appid.txt also works,
##   - mirrors achievements (data/achievements.json ids upper-cased) on unlock and on load,
##   - mirrors lifetime stats (data/steam.json) on save, storing with a short debounce,
##   - Steam Cloud through Remote Storage when greenfall/steam/cloud_mode = "remote_storage":
##     newest save wins on start-up, every save is uploaded (steam/steam_cloud.gd),
##   - opens the store page in the overlay for the demo's wishlist button.
## The real app ids go in project.godot [greenfall] (see docs/steam/README.md).

const CONFIG_PATH: String = "res://data/steam.json"
const SETTING_APP_ID: String = "greenfall/steam/app_id"
const SETTING_DEMO_APP_ID: String = "greenfall/steam/demo_app_id"
const SETTING_CLOUD_MODE: String = "greenfall/steam/cloud_mode"
## Steam's test app (Spacewar). Placeholder until the owner has a real app id.
const PLACEHOLDER_APP_ID: int = 480
const STORE_DELAY: float = 2.0

## The Steam singleton while active (or a fake object injected by tests through attach()).
var api: Object = null
var active: bool = false
## Human-readable reason for the current state (shown in logs / settings).
var status: String = "not started"
var cloud: SteamCloud
var _store_pending: bool = false
var _store_t: float = 0.0
var _stats: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stats = Economy.read_json(CONFIG_PATH).get("stats", [])
	EventBus.achievement_unlocked.connect(_on_achievement)
	EventBus.game_loaded.connect(sync_achievements)
	EventBus.game_saved.connect(push_stats)
	var skip: String = skip_reason()
	if skip != "":
		status = skip
		if Demo.is_demo():
			print("[steam] demo build; ", status)
		return
	var s: Object = find_singleton()
	if s == null:
		status = "GodotSteam extension not installed (addons/godotsteam); running without Steam"
		print("[steam] ", status)
		return
	attach(s, true)


## Why Steam should not be started in this run ("" = go ahead).
static func skip_reason() -> String:
	if DisplayServer.get_name() == "headless":
		return "headless run: Steam disabled"
	if "--no-steam" in OS.get_cmdline_user_args():
		return "--no-steam: Steam disabled"
	return ""


static func find_singleton() -> Object:
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	return null


static func app_id() -> int:
	var key: String = SETTING_DEMO_APP_ID if Demo.is_demo() else SETTING_APP_ID
	return int(ProjectSettings.get_setting(key, PLACEHOLDER_APP_ID))


## The full game's store page (the demo's wishlist target).
static func store_app_id() -> int:
	return int(ProjectSettings.get_setting(SETTING_APP_ID, PLACEHOLDER_APP_ID))


static func cloud_mode() -> String:
	return str(ProjectSettings.get_setting(SETTING_CLOUD_MODE, "remote_storage"))


## Use `s` as the Steam API. init=false skips steamInitEx (tests pass an already-"running" fake).
func attach(s: Object, init: bool = true) -> bool:
	api = s
	active = false
	if init and not _init_steam():
		api = null
		print("[steam] ", status)
		return false
	active = true
	status = "Steam active (app %d)" % app_id()
	cloud = SteamCloud.new(api) if cloud_mode() == "remote_storage" else null
	if cloud and cloud.enabled():
		# [worlds2] Every save profile's folder, each under its own cloud prefix.
		var legacy: int = cloud.adopt_legacy("p1_")
		if legacy > 0:
			print("[steam] cloud: %d pre-profile saves adopted into profile 1" % legacy)
		for n: int in range(1, SaveManager.PROFILES + 1):
			var res: Dictionary = cloud.sync_dir(SaveManager.profile_dir(n, true), SteamCloud.profile_prefix(n, false))  # the flat game's saves (older builds, --flat)
			if not res.is_empty():
				print("[steam] cloud sync p%d: " % n, res)
		# [v5load] The round world is the game now and saves under user://saves_round: sync that tree
		# too, under its own cloud prefix. (It used to be skipped as a preview.)
		if SaveManager.round_planets():
			for n: int in range(1, SaveManager.PROFILES + 1):
				var res2: Dictionary = cloud.sync_dir(SaveManager.profile_dir(n), SteamCloud.profile_prefix(n, true))
				if not res2.is_empty():
					print("[steam] cloud sync round p%d: " % n, res2)
	sync_achievements()
	print("[steam] ", status)
	return true


func detach() -> void:
	api = null
	active = false
	cloud = null
	status = "detached"


func _init_steam() -> bool:
	if api.has_method("isSteamRunning") and not bool(api.call("isSteamRunning")):
		status = "Steam client is not running; running without Steam"
		return false
	var res: Variant
	if api.has_method("steamInitEx"):
		# GodotSteam 4.x: steamInitEx(app_id, embed_callbacks); very old builds took a leading retrieve_stats bool.
		var n: int = api.get_method_argument_count("steamInitEx")
		res = api.call("steamInitEx", true, app_id(), false) if n >= 3 else api.call("steamInitEx", app_id(), false)
	elif api.has_method("steamInit"):
		res = api.call("steamInit", app_id(), false)
	else:
		status = "Steam singleton has no init method"
		return false
	var ok: bool
	if res is Dictionary:
		ok = int((res as Dictionary).get("status", 1)) == 0
		status = "Steam init failed: %s" % str((res as Dictionary).get("verbal", res))
	else:
		ok = bool(res)
		status = "Steam init failed"
	return ok


func _process(delta: float) -> void:
	if not active:
		return
	if api.has_method("run_callbacks"):
		api.call("run_callbacks")
	if _store_pending:
		_store_t += delta
		if _store_t >= STORE_DELAY:
			store_now()


# --- Achievements and stats -------------------------------------------------------------

static func api_name(achievement_id: String) -> String:
	return achievement_id.to_upper()


func _on_achievement(id: String) -> void:
	if not active:
		return
	api.call("setAchievement", api_name(id))
	_store_soon()


## Push every unlock in the save to Steam (old saves, offline unlocks, a cloud save from another PC).
func sync_achievements() -> void:
	if not active:
		return
	var n: int = 0
	for id: Variant in Achievements.unlocked_map():
		var nm: String = api_name(str(id))
		var have: Variant = api.call("getAchievement", nm) if api.has_method("getAchievement") else {}
		if have is Dictionary and bool((have as Dictionary).get("achieved", false)):
			continue
		api.call("setAchievement", nm)
		n += 1
	if n > 0:
		_store_soon()
	push_stats()


## Steam stat values for the current GameState ({api_name: int or float}).
func stat_values() -> Dictionary:
	var out: Dictionary = {}
	for s: Dictionary in _stats:
		var v: Variant = GameState.stats.get(str(s["key"]), 0.0)
		var f: float = (float(v) if (v is float or v is int) else 0.0) * float(s.get("scale", 1.0))
		@warning_ignore("incompatible_ternary")
		out[str(s["api"])] = int(floor(f)) if str(s.get("type", "INT")) == "INT" else f
	return out


func push_stats() -> void:
	if not active:
		return
	var vals: Dictionary = stat_values()
	for k: String in vals:
		if vals[k] is int:
			api.call("setStatInt", k, vals[k])
		else:
			api.call("setStatFloat", k, vals[k])
	_store_soon()


func _store_soon() -> void:
	_store_pending = true


func store_now() -> void:
	_store_pending = false
	_store_t = 0.0
	if active and api.has_method("storeStats"):
		api.call("storeStats")


# --- Cloud --------------------------------------------------------------------------------

## Called by SaveManager after a save file was written.
func on_saved(path: String) -> void:
	if active and cloud:  # [v5load] round-world saves too (SteamCloud.cloud_name gives them their prefix)
		cloud.push(path)


func on_deleted(path: String) -> void:
	if active and cloud:
		cloud.delete(SteamCloud.cloud_name(path))  # [worlds2] profile-prefixed name


# --- Store / overlay ----------------------------------------------------------------------

func store_url() -> String:
	return "https://store.steampowered.com/app/%d/" % store_app_id()


func open_store_page() -> void:
	if active and api.has_method("activateGameOverlayToStore") and (not api.has_method("isOverlayEnabled") or bool(api.call("isOverlayEnabled"))):
		api.call("activateGameOverlayToStore", store_app_id(), 0)
		return
	if DisplayServer.get_name() != "headless":
		OS.shell_open(store_url())
