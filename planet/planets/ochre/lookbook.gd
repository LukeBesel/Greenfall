class_name OchreLookbook
extends RefCounted
## [planet-ochre] Dev lookbook: Ochre's reusable kit laid out on the plateau under both suns, for
## review before the planets move onto walkable globes. `--ochre-lookbook=1` frames the props with
## the suns behind the camera; `--ochre-lookbook=2` looks up at both suns over the machines.
## Everything here is built with the same functions a globe would call per hub site:
## OchreExcavator.build, OchreEnv._truck, OchreProps junk / boulder / palm / agave / aloe / barrel,
## and swatches of the terrain material (strata rock, bench gravel, sand, salt crust).

const ORIGIN := Vector2(-720.0, -160.0)


static func build(env: OchreEnv) -> void:
	var root := Node3D.new()
	root.name = "Lookbook"
	env.add_child(root)
	var pit: OchrePit = env.pit
	# A levelled pad so the kit sits on one ground height.
	var base_y: float = top(pit, Vector2(130.0, 110.0)) - 0.6
	var pad := MeshInstance3D.new()
	pad.mesh = _vc_box(Vector3(130.0, 6.0, 110.0), Color(0.0, 1.0, 0.5, 0.0))
	pad.material_override = env._tmat()
	pad.position = Vector3(ORIGIN.x, base_y - 3.0 + 0.6, ORIGIN.y)
	root.add_child(pad)
	var y0: float = base_y + 0.6
	var p := func(x: float, z: float) -> Vector3: return Vector3(ORIGIN.x + x, y0, ORIGIN.y + z)
	# Excavators: ruined (left, boom slumped) and futuristic (right, planters and wind wheel).
	var hidden := Node3D.new()
	hidden.visible = false
	root.add_child(hidden)
	var ruined := Node3D.new()
	var future := Node3D.new()
	root.add_child(ruined)
	root.add_child(future)
	var mats_r: Dictionary = env._machine_mats()
	var mats_f: Dictionary = mats_r.duplicate()
	mats_f["paint"] = env._m("paint_future")
	var sc := Basis.from_scale(Vector3.ONE * 0.55)
	OchreExcavator.build({"always": ruined, "ruin": ruined, "up": hidden, "future": hidden},
		Transform3D(Basis(Vector3.UP, PI) * sc, p.call(-28.0, -28.0)), mats_r, "working", 11)
	OchreExcavator.build({"always": future, "ruin": hidden, "up": future, "future": future},
		Transform3D(sc, p.call(28.0, -28.0)), mats_f, "working", 12)
	# Haul trucks: rusted and planted-up.
	var tb := OchreProps.Batch.new()
	env._truck(tb, Transform3D(Basis(Vector3.UP, 0.35), p.call(-14.0, 10.0)), env._m("paint_ruin"), true)
	env._truck(tb, Transform3D(Basis(Vector3.UP, -0.35), p.call(14.0, 10.0)), env._m("paint_mid"), false)
	tb.flush(root)
	# Material swatches: strata rock pillar, bench gravel, plateau sand, salt crust.
	var sw: Array = [[Vector3(-34, 0, 30), Vector3(9, 14, 5), Color(0.5, 0.0, 0.5, 1.0)],
		[Vector3(-22, 0, 32), Vector3(8, 0.6, 8), Color(0.5, 1.0, 0.5, 1.0)],
		[Vector3(22, 0, 32), Vector3(8, 0.6, 8), Color(0.0, 1.0, 0.5, 0.0)],
		[Vector3(34, 0, 32), Vector3(8, 0.6, 8), Color(0.0, 1.0, 0.5, 1.0)]]
	for s: Array in sw:
		var mi := MeshInstance3D.new()
		mi.mesh = _vc_box(s[1], s[2])
		mi.material_override = env._tmat()
		mi.position = p.call((s[0] as Vector3).x, (s[0] as Vector3).z) + Vector3(0, (s[1] as Vector3).y * 0.5, 0)
		root.add_child(mi)
	# The junk set, life-size and doubled, in a row at the front.
	var junk: Dictionary = OchreProps.junk_meshes()
	var i: int = 0
	for id: String in junk:
		for k: int in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = junk[id]
			var scl: float = 2.2 if k == 0 else 1.0
			mi.transform = Transform3D(Basis(Vector3.UP, 0.4 + i * 0.7) * Basis.from_scale(Vector3.ONE * scl), p.call(-12.0 + i * 3.4, 30.0 + k * 3.0))
			root.add_child(mi)
		i += 1
	# Rocks and plants.
	for k: int in 7:
		var b := MeshInstance3D.new()
		b.mesh = OchreProps.boulder(1 + k % 3)
		b.transform = Transform3D(Basis(Vector3.UP, k * 1.3) * Basis.from_scale(Vector3.ONE * (0.8 + k * 0.45)), p.call(30.0 + (k % 4) * 3.5, 42.0 + floorf(k / 4.0) * 3.5))
		root.add_child(b)
	var plants: Array = [OchreProps.palm(1), OchreProps.palm(2), OchreProps.agave(1), OchreProps.agave(2), OchreProps.aloe(1), OchreProps.barrel_cactus(), OchreProps.palm(3)]
	for k: int in plants.size():
		var mi := MeshInstance3D.new()
		mi.mesh = plants[k]
		mi.transform = Transform3D(Basis(Vector3.UP, k * 0.9) * Basis.from_scale(Vector3.ONE * (1.0 if k in [0, 1, 6] else 1.6)), p.call(-40.0 + k * 3.2, 42.0 + (k % 2) * 3.0))
		root.add_child(mi)
	print("[ochre] lookbook at %s" % str(p.call(0.0, 0.0)))


## Dev `--ochre-site=<id>`: the site twice on a levelled pad, ruined (stage 1, restoration 0) on the
## left and futuristic (stage 5, restoration 1) on the right.
static func build_site(env: OchreEnv, id: String) -> void:
	var y0: float = top(env.pit, Vector2(260.0, 160.0))
	# A level stage round the two sites, with holes where they sit (a pit site digs below it).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Grid vertices inside a hole are pushed out onto its circle, so the edge is a smooth ring
	# (cells wholly inside collapse to nothing) instead of a stair-step of skipped cells.
	var cells := Vector2i(130, 80)
	var holes: Array[Vector2] = [Vector2(-56.0, 0.0), Vector2(56.0, 0.0)]
	var hr: float = 47.0
	var snap := func(v: Vector2) -> Vector2:
		for c: Vector2 in holes:
			var d: Vector2 = v - c
			if d.length() < hr:
				return c + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * hr
		return v
	for i: int in cells.x:
		for j: int in cells.y:
			var x0: float = -130.0 + i * 2.0
			var z0: float = -80.0 + j * 2.0
			var q: Array = []
			for v: Vector2 in [Vector2(x0, z0), Vector2(x0 + 2.0, z0), Vector2(x0 + 2.0, z0 + 2.0), Vector2(x0, z0 + 2.0)]:
				q.append(snap.call(v))
			for k: int in [0, 1, 2, 0, 2, 3]:
				var v: Vector2 = q[k]
				st.set_color(Color(0.3, 1.0, 0.5, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(ORIGIN.x + v.x, y0 - 0.05, ORIGIN.y + v.y))
	var pad := MeshInstance3D.new()
	pad.mesh = st.commit()
	pad.material_override = env._tmat()
	env.add_child(pad)
	for k: int in 2:
		var holder := Node3D.new()
		holder.name = "Site%d" % k
		holder.position = Vector3(ORIGIN.x + (-56.0 if k == 0 else 56.0), y0, ORIGIN.y)
		env.add_child(holder)
		OchreSites.build(id, holder, 1 if k == 0 else 5, 0.0 if k == 0 else 1.0)
	print("[ochre] site %s at %s" % [id, str(Vector3(ORIGIN.x, y0, ORIGIN.y))])


static func site_camera(pit: OchrePit) -> Array:
	var o := Vector3(ORIGIN.x, top(pit, Vector2(260.0, 160.0)), ORIGIN.y)
	match int(DevHooks.get_f("ochre-site-view", 0.0)):
		1:  # close on the ruined copy
			return [o + Vector3(-56.0, 16.0, 46.0), o + Vector3(-56.0, 3.0, 0.0)]
		2:  # close on the restored copy
			return [o + Vector3(56.0, 16.0, 46.0), o + Vector3(56.0, 3.0, 0.0)]
	return [o + Vector3(0.0, 44.0, 92.0), o + Vector3(0.0, -2.0, -2.0)]


## The two lookbook cameras: [position, target].
static func camera(view: int, pit: OchrePit) -> Array:
	var o := Vector3(ORIGIN.x, top(pit, Vector2(130.0, 110.0)), ORIGIN.y)
	if view == 2:
		return [o + Vector3(-6.0, 4.0, -62.0), o + Vector3(-30.0, 52.0, 60.0)]
	return [o + Vector3(0.0, 15.0, 74.0), o + Vector3(0.0, 9.0, 0.0)]


## The stage height: just above the highest ground (dunes) under a pad of `size` round ORIGIN.
static func top(pit: OchrePit, size: Vector2) -> float:
	var h: float = -INF
	for i: int in 13:
		for j: int in 13:
			var x: float = ORIGIN.x + (float(i) / 12.0 - 0.5) * size.x * 1.15
			var z: float = ORIGIN.y + (float(j) / 12.0 - 0.5) * size.y * 1.15
			h = maxf(h, pit.height_at(x, z))
	return h + 0.6


## A box with one vertex colour (the terrain shader reads its data from COLOR).
static func _vc_box(size: Vector3, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	OchreProps.put(st, OchreProps.unit_box(), Transform3D(Basis.from_scale(size), Vector3.ZERO), col)
	st.generate_normals()
	return st.commit()
