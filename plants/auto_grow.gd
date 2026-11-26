class_name AutoGrow
extends RefCounted
## [v13goals] Owner, 26 Nov: "maybe we forget about the whole planting thing and only clean up the
## planet and as that happens the planets slowly auto grow plants". The player only cleans. Clean
## ground greens by itself: grass first (plants/cell_verdure.gd), then flowers and bushes from the
## garden's own plants, sown here without seeds and never thirsty, then the wildlife that follows the
## hex levels (fauna/). The more of a hex's neighbourhood is clean, the faster it greens, so a hex a
## robot cleans next to another one comes up quicker than a lone one.
## Turned back on with data/plants.json "player_planting": true (seeds, the seed tin, the watering
## can, the planting robots and their goals come back with it).
## Nothing of its own is saved: the plants are the garden's (saved as before), and the hex levels
## follow from them (plants/hex_levels.gd).

const PATH: String = "res://data/plants.json"

static var _cfg: Dictionary = {}
## Tests flip this to run the old planting rules without editing data.
static var force: int = -1  # -1 data, 0 planting by hand, 1 automatic


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = Economy.read_json(PATH)
		_cfg = (d as Dictionary).get("auto_grow", {}) if d is Dictionary else {}
		_cfg["_on"] = not bool((d as Dictionary).get("player_planting", false)) if d is Dictionary else true
	return _cfg


## True when the player plants nothing and clean ground greens by itself (the game as it is now).
static func on() -> bool:
	if force >= 0:
		return force == 1
	return bool(cfg().get("_on", true))


## Greening speed of one hex: 1 alone, up to 1 + neighbour_boost when all six neighbours are clean
## (times data's growth). The garden's growth already carries the plant_growth stat (research).
static func rate(field: HexField, hid: int) -> float:
	var boost: float = float(cfg().get("neighbour_boost", 2.0))
	var share: float = clean_share(field, hid)
	return (1.0 + boost * share) * float(cfg().get("growth", 1.0))


## Share (0..1) of a hex's land neighbours that are clean.
static func clean_share(field: HexField, hid: int) -> float:
	if field == null or hid < 0:
		return 0.0
	var nb: PackedInt32Array = PackedInt32Array()
	if field is SphereField:
		nb = (field as SphereField).grid.neighbors(hid)
	elif field.has_method("neighbors"):
		nb = field.call("neighbors", hid)
	var land: int = 0
	var clean: int = 0
	for n: int in nb:
		if n < 0 or n >= field.hex_count() or field.is_water(n):
			continue
		land += 1
		if field.is_clean(n) or field.hex_hub[n] != 0:
			clean += 1
	return float(clean) / float(land) if land > 0 else 0.0


## One automatic step over the clean hexes `hexes` (ids): each may sprout one plant. Returns the
## number sown. `rng01` is a Callable() -> float in 0..1 (tests pass a fixed one).
static func sow_step(garden: Garden, hexes: Array, dt: float, rng01: Callable = Callable()) -> int:
	if garden == null or garden.world == null:
		return 0
	var field: HexField = garden.world.field
	var sow_s: float = maxf(float(cfg().get("sow_s", 40.0)), 0.1)
	var max_fill: float = clampf(float(cfg().get("max_fill", 0.9)), 0.0, 1.0)
	var n: int = 0
	var research: float = maxf(Economy.stat("plant_growth"), 0.1)
	for v: Variant in hexes:
		var hid: int = int(v)
		if hid < 0 or hid >= field.hex_count() or not field.is_clean(hid) or field.is_water(hid) or field.hex_hub[hid] != 0:
			continue
		var r: float = rate(field, hid)
		garden.auto_rate[hid] = r
		var roll: float = float(rng01.call()) if rng01.is_valid() else randf()
		if roll >= dt * r * research / sow_s:
			continue
		if garden.sow_auto(hid, max_fill):
			n += 1
	return n
