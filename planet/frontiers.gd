class_name Frontiers
extends RefCounted
## Late-game frontier districts (data/frontiers.json): Dust Flats, Frozen Port, Sunken City and
## the final Cradle Returns. Pure helpers (tests call these directly): which hub is which kind,
## their saved base levels, unlock gates and plant rules. The flat frontier districts themselves
## are gone (the globe retired them); goals, research and the campaign still read these rules.

const PATH: String = "res://data/frontiers.json"

static var _cfg: Dictionary = {}
static var _by_id: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
		_by_id.clear()
		for k: Dictionary in _cfg.get("kinds", []):
			_by_id[str(k["id"])] = k
	return _cfg


static func kinds() -> Array:
	return cfg().get("kinds", [])


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Dictionary in kinds():
		out.append(str(k["id"]))
	return out


static func def(id: String) -> Dictionary:
	cfg()
	return _by_id.get(id, {})


## The frontier kind whose district biome is `biome` (data biome, e.g. "cradle_landing").
static func def_for_biome(biome: String) -> Dictionary:
	if biome == "":
		return {}
	for k: Dictionary in kinds():
		if str(k.get("biome", "")) == biome:
			return k
	return {}


static func is_frontier_biome(biome: String) -> bool:
	return not def_for_biome(biome).is_empty()


## Kind id of the district a slice is showing ("" for ordinary districts).
static func world_kind(world: Node) -> String:
	if world == null or world.get("field") == null:
		return ""
	return str(def_for_biome(str((world.field as HexField).biome)).get("id", ""))


static func kind_name(id: String) -> String:
	return TranslationServer.translate(str(def(id).get("name", id.capitalize())))


# --- Saved per-district state ------------------------------------------------------------

## A district's saved dict (the live `world` for the current hub).
static func district(hub_i: int) -> Dictionary:
	if hub_i == GameState.current_hub:
		return GameState.world
	return GameState.districts.get(hub_i, {})


static func base_level(hub_i: int) -> int:
	var d: Dictionary = district(hub_i)
	return int(d.get("hub_level", 0 if d.is_empty() else 1))


## How many districts have a base at level >= l (frontier bases included).
static func bases_at_level(l: int) -> int:
	var n: int = 0
	var seen: Dictionary = {}
	for k: int in GameState.districts:
		seen[k] = true
		if int((GameState.districts[k] as Dictionary).get("hub_level", 1)) >= l:
			n += 1
	if not seen.has(GameState.current_hub) and int(GameState.world.get("hub_level", 1)) >= l:
		n += 1
	return n


## Share of land hexes at least Growing in a frontier district (saved summary).
static func growing_frac(hub_i: int) -> float:
	var f: Dictionary = district(hub_i).get("frontier", {})
	return float(f.get("growing_frac", 0.0))


# --- Unlocks -------------------------------------------------------------------------------

## {ok: bool, lines: Array[String] (each requirement with a tick), progress: 0..1}.
## `frontier_hubs` maps kind id -> hub index (PlanetData.frontier_hubs).
static func unlock_status(id: String, frontier_hubs: Dictionary) -> Dictionary:
	var u: Dictionary = def(id).get("unlock", {})
	var lines: Array[String] = []
	var met: int = 0
	var total: int = 0
	if u.has("research"):
		total += 1
		var rid: String = str(u["research"])
		var ok: bool = Research.has(rid)
		met += int(ok)
		lines.append(TranslationServer.translate("%s Research %s") % ["✓" if ok else "·", TranslationServer.translate(str(Research.def(rid).get("name", rid)))])
		var rt: String = str(Research.def(rid).get("requires_tech", ""))  # [pace2] e.g. "Needs Deep Drill: found on Ochre"
		if rt != "" and not ok:
			total += 1
			var okt: bool = Homeward.has_tech(rt)
			met += int(okt)
			lines.append("%s %s" % ["✓" if okt else "·", Homeward.tech_hint(rt)])
	if u.has("bases_l5"):
		total += 1
		var have: int = bases_at_level(5)
		var ok2: bool = have >= int(u["bases_l5"])
		met += int(ok2)
		lines.append(TranslationServer.translate("%s %d bases at level 5 (%d)") % ["✓" if ok2 else "·", int(u["bases_l5"]), have])
	if u.has("frontier"):
		total += 1
		var fid: String = str(u["frontier"])
		var lvl: int = base_level(int(frontier_hubs.get(fid, -1))) if frontier_hubs.has(fid) else 0
		var ok3: bool = lvl >= int(u.get("frontier_level", 1))
		met += int(ok3)
		lines.append(TranslationServer.translate("%s %s base at level %d (%d)") % ["✓" if ok3 else "·", kind_name(fid), int(u.get("frontier_level", 1)), lvl])
	if u.has("frontiers_l5"):
		total += 1
		var n: int = 0
		for fid: String in ["dust_flats", "frozen_port", "sunken_city"]:
			if frontier_hubs.has(fid) and base_level(int(frontier_hubs[fid])) >= 5:
				n += 1
		var ok4: bool = n >= int(u["frontiers_l5"])
		met += int(ok4)
		lines.append(TranslationServer.translate("%s All three frontier bases at level 5 (%d)") % ["✓" if ok4 else "·", n])
	if u.has("frontier_growing"):
		total += 1
		var need: float = float(u["frontier_growing"])
		var worst: float = 1.0
		for fid: String in ["dust_flats", "frozen_port", "sunken_city"]:
			worst = minf(worst, growing_frac(int(frontier_hubs.get(fid, -1))) if frontier_hubs.has(fid) else 0.0)
		var ok5: bool = worst >= need - 0.0001
		met += int(ok5)
		lines.append(TranslationServer.translate("%s Every frontier %d%% Growing or better (lowest %d%%)") % ["✓" if ok5 else "·", int(need * 100.0), int(worst * 100.0)])
	return {"ok": met >= total, "lines": lines, "progress": float(met) / maxf(total, 1.0)}


## Can the rocket fly to this hub? Ordinary hubs always; frontiers once unlocked (or dev flag).
static func can_launch(planet: PlanetData, hub_i: int) -> bool:
	var k: String = planet.frontier_kind(hub_i)
	if k == "" or DevHooks.has("frontiers-open"):
		return true
	if district(hub_i).has("frontier"):
		return true  # been there: the beacon stays
	return bool(unlock_status(k, planet.frontier_hubs)["ok"])


# --- Plants ----------------------------------------------------------------------------------

## Pick weight multiplier for a species in a district. Natives (species "biomes") grow only in
## their frontiers; elsewhere plain meadow species, which frontiers take at native_mult. In the
## Frozen Port outdoors only cold-hardy species grow (greenhouses take anything).
static func species_mult(sp: Dictionary, biome: String, greenhouse: bool = false) -> float:
	var bl: Array = sp.get("biomes", [])
	var k: Dictionary = def_for_biome(biome)
	if not bl.is_empty():
		return 1.0 if biome in bl else 0.0
	if k.is_empty():
		return 1.0
	if str(k.get("id", "")) == "frozen_port" and not greenhouse and not bool(sp.get("cold_hardy", false)):
		return 0.0
	return float(k.get("native_mult", 1.0))


## Water drains this much faster from plants here (Dust Flats heat).
static func plant_drain_mult(biome: String) -> float:
	return float(def_for_biome(biome).get("water", {}).get("plant_drain_mult", 1.0))
