class_name Surge
extends Node
## The Surge (design spec section 8): Lumi's own work charges her Bloom Core, and a full core is
## released by the player as a short burst in which her sweep widens and speeds up sharply. From
## the planet's wave district on, the release also pushes a wave of growth over the hexes round
## her. The rules and their numbers are SurgeRules and the planet's "balance" table; this node
## holds the state and is saved with the planet.
##
## Only hand work charges it: waste Lumi clears herself (EventBus.pollution_cleared with
## by_player, every kind), bales she presses (cube_made) and seeds she plants or plants she waters
## (hand_tended). Robots never do. Nothing charges it while no work is done (no idle charge, no
## charge while away), and it does not charge while a Surge is running.
##
##   charge()        0..1
##   can_release()   full and not running: release() will work
##   release()       starts the Surge; false when not ready
##   active()        a Surge is running; time_left() seconds of it remain
##   gauge()         what the Bloom Core gauge shows: the charge, or the Surge draining
##
## While a Surge runs its effect reaches the game through static calls, so no caller needs the
## node: Surge.stat_mod(stat, value) from Economy.stat (sweep rate, bite, width, reach),
## Surge.chest_pack() for how much chest room the swept waste takes, and Surge.running().
##
## The player releases with the "surge" action, or on a controller by pressing both zoom buttons
## together (every single button already has a job). The bot calls release() itself.
##
## Emits EventBus.surge_charged when the core fills, surge_released(district_id, output,
## wave_rings) and surge_ended.
##
## Dev flags: --surge-charge=0.95 sets the charge; --surge-demo=20 releases a Surge after that many
## seconds and holds it open (screenshots).
##
## Use: var s := Surge.new(); world.add_child(s); s.setup(def, districts, saved)

const NODE_NAME: String = "Surge"
const SAVE_KEY: String = "surge"
const ACTION: String = "surge"
## The two actions that, pressed together on a controller, release the Surge.
const PAD_CHORD: Array[String] = ["zoom_out", "zoom_in"]
const FLAG_CHARGE: String = "surge-charge"
const FLAG_DEMO: String = "surge-demo"
const STAT_COUNT: String = "surges_released"
## Seconds of the fastest allowed charging that may be banked (a pulse of work arrives at once).
const BANK_S: float = 10.0
const TEND_PLANT: String = "plant"
const TEND_WATER: String = "water"

## The running Surge's stat multipliers, for the static calls. One Surge is live at a time (the
## planet being played); the node that owns it clears these when it ends or leaves the tree.
static var _live: Dictionary[String, float] = {}
static var _live_pack: float = 1.0
static var _live_owner: int = 0

## Returns true while the player's own input may release the Surge (set by the world).
var input_gate: Callable

var _cfg: Dictionary = {"enabled": false}
var _districts: Districts
var _charge: float = 0.0
var _left: float = 0.0
var _allow: float = 0.0
var _grid: SphereGrid
var _garden: Garden
var _cell_fn: Callable
var _chord_down: bool = false
var _demo_at: float = -1.0
var _demo_hold: bool = false


func _init() -> void:
	name = NODE_NAME


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _live_owner == get_instance_id():
		_clear_live()  # freed without ever leaving a tree (tests, tools)


func _exit_tree() -> void:
	if EventBus.pollution_cleared.is_connected(_on_pollution_cleared):
		EventBus.pollution_cleared.disconnect(_on_pollution_cleared)
	if EventBus.cube_made.is_connected(_on_cube_made):
		EventBus.cube_made.disconnect(_on_cube_made)
	if EventBus.hand_tended.is_connected(_on_hand_tended):
		EventBus.hand_tended.disconnect(_on_hand_tended)
	if _live_owner == get_instance_id():
		_clear_live()


func _physics_process(delta: float) -> void:
	step(delta)
	if _release_pressed() and input_gate.is_valid() and bool(input_gate.call()):
		release()


## The Surge of a world (null when it has none).
static func of(world: Node) -> Surge:
	return world.get_node_or_null(NODE_NAME) as Surge if world != null else null


# --- Live effect (static) -----------------------------------------------------------------------

## Whether a Surge is running on the planet being played.
static func running() -> bool:
	return _live_owner != 0


## A stat of Lumi's with the running Surge applied (unchanged when none runs).
static func stat_mod(stat_id: String, value: float) -> float:
	return value * _live.get(stat_id, 1.0)


## Share of its volume that swept waste takes in the chest right now: the core's light packs a
## Surge's load tight, so the burst is spent sweeping and not walking to the bin.
static func chest_pack() -> float:
	return _live_pack


## Breakdown rows for the stat tooltip: [{source, text}].
static func breakdown(stat_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _live.has(stat_id):
		out.append({"source": TranslationServer.translate("Surge"), "text": "x%.2f" % _live[stat_id]})
	return out


static func _clear_live() -> void:
	_live.clear()
	_live_pack = 1.0
	_live_owner = 0


# --- Setup and state ----------------------------------------------------------------------------

## Reads the planet's Surge numbers and restores a save_state() dictionary ({} = an empty core).
func setup(def: PlanetDefinition, districts: Districts, saved: Dictionary = {}) -> void:
	_cfg = SurgeRules.config(def.table(SurgeRules.TABLE) if def else {})
	_districts = districts
	_left = 0.0
	_allow = _bank()
	load_state(saved)
	if DevHooks.has(FLAG_CHARGE):
		_charge = clampf(DevHooks.get_f(FLAG_CHARGE, 1.0), 0.0, 1.0)
	if DevHooks.has(FLAG_DEMO):
		_demo_at = DevHooks.get_f(FLAG_DEMO, 20.0)
	if not enabled():
		return
	if not EventBus.pollution_cleared.is_connected(_on_pollution_cleared):
		EventBus.pollution_cleared.connect(_on_pollution_cleared)
	if not EventBus.cube_made.is_connected(_on_cube_made):
		EventBus.cube_made.connect(_on_cube_made)
	if not EventBus.hand_tended.is_connected(_on_hand_tended):
		EventBus.hand_tended.connect(_on_hand_tended)


## What the growth wave needs: the globe's grid, the garden, and where Lumi stands (a hex id).
func bind_wave(grid: SphereGrid, garden: Garden, cell_fn: Callable) -> void:
	_grid = grid
	_garden = garden
	_cell_fn = cell_fn


## The charge only: a Surge cut short by a save is over when the save is loaded.
func save_state() -> Dictionary:
	return {"charge": snappedf(_charge, 0.0001)}


func load_state(saved: Dictionary) -> void:
	_charge = clampf(float(saved.get("charge", 0.0)), 0.0, 1.0) if enabled() else 0.0


# --- Queries ------------------------------------------------------------------------------------

func enabled() -> bool:
	return SurgeRules.enabled(_cfg)


func config() -> Dictionary:
	return _cfg


func charge() -> float:
	return _charge


func can_release() -> bool:
	return enabled() and _charge >= 1.0 and not active()


func active() -> bool:
	return _left > 0.0


func time_left() -> float:
	return _left


func duration() -> float:
	return float(_cfg.get("duration_s", 0.0))


## 0..1 for the Bloom Core gauge: the charge filling, or the running Surge draining.
func gauge() -> float:
	return clampf(_left / maxf(duration(), 0.001), 0.0, 1.0) if active() else _charge


## The place (from 1) in the planet's play order of the district Lumi is in, or was last in.
func district_n() -> int:
	return maxi(1, _districts.ids().find(district_id()) + 1) if _districts != null else 1


## The district Lumi stands in, or between districts the one the readouts show.
func district_id() -> String:
	if _districts == null:
		return ""
	var id: String = _districts.current_id()
	return id if id != "" else _districts.focus_id()


## Lumi's hand output during a Surge released here, against the same hands without it.
func output_mult() -> float:
	return SurgeRules.output_mult(_cfg, district_n())


## Units of Lumi's own work that fill the core here.
func units_needed() -> float:
	return SurgeRules.units_needed(_cfg, district_n())


# --- Changes ------------------------------------------------------------------------------------

## Lumi cleared `units` of waste with her own hands.
func add_work(units: float) -> void:
	_gain(SurgeRules.gain_for_units(_cfg, district_n(), units))


## Adds a share (0..1) of a full charge (a bale pressed, a seed planted).
func add_share(share: float) -> void:
	_gain(share)


## Starts the Surge. False when the core is not full or a Surge is already running.
func release() -> bool:
	if not can_release():
		return false
	var n: int = district_n()
	_charge = 0.0
	_left = duration()
	_allow = _bank()
	_live.clear()
	for id: String in (_cfg["stats"] as Dictionary):
		_live[id] = SurgeRules.stat_mult(_cfg, id, n)
	_live_pack = SurgeRules.chest_pack(_cfg, n)
	_live_owner = get_instance_id()
	GameState.inc_stat(STAT_COUNT)
	var rings: int = SurgeRules.wave_rings(_cfg, n) if _push_wave(n) > 0 else 0
	EventBus.surge_released.emit(district_id(), SurgeRules.output_mult(_cfg, n), rings)
	return true


## Advances the running Surge (and the charging allowance) by `dt` seconds.
func step(dt: float) -> void:
	_allow = minf(_allow + _allowance(dt), _bank())
	if _demo_at >= 0.0:
		_demo_at -= dt
		if _demo_at < 0.0:
			_charge = 1.0
			_demo_hold = release()
	if not active() or _demo_hold:
		return
	_left = maxf(0.0, _left - dt)
	if _left <= 0.0:
		if _live_owner == get_instance_id():
			_clear_live()
		EventBus.surge_ended.emit()


func _gain(share: float) -> void:
	if not enabled() or active() or share <= 0.0 or _charge >= 1.0:
		return
	if float(_cfg["min_fill_s"]) > 0.0:
		share = minf(share, _allow)
		_allow -= share
	if share <= 0.0:
		return
	_charge = minf(1.0, _charge + share)
	if _charge >= 1.0:
		EventBus.surge_charged.emit()


## Share of a charge that `dt` seconds of the fastest allowed charging are worth.
func _allowance(dt: float) -> float:
	var fastest: float = float(_cfg.get("min_fill_s", 0.0))
	return dt / fastest if fastest > 0.0 else 0.0


func _bank() -> float:
	return _allowance(BANK_S)


## Waters every plant within the wave's reach of Lumi and pushes its growth on. Returns how many
## hexes had plants to push.
func _push_wave(n: int) -> int:
	var rings: int = SurgeRules.wave_rings(_cfg, n)
	if rings <= 0 or _grid == null or _garden == null or not _cell_fn.is_valid():
		return 0
	var cell: int = int(_cell_fn.call())
	if cell < 0:
		return 0
	var hexes: int = 0
	for c: int in Districts.region_cells(_grid, cell, rings):
		if not _garden.hex_slots.has(c):
			continue
		var pushed: bool = false
		for s: int in (_garden.hex_slots[c] as PackedInt32Array):
			if _garden.slot_species[s] < 0:
				continue
			_garden.water(s, float(_cfg["wave_water_s"]))
			_garden.push_growth(s, float(_cfg["wave_stages"]))
			pushed = true
		if pushed:
			hexes += 1
	return hexes


func _release_pressed() -> bool:
	var chord: bool = Settings.last_input_pad
	for action: String in PAD_CHORD:
		chord = chord and InputMap.has_action(action) and Input.is_action_pressed(action)
	var chord_pressed: bool = chord and not _chord_down
	_chord_down = chord
	return chord_pressed or (InputMap.has_action(ACTION) and Input.is_action_just_pressed(ACTION))


func _on_pollution_cleared(_kind: String, amount: float, by_player: bool) -> void:
	if by_player:
		add_work(amount)


func _on_cube_made(_info: Dictionary) -> void:
	add_share(float(_cfg["per_bale"]))


func _on_hand_tended(action: String) -> void:
	match action:
		TEND_PLANT:
			add_share(float(_cfg["per_plant"]))
		TEND_WATER:
			add_share(float(_cfg["per_water"]))
