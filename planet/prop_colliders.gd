class_name PropColliders
extends RefCounted
## [world2] Simple, shared colliders for placed props (street furniture, yard kit, fence runs,
## landmarks, decor). One StaticBody3D per owner on PhysLayers.PROP (solid for Lumi, robots and
## bales; ignored by the camera arm), boxes and cylinders only, and the shape resources are
## shared between every collider of the same (rounded) size, so a few hundred props cost a few
## dozen shape resources and one body per builder.
## Footprints are kept (XZ circles) so junk pieces that happen to spawn inside a solid prop can be
## nudged out (push_out_pieces), and for tools/collider_audit.gd.

static var _boxes: Dictionary = {}  # Vector3i (cm) -> BoxShape3D
static var _cyls: Dictionary = {}   # Vector2i (cm) -> CylinderShape3D


## A prop body under `parent`. top_level: the street dressing's level layers scale while they rise
## out of the slab, and a collider must not follow that (non-uniform scaled shapes).
static func body(parent: Node, nm: String = "PropBody") -> StaticBody3D:
	var old: Node = parent.get_node_or_null(NodePath(nm))
	if old:  # a rebuild: replace the previous colliders
		parent.remove_child(old)
		old.queue_free()
	var b := StaticBody3D.new()
	b.name = nm
	b.collision_layer = PhysLayers.PROP
	b.collision_mask = 0
	b.add_to_group("prop_body")
	parent.add_child(b)
	b.top_level = true
	b.global_transform = Transform3D.IDENTITY
	return b


static func box_shape(size: Vector3) -> BoxShape3D:
	var k := Vector3i(roundi(maxf(size.x, 0.05) * 20.0), roundi(maxf(size.y, 0.05) * 20.0), roundi(maxf(size.z, 0.05) * 20.0))
	if not _boxes.has(k):
		var s := BoxShape3D.new()
		s.size = Vector3(k) / 20.0
		_boxes[k] = s
	return _boxes[k]


static func cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var k := Vector2i(roundi(maxf(radius, 0.03) * 40.0), roundi(maxf(height, 0.05) * 20.0))
	if not _cyls.has(k):
		var s := CylinderShape3D.new()
		s.radius = k.x / 40.0
		s.height = k.y / 20.0
		_cyls[k] = s
	return _cyls[k]


## Box centred at xf.origin (world space), oriented by xf.basis (rotation only).
static func add_box(b: StaticBody3D, xf: Transform3D, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = box_shape(size)
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	b.add_child(cs)
	cs.set_meta("foot", Vector3(xf.origin.x, xf.origin.z, Vector2(size.x, size.z).length() * 0.5))
	return cs


## Upright cylinder standing on `base` (world space).
static func add_cyl(b: StaticBody3D, base: Vector3, radius: float, height: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = cyl_shape(radius, height)
	cs.position = base + Vector3(0, height * 0.5, 0)
	b.add_child(cs)
	cs.set_meta("foot", Vector3(base.x, base.z, radius))
	return cs


## Box between two ground points (a fence run, a wall): `thick` wide, `height` tall.
static func add_run(b: StaticBody3D, a: Vector3, c: Vector3, height: float, thick: float = 0.2) -> CollisionShape3D:
	var d: Vector3 = c - a
	d.y = 0.0
	var len_: float = d.length()
	if len_ < 0.05:
		return null
	var bas := Basis.looking_at(d / len_, Vector3.UP)
	var mid: Vector3 = (a + c) * 0.5
	return add_box(b, Transform3D(bas, Vector3(mid.x, minf(a.y, c.y) + height * 0.5, mid.z)), Vector3(thick, height, len_))


## Turns the collisions under `root` on or off (props in a hidden hub-level layer, an egg that has
## not surfaced yet, must not block). Any StaticBody3D: its own layer is remembered.
static func set_active(root: Node, on: bool) -> void:
	for n: Node in root.find_children("*", "StaticBody3D", true, false):
		var sb := n as StaticBody3D
		if not sb.has_meta("layer_on"):
			sb.set_meta("layer_on", sb.collision_layer if sb.collision_layer != 0 else PhysLayers.PROP)
		sb.collision_layer = int(sb.get_meta("layer_on")) if on else 0


## Fits oriented boxes to the solid-looking meshes under `root` (world space; call once the props
## stand where they will stay): each MeshInstance3D at least `min_h` tall, reaching down to within
## 0.6 m of `root`'s base and not paper-thin gets a box of its own bounds (x0.92). Merged meshes
## wider than `max_w` are skipped (a whole frame in one mesh would wall the area in): give those
## hand-placed colliders. Returns how many boxes were added.
static func fit(b: StaticBody3D, root: Node3D, min_h: float = 0.35, max_w: float = 3.5) -> int:
	var n: int = 0
	var base_y: float = root.global_position.y
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform
		if xf.basis.determinant() == 0.0:
			continue
		# Measured in root's frame: its +Y is up on the globe.
		var wab: AABB = (root.global_transform.affine_inverse() * xf) * ab
		wab.position.y += base_y
		if wab.size.y < min_h or wab.position.y > base_y + 0.6 or maxf(wab.size.x, wab.size.z) < 0.08:
			continue
		if wab.size.x > max_w or wab.size.z > max_w or _see_through(mi):
			continue
		var sc: Vector3 = xf.basis.get_scale().abs()
		var size: Vector3 = (ab.size * sc * 0.92).max(Vector3(0.08, 0.08, 0.08))
		add_box(b, Transform3D(xf.basis.orthonormalized(), xf * ab.get_center()), size)
		n += 1
	return n


## Colliders for merged geometry (a whole ruin or landing pad in one mesh): the triangles under
## `root` are rasterized into `cell`-metre columns (world space); every column whose geometry is at
## least `min_h` tall becomes solid from its lowest to its highest point (capped at 3 m), and
## columns with the same quantized span merge greedily into rectangles, so a structure costs a
## handful of boxes. Wire slivers and see-through materials are ignored. Returns the box count.
static func from_geometry(b: StaticBody3D, root: Node3D, min_h: float = 0.5, cell: float = 0.5, skip_prefix: Array = []) -> int:
	var cols: Dictionary = {}  # Vector2i -> Vector2(min y, max y)
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or _see_through(mi):
			continue
		var skip: bool = false
		var anc: Node = mi
		while anc and anc != root and not skip:
			for pre: String in skip_prefix:
				if String(anc.name).begins_with(pre):
					skip = true
			anc = anc.get_parent()
		if skip:
			continue
		var xf: Transform3D = mi.global_transform
		var faces: PackedVector3Array = mi.mesh.get_faces()
		for i: int in range(0, faces.size(), 3):
			var a: Vector3 = xf * faces[i]
			var bb: Vector3 = xf * faces[i + 1]
			var cc: Vector3 = xf * faces[i + 2]
			var e_max: float = maxf((bb - a).length(), maxf((cc - bb).length(), (a - cc).length()))
			if e_max <= 0.0 or (bb - a).cross(cc - a).length() / e_max < 0.025 or e_max > 40.0:
				continue
			var mn: Vector3 = a.min(bb).min(cc)
			var mx: Vector3 = a.max(bb).max(cc)
			for cx: int in range(floori(mn.x / cell), floori(mx.x / cell) + 1):
				for cz: int in range(floori(mn.z / cell), floori(mx.z / cell) + 1):
					var k := Vector2i(cx, cz)
					var v: Vector2 = cols.get(k, Vector2(INF, -INF))
					cols[k] = Vector2(minf(v.x, mn.y), maxf(v.y, mx.y))
	# Quantize spans and merge runs of equal spans into rectangles (rows first, then stack rows).
	var by_span: Dictionary = {}  # Vector2i(bottom, top in 0.25 m) -> {Vector2i: true}
	for k: Vector2i in cols:
		var v: Vector2 = cols[k]
		if v.y - v.x < min_h:
			continue
		var top: float = minf(v.y, v.x + 3.0)
		var key := Vector2i(floori(v.x * 4.0), ceili(top * 4.0))
		if not by_span.has(key):
			by_span[key] = {}
		(by_span[key] as Dictionary)[k] = true
	var n: int = 0
	for key: Vector2i in by_span:
		var set_: Dictionary = by_span[key]
		var keys: Array = set_.keys()
		keys.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.y < q.y or (p.y == q.y and p.x < q.x))
		var used: Dictionary = {}
		for k0: Vector2i in keys:
			if used.has(k0):
				continue
			var w: int = 1
			while set_.has(k0 + Vector2i(w, 0)) and not used.has(k0 + Vector2i(w, 0)):
				w += 1
			var h: int = 1
			var grow: bool = true
			while grow:
				for dx: int in w:
					var kk: Vector2i = k0 + Vector2i(dx, h)
					if not set_.has(kk) or used.has(kk):
						grow = false
						break
				if grow:
					h += 1
			for dz: int in h:
				for dx: int in w:
					used[k0 + Vector2i(dx, dz)] = true
			var y0: float = key.x / 4.0
			var y1: float = key.y / 4.0
			var ctr := Vector3((k0.x + w * 0.5) * cell, (y0 + y1) * 0.5, (k0.y + h * 0.5) * cell)
			add_box(b, Transform3D(Basis.IDENTITY, ctr), Vector3(w * cell * 0.9, y1 - y0, h * cell * 0.9))
			n += 1
	return n


## Glass panes, holo fields and light: nothing to bump into.
static func _see_through(mi: MeshInstance3D) -> bool:
	var m: Material = mi.material_override if mi.material_override else (mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null)
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		return bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or bm.blend_mode != BaseMaterial3D.BLEND_MODE_MIX
	return false


## Junk pieces that spawned inside a solid prop's footprint slide out to its edge (deterministic:
## positions are rebuilt the same way on every load; only alive bits are saved). Returns how many
## moved. `view` (FieldView) re-seats the moved pieces when given.
static func push_out_pieces(root: Node, field: HexField, view: Node = null) -> int:
	if field == null:
		return 0
	var moved: int = 0
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		if not n.has_meta("foot"):
			continue
		var cs := n as CollisionShape3D
		var p: StaticBody3D = cs.get_parent() as StaticBody3D
		if p == null or (p.collision_layer == 0 and not p.has_meta("layer_on")):
			continue
		var f: Vector3 = cs.get_meta("foot")
		var r: float = f.z + 0.25
		var c := Vector3(f.x, 0.0, f.y)
		var pids := PackedInt32Array()
		for hid: int in field.hexes_near(c, 1 + int(r / field.hex_size)):
			pids.append_array(field.hex_pieces[hid])  # dead ones too: the Ledger can revive them
		for pid: int in pids:
			if field.is_water(field.piece_hex[pid]):
				continue
			var pp: Vector3 = field.piece_pos[pid]
			var d := Vector2(pp.x - c.x, pp.z - c.z)
			if d.length() >= r:
				continue
			var dir: Vector2 = d.normalized() if d.length() > 0.01 else Vector2(cos(float(pid)), sin(float(pid)))
			var np := Vector3(c.x + dir.x * r, pp.y, c.z + dir.y * r)
			if field.layout:
				np.y = field.layout.height_at(np.x, np.z)
			field.piece_pos[pid] = np
			if view and view.has_method("move_piece") and field.piece_alive[pid] == 1:
				view.call("move_piece", pid, np)
			moved += 1
	return moved
