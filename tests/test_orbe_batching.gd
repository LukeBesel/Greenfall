extends GutTest
## [orbE] Draw-call batching: kit building bodies merge per material (originals hidden, unmerge
## restores), static loose props merge only when auto-named and script-less (named pieces are
## left alone), and Lumi's far proxy has fewer surfaces than the rig and casts no shadow.


func test_kit_batch_merges_and_restores() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var a: KitBuilding = KitBuilding.create("module_small", "broken", 1)
	var b: KitBuilding = KitBuilding.create("module_medium", "broken", 2)
	b.position = Vector3(20, 0, 0)
	root.add_child(a)
	root.add_child(b)
	var r: Dictionary = KitBatch.merge(root)
	assert_eq(int(r["buildings"]), 2)
	assert_lt(int(r["surfaces_out"]), int(r["surfaces_in"]), "fewer surfaces than the bodies had")
	assert_false((a.get_node("Body") as MeshInstance3D).visible)
	assert_not_null(root.get_node_or_null(KitBatch.NODE_NAME))
	KitBatch.merge(root)  # again (after a state change): still one merged node
	var merged: int = 0
	for c: Node in root.get_children():
		if c.name == KitBatch.NODE_NAME:
			merged += 1
	assert_eq(merged, 1)
	KitBatch.unmerge(root)
	assert_true((a.get_node("Body") as MeshInstance3D).visible)
	assert_null(root.get_node_or_null(KitBatch.NODE_NAME))


func test_prop_batch_is_conservative() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var mat := StandardMaterial3D.new()
	for i: int in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = mat
		mi.position = Vector3(i * 2.0, 0, 0)
		root.add_child(mi)  # auto-named: "@MeshInstance3D@..."
	var named := MeshInstance3D.new()
	named.name = "Beacon"  # looked up by name: never merged
	named.mesh = BoxMesh.new()
	root.add_child(named)
	var r: Dictionary = PropBatch.merge(root)
	assert_eq(int(r["meshes"]), 3)
	assert_true(named.visible, "named pieces stay as they are")
	assert_eq(int(r["surfaces_out"]), 1, "one material, one surface")
	PropBatch.unmerge(root)
	for c: Node in root.get_children():
		assert_true((c as Node3D).visible)


func test_lumi_far_proxy() -> void:
	var model := PatchModel.new()
	add_child_autofree(model)
	var lod := LumiLod.new()
	add_child_autofree(lod)
	lod.setup(model, func() -> Vector3: return Vector3(0, 100, 0))
	assert_not_null(lod.proxy)
	assert_lt(int(lod.stats["surfaces_out"]), int(lod.stats["surfaces_in"]))
	assert_eq(lod.proxy.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_almost_eq(lod.proxy.visibility_range_begin, LumiLod.SWITCH_M, 0.01)


func test_far_impostor_is_one_surface() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0, 0)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0, 0, 1)
	var am := ArrayMesh.new()
	for m: StandardMaterial3D in [red, blue]:
		var bm := BoxMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.surface_get_arrays(0))
		am.surface_set_material(am.get_surface_count() - 1, m)
	var one: Mesh = JunkFarSingle.single(am)
	assert_eq(one.get_surface_count(), 1, "one draw per far model")
	var cols: PackedColorArray = one.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var has_red: bool = false
	var has_blue: bool = false
	for c: Color in cols:
		has_red = has_red or c.r > 0.9
		has_blue = has_blue or c.b > 0.9
	assert_true(has_red and has_blue, "each surface keeps its colour")
	assert_eq(JunkFarSingle.single(BoxMesh.new()).get_surface_count(), 1, "single-surface meshes pass through")
