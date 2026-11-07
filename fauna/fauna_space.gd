class_name FaunaSpace
extends RefCounted
## [fauna2] Keeps animals apart and out of the street furniture. Animals have no colliders, so
## every place one stands (spawn spots, wander and flee targets) is checked here:
##  - against the other animals: a body radius per species, so no two overlap (no duck on a deer);
##  - against props: an occupancy grid stamped from the world's prop-sized geometry (lamp posts,
##    hydrants, utility boxes, payphones, crates, pots, barrels, benches...), built by scan();
##  - against fences (chain-link around parking / vacant lots), the hub yard, and (in Fauna)
##    anything with a collider via a physics shape query, plus outposts and buildings.
## Pure data where it can be, unit-tested in tests/test_fauna_space.gd.

const CELL: float = 0.5
## Footprint and height bounds for "a prop an animal could stand inside" (metres).
const PROP_MAX_SIDE: float = 4.5
const PROP_MIN_H: float = 0.18
const PROP_MAX_BOTTOM: float = 0.8
## Node names (prefixes) that are never obstacles: ground cover, decals, effects, animals.
const SKIP_PREFIX: Array[String] = ["Weeds", "Puddles", "Flags", "Fauna", "Grass", "Decal", "Cracks", "Garden", "Junk", "Piece",
	"Litter", "Skyline", "Future_line", "Future_orb", "Future_sign", "Future_beam", "Future_pane", "FutureMover"]

var cells: Dictionary = {}  # Vector2i -> 1
var stamped: int = 0
var by_node: Dictionary = {}  # node name -> props stamped (debug)


static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


## Body radius (metres, before the per-animal size) used for spacing.
static func radius_of(sp: String, kind: String) -> float:
	match sp:
		"deer": return 0.55
		"seal": return 0.5
		"heron", "crane": return 0.35
		"fox", "arctic_fox": return 0.35
		"fennec": return 0.28
		"cat": return 0.28
		"duck", "turtle": return 0.28
		"rabbit": return 0.18
		"gull": return 0.22
		"pigeon": return 0.14
		"sparrow", "songbird", "frog", "lizard", "rat": return 0.1
	match kind:
		"bird": return 0.14
		"quad": return 0.35
	return 0.25


## Stamps an axis-aligned rect (world xz) as blocked.
func add_rect(r: Rect2) -> void:
	var a: Vector2i = cell_of(r.position.x, r.position.y)
	var b: Vector2i = cell_of(r.end.x, r.end.y)
	for x: int in range(a.x, b.x + 1):
		for z: int in range(a.y, b.y + 1):
			var k := Vector2i(x, z)
			if not cells.has(k):
				cells[k] = 1
				stamped += 1


func add_disc(c: Vector2, r: float) -> void:
	add_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))


## Is any prop within r of p (xz)? Cells are tested by their nearest point to p.
func blocked(p: Vector3, r: float) -> bool:
	if cells.is_empty():
		return false
	var a: Vector2i = cell_of(p.x - r, p.z - r)
	var b: Vector2i = cell_of(p.x + r, p.z + r)
	var r2: float = r * r
	for x: int in range(a.x, b.x + 1):
		for z: int in range(a.y, b.y + 1):
			if not cells.has(Vector2i(x, z)):
				continue
			var nx: float = clampf(p.x, x * CELL, (x + 1) * CELL)
			var nz: float = clampf(p.z, z * CELL, (z + 1) * CELL)
			if (nx - p.x) * (nx - p.x) + (nz - p.z) * (nz - p.z) <= r2:
				return true
	return false


## Would an animal of radius r at p overlap any of others (Array of Vector4(x, z, radius, _))?
static func spaced_ok(p: Vector3, r: float, others: Array) -> bool:
	for o: Vector4 in others:
		var dx: float = o.x - p.x
		var dz: float = o.y - p.z
		var m: float = r + o.z
		if dx * dx + dz * dz < m * m:
			return false
	return true


## Is the world AABB a prop an animal could stand inside (not ground, not a building, not a wire)?
static func prop_sized(bb: AABB, ground: float = 0.0) -> bool:
	if bb.size.x > PROP_MAX_SIDE or bb.size.z > PROP_MAX_SIDE:
		return false
	if bb.size.y < PROP_MIN_H:
		return false
	return bb.position.y - ground < PROP_MAX_BOTTOM and bb.end.y - ground > 0.25


## Stamps every prop-sized mesh / multimesh instance under root (skipping `skip` subtrees and
## ground-cover names). Returns the number of props stamped.
func scan(root: Node, skip: Array = []) -> int:
	var n: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node in skip:
			continue
		if node is Node3D and not (node as Node3D).visible:
			continue
		if node is CanvasItem or node is CanvasLayer:
			continue
		var nm: String = str(node.name)
		var skipped: bool = false
		for pre: String in SKIP_PREFIX:
			if nm.begins_with(pre):
				skipped = true
				break
		if skipped:
			continue
		if node is MultiMeshInstance3D:
			var mmi := node as MultiMeshInstance3D
			var mm: MultiMesh = mmi.multimesh
			if mm and mm.mesh and mm.transform_format == MultiMesh.TRANSFORM_3D:
				var aabb: AABB = mm.mesh.get_aabb()
				var cnt: int = mm.instance_count if mm.visible_instance_count < 0 else mini(mm.visible_instance_count, mm.instance_count)
				var gx: Transform3D = mmi.global_transform
				for i: int in cnt:
					var bb: AABB = (gx * mm.get_instance_transform(i)) * aabb
					if prop_sized(bb):
						_stamp_bb(bb)
						n += 1
						by_node[str(node.get_parent().name) + "/" + nm.left(18)] = int(by_node.get(str(node.get_parent().name) + "/" + nm.left(18), 0)) + 1
		elif node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh:
				var bb2: AABB = mi.global_transform * mi.mesh.get_aabb()
				if prop_sized(bb2):
					_stamp_bb(bb2)
					n += 1
					by_node[str(node.get_parent().name) + "/" + nm.left(18)] = int(by_node.get(str(node.get_parent().name) + "/" + nm.left(18), 0)) + 1
		for c: Node in node.get_children():
			stack.append(c)
	return n


func _stamp_bb(bb: AABB) -> void:
	# A thin pole's AABB can include an overhanging arm: stamp the footprint, shrunk a little.
	var r := Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z)
	add_rect(r.grow(-minf(0.1, minf(r.size.x, r.size.y) * 0.25)))


## Fences: the chain-link runs round parking and vacant lots in city districts (CityView). True
## when p keeps at least margin from every fence line and is not in the hub yard (unless yard_ok).
static func layout_ok(lay: CityLayout, p: Vector3, margin: float, yard_ok: bool = false) -> bool:
	if lay == null:
		return true
	var s: int = lay.surface_at(p.x, p.z)
	if s == CityLayout.Surface.BUILDING:
		return false
	if s == CityLayout.Surface.YARD and not yard_ok:
		return false
	# Keep off the yard fence too (it stands just outside the yard square).
	if not yard_ok:
		var hub_c := Vector2.ZERO
		if not lay.wild:
			var hk: Vector2i = lay.block_key_at(p.x, p.z)
			if int(lay.blocks.get(hk, {}).get("type", -1)) == CityLayout.Block.HUB:
				hub_c = Vector2(hk) * CityLayout.PITCH
			else:
				hub_c = Vector2(INF, INF)
		if hub_c.x != INF:
			var hh: float = CityLayout.YARD_HALF + 0.15 + margin
			if absf(p.x - hub_c.x) < hh and absf(p.z - hub_c.y) < hh:
				return false
	if lay.wild:
		return true
	var b: Dictionary = lay.blocks.get(lay.block_key_at(p.x, p.z), {})
	if b.is_empty():
		return true
	var t: int = int(b["type"])
	if t != CityLayout.Block.PARKING and t != CityLayout.Block.VACANT:
		return true
	var r: Rect2 = b["rect"]
	var dx: float = minf(absf(p.x - r.position.x), absf(p.x - r.end.x))
	var dz: float = minf(absf(p.z - r.position.y), absf(p.z - r.end.y))
	var inside_x: bool = p.x > r.position.x - margin and p.x < r.end.x + margin
	var inside_z: bool = p.z > r.position.y - margin and p.z < r.end.y + margin
	if inside_z and dx < margin:
		return false
	if inside_x and dz < margin:
		return false
	return true
