extends GutTest
## Verdance's six cities: each has a look in data and a script for its source landmark, the looks
## differ, Old Town's paint is what it was before the looks moved into data, and the stage and
## source hooks work city by city.

const DISTRICTS_PATH: String = "res://planets/verdance/data/districts.json"
## Old Town's palette as it stood in code before cities.json (the regression reference).
const OLD_WALLS: Array = [
	[0, Color(1.0, 0.95, 0.9)], [0, Color(1.0, 0.86, 0.78)], [0, Color(0.92, 0.9, 0.86)],
	[1, Color(1.0, 0.86, 0.62)], [1, Color(0.98, 0.78, 0.6)],
	[2, Color(0.97, 0.9, 0.72)], [2, Color(0.96, 0.86, 0.66)], [2, Color(0.93, 0.62, 0.45)],
	[2, Color(0.95, 0.76, 0.4)], [2, Color(0.42, 0.68, 0.66)], [2, Color(0.9, 0.64, 0.62)],
	[2, Color(0.62, 0.76, 0.88)],
]
const OLD_ROOFS: Array[Color] = [Color(0.8, 0.34, 0.2), Color(0.74, 0.3, 0.2), Color(0.66, 0.24, 0.18), Color(0.3, 0.6, 0.5),
	Color(0.34, 0.44, 0.6), Color(0.36, 0.28, 0.38), Color(0.78, 0.62, 0.36), Color(0.16, 0.5, 0.52)]
const OLD_AWNINGS: Array[Color] = [Color(0.84, 0.14, 0.1), Color(0.04, 0.5, 0.5), Color(0.94, 0.68, 0.08), Color(0.12, 0.3, 0.64), Color(0.2, 0.52, 0.3)]


func _plan(seed_v: int, floors: int = 4) -> Dictionary:
	return {"seed": seed_v, "floors": floors, "rect": Rect2(0, 0, 12, 11), "face": Vector2(0, 1), "style": "apartments"}


func _district_ids() -> Array[String]:
	var out: Array[String] = []
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DISTRICTS_PATH))
	for e: Dictionary in d["districts"]:
		out.append(str(e["id"]))
	return out


func test_every_district_has_a_city_with_a_script() -> void:
	var ids: Array[String] = _district_ids()
	assert_eq(ids.size(), 6)
	for id: String in ids:
		assert_true(CityLook.has(id), "%s has a look in cities.json" % id)
		var c: VerdanceCity = VerdanceCity.create(id)
		assert_not_null(c, "%s has a city script that extends VerdanceCity" % id)
		if c:
			assert_eq(c.city_id, id)
			c.free()


func test_an_unknown_city_is_null() -> void:
	assert_null(VerdanceCity.create("no_such_city"))
	assert_null(CityLook.of("no_such_city"))


func test_paint_gives_a_building_walls_roof_and_awning_in_every_city() -> void:
	for id: String in CityLook.ids():
		var bd: Dictionary = _plan(4471)
		CityLook.of(id).paint(bd)
		for k: String in ["tint", "wall_tex", "roof_tint", "awning", "awning_striped"]:
			assert_true(bd.has(k), "%s: paint sets %s" % [id, k])


func test_no_roof_in_any_city_is_white_or_grey() -> void:
	for id: String in CityLook.ids():
		var l: CityLook = CityLook.of(id)
		for c: Color in l.roofs + l.gables:
			assert_true(c.s > 0.04 and c.v < 0.85, "%s roof %s carries colour and is not white" % [id, c.to_html(false)])


func test_every_city_keeps_strong_colour_in_its_signs_and_awnings() -> void:
	for id: String in CityLook.ids():
		var l: CityLook = CityLook.of(id)
		var strong: int = 0
		for c: Color in l.signs + l.awnings:
			strong += 1 if c.s > 0.6 and c.v > 0.5 else 0
		assert_gte(strong, 4, "%s has at least four saturated sign and awning colours" % id)
		var walls: float = 0.0
		for w: Array in l.walls:
			walls += (w[1] as Color).v
		assert_gt(walls / float(l.walls.size()), 0.7, "%s's walls are bright on average" % id)


func test_old_town_paint_is_what_it_was_in_code() -> void:
	var look: CityLook = CityLook.of("old_town")
	for i: int in 300:
		var floors: int = 3 + i % 9
		var bd: Dictionary = _plan(1000 + i * 7919, floors)
		look.paint(bd)
		var h: int = hash([int(bd["seed"]), 9173])
		var wall: Array = OLD_WALLS[h % OLD_WALLS.size()]
		if floors >= 8 and int(wall[0]) == 0:
			wall = OLD_WALLS[5 + (h >> 4) % 4]
		assert_eq(int(bd["wall_tex"]), int(wall[0]))
		assert_eq(bd["tint"], (wall[1] as Color).lightened(float((h >> 8) % 7) * 0.01 - 0.03))
		assert_eq(bd["roof_tint"], OLD_ROOFS[(h >> 12) % OLD_ROOFS.size()])
		assert_eq(bd["awning"], OLD_AWNINGS[(h >> 16) % OLD_AWNINGS.size()])
		assert_eq(bd["awning_striped"], (h >> 20) % 3 != 0)


func test_no_two_cities_share_a_palette() -> void:
	var ids: Array[String] = CityLook.ids()
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: CityLook = CityLook.of(ids[i])
			var b: CityLook = CityLook.of(ids[j])
			var same_roofs: int = 0
			for c: Color in a.roofs:
				same_roofs += 1 if b.roofs.has(c) else 0
			var same_walls: int = 0
			for w: Array in a.walls:
				for w2: Array in b.walls:
					same_walls += 1 if (w[1] as Color).is_equal_approx(w2[1]) else 0
			assert_lte(same_roofs, 1, "%s and %s roofs" % [ids[i], ids[j]])
			assert_lte(same_walls, 1, "%s and %s walls" % [ids[i], ids[j]])


func test_every_city_has_its_own_roofline_or_street_dressing() -> void:
	var seen: Dictionary = {}
	for id: String in CityLook.ids():
		var l: CityLook = CityLook.of(id)
		var props: Array = (l.data.get("roof_props", {}) as Dictionary).keys()
		props.sort()
		var key: String = "%s|%s" % [str(l.data.get("street", "")), str(props)]
		assert_false(seen.has(key), "%s looks like %s from the street" % [id, str(seen.get(key, ""))])
		seen[key] = id
		assert_true(CityStreet.KINDS.has(str(l.data.get("street", ""))), "%s names a street dressing that exists" % id)


func test_shop_names_are_different_within_a_city_and_between_cities() -> void:
	var all: Dictionary = {}
	for id: String in CityLook.ids():
		var names: Array[String] = CityLook.of(id).shop_names
		assert_gte(names.size(), 12, "%s has names for a street of shops" % id)
		for n: String in names:
			assert_false(all.has(n), "'%s' is painted in %s and %s" % [n, id, str(all.get(n, ""))])
			all[n] = id


func test_every_landmark_has_a_footprint_on_its_three_blocks() -> void:
	for id: String in CityLook.ids():
		if id == "old_town":
			continue
		var c: VerdanceCity = VerdanceCity.create(id)
		var rects: Array[Rect2] = c._footprint()
		assert_gte(rects.size(), 3, "%s's landmark is several solid pieces" % id)
		for r: Rect2 in rects:
			assert_true(absf(r.get_center().x) < CityLayout.PITCH * 1.4 and absf(r.get_center().y) < CityLayout.PITCH * 1.4,
				"%s: piece %s stays near its block" % [id, str(r)])
		assert_ne(str(c.look.landmark().get("sign", "")), "", "%s's landmark carries a name" % id)
		c.free()


func test_a_landmark_rect_turns_with_the_side_of_town_it_stands_on() -> void:
	var c: VerdanceCity = VerdanceCity.create("scrapyard")
	c.frame = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-72.0, 0.0, 0.0))  # west of the yard, facing east
	var r: Rect2 = c.site_rect(Rect2(-2.0, 10.0, 4.0, 6.0))
	assert_almost_eq(r.position.x, -62.0, 0.001, "toward the yard is east")
	assert_almost_eq(r.size.x, 6.0, 0.001)
	assert_almost_eq(r.size.y, 4.0, 0.001)
	assert_almost_eq(r.get_center().y, 0.0, 0.001)
	c.free()


func test_stage_lights_one_city_and_not_its_neighbour() -> void:
	var a: VerdanceCity = VerdanceCity.create("highreach")
	var b: VerdanceCity = VerdanceCity.create("lowmeadow")
	add_child_autofree(a)
	add_child_autofree(b)
	a.set_stage(0)
	b.set_stage(0)
	a.set_stage(9)
	assert_eq(a.stage, VerdanceCity.MAX_STAGE)
	assert_eq(float(a.look.material(false).get_shader_parameter("lit")), 1.0)
	assert_eq(float(a.look.material(true).get_shader_parameter("sign_clean")), 1.0, "the outskirts follow")
	assert_eq(float(b.look.material(false).get_shader_parameter("lit")), 0.0, "the other city stays dark")
	a.set_stage(2)
	assert_gt(float(a.look.material(false).get_shader_parameter("lit")), 0.0, "shop lights come back at stage 2")
	a.set_stage(0)


func test_shutting_the_source_down_swaps_the_landmark_parts() -> void:
	for id: String in CityLook.ids():
		var c: VerdanceCity = VerdanceCity.create(id)
		add_child_autofree(c)
		var running: Node3D = c.place(Node3D.new(), VerdanceCity.STATE_BROKEN)
		var stopped: Node3D = c.place(Node3D.new(), VerdanceCity.STATE_SHUT_DOWN)
		var always: Node3D = c.place(Node3D.new())
		c.set_source_state(VerdanceCity.STATE_BROKEN)
		assert_true(running.visible and not stopped.visible and always.visible, "%s running" % id)
		c.set_source_state(VerdanceCity.STATE_SHUT_DOWN)
		assert_true(not running.visible and stopped.visible and always.visible, "%s shut down" % id)
		c.set_source_state("anything else")
		assert_eq(c.source_state, VerdanceCity.STATE_BROKEN)


func test_a_town_site_passes_its_source_state_on() -> void:
	var site := TownSite.new()
	add_child_autofree(site)
	assert_eq(site.source_state, "broken")
	site.set_source_state("shut_down")
	assert_eq(site.source_state, "shut_down")


func test_roof_props_are_cheap_meshes() -> void:
	for m: ArrayMesh in [CityRoofs.tank_mesh(), CityRoofs.sign_mesh(), CityRoofs.shade_mesh(), CityRoofs.gable_mesh(), CityRoofs.sawtooth_mesh(),
			CityRoofs.billboard_mesh(), CityRoofs.dome_mesh(), CityRoofs.flag_mesh()]:
		assert_lt(m.surface_get_array_len(0) / 3, 420, "a roof prop stays under 420 triangles")


func test_a_pitched_roof_mesh_fills_a_unit_box() -> void:
	var box: AABB = CityRoofs.gable_mesh().get_aabb()
	assert_almost_eq(box.size.x, 1.0, 0.01)
	assert_almost_eq(box.size.z, 1.0, 0.01)
	assert_almost_eq(box.end.y, 1.0, 0.03)


func test_a_lattice_tower_reaches_its_height() -> void:
	var g := BuildingDetail.Geo.new()
	CityKit.lattice(g, Vector3.ZERO, 2.0, 1.0, 30.0, 6, 0.1, Color.RED, Color.WHITE)
	var box: AABB = g.mesh().get_aabb()
	assert_almost_eq(box.end.y, 30.0, 0.2)
	assert_almost_eq(box.size.x, 4.2, 0.2)
