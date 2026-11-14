class_name ColliderAudit
extends Node
## [world2] Lists solid-looking props that nothing physical stands behind (Lumi, robots and bales
## would pass through them).
## Run: godot --headless --path . res://tools/collider_audit.tscn -- --fresh [--future=5] [--audit-all]
## Exit code 1 when a solid prop has no collider. tests/test_collider_audit.gd runs scan() on the
## start district's city and dressing.
##
## How: every visible GeometryInstance3D in the play area is checked in Lumi's body band (0.2 to
## 1.2 m over the local ground). Single props (a MeshInstance3D, each MultiMesh instance) by their
## AABB; merged geometry (street dressing batches, the yard kit, fence runs) by rasterizing its
## triangles into 0.5 m cells. A prop counts as solid when it is at least 0.5 m tall, stands on
## the ground and is not paper-thin; tiny clutter (paint, puddles, weeds, litter, junk, plants,
## animals, bales, robots, Lumi) is skipped. A solid prop or cell is covered when a box query over
## it touches anything on PhysLayers.SOLID (buildings count: a shopfront kit piece sits in the wall).

const BAND_LO: float = 0.2
const BAND_HI: float = 1.2
const MIN_H: float = 0.5
const MIN_W: float = 0.1
const CELL: float = 0.5
const MERGED: float = 1.5  # an AABB wider than this (merged geometry, arches, walls) is rasterized
## Node classes / names whose subtrees are never props.
const SKIP_CLASSES: Array[String] = ["Patch", "Robot", "JunkCube", "LitterView", "Fauna",
	"Garden", "FarJunk", "PickupFx", "GlobeView", "HUD", "PhotoMode", "SkyDirector", "Vfx"]
const SKIP_NAMES: Array[String] = ["Ground", "Cubes", "Fleet", "Skyline", "Fauna", "Garden", "Plants", "Sky", "Weather"]
## Mesh / node name fragments that are clutter, light or cloth (never solid).
const CLUTTER: Array[String] = ["weed", "puddle", "paint", "litter", "flower", "grass", "moss", "bulb", "pennant", "cloth",
	"tube", "glow", "neon", "label", "decal", "seam", "orb", "beam", "drone", "flag", "mote", "spark", "steam", "dust",
	"manhole", "twig", "sprout", "butterfl", "deadplant", "pots"]

var _fails: int = 0


static func _class_of(n: Node) -> String:
	var s: Script = n.get_script() as Script
	while s:
		if s.get_global_name() != "":
			return s.get_global_name()
		s = s.get_base_script()
	return n.get_class()


## "Owner" for the report: the nearest ancestor with a script class, then the node name.
static func _owner(n: Node) -> String:
	var a: Node = n.get_parent()
	while a and _class_of(a) == a.get_class():
		a = a.get_parent()
	return "%s(%s)/%s/%s" % [_class_of(a) if a else "?", String(a.name) if a else "", String(n.get_parent().name), String(n.name)]


static func _skip(n: Node) -> bool:
	if n.name in SKIP_NAMES or String(n.name).begins_with("Junk_"):
		return true
	if n.has_meta("pile"):
		return true
	var c: String = _class_of(n)
	return c in SKIP_CLASSES


static func _clutter(n: Node, mesh: Mesh) -> bool:
	var nm: String = (String(n.name) + " " + (mesh.resource_name if mesh else "") + " " + (mesh.resource_path.get_file() if mesh else "")).to_lower()
	for k: String in CLUTTER:
		if k in nm:
			return true
	return n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh


static func _ground(layout: CityLayout, x: float, z: float) -> float:
	return layout.height_at(x, z) if layout else 0.0


static func _in_building(layout: CityLayout, x: float, z: float) -> bool:
	if layout == null:
		return false
	for o: Vector2 in [Vector2.ZERO, Vector2(0.6, 0), Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0, -0.6)]:
		if layout.surface_at(x + o.x, z + o.y) == CityLayout.Surface.BUILDING:
			return true
	return false


static func _covered(space: PhysicsDirectSpaceState3D, center: Vector3, half: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = (half * 2.0).max(Vector3(0.04, 0.04, 0.04))
	q.shape = bs
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = PhysLayers.SOLID
	q.collide_with_areas = false
	return not space.intersect_shape(q, 1).is_empty()


## One solid-prop record: {where, size, owner}. Returns the leaks (props with no collider).
static func scan(root: Node, space: PhysicsDirectSpaceState3D, layout: CityLayout, radius: float, verbose: bool = false) -> Array:
	var leaks: Array = []
	var stack: Array[Node] = [root]
	var checked: int = 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != root and _skip(n):
			continue
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		for c: Node in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null or _clutter(mi, mi.mesh) or PropColliders._see_through(mi):
				continue
			checked += _check_xf(mi, mi.mesh, mi.global_transform, space, layout, radius, leaks)
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			var mm: MultiMesh = mmi.multimesh
			if mm == null or mm.mesh == null or _clutter(mmi, mm.mesh):
				continue
			var cnt: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			# Headless (dummy renderer) can't read MultiMesh transforms back: builders keep a CPU
			# copy in the "inst_xf" meta. Without it (and without a renderer) the MMI is skipped.
			var xfs: Array = mmi.get_meta("inst_xf", [])
			if xfs.is_empty() and DisplayServer.get_name() == "headless":
				if verbose and cnt > 0:
					print("[audit] (unreadable multimesh skipped: %s)" % str(mmi.get_path()))
				continue
			for i: int in mini(cnt, xfs.size()) if not xfs.is_empty() else cnt:
				var ix: Transform3D = xfs[i] if not xfs.is_empty() else mm.get_instance_transform(i)
				checked += _check_xf(mmi, mm.mesh, mmi.global_transform * ix, space, layout, radius, leaks)
	if verbose:
		print("[audit] checked %d solid props/cells" % checked)
	return leaks


static func _check_xf(n: Node, mesh: Mesh, xf: Transform3D, space: PhysicsDirectSpaceState3D, layout: CityLayout, radius: float, leaks: Array) -> int:
	if xf.basis.determinant() == 0.0:
		return 0
	var ab: AABB = xf * mesh.get_aabb()
	var c: Vector3 = ab.get_center()
	if Vector2(c.x, c.z).length() > radius + maxf(ab.size.x, ab.size.z):
		return 0
	if ab.size.x > MERGED or ab.size.z > MERGED:
		return _check_merged(n, mesh, xf, space, layout, radius, leaks)
	var g: float = _ground(layout, c.x, c.z)
	if Vector2(c.x, c.z).length() > radius:
		return 0
	if ab.position.y > g + 0.6 or ab.end.y < g + MIN_H or ab.size.y < 0.3 or minf(ab.size.x, ab.size.z) < MIN_W * 0.5 or maxf(ab.size.x, ab.size.z) < MIN_W:
		return 0
	if _in_building(layout, c.x, c.z):
		return 0
	var lo: float = maxf(ab.position.y, g + BAND_LO)
	var hi: float = minf(ab.end.y, g + BAND_HI)
	if hi - lo < 0.15:
		return 0
	var half := Vector3(ab.size.x * 0.4, (hi - lo) * 0.5, ab.size.z * 0.4)
	if not _covered(space, Vector3(c.x, (lo + hi) * 0.5, c.z), half):
		leaks.append({"owner": _owner(n), "mesh": mesh.resource_path.get_file() if mesh.resource_path != "" else mesh.resource_name,
			"at": Vector3(c.x, g, c.z).snapped(Vector3.ONE * 0.1), "size": ab.size.snapped(Vector3.ONE * 0.05)})
	return 1


## Merged geometry: rasterize the triangles that reach into the body band into 0.5 m cells; each
## cell column whose geometry spans >= MIN_H must be covered.
static func _check_merged(n: Node, mesh: Mesh, xf: Transform3D, space: PhysicsDirectSpaceState3D, layout: CityLayout, radius: float, leaks: Array) -> int:
	var faces: PackedVector3Array = mesh.get_faces()
	var cells: Dictionary = {}  # Vector2i -> Vector2(min y, max y) above ground
	for i: int in range(0, faces.size(), 3):
		var stack: Array = [[xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]]]
		while not stack.is_empty():
			var tri: Array = stack.pop_back()
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var cc: Vector3 = tri[2]
			var mn: Vector3 = a.min(b).min(cc)
			var mx: Vector3 = a.max(b).max(cc)
			if Vector2((mn.x + mx.x) * 0.5, (mn.z + mx.z) * 0.5).length() > radius:
				continue
			var g: float = _ground(layout, (mn.x + mx.x) * 0.5, (mn.z + mx.z) * 0.5)
			if mx.y < g + BAND_LO or mn.y > g + BAND_HI:
				continue
			if mx.x - mn.x > 12.0 or mx.z - mn.z > 12.0:
				continue  # a huge flat tri (slab, wall face) is never a prop
			var e_max: float = maxf((b - a).length(), maxf((cc - b).length(), (a - cc).length()))
			if e_max > 0.0 and (b - a).cross(cc - a).length() / e_max < 0.025:
				continue  # a sliver of a wire or cable (thinner than ~2.5 cm): never solid
			if e_max > CELL and mx.y - mn.y > 0.25 and (mx.x - mn.x > CELL or mx.z - mn.z > CELL):
				# Sloped or upright and wider than a cell: split, so each cell sees only the height
				# the surface has over it (a slumped roof is not a wall).
				var ab: Vector3 = (a + b) * 0.5
				var bc: Vector3 = (b + cc) * 0.5
				var ca: Vector3 = (cc + a) * 0.5
				stack.append_array([[a, ab, ca], [ab, b, bc], [ca, bc, cc], [ab, bc, ca]])
				continue
			var big: bool = mx.x - mn.x > CELL or mx.z - mn.z > CELL
			for cx: int in range(floori(mn.x / CELL), floori(mx.x / CELL) + 1):
				for cz: int in range(floori(mn.z / CELL), floori(mx.z / CELL) + 1):
					if big and _tri_dist(Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(cc.x, cc.z)) > CELL * 0.71:
						continue  # the cell is in the triangle's bounds but not under it (a diagonal wall)
					var k := Vector2i(cx, cz)
					var v: Vector2 = cells.get(k, Vector2(INF, -INF))
					cells[k] = Vector2(minf(v.x, mn.y - g), maxf(v.y, mx.y - g))
	var n_checked: int = 0
	var bad: Array = []
	if DevHooks.has("audit-debug"):
		print("[audit] merged %s: %d faces, %d cells" % [str(n.get_path()), faces.size() / 3, cells.size()])
	for k: Vector2i in cells:
		var v: Vector2 = cells[k]
		if v.y - maxf(v.x, 0.0) < MIN_H or v.x > 0.6:
			continue
		var cx: float = (k.x + 0.5) * CELL
		var cz: float = (k.y + 0.5) * CELL
		if _in_building(layout, cx, cz):
			continue
		n_checked += 1
		var g: float = _ground(layout, cx, cz)
		if not _covered(space, Vector3(cx, g + (BAND_LO + BAND_HI) * 0.5, cz), Vector3(CELL * 0.5, (BAND_HI - BAND_LO) * 0.5, CELL * 0.5)):
			bad.append(Vector3(cx, g, cz))
			if DevHooks.has("audit-debug"):
				print("[audit]     bad cell %s y %.2f..%.2f" % [str(Vector2(cx, cz)), v.x, v.y])
	if DevHooks.has("audit-debug") and n_checked > 0:
		print("[audit]   checked %d bad %d" % [n_checked, bad.size()])
	# Fringe: a bad cell next to a covered cell of the same mesh is the edge of a collider a little
	# smaller than its prop (colliders are shrunk ~8%), not a missing one.
	var bad_k: Dictionary = {}
	for p: Vector3 in bad:
		bad_k[Vector2i(floori(p.x / CELL), floori(p.z / CELL))] = p
	var seen: Dictionary = {}
	for k0: Vector2i in bad_k:
		var fringe: bool = false
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var nk: Vector2i = k0 + o
			if cells.has(nk) and not bad_k.has(nk) and (cells[nk] as Vector2).y - maxf((cells[nk] as Vector2).x, 0.0) >= MIN_H:
				fringe = true
				break
		if not fringe:
			seen[k0] = bad_k[k0]
	# One leak per connected group of bad cells.
	var done: Dictionary = {}
	for k: Vector2i in seen:
		if done.has(k):
			continue
		var group: Array = [k]
		done[k] = true
		var qi: int = 0
		while qi < group.size():
			var cur: Vector2i = group[qi]
			qi += 1
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var nk: Vector2i = cur + o
				if seen.has(nk) and not done.has(nk):
					done[nk] = true
					group.append(nk)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for g2: Vector2i in group:
			mn = mn.min(Vector2(g2) * CELL)
			mx = mx.max(Vector2(g2) * CELL + Vector2(CELL, CELL))
		var ctr: Vector2 = (mn + mx) * 0.5
		leaks.append({"owner": _owner(n), "mesh": "merged(%d cells)" % group.size(),
			"at": Vector3(ctr.x, 0, ctr.y).snapped(Vector3.ONE * 0.1), "size": Vector3(mx.x - mn.x, 0, mx.y - mn.y)})
	return n_checked


## 2D distance from p to triangle abc (0 inside).
static func _tri_dist(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d1: float = (p - a).cross(b - a)
	var d2: float = (p - b).cross(c - b)
	var d3: float = (p - c).cross(a - c)
	if (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0):
		if absf((b - a).cross(c - a)) > 1e-6:
			return 0.0
	return minf(_seg_dist(p, a, b), minf(_seg_dist(p, b, c), _seg_dist(p, c, a)))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/slice.tscn")
	var s: Node = packed.instantiate()
	get_tree().root.add_child(s)
	for i: int in 30:
		await get_tree().physics_frame
	var field: HexField = s.get("field")
	var layout: CityLayout = s.get("layout")
	var radius: float = float(field.radius) * field.hex_size * 1.75 + 6.0 if field else 60.0
	if DevHooks.has("audit-radius"):
		radius = DevHooks.get_f("audit-radius", radius)
	var leaks: Array = scan(s, (s as Node3D).get_world_3d().direct_space_state, layout, radius, true)
	var by_owner: Dictionary = {}
	for l: Dictionary in leaks:
		var key: String = "%s  %s" % [l["owner"], l["mesh"]]
		if not by_owner.has(key):
			by_owner[key] = []
		(by_owner[key] as Array).append(l)
	for key: String in by_owner:
		var arr: Array = by_owner[key]
		print("[audit] NO COLLIDER x%d  %s  e.g. at %s size %s" % [arr.size(), key, str(arr[0]["at"]), str(arr[0]["size"])])
		if DevHooks.has("audit-all"):
			for l: Dictionary in arr.slice(1):
				print("[audit]     at %s size %s" % [str(l["at"]), str(l["size"])])
	print("[audit] solid props without colliders: %d (radius %.0f m, hub level %d)" % [leaks.size(), radius, int(GameState.world.get("hub_level", 1))])
	_fails = leaks.size()
	get_tree().quit(1 if _fails > 0 else 0)
