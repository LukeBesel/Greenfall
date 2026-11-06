class_name Garden
extends Node3D
## Planting, watering and growth on clean hexes. Each clean hex has plant slots on a jittered
## grid. Plants grow one stage per grow_s while watered; thirsty plants droop and pause (never
## die). Blooms drop seeds. Hex life = mean stage / 4 drives the ground turning green and the
## planet cell state (Planted -> Growing -> Restored).

var world: Node
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

var _mms: Dictionary = {}  # "hex|species" -> MultiMeshInstance3D
var _slot_inst: Dictionary = {}  # slot -> [key, index]
var _tick: float = 0.0


func setup() -> void:
	cfg = Economy.read_json("res://data/plants.json")
	species = cfg.get("species", [])
	for s: Dictionary in species:
		_sp_weight_sum += float(s.get("weight", 1.0))
	var field: HexField = world.field
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and not field.is_water(id):
			_make_slots(id)
	_load()


func _make_slots(hid: int) -> void:
	var field: HexField = world.field
	var spacing: float = float(cfg.get("slot_spacing", 2.3))
	var c: Vector3 = field.hex_center(hid)
	var rng := RandomNumberGenerator.new()
	rng.seed = field.seed_value * 31 + hid
	var ids := PackedInt32Array()
	var r: int = int(ceil(field.hex_size / spacing)) + 1
	for gx: int in range(-r, r + 1):
		for gz: int in range(-r, r + 1):
			var p := c + Vector3(gx * spacing + rng.randf_range(-0.5, 0.5), 0, gz * spacing + rng.randf_range(-0.5, 0.5))
			if field.hex_at(p) != hid:
				continue
			if field.layout and field.layout.surface_at(p.x, p.z) in [CityLayout.Surface.BUILDING, CityLayout.Surface.ROAD]:
				continue  # roads stay roads; planting goes in lots, verges and sidewalks' edges
			p.y = field.layout.height_at(p.x, p.z) if field.layout else 0.0
			ids.append(slot_pos.size())
			slot_pos.append(p)
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
		if not hex_slots.has(h) or not world.field.is_clean(h):
			continue
		for s: int in hex_slots[h]:
			if empty != (slot_species[s] < 0):
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
	Vfx.burst("soil", p + Vector3(0, 0.05, 0), Color(0.36, 0.27, 0.2), 0.8)
	Audio.play("dig", 1.1, -8.0)
	GameState.inc_stat("plants_planted")
	_recount(slot_hex[slot])
	return true


func water(slot: int, amount_s: float) -> void:
	if slot_species[slot] < 0:
		return
	var sp: Dictionary = species[slot_species[slot]]
	var was_dry: bool = slot_water[slot] <= 0.0
	slot_water[slot] = minf(slot_water[slot] + amount_s, float(sp.get("water_s", 120)))
	if was_dry:
		_update_inst(slot)


func _pick_species(slot: int) -> int:
	var r: float = fmod(float(slot) * 0.6180339 + randf() * 0.5, 1.0) * _sp_weight_sum
	for i: int in species.size():
		r -= float(species[i].get("weight", 1.0))
		if r <= 0.0:
			return i
	return 0


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	var dt: float = _tick
	_tick = 0.0
	var changed_hexes: Dictionary = {}
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	var grow_mult: float = 1.0 + (hl.bonus("grow_pct") if hl else 0.0)
	var seed_mult: float = 1.0 + (hl.bonus("seed_pct") if hl else 0.0)
	for s: int in slot_species.size():
		if slot_species[s] < 0:
			continue
		var sp: Dictionary = species[slot_species[s]]
		if slot_water[s] > 0.0:
			slot_water[s] = maxf(0.0, slot_water[s] - dt)
			if slot_water[s] <= 0.0:
				_update_inst(s)  # droop
			if slot_stage[s] < 4:
				slot_progress[s] += dt * grow_mult / float(sp.get("grow_s", 40))
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
						Vfx.burst("sparkle", slot_pos[s] + Vector3(0, 0.5, 0), Color(1.0, 0.95, 0.6), 0.25)
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
	var cell: int = world.slice_cells[hid]
	var before: int = planet.state[cell]
	if life >= float(cfg.get("restored_life", 0.8)):
		planet.state[cell] = PlanetData.State.RESTORED
	elif life >= 0.35:
		planet.state[cell] = PlanetData.State.GROWING
	elif planted > 0:
		planet.state[cell] = PlanetData.State.PLANTED
	if before != planet.state[cell] and planet.state[cell] == PlanetData.State.RESTORED:
		EventBus.toast.emit("A hex is fully restored. Something small is already living in it.", "story")
		Audio.play("chime", 0.8, -4.0)
		EventBus.hex_restored.emit(hid)


# --- Visuals -------------------------------------------------------------------------

func _slot_xf(s: int) -> Transform3D:
	var sp: Dictionary = species[slot_species[s]]
	var stages: Array = cfg.get("stage_scale", [0.1, 0.3, 0.5, 0.8, 1.0])
	var sc: float = float(stages[slot_stage[s]]) * float(sp.get("scale", 1.0))
	var b := Basis(Vector3.UP, slot_yaw[s]).scaled(Vector3.ONE * sc)
	if slot_water[s] <= 0.0 and slot_stage[s] > 0:
		b = Basis(Vector3.RIGHT, 0.35) * b  # droop when thirsty
	return Transform3D(b, slot_pos[s])


func _update_inst(s: int) -> void:
	var key: String = "%d|%d" % [slot_hex[s], slot_species[s]]
	if not _slot_inst.has(s):
		if not _mms.has(key):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = AssetLib.model_mesh_lite(str(species[slot_species[s]]["model"]), 1500)
			mm.instance_count = (hex_slots[slot_hex[s]] as PackedInt32Array).size()
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 120.0
			add_child(mmi)
			_mms[key] = mmi
		var mmi2: MultiMeshInstance3D = _mms[key]
		var idx: int = mmi2.multimesh.visible_instance_count
		mmi2.multimesh.visible_instance_count = idx + 1
		_slot_inst[s] = [key, idx]
	var info: Array = _slot_inst[s]
	(_mms[info[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(int(info[1]), _slot_xf(s))


# --- Persistence -----------------------------------------------------------------------

func persist() -> Dictionary:
	var sp := PackedByteArray()
	sp.resize(slot_species.size())
	for i: int in slot_species.size():
		sp[i] = slot_species[i] + 1
	return {"species": Marshalls.raw_to_base64(sp) if not sp.is_empty() else "",
		"stage": Marshalls.raw_to_base64(slot_stage) if not slot_stage.is_empty() else "",
		"water": Marshalls.raw_to_base64(slot_water.to_byte_array()) if not slot_water.is_empty() else ""}


func _load() -> void:
	var d: Dictionary = GameState.world.get("garden", {})
	if d.is_empty():
		return
	var sp: PackedByteArray = Marshalls.base64_to_raw(str(d.get("species", "")))
	var st: PackedByteArray = Marshalls.base64_to_raw(str(d.get("stage", "")))
	var wa: PackedFloat32Array = Marshalls.base64_to_raw(str(d.get("water", ""))).to_float32_array()
	if sp.size() != slot_species.size():
		return
	for i: int in sp.size():
		slot_species[i] = int(sp[i]) - 1
		slot_stage[i] = st[i]
		slot_water[i] = wa[i] if i < wa.size() else 0.0
		if slot_species[i] >= 0:
			_update_inst(i)
	for h: int in hex_slots:
		_recount(h)
