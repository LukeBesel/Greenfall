class_name GardenDev
extends RefCounted
## [green] Dev helpers for honest screenshots of green districts:
##   --garden-report[=S]  print garden / life / plant-batch stats after S s (headless ok)


static func report(world: Node) -> void:
	var g: Garden = world.get("garden") as Garden
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	if g == null:
		print("[garden] no garden")
		return
	var planted: int = 0
	var by_stage: Array[int] = [0, 0, 0, 0, 0]
	for s: int in g.slot_species.size():
		if g.slot_species[s] >= 0:
			planted += 1
			by_stage[g.slot_stage[s]] += 1
	var by_level: Array[int] = [0, 0, 0, 0, 0, 0]
	if hl:
		for h: int in hl.levels:
			by_level[int(hl.levels[h])] += 1
	print("[garden] slots=%d planted=%d stages=%s levels=%s" % [g.slot_species.size(), planted, str(by_stage), str(by_level)])
	var vis: int = 0
	for key: String in g._mms:
		var mmi: MultiMeshInstance3D = g._mms[key]
		vis += mmi.multimesh.visible_instance_count
	print("[garden] batches=%d visible_instances=%d" % [g._mms.size(), vis])
	species_census(g)
	for h: int in g.hex_life:
		var lv: int = hl.level_of(h) if hl else -1
		var img_life: float = (world.view as FieldView)._life_img.get_pixel(world.field.hex_axial[h].x + world.field.radius, world.field.hex_axial[h].y + world.field.radius).r
		if float(g.hex_life[h]) > 0.0 or lv > 0:
			print("[garden] hex %d lv=%d life=%.2f img=%.2f slots=%d at=%s" % [h, lv, float(g.hex_life[h]), img_life, (g.hex_slots.get(h, PackedInt32Array()) as PackedInt32Array).size(), str(world.field.hex_center(h).round())])


## Per-species mesh census: full vs lite triangles and model size (for "why are plants invisible").
static func species_census(g: Garden) -> void:
	for sp: Dictionary in g.species:
		var id: String = str(sp["model"])
		var full: Mesh = AssetLib.model_mesh(id)
		var lite: Mesh = AssetLib.model_mesh_lite(id, 1500)
		print("[garden] species %s model=%s tris full=%d lite=%d aabb=%s" % [sp["id"], id, _tris(full), _tris(lite), str(AssetLib.model_aabb(id).size)])


static func _tris(m: Mesh) -> int:
	var n: int = 0
	for s: int in m.get_surface_count():
		var a: Array = m.surface_get_arrays(s)
		n += ((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


# --- Honest previews of restored ground (--restore, --future) ------------------------------
##   --restore=N[,level]  the N land hexes nearest the base become `level` (1 Clean .. 5 Thriving,
##                        default 4) with real planted slots at matching growth stages, life values
##                        and part-watered plants; --restore-bots=N Drip robots (default 2) and a
##                        Seedling work them. Levels below `level` ring outward (a half-green district):
##                        --restore-ramp spreads levels 5..1 from the base out.
##   --green-cam=hid,dist,pitch,yaw_deg   put Lumi on hex hid and frame it (screenshots)

## Stage mix per level (weights for stages 0..4) and the share of slots planted.
const LEVEL_STAGES: Dictionary = {
	2: [[0.55, 0.4, 0.05, 0.0, 0.0], 0.85],
	3: [[0.0, 0.15, 0.5, 0.3, 0.05], 1.0],
	4: [[0.0, 0.0, 0.05, 0.45, 0.5], 1.0],
	5: [[0.0, 0.0, 0.0, 0.0, 1.0], 1.0],
}


## Land hexes, nearest the base first.
static func land_by_distance(w: Node) -> Array:
	var fld: HexField = w.field
	var land: Array = range(fld.hex_count()).filter(func(h: int) -> bool: return fld.hex_hub[h] == 0 and not fld.is_water(h))
	land.sort_custom(func(a: int, b: int) -> bool: return fld.hex_center(a).length() < fld.hex_center(b).length())
	return land


static func clean_hex(w: Node, hid: int) -> void:
	var fld: HexField = w.field
	for pid: int in fld.hex_pieces[hid]:
		if fld.piece_alive[pid] == 1:
			fld.remove_piece(pid)
			w.view.hide_piece(pid)
	if not fld.is_clean(hid):
		fld.hex_clean[hid] = 1
		fld.cleaned_count += 1
	w.view.refresh_hex(hid, false)
	w.litter.refresh_hex(hid)
	w.planet.set_junk(w.slice_cells[hid], 0.0)
	w.planet.mark_clean(w.slice_cells[hid])


## Make one hex look and measure like `level` really grew there: clean, slots planted at a stage
## mix, water part-used (so watering robots have work), life and planet state from the garden's own
## recount, and the hex level set (never lowered).
static func grow_hex(w: Node, hid: int, level: int) -> void:
	level = clampi(level, 0, HexLevels.MAX_LEVEL)
	if level < 1:
		return
	clean_hex(w, hid)
	var g: Garden = w.get("garden") as Garden
	var hl: HexLevels = w.get("hex_levels") as HexLevels
	if g and level >= 2:
		GameState.flags["seeds_unlocked"] = true
		var mix: Array = LEVEL_STAGES[level][0]
		var share: float = LEVEL_STAGES[level][1]
		var sl: PackedInt32Array = g.hex_slots.get(hid, PackedInt32Array())
		for i: int in sl.size():
			var s: int = sl[i]
			var r: float = Meadow._hh(s, 17)
			if r > share:
				continue
			var pick: float = Meadow._hh(s, 23)
			var stage: int = 0
			for k: int in 5:
				pick -= float(mix[k])
				if pick <= 0.0:
					stage = k
					break
				stage = k
			g.slot_species[s] = g._pick_species(s)
			g.slot_stage[s] = stage
			g.slot_progress[s] = Meadow._hh(s, 29) * 0.8
			var full: float = float(g.species[g.slot_species[s]].get("water_s", 120))
			g.slot_water[s] = full * (0.35 + 0.6 * Meadow._hh(s, 31))
			g._update_inst(s)
		_quiet_recount(w, g, hid)
	if hl and hl.levels.has(hid):
		hl.levels[hid] = maxi(int(hl.levels[hid]), level)
		if level >= 4:  # a full sustain window so it doesn't read as un-sustained right away
			for k: int in hl._window:
				hl._push(hid, 100)


## --restore=N[,level] / --restore-ramp.
static func apply_restore(w: Node) -> void:
	var spec: PackedStringArray = DevHooks.get_s("restore", "7").split(",")
	var n: int = int(spec[0])
	var level: int = int(spec[1]) if spec.size() > 1 else 4
	var land: Array = land_by_distance(w)
	var ramp: bool = DevHooks.has("restore-ramp")
	for i: int in mini(n, land.size()):
		var lv: int = level
		if ramp:  # base outward: Thriving, Sustained, Growing, Planted, Clean in equal bands
			lv = clampi(5 - int(floor(float(i) * 5.0 / float(maxi(n, 1)))), 1, 5)
		grow_hex(w, int(land[i]), lv)
	var hl: HexLevels = w.get("hex_levels") as HexLevels
	if hl:
		hl._recalc_bonus()
	spawn_workers(w, land.slice(0, mini(n, land.size())))
	print("[restore] %d hexes to level %s%s" % [mini(n, land.size()), str(level), " (ramp)" if ramp else ""])


## Drip robots (and a Seedling) out on the restored ground, so shots show the crew at work.
static func spawn_workers(w: Node, hexes: Array) -> void:
	var fleet: Fleet = w.get("fleet") as Fleet
	if fleet == null or hexes.is_empty():
		return
	var n: int = int(DevHooks.get_f("restore-bots", 2.0))
	for k: int in n + 1:
		var hid: int = int(hexes[k % hexes.size()])
		var c: Vector3 = w.field.hex_center(hid) + Vector3(1.5 * k - 1.0, 0.2, 1.2)
		var t: String = "drip" if k < n else "seedling"
		GameState.flags["tier_" + t] = 2
		var rb: Robot = fleet.spawn(t, 2, c, 0.0, "%s-%d" % [t.capitalize(), k])
		rb.rebuild_visual()


## --green-cam=hid,dist,pitch,yaw_deg
static func apply_cam(w: Node) -> void:
	var spec: PackedStringArray = DevHooks.get_s("green-cam", "1,8,-0.45,0").split(",")
	var hid: int = int(spec[0])
	var patch: Node3D = w.patch
	var c: Vector3 = w.field.hex_center(hid)
	patch.global_position = Vector3(c.x, 0.2, c.z)
	var cam: CameraRig = w.cam
	cam.yaw = deg_to_rad(float(spec[3]) if spec.size() > 3 else 0.0)
	patch.rotation.y = cam.yaw
	cam.distance = float(spec[1]) if spec.size() > 1 else 8.0
	cam.pitch = float(spec[2]) if spec.size() > 2 else -0.45
	cam.snap()


## Garden._recount without the "hex restored" toast / chime (previews set many hexes at once).
static func _quiet_recount(w: Node, g: Garden, hid: int) -> void:
	var ids: PackedInt32Array = g.hex_slots.get(hid, PackedInt32Array())
	if ids.is_empty():
		return
	var sum: float = 0.0
	var planted: int = 0
	for s: int in ids:
		if g.slot_species[s] >= 0:
			planted += 1
			sum += float(g.slot_stage[s]) + 1.0
	var life: float = sum / (ids.size() * 5.0)
	g.hex_life[hid] = life
	w.view.set_life(hid, life)
	var cell: int = w.slice_cells[hid]
	if life >= float(g.cfg.get("restored_life", 0.8)):
		w.planet.state[cell] = PlanetData.State.RESTORED
	elif life >= 0.35:
		w.planet.state[cell] = PlanetData.State.GROWING
	elif planted > 0:
		w.planet.state[cell] = PlanetData.State.PLANTED
