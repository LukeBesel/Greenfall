extends GutTest
## [world3] Owner rule: "When you land there can't be working things like streetlamps. Only
## broken-down things you fix with parts and cubes." A fresh district has no lit light; street
## lights come back by hex (Sustained) or round the base (hub level 3), and old saves keep theirs.

var root: Node3D
var layout: CityLayout
var field: HexField
var levels: HexLevels
var power: StreetPower
var dressing: StreetDressing


func before_all() -> void:
	layout = CityLayout.new(4471, 150.0, false)
	field = HexField.new(4, 10.0, 4471, layout)
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field.generate(types, Vector2i(30, 40))


func _build(hub_level: int, sustained: Array = []) -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var city := CityView.new()
	root.add_child(city)
	city.build(layout, StandardMaterial3D.new())
	dressing = StreetDressing.new()
	root.add_child(dressing)
	dressing.build(layout, field, 0, "Old Town", "", hub_level)
	levels = HexLevels.new()  # not set up: just the level table
	autofree(levels)
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0:
			levels.levels[id] = 4 if id in sustained else 0
	power = StreetPower.new()
	root.add_child(power)
	power.setup(field, levels, hub_level)
	power.add_bulbs(city.lamp_bulbs)
	power.add_groups(dressing.power_groups)
	power.apply(false)
	await wait_frames(2)


func _lit() -> Array:
	return LightAudit.scan(root)


func test_fresh_district_has_no_lit_lights() -> void:
	await _build(1)
	assert_gt(power.group_count(), 6, "street lamps, neon signs and string lights are on the grid")
	assert_eq(power.lit_count(), 0)
	var lit: Array = _lit()
	for l: Dictionary in lit:
		gut.p("lit: %s" % str(l))
	assert_eq(lit.size(), 0, "nothing glows as working when you land")


func test_some_signs_hang_askew_until_powered() -> void:
	await _build(1)
	var hanging: int = 0
	for g: Dictionary in dressing.power_groups:
		if g.has("tilt") and not (g["tilt"] as Transform3D).is_equal_approx(g["home"]):
			hanging += 1
			assert_true((g["node"] as Node3D).transform.is_equal_approx(g["tilt"]))
	assert_gt(hanging, 0, "a broken sign or two dangles off one bracket")


func test_a_sustained_hex_flickers_its_lights_on() -> void:
	await _build(1)
	var g: Dictionary = {}
	for x: Dictionary in dressing.power_groups:
		if int(x["hex"]) >= 0:
			g = x
			break
	assert_false(g.is_empty())
	var h: int = g["hex"]
	levels.levels[h] = 4
	EventBus.hex_level_changed.emit(h, 4)
	assert_true(g["on"], "switched on")
	await wait_seconds(3.0)
	assert_almost_eq(float((g["mats"][0] as ShaderMaterial).get_shader_parameter("power")), 1.0, 0.01, "lit after the flicker")
	assert_true((g["node"] as Node3D).transform.is_equal_approx(g["home"]), "a hanging sign swings back level")
	for x: Dictionary in power._groups:
		if int(x["hex"]) != h and not power.powered(x):
			assert_false(x["on"], "other hexes stay dead")


func test_old_save_keeps_what_it_earned() -> void:
	# Hub level 3 rewires the block round the base; a Sustained hex has its own street lit.
	var far_hex: int = -1
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and field.hex_center(id).length() > StreetPower.HUB_RADIUS + 15.0:
			far_hex = id
			break
	await _build(3, [far_hex])
	assert_gt(power.lit_count(), 0)
	var near_on: int = 0
	for g: Dictionary in power._groups:
		var near: bool = Vector2(g["at"].x, g["at"].z).length() <= StreetPower.HUB_RADIUS
		if near:
			assert_true(g["on"], "round the base at hub level 3")
			near_on += 1
		elif int(g["hex"]) == far_hex:
			assert_true(g["on"], "the Sustained hex's own lights")
		else:
			assert_false(g["on"])
		assert_almost_eq(float((g["mats"][0] as ShaderMaterial).get_shader_parameter("power")), 1.0 if g["on"] else 0.0, 0.01, "no flicker on load")
	assert_gt(near_on, 0)
