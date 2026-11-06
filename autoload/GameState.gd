extends Node
## Owns the persistent game state as plain data. Presentation nodes read from it.
## Runs the fixed-rate simulation tick (10 Hz) independent of frame rate.

const SIM_HZ: float = 10.0
const SAVE_VERSION: int = 1
const RATE_WINDOW_S: float = 60.0

var currencies: Dictionary = {}  # id -> BigNum
var upgrades: Dictionary = {}  # id -> int level
var stats: Dictionary = {}  # id -> float / Dictionary
var flags: Dictionary = {}  # id -> Variant (milestones, tutorial, easter eggs)
## Opaque per-system blobs (field, player, loose cubes, ...). Systems write and read their own key.
var world: Dictionary = {}
## Robot parts in storage: Array of {type: int, rarity: int}.
var parts: Array = []
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
	currencies = {"cubes": BigNum.zero()}
	upgrades = {}
	stats = {
		"cubes_made": 0, "pure_cubes": 0, "perfect_cubes": 0, "lumpy_cubes": 0,
		"junk_removed": {}, "hexes_cleaned": 0, "distance_m": 0.0, "time_played": 0.0,
		"cubes_earned_total": [0.0, 0], "cubes_cashed": 0, "upgrades_bought": 0,
	}
	flags = {}
	world = {}
	parts = []
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

func get_currency(id: String) -> BigNum:
	if not currencies.has(id):
		currencies[id] = BigNum.zero()
	return currencies[id]


func add_currency(id: String, amount: BigNum) -> void:
	currencies[id] = get_currency(id).add(amount)
	if id == "cubes" and amount.mantissa > 0.0:
		var total: BigNum = BigNum.from_serialized(stats.get("cubes_earned_total", [0.0, 0]))
		stats["cubes_earned_total"] = total.add(amount).serialize()
		_income_log.append(Vector2(_clock, amount.to_float()))
	EventBus.currency_changed.emit(id, currencies[id])


func can_afford(id: String, amount: BigNum) -> bool:
	return get_currency(id).gte(amount)


func spend(id: String, amount: BigNum) -> bool:
	if not can_afford(id, amount):
		return false
	currencies[id] = get_currency(id).sub(amount)
	EventBus.currency_changed.emit(id, currencies[id])
	return true


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


func level_of(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))


# --- Serialization ------------------------------------------------------------

func to_dict() -> Dictionary:
	var cur: Dictionary = {}
	for k: String in currencies:
		cur[k] = (currencies[k] as BigNum).serialize()
	return {
		"version": SAVE_VERSION,
		"created_unix": created_unix,
		"saved_unix": Time.get_unix_time_from_system(),
		"currencies": cur,
		"upgrades": upgrades.duplicate(true),
		"stats": stats.duplicate(true),
		"flags": flags.duplicate(true),
		"world": world.duplicate(true),
		"parts": parts.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	new_game()
	created_unix = float(d.get("created_unix", created_unix))
	saved_unix = float(d.get("saved_unix", 0.0))
	var cur: Dictionary = d.get("currencies", {})
	for k: String in cur:
		currencies[k] = BigNum.from_serialized(cur[k])
	var ups: Dictionary = d.get("upgrades", {})
	for k: String in ups:
		upgrades[k] = int(ups[k])
	var st: Dictionary = d.get("stats", {})
	for k: String in st:
		stats[k] = st[k]
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	world = (d.get("world", {}) as Dictionary).duplicate(true)
	parts = (d.get("parts", []) as Array).duplicate(true)
