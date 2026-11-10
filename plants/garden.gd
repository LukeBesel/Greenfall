class_name Garden
extends Node3D
## Planting, watering and growth on clean hexes. Each clean hex has plant slots on a jittered
## grid in the cell's own frame on the globe ground, made when Lumi plants or waters near it (a
## 164k-cell globe can't hold every slot) and seeded by the cell, so a cell always gets the same
## slots; they are saved per cell, not by slot index. Plants grow one stage per grow_s while watered; thirsty plants droop and pause (never
## die). Blooms drop seeds. Hex life = mean stage / 4 drives the ground turning green and the
## planet cell state (Planted -> Growing -> Restored).

## [v4grow] A seed went in / a plant got water (was_dry: it had none). plants/garden_marks.gd.
signal planted(slot: int)
signal watered(slot: int, was_dry: bool)

var world: Node
## The globe's per-cell state (far shell, planet %) and its sites (town paving): set by the slice.
var cells: SphereCells
var site_manager: SiteManager
var cfg: Dictionary
var species: Array = []
var _sp_weight_sum: float = 0.0

# Slots (flat arrays, all hexes)
var slot_pos := PackedVector3Array()
var slot_hex := PackedInt32Array()
var slot_species := PackedInt32Array()  # -1 = empty
var slot_stage := PackedByteArray()
var slot_progress := PackedFloat32Array()
var slot_water := PackedFloat32Array()   # seconds of water left
var slot_yaw := PackedFloat32Array()
var hex_slots: Dictionary = {}  # hex id -> PackedInt32Array of slot ids
var hex_life: Dictionary = {}   # hex id -> float 0..1

var _mms: Dictionary = {}  # "chunk|species" -> MultiMeshInstance3D
## [deck] Plants batch per globe chunk and species (was per hex: ~2 plants per draw). chunk key
## -> slot count (instance capacity of each species' MultiMesh there).
var _chunk_cap: Dictionary = {}
## [biomes] A per-hex growth bonus (greenhouses).
var hex_grow_bonus: Dictionary = {}
var _slot_inst: Dictionary = {}  # slot -> [key, index]
var _tick: float = 0.0
const VARIANT_TRIS: int = 3000  # [green]
const MAX_VARIANTS: int = 3  # [green] caps the batch count (chunk x species x variant)
var _saved_cells: Dictionary = {}  # cell -> [species bytes, stage bytes, water floats] not made yet


func setup() -> void:
	cfg = Economy.planet_table("plants")
	species = cfg.get("species", [])
	for s: Dictionary in species:
		_sp_weight_sum += float(s.get("weight", 1.0))
	_load()  # slots come per cell, on demand (ensure_hex)


## [biomes] Can this empty slot take a seed here? (not under water, not on paving)
func plantable(s: int) -> bool:
	if world == null or world.field.is_water(slot_hex[s]):
		return false
	return not on_paving(s)  # [v4grow] streets, sidewalks and kerbs, the pad, buildings


## Makes a land cell's slots (once) and restores what a save had planted there.
func ensure_hex(hid: int) -> void:
	if hid < 0 or hex_slots.has(hid):
		return
	var field: SphereField = world.field
	if field.hex_hub[hid] != 0 or field.is_water(hid):
		return
	var first: int = slot_pos.size()
	_make_slots(hid)
	for i: int in range(first, slot_pos.size()):
		var ck: Vector2i = _chunk_of(i)
		_chunk_cap[ck] = int(_chunk_cap.get(ck, 0)) + 1
	var d: Variant = _saved_cells.get(hid)
	if d is Array and (d as Array).size() == 3:
		var sp: PackedByteArray = d[0]
		var st: PackedByteArray = d[1]
		var wa: PackedFloat32Array = d[2]
		var ids: PackedInt32Array = hex_slots[hid]
		for k: int in mini(ids.size(), sp.size()):
			var sl: int = ids[k]
			slot_species[sl] = int(sp[k]) - 1
			slot_stage[sl] = st[k]
			slot_water[sl] = wa[k] if k < wa.size() else 0.0
			if slot_species[sl] >= 0:
				_update_inst(sl)
		_saved_cells.erase(hid)
		_recount(hid)


func _make_slots(hid: int) -> void:
	var f: SphereField = world.field
	var spacing: float = float(cfg.get("slot_spacing", 2.3))
	var ctr: Vector3 = f.grid.centers[hid]
	var fr: Basis = SphereGrid.frame(ctr)
	var rng := RandomNumberGenerator.new()
	rng.seed = f.seed_value * 31 + hid
	var ids := PackedInt32Array()
	var r: int = int(ceil(f.hex_size / spacing)) + 1
	for gx: int in range(-r, r + 1):
		for gz: int in range(-r, r + 1):
			var lx: float = gx * spacing + rng.randf_range(-0.5, 0.5)
			var lz: float = gz * spacing + rng.randf_range(-0.5, 0.5)
			var d: Vector3 = (ctr + (fr.x * lx + fr.z * lz) / f.grid.radius_m).normalized()
			if f.grid.cell_at(d) != hid:
				continue
			ids.append(slot_pos.size())
			slot_pos.append(f.terrain.ground(d))
			slot_hex.append(hid)
			slot_species.append(-1)
			slot_stage.append(0)
			slot_progress.append(0.0)
			slot_water.append(0.0)
			slot_yaw.append(rng.randf() * TAU)
	hex_slots[hid] = ids


func unlocked() -> bool:
	return GameState.flags.get("seeds_unlocked", false)


## Nearest empty slot in front of a position on a clean hex.
func free_slot_near(pos: Vector3, fwd: Vector3, reach: float = 2.2) -> int:
	return _slot_near(pos, fwd, reach, true)


func planted_near(pos: Vector3, fwd: Vector3, reach: float = 2.8) -> Array[int]:
	var out: Array[int] = []
	var hid: int = world.field.hex_at(pos + fwd * 1.0)
	for h: int in [hid, world.field.hex_at(pos)]:
		ensure_hex(h)  # [orbB]
		if not hex_slots.has(h):
			continue
		for s: int in hex_slots[h]:
			if slot_species[s] >= 0 and slot_pos[s].distance_to(pos + fwd * 1.2) <= reach:
				out.append(s)
	return out


func _slot_near(pos: Vector3, fwd: Vector3, reach: float, empty: bool) -> int:
	var best: int = -1
	var best_d: float = INF
	for h: int in [world.field.hex_at(pos + fwd * 1.0), world.field.hex_at(pos)]:
		if world.field.is_clean(h):
			ensure_hex(h)  # [orbB]
		if not hex_slots.has(h) or not world.field.is_clean(h):
			continue
		for s: int in hex_slots[h]:
			if empty != (slot_species[s] < 0):
				continue
			if empty and not plantable(s):  # [biomes]
				continue
			var d: float = slot_pos[s].distance_to(pos + fwd * 1.0)
			if d < reach and d < best_d:
				best_d = d
				best = s
	return best


func plant(slot: int) -> bool:
	if slot < 0 or slot_species[slot] >= 0 or not GameState.can_afford("seeds", BigNum.from_float(1.0)):
		return false
	GameState.spend("seeds", BigNum.from_float(1.0))
	slot_species[slot] = _pick_species(slot)
	slot_stage[slot] = 0
	slot_progress[slot] = 0.0
	slot_water[slot] = 0.0
	_update_inst(slot)
	var p: Vector3 = slot_pos[slot]
	Vfx.burst("soil", p + OrbitUp.up(p) * 0.05, Color(0.36, 0.27, 0.2), 0.8)  # [orbB] local up
	Audio.play("dig", 1.1, -8.0)
	GameState.inc_stat("plants_planted")
	_recount(slot_hex[slot])
	planted.emit(slot)  # [v4grow]
	return true


func water(slot: int, amount_s: float) -> void:
	if slot_species[slot] < 0:
		return
	var sp: Dictionary = species[slot_species[slot]]
	var was_dry: bool = slot_water[slot] <= 0.0
	slot_water[slot] = minf(slot_water[slot] + amount_s, float(sp.get("water_s", 120)))
	if was_dry:
		_perk[slot] = PERK_S  # [v4grow] it straightens up with a little bounce
		_update_inst(slot)
	watered.emit(slot, was_dry)


func _pick_species(slot: int) -> int:
	# [biomes] Frontier natives / cold rules scale the weights (Frontiers.species_mult).
	var biome: String = str(world.field.biome) if world else ""
	var gh: bool = hex_grow_bonus.has(slot_hex[slot])
	var ws: Array[float] = []
	var sum: float = 0.0
	for sp: Dictionary in species:
		ws.append(float(sp.get("weight", 1.0)) * Frontiers.species_mult(sp, biome, gh))
		sum += ws[-1]
	if sum <= 0.0:
		return 0
	var r: float = fmod(float(slot) * 0.6180339 + randf() * 0.5, 1.0) * sum
	for i: int in species.size():
		r -= ws[i]
		if r <= 0.0 and ws[i] > 0.0:
			return i
	for i: int in range(species.size() - 1, -1, -1):
		if ws[i] > 0.0:
			return i
	return 0


func _process(delta: float) -> void:
	_perk_step(delta)  # [v4grow]
	_tick += delta
	if _tick < 0.5:
		return
	var dt: float = _tick
	_tick = 0.0
	var changed_hexes: Dictionary = {}
	# Irrigation research: buried drip lines halve how fast plants dry out.
	var drain: float = dt * (0.5 if Research.has("irrigation") else 1.0) * Frontiers.plant_drain_mult(str(world.field.biome))  # [biomes] desert heat
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	var grow_mult: float = 1.0 + (hl.bonus("grow_pct") if hl else 0.0)
	var seed_mult: float = 1.0 + (hl.bonus("seed_pct") if hl else 0.0)
	# [beat] The garden ramp (~1 h in): research such as Pollinator Survey raises these.
	grow_mult *= maxf(Economy.stat("plant_growth"), 0.1)
	seed_mult *= maxf(Economy.stat("seed_yield"), 0.1)
	for s: int in slot_species.size():
		if slot_species[s] < 0:
			continue
		var sp: Dictionary = species[slot_species[s]]
		if slot_water[s] > 0.0:
			slot_water[s] = maxf(0.0, slot_water[s] - drain)
			if slot_water[s] <= 0.0:
				_update_inst(s)  # droop
			if slot_stage[s] < 4:
				slot_progress[s] += dt * (grow_mult + float(hex_grow_bonus.get(slot_hex[s], 0.0))) / float(sp.get("grow_s", 40))  # [biomes] greenhouses
				if slot_progress[s] >= 1.0:
					slot_progress[s] = 0.0
					slot_stage[s] += 1
					_update_inst(s)
					changed_hexes[slot_hex[s]] = true
					if slot_stage[s] == 1:
						Audio.play("pop", 1.4, -16.0)
					if slot_stage[s] == 4:
						GameState.add_currency("seeds", BigNum.from_float(float(sp.get("seed_yield", 0.5)) * seed_mult))
						GameState.inc_stat("plants_bloomed")
						Vfx.burst("sparkle", slot_pos[s] + OrbitUp.up(slot_pos[s]) * 0.5, Color(1.0, 0.95, 0.6), 0.25)  # [orbB]
	for h: int in changed_hexes:
		_recount(h)


func _recount(hid: int) -> void:
	var ids: PackedInt32Array = hex_slots.get(hid, PackedInt32Array())
	if ids.is_empty():
		return
	var sum: float = 0.0
	var planted: int = 0
	for s: int in ids:
		if slot_species[s] >= 0:
			planted += 1
			sum += float(slot_stage[s]) + 1.0
	var life: float = sum / (ids.size() * 5.0)
	hex_life[hid] = life
	world.view.set_life(hid, life)
	var planet: PlanetData = world.planet
	var cell: int = hid  # cell ids are the planet's ids
	var before: int = planet.state[cell]
	if life >= float(cfg.get("restored_life", 0.8)):
		planet.state[cell] = PlanetData.State.RESTORED
	elif life >= 0.35:
		planet.state[cell] = PlanetData.State.GROWING
	elif planted > 0:
		planet.state[cell] = PlanetData.State.PLANTED
	if before != planet.state[cell]:  # the globe's cells (far shell, planet %) follow
		cells.set_state(cell, planet.state[cell])
	if before != planet.state[cell] and planet.state[cell] == PlanetData.State.RESTORED:
		EventBus.toast.emit(tr("A hex is fully restored. Something small is already living in it."), "story")
		Audio.play("chime", 0.8, -4.0)
		EventBus.hex_restored.emit(hid)


# --- Visuals -------------------------------------------------------------------------

## Each species is sized to a real height per stage (data/plants.json globe_heights, capped in
## width); the seed and sprout stages are the GardenMarks sprout on its soil mound, a thirsty
## plant droops hard, and a watered one perks up.
func _slot_xf(s: int) -> Transform3D:
	var sc: float = globe_scale(s) * (1.0 + 0.18 * perk_of(s))
	if sc <= 0.0:
		return Transform3D(Basis().scaled(Vector3.ONE * 0.0001), slot_pos[s])
	var b := Basis(Vector3.UP, slot_yaw[s]).scaled(Vector3.ONE * sc)
	if slot_water[s] <= 0.0:  # thirsty: a hard droop, squat and leaning
		b = Basis(Vector3.RIGHT, 0.55) * b.scaled(Vector3(1.1, 0.72, 1.1))
	return Transform3D(SphereGrid.frame(slot_pos[s].normalized()) * b, slot_pos[s] + slot_pos[s].normalized() * lift_of(s))


func _chunk_of(s: int) -> Vector2i:
	return Vector2i((world.field as SphereField).grid.cell_chunk[slot_hex[s]], -1)


## [green] Which single variant of the species' plant file this slot shows (PlantParts).
func _variant_of(s: int) -> int:
	var n: int = mini(PlantParts.variants(str(species[slot_species[s]]["model"]), VARIANT_TRIS).size(), MAX_VARIANTS)
	return (s * 7919 + slot_species[s] * 31) % maxi(n, 1)


func _update_inst(s: int) -> void:
	var ck: Vector2i = _chunk_of(s)
	var vi: int = _variant_of(s)  # [green] one clump per slot, not the file's whole row of variants
	var key: String = "%d,%d|%d|%d" % [ck.x, ck.y, slot_species[s], vi]
	if not _slot_inst.has(s):
		if not _mms.has(key):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = PlantParts.variants(str(species[slot_species[s]]["model"]), VARIANT_TRIS)[vi]
			mm.mesh = _vivid(mm.mesh)  # [v4grow] a touch brighter and greener (they read pale)
			mm.instance_count = int(_chunk_cap.get(ck, 1))
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 150.0
			add_child(mmi)
			_mms[key] = mmi
		var mmi2: MultiMeshInstance3D = _mms[key]
		var idx: int = mmi2.multimesh.visible_instance_count
		if idx >= mmi2.multimesh.instance_count:  # a late hex added slots to an existing chunk batch
			var keep: Array[Transform3D] = []
			for k: int in idx:
				keep.append(mmi2.multimesh.get_instance_transform(k))
			mmi2.multimesh.instance_count = maxi(int(_chunk_cap.get(ck, 1)), idx + 1)
			for k: int in idx:
				mmi2.multimesh.set_instance_transform(k, keep[k])
			mmi2.multimesh.visible_instance_count = idx
		mmi2.multimesh.visible_instance_count = idx + 1
		_slot_inst[s] = [key, idx]
	var info: Array = _slot_inst[s]
	(_mms[info[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(int(info[1]), _slot_xf(s))


# --- Persistence -----------------------------------------------------------------------

## The save: per planted cell, its slots' species / stage / water.
func persist() -> Dictionary:
	var out: Dictionary = {}
	for h: int in hex_slots:
		var ids: PackedInt32Array = hex_slots[h]
		var any: bool = false
		var sp := PackedByteArray()
		var st := PackedByteArray()
		var wa := PackedFloat32Array()
		for sl: int in ids:
			sp.append(slot_species[sl] + 1)
			st.append(slot_stage[sl])
			wa.append(slot_water[sl])
			any = any or slot_species[sl] >= 0
		if any:
			out[str(h)] = [Marshalls.raw_to_base64(sp), Marshalls.raw_to_base64(st), Marshalls.raw_to_base64(wa.to_byte_array())]
	for h: int in _saved_cells:  # planted cells this run never came near: keep them
		var e: Array = _saved_cells[h]
		out[str(h)] = [Marshalls.raw_to_base64(e[0]), Marshalls.raw_to_base64(e[1]), Marshalls.raw_to_base64((e[2] as PackedFloat32Array).to_byte_array())]
	return {"cells": out}


func _load() -> void:
	var d: Dictionary = GameState.world.get("garden", {})
	var cells: Dictionary = d.get("cells", {})
	for k: Variant in cells:
		var e: Array = cells[k]
		if e.size() < 3:
			continue
		_saved_cells[int(str(k))] = [Marshalls.base64_to_raw(str(e[0])), Marshalls.base64_to_raw(str(e[1])), Marshalls.base64_to_raw(str(e[2])).to_float32_array()]
	for h: int in _saved_cells.keys():  # planted cells come back with their plants
		ensure_hex(h)


# --- [v4grow] Owner playtest 3 #51: plants you can see -------------------------------------------
# The Poly Haven clumps are 7-40 cm tall: at their own scale a fresh seed was 2 cm and a bloom
# 18 cm, invisible from Lumi's camera, so each stage has a real height (_slot_xf).

const PERK_S: float = 0.7
var _perk: Dictionary = {}  # slot -> seconds of the perk-up bounce left
var _variant_size: Dictionary = {}  # "species|variant" -> AABB size of that clump


## 0..1 bounce while a just-watered plant straightens (0 when none).
func perk_of(s: int) -> float:
	return sin(PI * (1.0 - float(_perk[s]) / PERK_S)) if _perk.has(s) else 0.0


func _perk_step(delta: float) -> void:
	if _perk.is_empty():
		return
	for s: int in _perk.keys():
		_perk[s] = float(_perk[s]) - delta
		if float(_perk[s]) <= 0.0:
			_perk.erase(s)
		if slot_species[s] >= 0:
			_update_inst(s)


## Height (m) a plant of this stage stands on the globe (0: only the sprout shows).
func globe_height(stage: int) -> float:
	var hs: Array = cfg.get("globe_heights", [0.0, 0.0, 0.5, 0.75, 1.0])
	return float(hs[clampi(stage, 0, hs.size() - 1)])


## The uniform scale that makes slot s's clump globe_height(stage) tall (times the species'
## scale), no wider than globe_max_width.
func globe_scale(s: int) -> float:
	var h: float = globe_height(slot_stage[s])
	if h <= 0.0:
		return 0.0
	var key: String = "%d|%d" % [slot_species[s], _variant_of(s)]
	if not _variant_size.has(key):
		var vs: Array = PlantParts.variants(str(species[slot_species[s]]["model"]), VARIANT_TRIS)
		_variant_size[key] = (vs[_variant_of(s)] as Mesh).get_aabb().size if not vs.is_empty() else Vector3(0.3, 0.3, 0.3)
	var sz: Vector3 = _variant_size[key]
	var sc: float = h * float(species[slot_species[s]].get("scale", 1.0)) / maxf(sz.y, 0.05)
	return minf(sc, float(cfg.get("globe_max_width", 1.6)) / maxf(maxf(sz.x, sz.z), 0.05))


## Planted slots on the cells made so far (sparse: the cells Lumi has been near).
func planted_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for h: int in hex_slots:
		for sl: int in hex_slots[h]:
			if slot_species[sl] >= 0:
				out.append(sl)
	return out


# --- [v4grow] Planting stays off the paving ------------------------------------------------------
# A cell's slots are kept as they were (their order is what the save holds), and a slot on a town's street,
# sidewalk and kerb, the yard pad or a building can't take a seed (its soil mound would sit half
# under the tiles). Checked at the slot and MOUND_R round it. The lots' kit ground patches (8 cm
# concrete plates on sand) stay plantable, but the mound and the plant stand on
# top of the plates (lift_of), and the patch's kerb band is kept clear. Cached once the town is in.

const PAVED: Array[int] = [CityLayout.Surface.ROAD, CityLayout.Surface.SIDEWALK, CityLayout.Surface.BUILDING, CityLayout.Surface.YARD]
const MOUND_R: float = 0.7
const LOT_HALF: float = 9.0  # a town's lot ground patch (18 x 18 m)
const LOT_KERB_M: float = 0.8
const PLATE_TOP: float = 0.12
var _paving: Dictionary = {}  # slot -> [on paving, lift (m)] (known)


## True when slot s lies on (or its mound would reach) a loaded town's paving.
func on_paving(s: int) -> bool:
	return bool(_ground_info(s)[0])


## How far above the terrain slot s's ground is (the top of a lot's plates, else 0).
func lift_of(s: int) -> float:
	return float(_ground_info(s)[1])


func _ground_info(s: int) -> Array:
	if _paving.has(s):
		return _paving[s]
	var towns: Array = _towns()
	if towns.is_empty():
		return [false, 0.0]  # no town loaded here yet: open ground (asked again later)
	var p: Vector3 = slot_pos[s]
	var out: Array = [false, 0.0]
	for t: Array in towns:
		var vs: TownSite = t[0]
		var loc: Vector3 = (t[1] as Transform3D) * p
		if Vector2(loc.x, loc.z).length() > vs.town_r + MOUND_R:
			continue
		for o: Vector2 in [Vector2.ZERO, Vector2(MOUND_R, 0), Vector2(-MOUND_R, 0), Vector2(0, MOUND_R), Vector2(0, -MOUND_R)]:
			if paved(vs.layout, loc.x + o.x, loc.z + o.y):
				out[0] = true
		var lots: Variant = vs.get("_lots")
		for lot: Dictionary in lots if lots is Array else []:
			var d: Vector2 = (Vector2(loc.x, loc.z) - (lot["c"] as Vector2)).abs()
			var m: float = maxf(d.x, d.y)
			if m < LOT_HALF + MOUND_R:
				if m > LOT_HALF - LOT_KERB_M - MOUND_R:
					out[0] = true  # the patch's kerb band
				else:
					out[1] = PLATE_TOP
	_paving[s] = out
	return out


## Paving in a town layout at site-local (x, z): its streets (only round blocks the town kept),
## sidewalks and kerbs, the yard pad and building footprints.
static func paved(lay: CityLayout, x: float, z: float) -> bool:
	if lay == null:
		return false
	var srf: int = lay.surface_at(x, z)
	if not srf in PAVED:
		return false
	return srf == CityLayout.Surface.YARD or lay.wild or lay.blocks.has(lay.block_key_at(x, z))


## [TownSite, inverse of its transform] for every loaded town on the globe.
func _towns() -> Array:
	var out: Array = []
	if site_manager == null:
		return out
	for pf: Variant in site_manager.prefabs:
		if not (pf is SitePrefab) or not is_instance_valid(pf) or (pf as SitePrefab).content == null:
			continue
		for c: Node in (pf as SitePrefab).content.get_children():
			if c is TownSite and (c as TownSite).layout != null and (c as Node3D).is_inside_tree():
				out.append([c, (c as Node3D).global_transform.affine_inverse()])
	return out


# --- [v4grow] Grown plants read pale: a richer copy of each clump's materials -------

const VIVID_TINT := Color(1.08, 1.22, 0.98)
static var _vivid_cache: Dictionary = {}  # mesh rid -> Mesh


static func _vivid(m: Mesh) -> Mesh:
	if m == null:
		return m
	if _vivid_cache.has(m.get_rid()):
		return _vivid_cache[m.get_rid()]
	var out: Mesh = m.duplicate()
	for i: int in out.get_surface_count():
		var mat: Material = out.surface_get_material(i)
		if mat is BaseMaterial3D:
			var v: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
			v.albedo_color = v.albedo_color * VIVID_TINT
			v.roughness = maxf(v.roughness, 0.85)  # less sky sheen (the whitish cast)
			v.metallic_specular = minf(v.metallic_specular, 0.3)
			out.surface_set_material(i, v)
	_vivid_cache[m.get_rid()] = out
	return out
