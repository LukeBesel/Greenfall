extends GutTest
## [kit] Art kit (art/kit/*): primitives build valid geometry with baked edge/AO data, primitives
## and meshes are cached, builders produce one named surface per material key, materials are
## cached and powered trims switch off, ground patches and buildings build for every state.


func test_bevel_box_geometry_and_edge_mask() -> void:
	var a: Array = KitMesh.bevel_box(Vector3(2, 1, 1), 0.05, 1)
	var v: PackedVector3Array = a[KitMesh.ARR_V]
	var c: PackedColorArray = a[KitMesh.ARR_C]
	var idx: PackedInt32Array = a[KitMesh.ARR_I]
	assert_gt(v.size(), 24, "more than a plain box")
	assert_eq(idx.size() % 3, 0)
	var aabb := AABB(v[0], Vector3.ZERO)
	for p: Vector3 in v:
		aabb = aabb.expand(p)
	assert_almost_eq(aabb.size.x, 2.0, 0.01, "keeps its size")
	assert_almost_eq(aabb.size.y, 1.0, 0.01)
	var has_edge: bool = false
	var has_flat: bool = false
	for col: Color in c:
		has_edge = has_edge or col.r > 0.99
		has_flat = has_flat or col.r < 0.01
	assert_true(has_edge and has_flat, "edge mask has edges and flat faces")


func test_box_winding_faces_outward() -> void:
	# Godot front faces are clockwise: the geometric normal (b-a)x(c-a) points INTO the box.
	var a: Array = KitMesh.bevel_box(Vector3(1, 1, 1), 0.05, 1)
	var v: PackedVector3Array = a[KitMesh.ARR_V]
	var idx: PackedInt32Array = a[KitMesh.ARR_I]
	var outward: int = 0
	for t: int in range(0, idx.size(), 3):
		var g: Vector3 = (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]])
		var centre: Vector3 = (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		if g.dot(centre) > 0.0:
			outward += 1
	assert_eq(outward, 0, "every triangle is clockwise seen from outside")


func test_primitive_cache() -> void:
	var hits: int = int(KitMesh.stats["prim_hits"])
	var a: Array = KitMesh.bevel_box(Vector3(0.7, 0.3, 0.2), 0.02)
	var b: Array = KitMesh.bevel_box(Vector3(0.7, 0.3, 0.2), 0.02)
	assert_same(a, b, "same params -> same cached arrays")
	assert_gt(int(KitMesh.stats["prim_hits"]), hits)
	var c: Array = KitMesh.bevel_cylinder(0.3, 1.0, 0.04, 12)
	assert_same(c, KitMesh.bevel_cylinder(0.3, 1.0, 0.04, 12))
	assert_gt((c[KitMesh.ARR_I] as PackedInt32Array).size(), 12 * 6)


func test_mesh_cache() -> void:
	var n: Array = [0]
	var make := func() -> Resource:
		n[0] += 1
		return ArrayMesh.new()
	var m1: Resource = KitMesh.cached("test:kit:cache", make)
	var m2: Resource = KitMesh.cached("test:kit:cache", make)
	assert_same(m1, m2)
	assert_eq(n[0], 1, "built once")


func test_builder_surfaces_by_key() -> void:
	var b := KitMesh.Builder.new(3)
	b.box("paint:main", Vector3(1, 1, 1))
	b.box("paint:main", Vector3(1, 2, 1), KitMesh.xf(Vector3(2, 0, 0)))
	b.cyl("steel", 0.2, 1.0)
	b.tube("rubber", PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 0)]), 0.05, 6, 0.2)
	b.decal("arrow", Vector2(1, 1), KitMesh.xf(Vector3(0, 0, 0.5)))
	var m: ArrayMesh = b.commit()
	assert_eq(m.get_surface_count(), 4, "one surface per material")
	var names: Array = []
	for s: int in m.get_surface_count():
		names.append(m.surface_get_name(s))
	assert_eq(names, ["paint", "steel", "rubber", "decal"])
	assert_gt(b.tri_count(), 100)


func test_panel_wall_and_missing_panels() -> void:
	var full := KitMesh.Builder.new(1)
	KitMesh.panel_wall(full, 6.0, 3.0, Transform3D.IDENTITY, {"key": "paint:main"})
	var broken := KitMesh.Builder.new(1)
	KitMesh.panel_wall(broken, 6.0, 3.0, Transform3D.IDENTITY, {"key": "paint:main", "missing": 0.5, "tilt": 1.0})
	assert_true(full.surf.has("paint") and full.surf.has("steel") and full.surf.has("dark_steel"), "panels, bolts, frame")
	assert_lt(broken.tri_count(), full.tri_count(), "broken wall is missing panels")


func test_materials_cached_and_power_switch() -> void:
	assert_same(KitMat.paint("teal", "repaired"), KitMat.paint("teal", "repaired"))
	assert_ne(KitMat.paint("teal", "broken"), KitMat.paint("teal", "restored"))
	var on: StandardMaterial3D = KitMat.trim("warm", true)
	var off: StandardMaterial3D = KitMat.trim("warm", false)
	assert_true(on.emission_enabled)
	assert_false(off.emission_enabled, "unpowered trims never glow")
	assert_false((KitMat.for_key("trim:cool", "broken", true) as StandardMaterial3D).emission_enabled, "broken never glows")
	for k: String in ["paint:main", "steel", "dark_steel", "rusty", "concrete", "hazard", "rubber", "glass", "trim:warm", "foliage", "dirt", "decal:arrow"]:
		assert_not_null(KitMat.for_key(k, "repaired", true, {"main": "cream"}), k)


func test_apply_sets_surface_materials() -> void:
	var b := KitMesh.Builder.new(1, {"main": "orange"}, "restored")
	b.box("paint:main", Vector3.ONE)
	b.box("paint:accent", Vector3.ONE)
	b.box("hazard", Vector3.ONE)
	b.box("trim:warm", Vector3(1, 0.05, 0.05))
	b.box("trim:red", Vector3(1, 0.05, 0.05))
	assert_eq(b.surface_count(), 2, "all paints share one surface, all trims another")
	var cust: PackedFloat32Array = b.surf["paint"][5]
	assert_almost_eq(cust[0], KitMat.color("orange").r, 0.01, "palette role baked per vertex")
	assert_almost_eq(cust[1], KitMat.color("orange").g, 0.01)
	var mi := KitMesh.instance(b)
	assert_same(mi.get_surface_override_material(0), KitMat.paint_vc("restored"))
	assert_same(mi.get_surface_override_material(1), KitMat.trim_vc(true))
	KitMat.apply(mi, "broken", true)
	assert_same(mi.get_surface_override_material(1), KitMat.trim_vc(false), "broken trims are dark")
	mi.free()


func test_ground_patch_all_states() -> void:
	for st: String in KitMat.STATES:
		var p: Node3D = KitMesh.ground_patch(Vector2(6, 4), st, 2)
		var plates: MeshInstance3D = p.get_node("Plates")
		assert_gt(plates.mesh.get_surface_count(), 1, st)
		var tufts: MultiMeshInstance3D = p.get_node("Tufts")
		assert_gt(tufts.multimesh.instance_count, 0, st + " has tufts")
		assert_gt((p.get_node("Grit") as MultiMeshInstance3D).multimesh.instance_count, 0, st + " has grit")
		p.free()
	var a: Node3D = KitMesh.ground_patch(Vector2(6, 4), "broken", 2)
	var b: Node3D = KitMesh.ground_patch(Vector2(6, 4), "broken", 2)
	assert_same((a.get_node("Plates") as MeshInstance3D).mesh, (b.get_node("Plates") as MeshInstance3D).mesh, "patch meshes cached")
	a.free()
	b.free()


func test_props_build() -> void:
	var b := KitMesh.Builder.new(4)
	for st: String in KitMat.STATES:
		KitProps.lamp_post(b, Transform3D.IDENTITY, 4.0, st)
		KitProps.antenna(b, Transform3D.IDENTITY, 4.0, st)
		KitProps.dish(b, Transform3D.IDENTITY, 1.0, st)
		KitProps.tank(b, Transform3D.IDENTITY, 1.0, 2.5, "paint:main", st)
		KitProps.solar_panel(b, Transform3D.IDENTITY, Vector2(2, 1), st)
		KitProps.stairs(b, Transform3D.IDENTITY, 1.5, 2.0, 1.0, "paint:rail", st)
		KitProps.crate_stack(b, Transform3D.IDENTITY, 5, st)
		KitProps.planter(b, Transform3D.IDENTITY, 2.0, st)
		KitProps.hatch(b, Transform3D.IDENTITY, Vector2(1.2, 2.2), st)
	KitProps.ladder(b, Transform3D.IDENTITY, 4.0)
	KitProps.vent(b, Transform3D.IDENTITY)
	KitProps.barrel(b, Transform3D.IDENTITY, "paint:barrel", true)
	KitProps.debris(b, Transform3D.IDENTITY)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3.ZERO, Vector3(0, 2, 0), Vector3(2, 2, 0)]))
	KitProps.cable(b, Transform3D.IDENTITY, Vector3(0, 3, 0), Vector3(4, 3, 0))
	var m: ArrayMesh = b.commit()
	assert_gt(m.get_surface_count(), 8)
	assert_gt(b.lights.size(), 0, "lamps and door lights request lights")


func test_buildings_all_kinds_and_states() -> void:
	for k: String in KitBuilding.KINDS:
		var d: KitBuilding.BuildData = KitBuilding.mesh_for(k, "repaired", 1)
		assert_not_null(d.mesh, k)
		assert_lt(d.mesh.get_surface_count(), 13, k + ": few draw calls")
		assert_gt(d.tris, 2000, k + ": detailed")
		assert_lt(d.tris, 140000, k + ": not absurdly heavy")
		assert_same(KitBuilding.mesh_for(k, "repaired", 1), d, k + " cached")
	var bld := KitBuilding.create("module_small", "broken", 2)
	add_child(bld)
	assert_false(bld.is_lit(), "broken buildings are dark")
	var broken_mesh: Mesh = (bld.get_node("Body") as MeshInstance3D).mesh
	bld.set_state("restored")
	assert_true(bld.is_lit())
	assert_ne((bld.get_node("Body") as MeshInstance3D).mesh, broken_mesh, "state swaps geometry")
	var lit: int = 0
	for c: Node in bld.get_children():
		if c is OmniLight3D and (c as OmniLight3D).visible:
			lit += 1
	assert_gt(lit, 0, "restored building has lights on")
	bld.set_powered(false)
	for c: Node in bld.get_children():
		if c is OmniLight3D:
			assert_false((c as OmniLight3D).visible, "unpowered: lights off")
	bld.free()
