extends GutTest
## [art3] The vertex data art/shaders/building_city.gdshader reads from BuildingDetail meshes:
## the wall material packed above the flag bits, and where each wall vertex sits on its wall
## (metres above the foot, metres below the top: grime, ivy and rain runs hang on these).


func test_mat_packs_the_wall_material_above_the_flags() -> void:
	var g := BuildingDetail.Geo.new()
	g.mat(BuildingDetail.K_FACADE, Color.WHITE, BuildingDetail.T_CONCRETE, BuildingDetail.F_RIBBON | BuildingDetail.F_RUIN)
	var packed: int = int(g.uv2.y)
	assert_eq((packed >> 8) & 7, BuildingDetail.T_CONCRETE, "material in bits 8..10")
	assert_eq(packed & BuildingDetail.F_RIBBON, BuildingDetail.F_RIBBON)
	assert_eq(packed & BuildingDetail.F_RUIN, BuildingDetail.F_RUIN, "F_RUIN lies above the material bits")
	for f: int in [BuildingDetail.F_SHOP, BuildingDetail.F_RIBBON, BuildingDetail.F_ROOF_CONCRETE, BuildingDetail.F_ROOF_SEAMS_X,
			BuildingDetail.F_HOOPS, BuildingDetail.F_RUST, BuildingDetail.F_STRIPES, BuildingDetail.F_CURTAIN]:
		assert_lt(f, BuildingDetail.T_SHIFT, "a low flag stays under the material bits")
	for f2: int in [BuildingDetail.F_RUIN, BuildingDetail.F_LOUVRE]:
		assert_eq(f2 & (7 * BuildingDetail.T_SHIFT), 0, "a high flag stays clear of the material bits")


func test_box_sides_carry_their_height_on_the_wall() -> void:
	var g := BuildingDetail.Geo.new()
	g.uv = Vector2(11.0, 22.0)
	g.mat(BuildingDetail.K_FACADE, Color.WHITE, BuildingDetail.T_BRICK)
	g.abox(Vector3(2, 5, 3), Vector3(6, 9, 4))
	var sides: int = 0
	for i: int in g.v.size():
		if absf(g.n[i].y) > 0.5:
			assert_eq(g.u2[i].x, BuildingDetail.NO_WALL, "a top face is no wall")
			continue
		sides += 1
		assert_almost_eq(g.u[i].y, g.v[i].y - 5.0, 0.001, "UV.y: metres above the box's foot")
		assert_almost_eq(g.u2[i].x, 14.0 - g.v[i].y, 0.001, "UV2.x: metres below the box's top")
		assert_almost_eq(g.u[i].x, 22.0 if absf(g.n[i].x) > 0.5 else 11.0, 0.001, "UV.x: this face's bay offset")
	assert_eq(sides, 24, "four side faces")


func test_proxy_buildings_build_whole_for_every_look() -> void:
	var det := BuildingDetail.new()
	var looks: Dictionary = {}
	for s: int in 60:
		for style: String in ["apartments", "factory"]:
			var floors: int = 2 + (s * 7) % 20
			var bd: Dictionary = {"rect": Rect2(-9, -6, 18, 12), "face": [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)][s % 4],
				"bays": 6, "floors": floors, "style": style, "seed": 1000 + s * 7919, "ruined": s % 3 == 0, "trim": s % 8}
			if absf((bd["face"] as Vector2).x) > 0.5:
				bd["rect"] = Rect2(-6, -9, 12, 18)
			var body := BuildingDetail.Geo.new()
			var dg := BuildingDetail.Geo.new()
			det.proxy_building(bd, body, dg)
			assert_gt(body.tri_count(), 20)
			var top: float = 0.0
			for i: int in body.v.size():
				assert_true(body.v[i].is_finite(), "finite vertex")
				top = maxf(top, body.v[i].y)
				var kind: int = int(body.c[i].a * 16.0)
				looks[kind] = true
			assert_lt(top, float(floors) * 3.0 + 32.0, "nothing far above the roof (a mast at most)")
			assert_eq(int(CoplanarAudit.audit(body.v)["pairs"]), 0, "no z-fighting faces (seed %d %s)" % [s, style])
	for k: int in [BuildingDetail.K_FACADE, BuildingDetail.K_ROOF, BuildingDetail.K_METAL, BuildingDetail.K_COPING, BuildingDetail.K_LAMP]:
		assert_true(looks.has(k), "kind %d is in use" % k)


func test_ivy_card_is_two_layers_with_wall_heights() -> void:
	var m: ArrayMesh = BuildingDetail.ivy_card(Vector3(1, 0, 2), Vector3.RIGHT, Vector3.BACK, 12.0, 9.0, 77)
	var arr: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var u: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	assert_eq(v.size(), 12)
	for i: int in v.size():
		assert_almost_eq(u[i].y + u2[i].x, 9.0, 0.001, "above the foot + below the top = the wall's height")
		assert_gt(v[i].z, 2.0, "off the wall, on its outer side")
		assert_lt(v[i].z, 2.2)
