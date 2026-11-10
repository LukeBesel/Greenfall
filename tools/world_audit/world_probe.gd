extends Node
## World audit probe (task M3-17): read-only numbers about the globe being played.
## Run: godot --headless --path . res://tools/world_audit/world_probe.tscn -- --fresh
## Optional: --probe-out=PATH (JSON; default res://screenshots/world/world_probe.json),
##           --probe-hubs=N (only the first N hubs), --probe-sample=N (junk cells sampled per band).
## Builds the globe (OrbitPlanet) without the slice, then for every hub site builds its prefab,
## reads the town through its public fields (duck-typed: no planet class is named here), lays the
## junk of sample cells in ring bands, and frees the prefab. Then it classifies every land cell
## (pad, town outskirts, hinterland zone) and samples what stands along three walks out of the
## start. Nothing is saved and no game state is changed outside this process.

const BANDS: Array = [[1, 6], [7, 12], [13, 18]]
const WALKS_M: Array[float] = [150.0, 300.0, 600.0, 1000.0]
const WALK_DIRS: Dictionary = {"north": Vector2(0, -1), "east": Vector2(1, 0), "south_west": Vector2(-0.7071, 0.7071)}

var g: OrbitPlanet
var out: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _hub_buildings: Array = []  # world points of every town + outskirts building footprint centre
var _land_buildings: Array = []  # world points of every hinterland building


func _ready() -> void:
	await get_tree().process_frame
	_rng.seed = 1717
	var def: PlanetDefinition = Planets.current()
	g = OrbitPlanet.new()
	g.name = "Globe"
	add_child(g)
	await g.build(def.world_seed)
	await g.build_start_site()
	_globe()
	var n_hubs: int = mini(g.sites.size(), int(DevHooks.get_f("probe-hubs", 99.0)))
	var hubs: Array = []
	for i: int in n_hubs:
		hubs.append(await _hub(i))
	out["hubs"] = hubs
	_land()
	_walks()
	var path: String = DevHooks.get_s("probe-out", "res://screenshots/world/world_probe.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[world-probe] wrote %s" % path)
	get_tree().quit(0)


# --- The globe as a whole --------------------------------------------------------------------

func _globe() -> void:
	var n: int = g.grid.cell_count()
	var water: int = 0
	var city: int = 0
	var junk_sum: float = 0.0
	var biomes: Dictionary = {}
	for c: int in n:
		if g.cells.state[c] == OrbitPlanet.WATER:
			water += 1
			continue
		junk_sum += g.cells.junk[c]
		if g.planet.city[c] >= 0:
			city += 1
		var b: String = PlanetData.BIOMES[g.planet.biome[c]]
		biomes[b] = int(biomes.get(b, 0)) + 1
	var land: int = n - water
	var m: Dictionary = g.grid.hex_metrics()
	out["globe"] = {"cells": n, "land": land, "water": water, "radius_m": g.grid.radius_m,
		"area_km2": 4.0 * PI * g.grid.radius_m * g.grid.radius_m / 1.0e6, "hex_metrics": m,
		"mean_junk_land": junk_sum / maxf(1.0, land), "survey_city_cells": city, "survey_cities": g.planet.cities.size(),
		"biomes_land": biomes, "hub_min_spacing_m": g.hub_spacing(true), "hub_mean_spacing_m": g.hub_spacing(false)}
	print("[world-probe] globe: %s" % str(out["globe"]))


# --- One hub site ----------------------------------------------------------------------------

func _hub(i: int) -> Dictionary:
	var sm: SiteManager = g.site_manager
	var s: Dictionary = g.sites[i]
	var p: SitePrefab = sm.build_hub(i, true)
	if not p.is_built:
		await p.rebuilt
	await get_tree().process_frame
	var d: Dictionary = {"index": i, "pad_flat_m": float(s["flat"]), "pad_blend_m": float(s["blend"]), "site_id": p.site_id}
	var dir: Vector3 = (s["dir"] as Vector3).normalized()
	var xz: Vector2 = _local_from_start(dir)
	d["from_start_xz"] = [snappedf(xz.x, 1.0), snappedf(xz.y, 1.0)]
	d["from_start_m"] = snappedf(dir.angle_to((g.sites[0]["dir"] as Vector3).normalized()) * g.grid.radius_m, 1.0)
	var near: float = INF
	for o: Dictionary in g.sites:
		if int(o["index"]) != i:
			near = minf(near, dir.angle_to((o["dir"] as Vector3).normalized()) * g.grid.radius_m)
	d["nearest_hub_m"] = snappedf(near, 1.0)
	d["biome"] = PlanetData.BIOMES[g.planet.biome[int(s["cell"])]]
	var town: TownSite = _find_town(p)
	if town:
		d.merge(_town(town, s["transform"]))
	d["bands"] = _bands(int(s["cell"]))
	d["wreck_landmarks_in_sampled_cells"] = _landmarks_in(int(s["cell"]))
	print("[world-probe] hub %d: %s" % [i, str(d)])
	if i > 0:
		sm.free_hub(i)
		await get_tree().process_frame
	return d


func _find_town(n: Node) -> TownSite:
	if n is TownSite:
		return n as TownSite
	for c: Node in n.get_children():
		var t: TownSite = _find_town(c)
		if t:
			return t
	return null


func _town(town: TownSite, site_xf: Transform3D) -> Dictionary:
	var d: Dictionary = {"kind": str(town.get("kind")), "town_r_m": town.town_r}
	var lay: CityLayout = town.layout
	var types: Dictionary = {}
	var floors: Array[int] = []
	var ruined: int = 0
	var factory: int = 0
	var reach: float = 0.0
	for key: Vector2i in lay.blocks:
		var b: Dictionary = lay.blocks[key]
		var tn: String = str(CityLayout.Block.keys()[int(b["type"])])
		types[tn] = int(types.get(tn, 0)) + 1
		var r: Rect2 = b["rect"]
		reach = maxf(reach, maxf(maxf(absf(r.position.x), absf(r.end.x)), maxf(absf(r.position.y), absf(r.end.y))))
		for bd: Dictionary in b.get("buildings", []):
			floors.append(int(bd.get("floors", 0)))
			ruined += 1 if bool(bd.get("ruined", false)) else 0
			factory += 1 if str(bd.get("style", "")) == "factory" else 0
			var br: Rect2 = bd["rect"]
			_hub_buildings.append(site_xf * Vector3(br.get_center().x, 0.0, br.get_center().y))
	floors.sort()
	d["blocks"] = types
	d["block_count"] = lay.blocks.size()
	d["street_grid_reach_m"] = snappedf(reach, 1.0)
	d["pad_buildings"] = floors.size()
	d["pad_floors"] = _spread(floors)
	d["pad_ruined"] = ruined
	d["pad_factory_style"] = factory
	var fur: Variant = town.get("furniture")
	if fur is Node:
		var counts: Dictionary = (fur as Node).get("counts")
		var total: int = 0
		for k: String in counts:
			total += int(counts[k])
		d["furniture"] = counts
		d["furniture_total"] = total
	var osk: Variant = town.get("outskirts")
	if osk is Node:
		d["outskirts"] = (osk as Node).get("stats")
		for e: Array in (osk as Node).get("foot"):
			var fr: Transform3D = e[0]
			var rr: Rect2 = e[1]
			_hub_buildings.append(fr * Vector3(rr.get_center().x, 0.0, rr.get_center().y))
	var dr: Variant = town.get("dressing")
	if dr is Node:
		d["landmark_prop"] = str((dr as Node).get("_lm_kind"))
	d["district_name"] = str(town.get("district_name"))
	d["mesh_instances"] = town.find_children("*", "MeshInstance3D", true, false).size()
	d["multimeshes"] = town.find_children("*", "MultiMeshInstance3D", true, false).size()
	d["lights"] = town.find_children("*", "Light3D", true, false).size()
	d["labels"] = town.find_children("*", "Label3D", true, false).size()
	return d


static func _spread(a: Array[int]) -> Dictionary:
	if a.is_empty():
		return {}
	@warning_ignore("integer_division")
	return {"min": a[0], "median": a[a.size() / 2], "max": a[a.size() - 1]}


## Rings of cells round `cell`: [ring index] -> cells.
func _rings(cell: int, rings: int) -> Array:
	var res: Array = [PackedInt32Array([cell])]
	var seen: Dictionary = {cell: true}
	for r: int in rings:
		var nxt := PackedInt32Array()
		for q: int in res[r]:
			for o: int in g.grid.neighbors(q):
				if not seen.has(o):
					seen[o] = true
					nxt.append(o)
		res.append(nxt)
	return res


var _sampled: PackedInt32Array


func _bands(cell: int) -> Array:
	var rings: Array = _rings(cell, 18)
	var res: Array = []
	var sample_n: int = int(DevHooks.get_f("probe-sample", 70.0))
	_sampled = PackedInt32Array()
	for band: Array in BANDS:
		var all := PackedInt32Array()
		for r: int in range(int(band[0]), int(band[1]) + 1):
			all.append_array(rings[r])
		var water: int = 0
		var hub: int = 0
		var land := PackedInt32Array()
		for c: int in all:
			if g.cells.state[c] == OrbitPlanet.WATER:
				water += 1
			elif g.cells.has_flag(c, SphereCells.F_HUB):
				hub += 1
			else:
				land.append(c)
		var pick: PackedInt32Array = _sample(land, sample_n if int(band[0]) > 1 else 126)
		var pieces: int = 0
		var lo: int = 1 << 30
		var hi: int = 0
		for c: int in pick:
			g.field.materialize(c)
			var k: int = g.field.pieces_in(c).size()
			pieces += k
			lo = mini(lo, k)
			hi = maxi(hi, k)
		_sampled.append_array(pick)
		res.append({"rings": band, "cells": all.size(), "water_share": float(water) / maxf(1.0, all.size()),
			"hub_ground_share": float(hub) / maxf(1.0, all.size()), "junk_cells_sampled": pick.size(),
			"pieces_per_cell": float(pieces) / maxf(1.0, pick.size()), "pieces_min": lo if not pick.is_empty() else 0, "pieces_max": hi})
	return res


func _sample(a: PackedInt32Array, k: int) -> PackedInt32Array:
	if a.size() <= k:
		return a
	var idx: Array = Array(a)
	var res := PackedInt32Array()
	for j: int in k:
		var at: int = _rng.randi_range(j, idx.size() - 1)
		var t: int = idx[j]
		idx[j] = idx[at]
		idx[at] = t
		res.append(int(idx[j]))
	return res


func _landmarks_in(_cell: int) -> Dictionary:
	var by: Dictionary = {}
	var set: Dictionary = {}
	for c: int in _sampled:
		set[c] = true
	for lm: Dictionary in g.field.landmarks:
		if set.has(int(lm["hex"])):
			by[str(lm["model"])] = int(by.get(str(lm["model"]), 0)) + 1
	return by


## Metres east (x) and south (z) of the start cell along the ground: what --orbit-spawn=x,z takes.
func _local_from_start(dir: Vector3) -> Vector2:
	var up: Vector3 = g.grid.centers[g.start_cell()]
	var f: Basis = SphereGrid.frame(up)
	var a: float = up.angle_to(dir)
	if a < 0.00001:
		return Vector2.ZERO
	var t: Vector3 = (dir - up * up.dot(dir)).normalized()
	return Vector2(t.dot(f.x), t.dot(f.z)) * a * g.grid.radius_m


# --- The land between the sites ---------------------------------------------------------------

var _land_node: Node
var _zone_of: Dictionary = {}


func _land() -> void:
	var hubs: Array[Vector3] = []
	for s: Dictionary in g.sites:
		hubs.append((s["dir"] as Vector3).normalized())
	_land_node = SiteBuilders.build_surroundings(g.planet_id, {"parent": self, "grid": g.grid, "terrain": g.terrain, "cells": g.cells,
		"hubs": hubs, "seed": g.seed_value, "keep_out": g.yard_keep_out(), "focus": null})
	var res: Dictionary = {"has_surroundings": _land_node != null}
	var n: int = g.grid.cell_count()
	var cls: Dictionary = {"water": 0, "site_pad": 0, "town_outskirts": 0, "between": 0}
	var zones: Dictionary = {"open": 0, "suburb": 0, "industrial": 0}
	var zone_b: Dictionary = {"open": 0, "suburb": 0, "industrial": 0}
	var zone_p: Dictionary = {"open": 0, "suburb": 0, "industrial": 0}
	var arch: Dictionary = {}
	var props: Dictionary = {}
	var empty: int = 0
	var by_zone_cells: Dictionary = {"open": [], "suburb": [], "industrial": []}
	var clear_m: float = float(_land_node.get("HUB_CLEAR_M")) if _land_node else 345.0
	var arch_tbl: Array = _land_node.get("ARCH") if _land_node else []
	var prop_tbl: Array = Array(_land_node.get("PROPS")) if _land_node else []
	var shore_between: int = 0
	for c: int in n:
		if g.cells.state[c] == OrbitPlanet.WATER:
			cls["water"] += 1
			continue
		if g.cells.has_flag(c, SphereCells.F_SITE):
			cls["site_pad"] += 1
			continue
		var dir: Vector3 = g.grid.centers[c]
		var hm: float = INF
		for h: Vector3 in hubs:
			hm = minf(hm, h.angle_to(dir) * g.grid.radius_m)
		if hm < clear_m:
			cls["town_outskirts"] += 1
			continue
		cls["between"] += 1
		if _land_node == null:
			continue
		var zn: String = _zone(dir, hm, clear_m)
		_zone_of[c] = zn
		zones[zn] += 1
		(by_zone_cells[zn] as Array).append(c)
		var lst: Array = _land_node.call("_decide", c)
		_land_node.call("_register", c, lst)
		if lst.is_empty():
			empty += 1
			for o: int in g.grid.neighbors(c):
				if g.cells.state[o] == OrbitPlanet.WATER:
					shore_between += 1
					break
		for e: Array in lst:
			var k: int = int(e[0])
			if k >= 0:
				var nm: String = str(arch_tbl[k][0])
				arch[nm] = int(arch.get(nm, 0)) + 1
				zone_b[zn] += 1
				_land_buildings.append((e[1] as Transform3D).origin)
			else:
				var pn: String = str(prop_tbl[-1 - k])
				props[pn] = int(props.get(pn, 0)) + 1
				zone_p[zn] += 1
	res["cells"] = cls
	res["zones"] = zones
	res["zone_buildings"] = zone_b
	res["zone_props"] = zone_p
	res["archetypes"] = arch
	res["props"] = props
	res["between_cells_with_nothing"] = empty
	res["between_empty_shore_cells"] = shore_between
	var junk: Dictionary = {}
	for zn: String in by_zone_cells:
		var pick: PackedInt32Array = _sample(PackedInt32Array(by_zone_cells[zn] as Array), 150)
		var pieces: int = 0
		for c: int in pick:
			g.field.materialize(c)
			pieces += g.field.pieces_in(c).size()
		junk[zn] = float(pieces) / maxf(1.0, pick.size())
	res["junk_pieces_per_cell"] = junk
	res["wreck_landmarks_total_materialized"] = g.field.landmarks.size()
	res["cells_materialized"] = _count_materialized()
	out["land"] = res
	print("[world-probe] land: %s" % str(res))


func _count_materialized() -> int:
	var k: int = 0
	for b: int in g.field.materialized:
		k += b
	return k


## The surroundings' zone for a cell (the same low-frequency noise the surroundings node holds:
## read here, not changed). open / suburb / industrial.
func _zone(dir: Vector3, hub_m: float, clear_m: float) -> String:
	var zn: FastNoiseLite = _land_node.get("_zone")
	var p: Vector3 = dir * g.terrain.R
	var z: float = zn.get_noise_3dv(p) + clampf(1.0 - (hub_m - clear_m) / 400.0, 0.0, 1.0) * 0.35
	if z < -0.05:
		return "open"
	return "industrial" if zn.get_noise_3dv(p * 1.7 + Vector3(300, 0, 0)) > 0.25 else "suburb"


# --- Walking out from the start ---------------------------------------------------------------

func _walks() -> void:
	var res: Dictionary = {}
	var c0: int = g.start_cell()
	for nm: String in WALK_DIRS:
		var v: Vector2 = WALK_DIRS[nm]
		var rows: Array = []
		for m: float in WALKS_M:
			var dir: Vector3 = g.terrain.local_to_dir(c0, v.x * m, v.y * m)
			var c: int = g.grid.cell_at(dir)
			var pos: Vector3 = dir * g.terrain.R
			var row: Dictionary = {"m": m, "spawn": "%d,%d" % [int(v.x * m), int(v.y * m)], "water": g.cells.state[c] == OrbitPlanet.WATER,
				"on_pad": g.cells.has_flag(c, SphereCells.F_SITE), "zone": str(_zone_of.get(c, "town"))}
			for rr: float in [60.0, 150.0]:
				row["town_buildings_%dm" % int(rr)] = _within(_hub_buildings, pos, rr)
				row["land_buildings_%dm" % int(rr)] = _within(_land_buildings, pos, rr)
			var wet: int = 0
			var around: PackedInt32Array = g.grid.cells_within(dir, 150.0, c)
			for o: int in around:
				wet += 1 if g.cells.state[o] == OrbitPlanet.WATER else 0
			row["water_share_150m"] = float(wet) / maxf(1.0, around.size())
			rows.append(row)
		res[nm] = rows
	out["walks"] = res
	out["render_points"] = _render_points()
	print("[world-probe] walks: %s" % str(res))


static func _within(pts: Array, pos: Vector3, r: float) -> int:
	var k: int = 0
	for p: Vector3 in pts:
		if p.distance_to(pos) <= r:
			k += 1
	return k


## Spots within 1.6 km of the start for renders of the land between: per zone, the cell with the
## most buildings within 100 m (open: the fewest) and no water within 150 m, as --orbit-spawn x,z.
func _render_points() -> Dictionary:
	var res: Dictionary = {}
	var up: Vector3 = g.grid.centers[g.start_cell()]
	var best: Dictionary = {}
	var k: int = 0
	for c: int in _zone_of:
		k += 1
		if k % 7 != 0:
			continue
		var dir: Vector3 = g.grid.centers[c]
		var m: float = up.angle_to(dir) * g.grid.radius_m
		if m > 1600.0 or m < 500.0:
			continue
		var dry: bool = true
		for o: int in g.grid.cells_within(dir, 150.0, c):
			if g.cells.state[o] == OrbitPlanet.WATER:
				dry = false
				break
		if not dry:
			continue
		var zn: String = _zone_of[c]
		var nb: int = _within(_land_buildings, dir * g.terrain.R, 100.0)
		var score: int = -nb if zn == "open" else nb
		if not best.has(zn) or score > int(best[zn][0]):
			var xz: Vector2 = _local_from_start(dir)
			best[zn] = [score, {"spawn": "%d,%d" % [int(xz.x), int(xz.y)], "from_start_m": snappedf(m, 1.0), "land_buildings_100m": nb}]
	for zn: String in best:
		res[zn] = best[zn][1]
	print("[world-probe] render points: %s" % str(res))
	return res
