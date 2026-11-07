extends Node
## Data-driven economy: loads tool/upgrade/junk data, computes stats, costs and cube values.
## Pure functions where possible so tests and the balance simulator can call them directly.

var junk_types: Dictionary = {}  # id -> Dictionary
var junk_ids: Array[String] = []
var upgrade_defs: Dictionary = {}  # id -> Dictionary
var upgrade_order: Array[String] = []
var patch_base: Dictionary = {}
var cube_rules: Dictionary = {}
var planet: Dictionary = {}
var landmarks: Array = []
## Wilderness biome junk sets (data/junk.json "biomes"), keyed by PlanetData biome name.
var biome_sets: Dictionary = {}
var parts: Dictionary = {}
var robots: Dictionary = {}  # type id -> def
var robot_order: Array[String] = []
var robot_tiers: Array = []
var robot_cfg: Dictionary = {}


func _ready() -> void:
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


func load_data() -> void:
	junk_types.clear()
	junk_ids.clear()
	var jd: Dictionary = read_json("res://data/junk.json")
	landmarks = jd.get("landmarks", [])
	biome_sets = jd.get("biomes", {})
	for t: Dictionary in jd.get("types", []):
		junk_types[t["id"]] = t
		junk_ids.append(t["id"])
	upgrade_defs.clear()
	upgrade_order.clear()
	for u: Dictionary in read_json("res://data/upgrades.json").get("upgrades", []):
		upgrade_defs[u["id"]] = u
		upgrade_order.append(u["id"])
	var pd: Dictionary = read_json("res://data/patch.json")
	patch_base = pd.get("stats", {})
	cube_rules = pd.get("cube", {})
	planet = read_json("res://data/planet.json")
	parts = read_json("res://data/parts.json")
	robot_cfg = read_json("res://data/robots.json")
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
			d["icon"] = "speed"
			upgrade_defs[uid] = d
			upgrade_order.append(uid)


# --- Stats --------------------------------------------------------------------

## Effective value of a stat given the current upgrade levels (or an override map).
func stat(stat_id: String, levels: Variant = null) -> float:
	var lv: Dictionary = levels if levels is Dictionary else GameState.upgrades
	var value: float = base_stat(stat_id)
	var mul: float = 1.0
	for uid: String in upgrade_order:
		var u: Dictionary = upgrade_defs[uid]
		if u["stat"] != stat_id:
			continue
		var level: int = int(lv.get(uid, 0))
		if level <= 0:
			continue
		if u["mode"] == "add":
			value += float(u["amount"]) * level
		else:
			mul *= 1.0 + float(u["amount"]) * level
	# Research bonuses (systems/research.gd) apply on top of upgrades.
	# The worn design's small buff (systems/designs.gd) last.  [skins]
	return Designs.apply(stat_id, Research.stat_mod(stat_id, value * mul))


## Base value of a stat before upgrades: Patch stats come from data/patch.json, dotted robot
## stats ("<type>.<stat>") from data/robots.json (Mk I, before tier and rarity multipliers).
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
			out.append({"source": "%s Lv %d" % [tr(str(u["name"])), level], "text": "+" + _fmt_stat(float(u["amount"]) * level)})
		else:
			out.append({"source": "%s Lv %d" % [tr(str(u["name"])), level], "text": "x%.2f" % (1.0 + float(u["amount"]) * level)})
	out.append_array(Research.breakdown(stat_id))
	out.append_array(Designs.breakdown(stat_id))  # [skins]
	return out


func _fmt_stat(v: float) -> String:
	if is_equal_approx(v, round(v)):
		return str(int(round(v)))
	return "%.2f" % v


# --- Upgrades -----------------------------------------------------------------

func upgrade_max(id: String) -> int:
	return int(upgrade_defs[id].get("max_level", -1))


func is_maxed(id: String) -> bool:
	var m: int = upgrade_max(id)
	return m >= 0 and GameState.level_of(id) >= m


func is_unlocked(id: String) -> bool:
	var req: Dictionary = upgrade_defs[id].get("requires", {})
	for rid: String in req:
		if GameState.level_of(rid) < int(req[rid]):
			return false
	return true


static func cost_at(base_cost: float, growth: float, level: int) -> BigNum:
	return BigNum.from_float(base_cost).mul(BigNum.new(pow(growth, level), 0)) if level < 300 \
		else BigNum.from_float(base_cost).mul(BigNum.new(1.0, int(level * log(growth) / log(10.0))))


func upgrade_cost(id: String, level: int = -1) -> BigNum:
	var u: Dictionary = upgrade_defs[id]
	var lv: int = level if level >= 0 else GameState.level_of(id)
	return cost_at(float(u["base_cost"]), float(u["growth"]), lv)


## Total cost of buying n levels starting from the current level (geometric series).
func cost_for_n(id: String, n: int) -> BigNum:
	var u: Dictionary = upgrade_defs[id]
	var lv: int = GameState.level_of(id)
	var g: float = float(u["growth"])
	var first: BigNum = cost_at(float(u["base_cost"]), g, lv)
	if is_equal_approx(g, 1.0):
		return first.mul_f(n)
	return first.mul_f((pow(g, n) - 1.0) / (g - 1.0))


## How many levels the player can buy right now, respecting max level.
func max_affordable(id: String, budget: BigNum = null) -> int:
	var money: BigNum = budget if budget != null else GameState.get_currency("cubes")
	var u: Dictionary = upgrade_defs[id]
	var m: int = upgrade_max(id)
	var room: int = 1000 if m < 0 else m - GameState.level_of(id)
	var n: int = 0
	var spent: BigNum = BigNum.zero()
	var lv: int = GameState.level_of(id)
	while n < room:
		var c: BigNum = cost_at(float(u["base_cost"]), float(u["growth"]), lv + n)
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
	if not GameState.spend("cubes", cost):
		return 0
	GameState.upgrades[id] = GameState.level_of(id) + count
	GameState.inc_stat("upgrades_bought", count)
	EventBus.upgrade_bought.emit(id, GameState.level_of(id))
	return count


## Stat value if this upgrade were at `level` (others unchanged). For before/after display.
func stat_with_upgrade_level(id: String, level: int) -> float:
	var lv: Dictionary = GameState.upgrades.duplicate()
	lv[id] = level
	return stat(upgrade_defs[id]["stat"], lv)


# --- Cubes --------------------------------------------------------------------

## contents: type_id -> volume. Returns {value: BigNum, pure: bool, perfect: bool, lumpy: bool,
## dominant: type_id, colors: Array[Color], volume: float}.
func evaluate_cube(contents: Dictionary, capacity: float, value_mult: float = -1.0) -> Dictionary:
	var vol: float = 0.0
	var base_value: float = 0.0
	var dominant: String = ""
	var dom_vol: float = -1.0
	var types_present: int = 0
	for t: String in contents:
		var v: float = float(contents[t])
		if v <= 0.0:
			continue
		types_present += 1
		vol += v
		base_value += v * float(junk_types.get(t, {}).get("value", 1.0))
		if v > dom_vol:
			dom_vol = v
			dominant = t
	var fill: float = vol / maxf(capacity, 0.001)
	var band: Array = cube_rules.get("perfect_band", [0.9, 1.0])
	var pure: bool = types_present == 1
	var lumpy: bool = fill > float(band[1]) + 0.0001
	var perfect: bool = not lumpy and fill >= float(band[0])
	var mult: float = value_mult if value_mult >= 0.0 else stat("cube_value_mult")
	if pure:
		mult *= float(cube_rules.get("pure_mult", 2.0))
	if perfect:
		mult *= float(cube_rules.get("perfect_mult", 1.5))
	if lumpy:
		mult *= float(cube_rules.get("lumpy_mult", 0.8))
	var colors: Array[Color] = []
	var sorted_types: Array = contents.keys()
	sorted_types.sort_custom(func(a: String, b: String) -> bool: return float(contents[a]) > float(contents[b]))
	for t: String in sorted_types:
		if float(contents[t]) > 0.0 and colors.size() < 3:
			colors.append(Color.html(str(junk_types.get(t, {}).get("cube_color", "#888888"))))
	return {
		"value": BigNum.from_float(base_value * mult),
		"pure": pure, "perfect": perfect, "lumpy": lumpy,
		"dominant": dominant, "colors": colors, "volume": vol, "fill": fill,
	}


func rarity(idx: int) -> Dictionary:
	var r: Array = parts.get("rarities", [])
	return r[clampi(idx, 0, r.size() - 1)] if not r.is_empty() else {}


func part_type(idx: int) -> Dictionary:
	var t: Array = parts.get("types", [])
	return t[clampi(idx, 0, t.size() - 1)] if not t.is_empty() else {}


## A robot's effective stat: fleet upgrades x tier multiplier x part-rarity bonus.
func robot_stat(type_id: String, stat_id: String, tier: int = 0, rarity_bonus: float = 0.0) -> float:
	var v: float = stat("%s.%s" % [type_id, stat_id])
	if stat_id in ["speed", "scoop_rate", "capacity", "efficiency"]:
		v *= float(robot_tiers[clampi(tier, 0, robot_tiers.size() - 1)].get("mult", 1.0)) if not robot_tiers.is_empty() else 1.0
	return v * (1.0 + rarity_bonus)


func tier_name(tier: int) -> String:
	return tr(str(robot_tiers[clampi(tier, 0, robot_tiers.size() - 1)].get("name", "Mk I"))) if not robot_tiers.is_empty() else tr("Mk I")


func hex_bonus(junk_volume: float) -> BigNum:
	var f: Dictionary = planet.get("slice_field", {})
	return BigNum.from_float(float(f.get("bonus_base", 4.0)) + junk_volume * float(f.get("bonus_per_volume", 0.3)))


## Biome set for a wilderness district ({} for cities or unknown biomes).
func biome_set(biome: String) -> Dictionary:
	return biome_sets.get(biome, {})


## Landmark list for a district: the biome's own wrecks in the wilderness, else the city list.
func landmarks_for(biome: String) -> Array:
	return biome_set(biome).get("landmarks", landmarks)
