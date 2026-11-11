extends Node
## Data-driven economy: loads tool/upgrade/junk data, computes stats, costs and cube values.
## Pure functions where possible so tests and the balance simulator can call them directly.

var junk_types: Dictionary = {}  # id -> Dictionary
var junk_ids: Array[String] = []
var upgrade_defs: Dictionary = {}  # id -> Dictionary
var upgrade_order: Array[String] = []
var patch_base: Dictionary = {}
var cube_rules: Dictionary = {}
## Tipping a loose load (the planet's "player" table, key "dump"): {mult, after_baler, radius_m}.
var dump_rules: Dictionary = {}
## The scoop pulse (the planet's "player" table, key "scoop"): {bite_vol}.
var scoop_rules: Dictionary = {}
var planet: Dictionary = {}
var landmarks: Array = []
## Wilderness biome junk sets (the planet's "pollution" table, key "biomes"), keyed by PlanetData biome name.
var biome_sets: Dictionary = {}
var parts: Dictionary = {}
var robots: Dictionary = {}  # type id -> def
var robot_order: Array[String] = []
var robot_tiers: Array = []
var robot_cfg: Dictionary = {}
## Price tiers of the upgrade tracks (the planet's "upgrades" table, key "tiers"): {levels, ratio,
## cost}, one entry per district in play order. Empty on a planet whose upgrades are not tiered.
var track_tiers: Dictionary = {}
## The flag that holds how many districts are open (Districts writes it; one from a new game).
const FLAG_TIERS_OPEN: String = "districts_open"
## What an upgrade costs when its row names no "currency".
const DEFAULT_UPGRADE_CURRENCY: String = "cubes"
## The flag that holds the part of a cube not paid out yet (see whole_cubes).
const FLAG_CUBE_CARRY: String = "cube_carry"

var _planet_cache_drops: Array[Callable] = []


func _ready() -> void:
	Planets.current_changed.connect(_on_planet_changed)
	load_data()


static func read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing data file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("Bad JSON in %s" % path)
	return {}


## One of the current planet's content tables (PlanetDefinition.tables), as a private copy the
## caller may keep and edit. Empty when the planet does not have that table.
func planet_table(table_name: String) -> Dictionary:
	var def: PlanetDefinition = Planets.current()
	if def == null:
		push_error("No current planet: cannot read table '%s'" % table_name)
		return {}
	return def.table(table_name).duplicate(true)


## Static loaders that keep a planet table call this with the function that forgets it. It runs
## once, the next time the current planet changes; the loader registers again when it reloads.
func drop_on_planet_change(drop: Callable) -> void:
	if not drop in _planet_cache_drops:
		_planet_cache_drops.append(drop)


func _on_planet_changed(_planet: PlanetDefinition) -> void:
	var drops: Array[Callable] = _planet_cache_drops.duplicate()
	_planet_cache_drops.clear()
	for drop: Callable in drops:
		drop.call()
	load_data()


func load_data() -> void:
	junk_types.clear()
	junk_ids.clear()
	var jd: Dictionary = planet_table("pollution")
	landmarks = jd.get("landmarks", [])
	biome_sets = jd.get("biomes", {})
	for t: Dictionary in jd.get("types", []):
		junk_types[t["id"]] = t
		junk_ids.append(t["id"])
	upgrade_defs.clear()
	upgrade_order.clear()
	var ud: Dictionary = planet_table("upgrades")
	track_tiers = ud.get("tiers", {})
	for u: Dictionary in ud.get("upgrades", []):
		upgrade_defs[u["id"]] = u
		upgrade_order.append(u["id"])
	var pd: Dictionary = planet_table("player")
	patch_base = pd.get("stats", {})
	cube_rules = pd.get("cube", {})
	dump_rules = pd.get("dump", {})
	scoop_rules = pd.get("scoop", {})
	planet = planet_table("field")
	parts = read_json("res://data/parts.json")
	robot_cfg = planet_table("robots")
	robots.clear()
	robot_order.clear()
	robot_tiers = robot_cfg.get("tiers", [])
	for r: Dictionary in robot_cfg.get("types", []):
		robots[r["id"]] = r
		robot_order.append(r["id"])
		# Fleet upgrades become ordinary upgrades on the "bots" tab with stat "<type>.<stat>".
		for u: Dictionary in r.get("upgrades", []):
			var uid: String = "bot_%s_%s" % [r["id"], u["stat"]]
			var d: Dictionary = u.duplicate()
			d["id"] = uid
			d["tab"] = "bots"
			d["robot"] = r["id"]
			d["name"] = "%s: %s" % [tr(str(r["name"])), tr(str(u["name"]))]
			d["desc"] = tr("Every %s in the fleet.") % tr(str(r["name"]))
			d["stat"] = "%s.%s" % [r["id"], u["stat"]]
			d["currency"] = str(u.get("currency", robot_cfg.get("upgrade_currency", DEFAULT_UPGRADE_CURRENCY)))
			d["icon"] = "speed"
			upgrade_defs[uid] = d
			upgrade_order.append(uid)
	_index_upgrades()


## [health] stat id -> upgrade ids in upgrade_order order, so stat() doesn't scan every upgrade
## (robots call it each physics frame). Rebuilt whenever the tables are loaded.
var _by_stat: Dictionary = {}


func _index_upgrades() -> void:
	_by_stat.clear()
	for uid: String in upgrade_order:
		var sid: String = str(upgrade_defs[uid]["stat"])
		if not _by_stat.has(sid):
			_by_stat[sid] = [] as Array[String]
		(_by_stat[sid] as Array[String]).append(uid)


# --- Stats --------------------------------------------------------------------

## Effective value of a stat given the current upgrade levels (or an override map).
func stat(stat_id: String, levels: Variant = null) -> float:
	var lv: Dictionary = levels if levels is Dictionary else GameState.upgrades
	var value: float = base_stat(stat_id)
	var mul: float = 1.0
	if _by_stat.is_empty() and not upgrade_order.is_empty():  # [health] tables filled by hand (tests)
		_index_upgrades()
	for uid: String in _by_stat.get(stat_id, []):
		var u: Dictionary = upgrade_defs[uid]
		var level: int = int(lv.get(uid, 0))
		if level <= 0:
			continue
		if u["mode"] == "add":
			value += float(u["amount"]) * level
		else:
			mul *= 1.0 + float(u["amount"]) * level
	# Research bonuses (systems/research.gd) apply on top of upgrades.
	# The worn design's small buff (systems/designs.gd) last.  [skins]  Decor charm and nursery caretakers  [late]
	# The fitted rig modules (systems/rigs.gd) after everything else: a module's floor is a floor.
	return Rigs.stat_mod(stat_id, Designs.apply(stat_id, Research.stat_mod(stat_id, value * mul) * Decor.stat_mult(stat_id) * Nursery.stat_mult(stat_id)))


## Base value of a stat before upgrades: Lumi's stats come from the planet's "player" table, dotted
## robot stats ("<type>.<stat>") from its "robots" table (Mk I, before tier and rarity multipliers).
func base_stat(stat_id: String) -> float:
	if "." in stat_id:
		var parts_id: PackedStringArray = stat_id.split(".")
		return float(robots.get(parts_id[0], {}).get("stats", {}).get(parts_id[1], 0.0))
	return float(patch_base.get(stat_id, 0.0))


## Where a stat comes from: [{source, text}], for the "no hidden multipliers" tooltip.
func stat_breakdown(stat_id: String) -> Array[Dictionary]:
	var base_label: String = tr("Base (Mk I, before tier and part rarity)") if "." in stat_id else tr("Base")
	var out: Array[Dictionary] = [{"source": base_label, "text": _fmt_stat(base_stat(stat_id))}]
	for uid: String in upgrade_order:
		var u: Dictionary = upgrade_defs[uid]
		var level: int = GameState.level_of(uid)
		if u["stat"] != stat_id or level <= 0:
			continue
		if u["mode"] == "add":
			out.append({"source": tr("%s Lv %d") % [tr(str(u["name"])), level], "text": "+" + _fmt_stat(float(u["amount"]) * level)})
		else:
			out.append({"source": tr("%s Lv %d") % [tr(str(u["name"])), level], "text": "x%.2f" % (1.0 + float(u["amount"]) * level)})
	out.append_array(Research.breakdown(stat_id))
	out.append_array(Designs.breakdown(stat_id))  # [skins]
	out.append_array(Rigs.breakdown(stat_id))
	return out


func _fmt_stat(v: float) -> String:
	if is_equal_approx(v, round(v)):
		return str(int(round(v)))
	return "%.2f" % v


# --- Upgrades -----------------------------------------------------------------

## The last level of an upgrade on this planet (-1 = no limit).
func upgrade_max(id: String) -> int:
	var u: Dictionary = upgrade_defs[id]
	if is_track(u):
		var total: int = 0
		for n: int in _tier_levels(u):
			total += n
		return total
	return int(u.get("max_level", -1))


## The last level that can be bought now: a track sells the levels of the tiers its open
## districts have reached; anything else its max level.
func upgrade_cap(id: String) -> int:
	var u: Dictionary = upgrade_defs[id]
	if not is_track(u):
		return upgrade_max(id)
	var levels: Array[int] = _tier_levels(u)
	var total: int = 0
	for t: int in mini(tiers_open(), levels.size()):
		total += levels[t]
	return total


func is_maxed(id: String) -> bool:
	var m: int = upgrade_cap(id)
	return m >= 0 and GameState.level_of(id) >= m


## True when a track has sold every level its open districts allow but has more on this planet.
func waits_for_district(id: String) -> bool:
	return upgrade_defs.has(id) and is_maxed(id) and GameState.level_of(id) < upgrade_max(id)


## How many districts are open: each one opens the next price tier of every track.
func tiers_open() -> int:
	return maxi(1, int(GameState.flags.get(FLAG_TIERS_OPEN, 1)))


## A track is an upgrade priced by tier (the planet's upgrades table has "tiers" and the row says
## "track": true); every other upgrade costs base_cost x growth^level up to max_level.
func is_track(u: Dictionary) -> bool:
	return bool(u.get("track", false)) and not track_tiers.is_empty()


## Levels a track holds in each tier: its own "tier_levels" or the table's.
func _tier_levels(u: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for n: Variant in u.get("tier_levels", track_tiers.get("levels", [])):
		out.append(maxi(0, int(n)))
	return out


## Cost of a track's level `level` -> `level + 1`: inside a tier each level costs the tier's ratio
## times the one before. The track's first tier starts at the row's base_cost (when it has one),
## every other tier at weight x the tier's cost.
func track_cost(u: Dictionary, level: int) -> float:
	var levels: Array[int] = _tier_levels(u)
	var ratios: Array = track_tiers.get("ratio", [])
	var costs: Array = track_tiers.get("cost", [])
	var tier: int = -1
	var first_tier: int = -1
	var first: int = 0  # the track level `tier` starts at
	var below: int = 0
	for t: int in levels.size():
		if levels[t] <= 0:
			continue
		if first_tier < 0:
			first_tier = t
		tier = t
		first = below
		if level < below + levels[t]:
			break
		below += levels[t]
	if tier < 0:
		return 0.0
	var start: float = float(u.get("base_cost", 0.0))
	if tier != first_tier or start <= 0.0:
		start = float(u.get("weight", 1.0)) * (float(costs[tier]) if tier < costs.size() else 0.0)
	var ratio: float = float(ratios[tier]) if tier < ratios.size() else 1.0
	return round(start * pow(ratio, level - first))


func is_unlocked(id: String) -> bool:
	var u: Dictionary = upgrade_defs[id]
	# [camp] Machine upgrades (Belt Drive, Baler Hydraulics, Recycler Yield) need their machine
	# built first: they used to sell with nothing in the yard to show for it.
	var sid: String = str(upgrade_defs[id].get("requires_station", ""))
	if sid != "" and not Stations.built_in_state(sid):
		return false
	if int(u.get("min_district", 0)) >= tiers_open():
		return false
	var req: Dictionary = u.get("requires", {})
	for rid: String in req:
		if GameState.level_of(rid) < int(req[rid]):
			return false
	# [pace] Late upgrades (automation) can also wait for research or a base level.
	var rr: String = str(u.get("requires_research", ""))
	if rr != "" and not Research.has(rr):
		return false
	var mb: int = int(u.get("min_base_level", 0))
	if mb > 0 and int(GameState.world.get("hub_level", 1)) < mb and Frontiers.bases_at_level(mb) == 0:
		return false
	return true


## [pace] Why an upgrade is locked, for the workbench ("" when unlocked).
func lock_reason(id: String) -> String:
	var u: Dictionary = upgrade_defs[id]
	if int(u.get("min_district", 0)) >= tiers_open():
		return tr("Opens in a later city")
	var req: Dictionary = u.get("requires", {})
	for rid: String in req:
		if GameState.level_of(rid) < int(req[rid]) and upgrade_defs.has(rid):
			return tr("Needs %s Lv %d") % [tr(str(upgrade_defs[rid].get("name", rid))), int(req[rid])]
	var rr: String = str(u.get("requires_research", ""))
	if rr != "" and not Research.has(rr):
		return tr("Needs research: %s") % tr(str(Research.def(rr).get("name", rr)))
	var mb: int = int(u.get("min_base_level", 0))
	if mb > 0 and int(GameState.world.get("hub_level", 1)) < mb and Frontiers.bases_at_level(mb) == 0:
		return tr("Needs base level %d") % mb
	return ""


static func cost_at(base_cost: float, growth: float, level: int) -> BigNum:
	return BigNum.from_float(base_cost).mul(BigNum.new(pow(growth, level), 0)) if level < 300 \
		else BigNum.from_float(base_cost).mul(BigNum.new(1.0, int(level * log(growth) / log(10.0))))


## The currency an upgrade is paid in: cubes, unless its row says otherwise (the crew's per-type
## upgrades cost what the planet's robots table names in "upgrade_currency").
func upgrade_currency(id: String) -> String:
	return str((upgrade_defs.get(id, {}) as Dictionary).get("currency", DEFAULT_UPGRADE_CURRENCY))


func upgrade_cost(id: String, level: int = -1) -> BigNum:
	var u: Dictionary = upgrade_defs[id]
	var lv: int = level if level >= 0 else GameState.level_of(id)
	if is_track(u):
		return BigNum.from_float(track_cost(u, lv))
	return cost_at(float(u["base_cost"]), float(u["growth"]), lv)


## Total cost of buying n levels starting from the current level.
func cost_for_n(id: String, n: int) -> BigNum:
	var lv: int = GameState.level_of(id)
	var total: BigNum = BigNum.zero()
	for k: int in n:
		total = total.add(upgrade_cost(id, lv + k))
	return total


## How many levels the player can buy right now, respecting the level cap.
func max_affordable(id: String, budget: BigNum = null) -> int:
	var money: BigNum = budget if budget != null else GameState.get_currency(upgrade_currency(id))
	var m: int = upgrade_cap(id)
	var room: int = 1000 if m < 0 else m - GameState.level_of(id)
	var n: int = 0
	var spent: BigNum = BigNum.zero()
	var lv: int = GameState.level_of(id)
	while n < room:
		var c: BigNum = upgrade_cost(id, lv + n)
		if not money.gte(spent.add(c)):
			break
		spent = spent.add(c)
		n += 1
	return n


## Buys up to n levels (n <= 0 means max). Returns levels bought.
func buy_upgrade(id: String, n: int = 1) -> int:
	if not upgrade_defs.has(id) or not is_unlocked(id) or is_maxed(id):
		return 0
	var can: int = max_affordable(id)
	var count: int = can if n <= 0 else mini(n, can)
	if count <= 0:
		return 0
	var cost: BigNum = cost_for_n(id, count)
	if not GameState.spend(upgrade_currency(id), cost):
		return 0
	GameState.upgrades[id] = GameState.level_of(id) + count
	GameState.inc_stat("upgrades_bought", count)
	Pace.sync_flags()  # [pace]
	EventBus.upgrade_bought.emit(id, GameState.level_of(id))
	return count


## Stat value if this upgrade were at `level` (others unchanged). For before/after display.
func stat_with_upgrade_level(id: String, level: int) -> float:
	var lv: Dictionary = GameState.upgrades.duplicate()
	lv[id] = level
	return stat(upgrade_defs[id]["stat"], lv)


# --- Cubes --------------------------------------------------------------------

## What a pressed bale is worth. contents: type_id -> volume. `worth`: what the load pays tipped
## loose (its share of the hexes it came from, HexWorth); below zero the load is priced by the unit
## at each waste type's value (loads with no hex behind them). The press quality multiplies it:
## plain, good (at least good_from full) or perfect (inside perfect_band); an overstuffed chest
## presses a plain bale. Every one of them pays more than tipping the same load loose.
## Returns {value: BigNum, quality: "plain" | "good" | "perfect", pure, perfect, lumpy, dominant,
## colors, volume, fill, loose: float}.
func evaluate_cube(contents: Dictionary, capacity: float, value_mult: float = -1.0, worth: float = -1.0) -> Dictionary:
	var vol: float = 0.0
	var unit_value: float = 0.0
	var dominant: String = ""
	var dom_vol: float = -1.0
	var types_present: int = 0
	for t: String in contents:
		var v: float = float(contents[t])
		if v <= 0.0:
			continue
		types_present += 1
		vol += v
		unit_value += v * float(junk_types.get(t, {}).get("value", 1.0))
		if v > dom_vol:
			dom_vol = v
			dominant = t
	var fill: float = vol / maxf(capacity, 0.001)
	var band: Array = cube_rules.get("perfect_band", [0.9, 1.0])
	var lumpy: bool = fill > float(band[1]) + 0.0001
	var perfect: bool = not lumpy and fill >= float(band[0])
	var quality: String = press_quality(fill)
	var loose: float = worth if worth >= 0.0 else unit_value
	var mult: float = (value_mult if value_mult >= 0.0 else stat("cube_value_mult")) * press_mult(quality)
	var colors: Array[Color] = []
	var sorted_types: Array = contents.keys()
	sorted_types.sort_custom(func(a: String, b: String) -> bool: return float(contents[a]) > float(contents[b]))
	for t: String in sorted_types:
		if float(contents[t]) > 0.0 and colors.size() < 3:
			colors.append(Color.html(str(junk_types.get(t, {}).get("cube_color", "#888888"))))
	return {
		"value": BigNum.from_float(loose * mult), "quality": quality, "loose": loose,
		"pure": types_present == 1, "perfect": perfect, "lumpy": lumpy,
		"dominant": dominant, "colors": colors, "volume": vol, "fill": fill,
	}


const PRESS_PLAIN: String = "plain"
const PRESS_GOOD: String = "good"
const PRESS_PERFECT: String = "perfect"


## The quality of a bale pressed with the chest `fill` full (1.0 = to the brim).
func press_quality(fill: float) -> String:
	var band: Array = cube_rules.get("perfect_band", [0.9, 1.0])
	if fill > float(band[1]) + 0.0001:
		return PRESS_PLAIN
	if fill >= float(band[0]):
		return PRESS_PERFECT
	return PRESS_GOOD if fill >= float(cube_rules.get("good_from", 0.6)) else PRESS_PLAIN


## What a bale of that quality pays against the same load tipped loose (the planet's "player"
## table, cube.plain_mult / good_mult / perfect_mult). Never less than a hair above the loose
## rate: a pressed bale always beats tipping.
func press_mult(quality: String) -> float:
	return maxf(float(cube_rules.get(quality + "_mult", 1.0)), loose_mult() * MIN_PRESS_EDGE)


## The least a pressed bale pays against a loose load when a planet's data would let them tie.
const MIN_PRESS_EDGE: float = 1.01


## What a loose load pays against its worth (the planet's "player" table, dump.mult).
func loose_mult() -> float:
	return float(dump_rules.get("mult", 1.0))


## Pays `amount` cubes as a whole number: the part of a cube left over is kept (in the save) and
## added to the next payout, so the purse always shows whole cubes and nothing is lost to rounding.
## Returns the cubes paid now.
func pay_whole_cubes(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var total: float = amount + float(GameState.flags.get(FLAG_CUBE_CARRY, 0.0))
	var whole: float = floorf(total + 0.000001)
	GameState.flags[FLAG_CUBE_CARRY] = maxf(0.0, total - whole)
	if whole > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(whole))
	return whole


func rarity(idx: int) -> Dictionary:
	var r: Array = parts.get("rarities", [])
	return r[clampi(idx, 0, r.size() - 1)] if not r.is_empty() else {}


func part_type(idx: int) -> Dictionary:
	var t: Array = parts.get("types", [])
	return t[clampi(idx, 0, t.size() - 1)] if not t.is_empty() else {}


## A robot's effective stat: fleet upgrades x tier multiplier x part-rarity bonus.
const _TIER_STATS: Array[String] = ["speed", "scoop_rate", "capacity", "efficiency", "dig_rate"]  # [health] no per-call array


func robot_stat(type_id: String, stat_id: String, tier: int = 0, rarity_bonus: float = 0.0) -> float:
	var v: float = stat(type_id + "." + stat_id)
	if stat_id in _TIER_STATS:
		v *= float(robot_tiers[clampi(tier, 0, robot_tiers.size() - 1)].get("mult", 1.0)) if not robot_tiers.is_empty() else 1.0
	return v * (1.0 + rarity_bonus)


func tier_name(tier: int) -> String:
	return tr(str(robot_tiers[clampi(tier, 0, robot_tiers.size() - 1)].get("name", "Mk I"))) if not robot_tiers.is_empty() else tr("Mk I")


## Biome set for a wilderness district ({} for cities or unknown biomes).
func biome_set(biome: String) -> Dictionary:
	return biome_sets.get(biome, {})


## Landmark list for a district: the biome's own wrecks in the wilderness, else the city list.
func landmarks_for(biome: String) -> Array:
	return biome_set(biome).get("landmarks", landmarks)
