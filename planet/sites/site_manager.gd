class_name SiteManager
extends Node3D
## [orbD] Every hub site on one walkable globe: builds each hub's prefab (PlanetEnvs.build_site)
## when Lumi comes within BUILD_R of it and frees it past FREE_R (only the near site is 3D, the
## rest is the far shell), clears junk under building footprints, keeps the `site_inv` shader
## global on the nearest site, and owns the hub-region bookkeeping:
## - planet % (owner decision Nov 8) = clean share of the cells within REGION_RINGS rings of each
##   BUILT hub (the start hub always counts). planet_fraction() is what the HUD shows.
## - growth: the rest of the globe greens slowly as hubs thrive. Each hub has a growth radius
##   (m) on top of its region that grows with the region's clean share; tick(dt) turns the junk
##   cells inside it into restored ground, a few per second, so the far shell and the survey
##   hologram (both read SphereCells) show it spreading.
## Use: var sm := SiteManager.new(); add_child(sm); sm.setup(globe_node, planet_id, sites_array).
## sites_array: SphereTerrain.reserve_site results, hub 0 first.

signal site_built(i: int, prefab: SitePrefab)

const BUILD_R: float = 420.0
const FREE_R: float = 650.0
## Hub region: cells within this many rings of a hub count for planet % (10 m hexes: ~17 m a
## ring, so 18 rings ~ 310 m, ~1000 cells a hub).
const REGION_RINGS: int = 18
## Growth beyond the region: metres per unit of thriving per minute, and its cap.
const GROW_M_PER_MIN: float = 6.0
const GROW_MAX_M: float = 900.0
const RESTORED: int = 4

var globe: Node3D
var planet_id: String = "verdance"
var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var sites: Array[Dictionary] = []
var prefabs: Array = []          # SitePrefab or null, per site
var roots: Array[Node3D] = []
var built: PackedByteArray        # hub built (counts for planet %); hub 0 always
var levels: PackedInt32Array      # base level per hub (1..5)
var growth_m: PackedFloat32Array  # growth radius past the region, per hub
var regions: Array[PackedInt32Array] = []
var nearest: int = -1
var _region_of: Dictionary = {}   # cell -> hub (first hub wins)
var _grow_acc: float = 0.0
var _poll: float = 0.0
var _building: bool = false
var _seed: int = 4471


func setup(p_globe: Node3D, p_planet: String, p_sites: Array[Dictionary], p_seed: int = 4471) -> void:
	globe = p_globe
	planet_id = p_planet
	grid = globe.get("grid")
	terrain = globe.get("terrain")
	cells = globe.get("cells")
	sites = p_sites
	_seed = p_seed
	prefabs.resize(sites.size())
	built = PackedByteArray()
	built.resize(sites.size())
	levels = PackedInt32Array()
	levels.resize(sites.size())
	levels.fill(1)
	growth_m = PackedFloat32Array()
	growth_m.resize(sites.size())
	if sites.size() > 0:
		built[0] = 1
	for i: int in sites.size():
		var r := Node3D.new()
		r.name = "HubSite%d" % i
		add_child(r)
		roots.append(r)
		var c: int = int(sites[i]["cell"])
		var reg: PackedInt32Array = grid.cells_around(c, REGION_RINGS) if grid else PackedInt32Array()
		regions.append(reg)
		for k: int in reg:
			if not _region_of.has(k):
				_region_of[k] = i


## Builds hub i's prefab now (normally done by distance). Returns it (await .rebuilt if not built).
func build_hub(i: int) -> SitePrefab:
	if prefabs[i] != null:
		return prefabs[i]
	var s: Dictionary = sites[i].duplicate()
	s["planet"] = planet_id
	s["hub_index"] = i
	s["seed"] = _seed
	var p: SitePrefab = PlanetEnvs.build_site(roots[i], s, levels[i], restoration_of(i))
	prefabs[i] = p
	if p.is_built:
		_on_built(i, p)
	else:
		p.rebuilt.connect(func() -> void: _on_built(i, p), CONNECT_ONE_SHOT)
	return p


func free_hub(i: int) -> void:
	if prefabs[i] == null:
		return
	(prefabs[i] as Node).queue_free()
	prefabs[i] = null


func prefab(i: int) -> SitePrefab:
	return prefabs[i] if i >= 0 and i < prefabs.size() else null


func _on_built(i: int, p: SitePrefab) -> void:
	_clear_footprints(i, p)
	site_built.emit(i, p)


## Junk never sits inside a building: cells whose centre falls in a footprint go clean.
func _clear_footprints(i: int, p: SitePrefab) -> void:
	if cells == null or p.content == null:
		return
	var rects: Array[Rect2] = []
	for c: Node in p.content.get_children():
		if c.has_method("footprints"):
			rects.append_array(c.call("footprints"))
	if rects.is_empty():
		return
	var inv: Transform3D = (sites[i]["transform"] as Transform3D).affine_inverse()
	var field: Variant = globe.get("field")
	for c: int in sites[i]["cells"]:
		var lp: Vector3 = inv * terrain.ground(grid.centers[c])
		var q := Vector2(lp.x, lp.z)
		for r: Rect2 in rects:
			if r.grow(1.5).has_point(q):
				cells.set_junk(c, 0.0)
				cells.set_state(c, 1)
				if field is SphereField:
					var f: SphereField = field
					f.hex_left[c] = 0.0
					if f.hex_hub[c] == 0:
						f.hex_hub[c] = 1
						f.junk_hex_count -= 1
						if f.hex_clean[c] == 1:
							f.cleaned_count -= 1
					f.hex_clean[c] = 1
				break


# --- Per frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		_stream()
	_grow_acc += delta
	if _grow_acc >= 2.0:
		grow(_grow_acc)
		_grow_acc = 0.0


func _focus() -> Vector3:
	var l: Variant = globe.get("lumi") if globe else null
	if l is Node3D and (l as Node3D).is_inside_tree():
		return (l as Node3D).global_position
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3.ZERO


func _stream() -> void:
	if sites.is_empty():
		return
	var p: Vector3 = _focus()
	if p == Vector3.ZERO:
		return
	var best: int = -1
	var best_d: float = INF
	for i: int in sites.size():
		var d: float = (sites[i]["transform"] as Transform3D).origin.distance_to(p)
		if d < best_d:
			best_d = d
			best = i
		if d < BUILD_R and prefabs[i] == null and not _building:
			build_hub(i)
		elif d > FREE_R and prefabs[i] != null:
			free_hub(i)
	if best != nearest:
		nearest = best
		if prefabs[best] != null:
			point_shaders_at(prefabs[best])
		else:
			set_site_frame(sites[best]["transform"])


static func point_shaders_at(p: SitePrefab) -> void:
	set_site_frame(p.global_transform if p.is_inside_tree() else Transform3D.IDENTITY)


## The `site_inv` shader global: world-space shader maths (city, deco, slab, mural, junk coat)
## run in this frame's local space. Identity = the flat game.
static func set_site_frame(xf: Transform3D) -> void:
	RenderingServer.global_shader_parameter_set("site_inv", Projection(xf.affine_inverse()))


func _exit_tree() -> void:
	set_site_frame(Transform3D.IDENTITY)


# --- Stage, planet %, growth ----------------------------------------------------------------

## Mean clean share of hub i's region (0..1).
func region_clean(i: int) -> float:
	if cells == null or i >= regions.size():
		return 0.0
	var reg: PackedInt32Array = regions[i]
	var n: int = 0
	var ok: int = 0
	for c: int in reg:
		if cells.state[c] == 5:  # water
			continue
		n += 1
		if not cells.is_dirty(c):
			ok += 1
	return float(ok) / maxf(1.0, float(n))


## Restoration shown on hub i's prefab: its region's clean share.
func restoration_of(i: int) -> float:
	return region_clean(i)


func set_level(i: int, l: int) -> void:
	levels[i] = clampi(l, 1, 5)
	if prefabs[i] != null:
		(prefabs[i] as SitePrefab).set_stage(levels[i])


## Marks hub i as built (its region now counts for planet %).
func set_built(i: int, on: bool = true) -> void:
	built[i] = 1 if on or i == 0 else 0


## Planet %: clean share over the regions of the built hubs (cells counted once).
func planet_fraction() -> float:
	if cells == null:
		return 0.0
	var n: int = 0
	var ok: int = 0
	for c: Variant in _region_of:
		var i: int = _region_of[c]
		if built[i] == 0:
			continue
		var ci: int = c
		if cells.state[ci] == 5:
			continue
		n += 1
		if not cells.is_dirty(ci):
			ok += 1
	return float(ok) / maxf(1.0, float(n))


## Grows each built hub's greening radius by how well its region thrives, and restores the
## junk cells it reaches (outside every region: the regions are the player's and bots' work).
func grow(dt: float) -> int:
	if cells == null or grid == null:
		return 0
	var changed: int = 0
	for i: int in sites.size():
		if built[i] == 0:
			continue
		var thrive: float = clampf((region_clean(i) - 0.5) * 2.0, 0.0, 1.0)
		if thrive <= 0.0:
			continue
		var old: float = growth_m[i]
		var g: float = minf(GROW_MAX_M, old + GROW_M_PER_MIN * thrive * dt / 60.0)
		growth_m[i] = g
		if int(g / 8.0) == int(old / 8.0):
			continue
		var c0: int = int(sites[i]["cell"])
		var r_in: float = float(REGION_RINGS) * 17.3
		for c: int in grid.cells_within(grid.centers[c0], r_in + g, c0):
			if _region_of.has(c) or cells.state[c] == 5 or not cells.is_dirty(c):
				continue
			if grid.distance_m(c, c0) < r_in + old:
				continue
			cells.set_junk(c, 0.0)
			cells.set_state(c, RESTORED)
			changed += 1
	return changed


# --- Rocket hops -------------------------------------------------------------------------------

## World transform of hub i's rocket pad (built prefab anchor, else the default spot on the pad).
func pad_xf(i: int) -> Transform3D:
	var p: SitePrefab = prefabs[i] if i < prefabs.size() else null
	if p and p.is_built and p.is_inside_tree():
		return p.anchor_xf("rocket_pad")
	var core: float = float(SiteBuilders.find(planet_id, SiteBuilders.site_for_hub(planet_id, i)).get("clear_core_m", 12.0))
	return (sites[i]["transform"] as Transform3D) * Transform3D(Basis(), Vector3(0, 0, -maxf(core, 9.0) * 0.65))


func save_state() -> Dictionary:
	return {"built": Array(built), "levels": Array(levels), "growth": Array(growth_m)}


func load_state(d: Dictionary) -> void:
	var b: Array = d.get("built", [])
	var l: Array = d.get("levels", [])
	var g: Array = d.get("growth", [])
	for i: int in sites.size():
		if i < b.size():
			built[i] = int(b[i])
		if i < l.size():
			levels[i] = clampi(int(l[i]), 1, 5)
		if i < g.size():
			growth_m[i] = float(g[i])
	if sites.size() > 0:
		built[0] = 1
