extends Node
## Owns the persistent game state as plain data. Presentation nodes read from it.
## Runs the fixed-rate simulation tick (10 Hz) independent of frame rate.

const SIM_HZ: float = 10.0
const SAVE_VERSION: int = 4  # [money] v2: three currencies (cubes, parts, seeds); [pace] v3: Baler / Lift Strength upgrades; [ui2] v4: robot part items -> Parts
const RATE_WINDOW_S: float = 60.0

var currencies: Dictionary = {}  # id -> BigNum
var upgrades: Dictionary = {}  # id -> int level
var stats: Dictionary = {}  # id -> float / Dictionary
var flags: Dictionary = {}  # id -> Variant (milestones, tutorial, easter eggs)
## Opaque per-system blobs (field, player, loose cubes, ...). Systems write and read their own key.
var world: Dictionary = {}
## Legacy robot part items ({type, rarity}); [ui2] always folded into Parts (RobotParts.fold_items).
var parts: Array = []
## Per-hub district state. `world` is always districts[current_hub].
var districts: Dictionary = {}
var current_hub: int = 0
## Whole-planet state (PlanetData.to_dict()).
var planet_state: Dictionary = {}
## [orbB] The walkable globe's state (scenes/slice_orbit.gd: schema, cells, sites, positions as
## direction + height). Empty until an --orbit run saves; the flat keys above are left alone.
var orbit: Dictionary = {}
## [orbB] On the globe `world` is the hub site's own dict (inside `orbit`), like a district's on the
## flat game; the flat district's dict waits here, and saves keep writing it unchanged.
var flat_world: Variant = null
## Set while switching districts: the next scene load uses the in-memory state (not saved).
var reload_in_memory: bool = false
var created_unix: float = 0.0
var saved_unix: float = 0.0

var _sim_accum: float = 0.0
## Recent income events (time, value float) for the per-second rate display.
var _income_log: Array[Vector2] = []
var _clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	new_game()


func new_game() -> void:
	currencies = {"cubes": BigNum.zero(), "parts": BigNum.zero(), "seeds": BigNum.zero()}  # [money]
	upgrades = {}
	stats = {
		"cubes_made": 0, "pure_cubes": 0, "perfect_cubes": 0, "lumpy_cubes": 0,
		"junk_removed": {}, "hexes_cleaned": 0, "distance_m": 0.0, "time_played": 0.0,
		"cubes_earned_total": [0.0, 0], "cubes_cashed": 0, "upgrades_bought": 0,
	}
	flags = {}
	world = {}
	parts = []
	districts = {0: world}
	current_hub = 0
	planet_state = {}
	orbit = {}  # [orbB]
	flat_world = null  # [orbB]
	created_unix = Time.get_unix_time_from_system()
	saved_unix = 0.0
	_income_log.clear()


func _physics_process(delta: float) -> void:
	_sim_accum += delta
	var step: float = 1.0 / SIM_HZ
	while _sim_accum >= step:
		_sim_accum -= step
		_clock += step
		stats["time_played"] = float(stats.get("time_played", 0.0)) + step
		EventBus.sim_tick.emit(step)


# --- Currency -----------------------------------------------------------------

## [money] Exactly three currencies (core/currencies.gd, data/currencies.json): cubes, parts, seeds.
## Retired ids ("bolts", "data", "compost", ...) still work through the legacy alias layer: they
## read and write the new currency at the table's rate (and warn once in debug builds).
func get_currency(id: String) -> BigNum:
	if not Currencies.is_currency(id) and Currencies.is_legacy(id):
		var r: Array = Currencies.resolve(id, 1.0)
		var per: float = float(r[1])
		return get_currency(str(r[0])).mul_f(1.0 / per) if per > 0.0 else BigNum.zero()
	if not currencies.has(id):
		currencies[id] = BigNum.zero()
	return currencies[id]


func add_currency(id: String, amount: BigNum) -> void:
	if not Currencies.is_currency(id) and Currencies.is_legacy(id):  # [money]
		var per: float = float(Currencies.resolve(id, 1.0)[1])
		if per <= 0.0:
			return
		add_currency(Currencies.canonical(id), amount.mul_f(per))
		return
	currencies[id] = get_currency(id).add(amount)
	if currencies[id].mantissa < 0.0:  # [beat] currencies never go negative
		currencies[id] = BigNum.zero()
	if id == "cubes" and amount.mantissa > 0.0:
		var total: BigNum = BigNum.from_serialized(stats.get("cubes_earned_total", [0.0, 0]))
		stats["cubes_earned_total"] = total.add(amount).serialize()
		_income_log.append(Vector2(_clock, amount.to_float()))
	EventBus.currency_changed.emit(id, currencies[id])


func can_afford(id: String, amount: BigNum) -> bool:
	if not Currencies.is_currency(id) and Currencies.is_legacy(id):  # [money]
		return get_currency(Currencies.canonical(id)).gte(amount.mul_f(float(Currencies.resolve(id, 1.0)[1])))
	return get_currency(id).gte(amount)


func spend(id: String, amount: BigNum) -> bool:
	if not Currencies.is_currency(id) and Currencies.is_legacy(id):  # [money]
		return spend(Currencies.canonical(id), amount.mul_f(float(Currencies.resolve(id, 1.0)[1])))
	if not can_afford(id, amount):
		return false
	currencies[id] = get_currency(id).sub(amount)
	if currencies[id].mantissa < 0.0:  # [beat] near-equal amounts pass gte(): never leave a tiny negative
		currencies[id] = BigNum.zero()
	EventBus.currency_changed.emit(id, currencies[id])
	return true


## [money] Cost dictionaries ({"cubes": 1500, "parts": 40}, legacy keys folded): affordable / pay.
func can_afford_all(cost: Dictionary, mult: float = 1.0) -> bool:
	var f: Dictionary = Currencies.fold(cost)
	for id: String in Currencies.IDS:
		if float(f.get(id, 0.0)) > 0.0 and not can_afford(id, BigNum.from_float(float(f[id]) * mult)):
			return false
	return true


func spend_all(cost: Dictionary, mult: float = 1.0) -> bool:
	if not can_afford_all(cost, mult):
		return false
	var f: Dictionary = Currencies.fold(cost)
	for id: String in Currencies.IDS:
		if float(f.get(id, 0.0)) > 0.0:
			spend(id, BigNum.from_float(float(f[id]) * mult))
	return true


func add_all(reward: Dictionary, mult: float = 1.0) -> void:
	var f: Dictionary = Currencies.fold(reward)
	for id: String in Currencies.IDS:
		if float(f.get(id, 0.0)) != 0.0:
			add_currency(id, BigNum.from_float(float(f[id]) * mult))


## Average income per second over the recent window (cash-ins are bursty).
func income_rate() -> float:
	var cutoff: float = _clock - RATE_WINDOW_S
	while not _income_log.is_empty() and _income_log[0].x < cutoff:
		_income_log.pop_front()
	if _income_log.is_empty():
		return 0.0
	var total: float = 0.0
	for e: Vector2 in _income_log:
		total += e.y
	var span: float = clampf(_clock - _income_log[0].x, 10.0, RATE_WINDOW_S)
	return total / span


# --- Stats --------------------------------------------------------------------

func inc_stat(id: String, amount: float = 1.0) -> void:
	stats[id] = float(stats.get(id, 0.0)) + amount


func add_junk_removed(type_id: String, volume: float) -> void:
	var d: Dictionary = stats.get("junk_removed", {})
	d[type_id] = float(d.get(type_id, 0.0)) + volume
	stats["junk_removed"] = d


## [orbB] Make `d` the active per-hub dict (the globe's start site); the flat one is kept for saves.
func use_orbit_world(d: Dictionary) -> void:
	if flat_world == null:
		flat_world = world
	world = d


func _districts_for_save() -> Dictionary:
	districts[current_hub] = world if flat_world == null else flat_world  # [orbB]
	var out: Dictionary = {}
	for k: int in districts:
		out[str(k)] = (districts[k] as Dictionary).duplicate(true)
	return out


## Switch the active district (call after the current scene has persisted into `world`).
func switch_hub(i: int) -> void:
	if flat_world != null:  # [orbB] the globe's hub dict is not a flat district
		world = flat_world
		flat_world = null
	districts[current_hub] = world
	current_hub = i
	if not districts.has(i):
		districts[i] = {}
	world = districts[i]


func level_of(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))


# --- Serialization ------------------------------------------------------------

func to_dict() -> Dictionary:
	var cur: Dictionary = {}
	for k: String in currencies:
		cur[k] = (currencies[k] as BigNum).serialize()
	# Keep the in-memory stamp in step with the file, so offline time is measured from the last save.
	saved_unix = Time.get_unix_time_from_system()
	return {
		"version": SAVE_VERSION,
		"created_unix": created_unix,
		"saved_unix": saved_unix,
		"currencies": cur,
		"upgrades": upgrades.duplicate(true),
		"stats": stats.duplicate(true),
		"flags": flags.duplicate(true),
		"world": (world if flat_world == null else (flat_world as Dictionary)).duplicate(true),  # [orbB]
		"parts": parts.duplicate(true),
		"districts": _districts_for_save(),
		"current_hub": current_hub,
		"planet_state": planet_state.duplicate(true),
		"orbit": orbit.duplicate(true),  # [orbB]
	}


func from_dict(d: Dictionary) -> void:
	new_game()
	created_unix = float(d.get("created_unix", created_unix))
	saved_unix = float(d.get("saved_unix", 0.0))
	var cur: Dictionary = d.get("currencies", {})
	for k: String in cur:
		if Currencies.is_currency(k):  # [money] migrate() already folded legacy ids
			currencies[k] = BigNum.from_serialized(cur[k])
		else:
			add_currency(k, BigNum.from_serialized(cur[k]))
	var ups: Dictionary = d.get("upgrades", {})
	for k: String in ups:
		upgrades[k] = int(ups[k])
	var st: Dictionary = d.get("stats", {})
	for k: String in st:
		stats[k] = st[k]
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	world = (d.get("world", {}) as Dictionary).duplicate(true)
	parts = (d.get("parts", []) as Array).duplicate(true)
	current_hub = int(d.get("current_hub", 0))
	planet_state = (d.get("planet_state", {}) as Dictionary).duplicate(true)
	orbit = (d.get("orbit", {}) as Dictionary).duplicate(true)  # [orbB]
	flat_world = null
	districts = {}
	var ds: Dictionary = d.get("districts", {})
	for k: Variant in ds:
		districts[int(str(k))] = (ds[k] as Dictionary).duplicate(true)
	if districts.has(current_hub):
		world = districts[current_hub]
	else:
		districts[current_hub] = world
