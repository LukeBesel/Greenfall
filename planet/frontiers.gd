class_name Frontiers
extends RefCounted
## Late-game frontier districts (data/frontiers.json): Dust Flats, Frozen Port, Sunken City and
## the final Cradle Returns. Pure helpers (tests call these directly): which hub is which kind,
## unlock gates, field setup (ice, flood rings, tougher junk) and the mechanics' rules (sandstorm
## targets, thawing, water levels, the Cradle pad). The live node is FrontierDistrict; visuals
## are FrontierView.

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


# --- Field setup -----------------------------------------------------------------------------

## Field parameters for a hub's district: {} for ordinary hubs.
static func field_params(planet: PlanetData, hub_i: int) -> Dictionary:
	var k: String = planet.frontier_kind(hub_i)
	return def(k) if k != "" else {}


## Ring (hex distance from the base) of a hex.
static func ring_of(field: HexField, hid: int) -> int:
	return Hex.distance(field.hex_axial[hid], Vector2i.ZERO)


## Water hexes before generation. Frozen Port: the harbour, east of harbour_x on the outer rings.
## Sunken City: every hex past the dry ring. Others: none (the frontier replaces planet lakes).
static func water_ids_for(kind: Dictionary, radius: int, hex_size: float) -> Dictionary:
	var out: Dictionary = {}
	var sp: Array[Vector2i] = Hex.spiral(radius)
	for i: int in sp.size():
		var d: int = Hex.distance(sp[i], Vector2i.ZERO)
		var w: Vector2 = Hex.axial_to_world(sp[i], hex_size)
		match str(kind.get("id", "")):
			"frozen_port":
				if d >= 2 and w.x > float(kind.get("ice", {}).get("harbour_x", 14.0)):
					out[i] = true
			"sunken_city":
				if d > int(kind.get("flood", {}).get("dry_ring", 1)):
					out[i] = true
	return out


## Bulkier junk: scales every piece's volume (cubes per piece and compartment use) and the hex
## totals. Must run after generate() and before apply_dict() (which recounts what is left).
static func toughen(field: HexField, vol_mult: float) -> void:
	if is_equal_approx(vol_mult, 1.0):
		return
	for pid: int in field.piece_count():
		field.piece_vol[pid] *= vol_mult
	for id: int in field.hex_count():
		field.hex_total[id] *= vol_mult
		field.hex_left[id] = field.hex_total[id]


# --- Sandstorm (Dust Flats) ------------------------------------------------------------------

## Hexes a storm can re-dust: clean, dry, non-hub, unplanted land that no Sustained hex shelters.
## levels: hex id -> level (HexLevels.levels); planted: Callable(hid) -> bool.
static func storm_candidates(field: HexField, levels: Dictionary, planted: Callable, shelter_level: int, shelter_ring: int) -> Array[int]:
	var walls: Array[int] = []
	for id: Variant in levels:
		if int(levels[id]) >= shelter_level:
			walls.append(int(id))
	var out: Array[int] = []
	for id: int in field.hex_count():
		if field.hex_hub[id] != 0 or field.is_water(id) or not field.is_clean(id):
			continue
		if planted.is_valid() and bool(planted.call(id)):
			continue
		var sheltered: bool = false
		for w: int in walls:
			if Hex.distance(field.hex_axial[w], field.hex_axial[id]) <= shelter_ring:
				sheltered = true
				break
		if not sheltered:
			out.append(id)
	return out


## How many hexes a storm hits: grows with how much of the district is clean.
static func storm_count(storm: Dictionary, cleaned: int, fences: bool) -> int:
	var h: Array = storm.get("hexes", [2, 6])
	@warning_ignore("integer_division")
	var n: int = int(h[0]) + cleaned / maxi(1, int(storm.get("per_cleaned", 10)))
	n = mini(n, int(h[1]))
	if fences:
		n = maxi(1, int(round(n * (1.0 - float(storm.get("fences_cut", 0.4))))))
	return n


## Dead pieces spread across a hex for a storm to blow back (more spread than a Ledger dump).
static func storm_pieces(field: HexField, hid: int, r: RandomNumberGenerator, frac: float, min_n: int, max_n: int) -> PackedInt32Array:
	var dead: Array[int] = []
	for pid: int in field.hex_pieces[hid]:
		if field.piece_alive[pid] == 0:
			dead.append(pid)
	var out := PackedInt32Array()
	if dead.size() < min_n:
		return out
	for k: int in range(dead.size() - 1, 0, -1):
		var j: int = r.randi() % (k + 1)
		var t: int = dead[k]
		dead[k] = dead[j]
		dead[j] = t
	var need: float = maxf(frac, (1.0 - field.clean_threshold) * 1.5) * field.hex_total[hid]
	var vol: float = 0.0
	for pid: int in dead:
		if out.size() >= max_n or (vol >= need and out.size() >= min_n):
			break
		out.append(pid)
		vol += field.piece_vol[pid]
	return out


# --- Ice (Frozen Port) -----------------------------------------------------------------------

## Starting ice per hex (1 = frozen solid, 0 = none). Deterministic from the field seed.
static func initial_ice(field: HexField, ice: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(field.hex_count())
	for id: int in field.hex_count():
		if field.hex_hub[id] != 0:
			continue
		var r := RandomNumberGenerator.new()
		r.seed = hash([field.seed_value, id, 991])
		var ring: int = ring_of(field, id)
		var frac: float = float(ice.get("ring1_frac", 0.5)) if ring <= 1 else float(ice.get("frac", 0.85))
		if field.is_water(id) or r.randf() < frac:
			out[id] = 1.0
	return out


## Thaw rates per hex per second from heaters (own hex full rate, neighbours spread_mult) and
## Lumi's beam (beam_hex at the beam rate). Returns hex id -> rate.
static func thaw_rates(field: HexField, ice_cfg: Dictionary, heaters: Array, beam_hex: int, heat_pumps: bool, lance: bool) -> Dictionary:
	var out: Dictionary = {}
	var base: float = 1.0 / maxf(float(ice_cfg.get("thaw_s", 80.0)), 1.0)
	var pump: float = float(ice_cfg.get("pump_mult", 1.6)) if heat_pumps else 1.0
	var spread: float = float(ice_cfg.get("spread_mult", 0.22)) * (1.5 if heat_pumps else 1.0)
	for h: Variant in heaters:
		var hid: int = int(h)
		if hid < 0 or hid >= field.hex_count():
			continue
		out[hid] = float(out.get(hid, 0.0)) + base * pump
		for nb: Vector2i in Hex.neighbors(field.hex_axial[hid]):
			var n: int = int(field.axial_to_id.get(nb, -1))
			if n >= 0:
				out[n] = float(out.get(n, 0.0)) + base * pump * spread
	if beam_hex >= 0:
		out[beam_hex] = float(out.get(beam_hex, 0.0)) + (2.0 if lance else 1.0) / maxf(float(ice_cfg.get("beam_thaw_s", 240.0)), 1.0)
	return out


## Applies dt seconds of thaw. Returns the hexes that just became ice-free.
static func thaw_step(ice: PackedFloat32Array, rates: Dictionary, dt: float) -> Array[int]:
	var freed: Array[int] = []
	for h: Variant in rates:
		var hid: int = int(h)
		if hid < 0 or hid >= ice.size() or ice[hid] <= 0.0:
			continue
		ice[hid] = maxf(0.0, ice[hid] - float(rates[h]) * dt)
		if ice[hid] <= 0.0:
			freed.append(hid)
	return freed


static func heater_cost(ice_cfg: Dictionary, placed: int) -> float:
	return round(float(ice_cfg.get("heater_cost", 90)) * pow(float(ice_cfg.get("heater_growth", 1.32)), placed))


static func greenhouse_cost(ice_cfg: Dictionary, built: int) -> float:
	return round(float(ice_cfg.get("greenhouse_cost", 450)) * pow(float(ice_cfg.get("greenhouse_growth", 1.25)), built))


# --- Flood (Sunken City) --------------------------------------------------------------------

## The drain stage that reveals a hex (1 = first ring past the dry ring), 0 if it starts dry.
static func flood_stage_of(field: HexField, hid: int, flood: Dictionary) -> int:
	var ring: int = ring_of(field, hid)
	var dry: int = int(flood.get("dry_ring", 1))
	return 0 if ring <= dry else mini(ring - dry, int(flood.get("stages", 3)))


## Hexes the next drain (stage `next`) would reveal: still water, stage == next.
static func drain_hexes(field: HexField, next: int, flood: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for id: int in field.hex_count():
		if field.is_water(id) and flood_stage_of(field, id, flood) == next:
			out.append(id)
	return out


## Share of the next stage's water hexes that are clean (skimmed).
static func drain_progress(field: HexField, next: int, flood: Dictionary) -> float:
	var hs: Array[int] = drain_hexes(field, next, flood)
	if hs.is_empty():
		return 0.0
	var c: int = 0
	for h: int in hs:
		if field.is_clean(h):
			c += 1
	return float(c) / hs.size()


static func drain_ready(field: HexField, drained: int, flood: Dictionary) -> bool:
	if drained >= int(flood.get("stages", 3)):
		return false
	return drain_progress(field, drained + 1, flood) >= float(flood.get("drain_at", 0.8)) - 0.0001


## Turns a water hex into land: pieces settle onto the street. No view work (caller refreshes).
static func drain_hex(field: HexField, hid: int) -> void:
	field.hex_water[hid] = 0
	field.water_ids.erase(hid)
	for pid: int in field.hex_pieces[hid]:
		var p: Vector3 = field.piece_pos[pid]
		p.y = field.layout.height_at(p.x, p.z) if field.layout else 0.0
		field.piece_pos[pid] = p


## How far the city sits below its streets for a number of drained stages (metres).
static func sink_for(drained: int, flood: Dictionary) -> float:
	var st: int = maxi(1, int(flood.get("stages", 3)))
	return float(flood.get("sink_m", 7.5)) * (1.0 - clampf(float(drained) / st, 0.0, 1.0))


# --- Cradle pad ------------------------------------------------------------------------------

## Pad hexes: the centre hex and its rings (data "pad").
static func pad_hexes(field: HexField, pad: Dictionary) -> Array[int]:
	var c: Array = pad.get("center", [0, -3])
	var ca := Vector2i(int(c[0]), int(c[1]))
	var out: Array[int] = []
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and Hex.distance(field.hex_axial[id], ca) <= int(pad.get("ring", 1)):
			out.append(id)
	return out


## {pad_clean, pad_level, district: share of land at complete.level, done}.
static func cradle_progress(field: HexField, levels: Dictionary, kind: Dictionary) -> Dictionary:
	var pad: Array[int] = pad_hexes(field, kind.get("pad", {}))
	var need_lv: int = int(kind.get("pad", {}).get("level", 4))
	var clean: int = 0
	var lv_ok: int = 0
	for h: int in pad:
		if field.is_clean(h):
			clean += 1
		if int(levels.get(h, 0)) >= need_lv:
			lv_ok += 1
	var comp: Dictionary = kind.get("complete", {})
	var land: int = 0
	var good: int = 0
	for h: Variant in levels:
		land += 1
		if int(levels[h]) >= int(comp.get("level", 3)):
			good += 1
	var frac: float = float(good) / maxf(land, 1.0)
	var pad_n: int = maxi(pad.size(), 1)
	var done: bool = lv_ok >= pad.size() and not pad.is_empty() and frac >= float(comp.get("frac", 0.7)) - 0.0001
	return {"pad_clean": float(clean) / pad_n, "pad_level": float(lv_ok) / pad_n, "district": frac, "done": done}


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
