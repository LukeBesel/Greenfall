extends GutTest
## CityOldTown: the first city's palette, its regrowth stage hook and its source landmark's switch.


func _plan(seed_v: int, floors: int = 4) -> Dictionary:
	return {"seed": seed_v, "floors": floors, "rect": Rect2(0, 0, 12, 11), "face": Vector2(0, 1), "style": "apartments"}


func test_paint_gives_a_building_walls_roof_and_awning() -> void:
	var bd: Dictionary = _plan(4471)
	CityOldTown.paint(bd)
	for k: String in ["tint", "wall_tex", "roof_tint", "awning", "awning_striped"]:
		assert_true(bd.has(k), "paint sets %s" % k)


func test_no_roof_in_the_palette_is_white_or_grey() -> void:
	for c: Color in CityOldTown.ROOFS:
		assert_true(c.s > 0.04 and c.v < 0.85, "roof %s carries colour and is not white" % c.to_html(false))


func test_paint_is_the_same_for_the_same_seed() -> void:
	var a: Dictionary = _plan(99)
	var b: Dictionary = _plan(99)
	CityOldTown.paint(a)
	CityOldTown.paint(b)
	assert_eq(a["tint"], b["tint"])
	assert_eq(a["roof_tint"], b["roof_tint"])


func test_the_palette_is_spread_over_many_buildings() -> void:
	var roofs: Dictionary = {}
	var walls: Dictionary = {}
	for i: int in 200:
		var bd: Dictionary = _plan(1000 + i * 7919)
		CityOldTown.paint(bd)
		roofs[bd["roof_tint"]] = true
		walls[int(bd["wall_tex"])] = true
	assert_gt(roofs.size(), 4, "several roof colours in a town")
	assert_eq(walls.size(), 3, "brick, pale brick and painted render all turn up")


func test_stage_drives_the_town_material_and_clamps() -> void:
	var town := CityOldTown.new()
	add_child_autofree(town)
	var mat: ShaderMaterial = CityOldTown.material(false)
	var outer: ShaderMaterial = CityOldTown.material(true)
	town.set_stage(0)
	assert_eq(float(mat.get_shader_parameter("lit")), 0.0, "nothing is lit in a polluted town")
	assert_eq(float(mat.get_shader_parameter("sign_clean")), 0.0)
	town.set_stage(2)
	assert_gt(float(mat.get_shader_parameter("lit")), 0.0, "shop lights come back at stage 2")
	town.set_stage(9)
	assert_eq(town.stage, CityOldTown.MAX_STAGE)
	assert_eq(float(mat.get_shader_parameter("lit")), 1.0)
	assert_eq(float(mat.get_shader_parameter("sign_clean")), 1.0)
	assert_eq(float(outer.get_shader_parameter("lit")), 1.0, "the outskirts follow")
	town.set_stage(0)


func test_source_state_is_broken_unless_shut_down() -> void:
	var town := CityOldTown.new()
	add_child_autofree(town)
	assert_eq(town.source_state, CityOldTown.STATE_BROKEN)
	town.set_source_state(CityOldTown.STATE_SHUT_DOWN)
	assert_eq(town.source_state, CityOldTown.STATE_SHUT_DOWN)
	town.set_source_state("anything else")
	assert_eq(town.source_state, CityOldTown.STATE_BROKEN)


func test_a_town_site_keeps_its_district_stage_in_range() -> void:
	var site := TownSite.new()
	add_child_autofree(site)
	site.set_district_stage(3)
	assert_eq(site.district_stage, 3)
	site.set_district_stage(42)
	assert_eq(site.district_stage, Districts.MAX_STAGE)
	site.set_district_stage(-1)
	assert_eq(site.district_stage, 0)
