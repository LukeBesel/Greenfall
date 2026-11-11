extends GutTest
## [v3qa] Owner item 41: glitch fixes on round Verdance (docs/QA_VERDANCE.md).

var _g5: SphereGrid
var _t5: SphereTerrain


func before_all() -> void:
	_g5 = SphereGrid.new()
	_g5.generate(5)
	_g5.radius_m = SphereGrid.radius_for(5, 10.0)
	_t5 = SphereTerrain.new(_g5, 7)


func _crew() -> SphereCrew:
	var cells := SphereCells.new(_g5.cell_count())
	var surface := SphereSurface.new(_g5.radius_m)
	surface.height_fn = _t5.height
	surface.cell_fn = func(p: Vector3, _h: int) -> int: return _g5.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return _g5.centers[c]
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(_g5, cells, null, surface, SphereSwarm.new(surface))
	crew.hub_cell = 100
	crew.depot_cell = 100
	return crew


## QA #1: the globe's Fleet keeps its robots in the crew (robots() is empty), so "Build your first
## robot" never finished and the story stopped at the Bot Bay.
func test_robot_objective_counts_globe_crews() -> void:
	var crew: SphereCrew = _crew()
	var w := Node3D.new()
	add_child_autofree(w)
	var sf := SphereFleet.new()
	sf.crew = crew
	w.add_child(sf)
	assert_eq(sf.robot_total(), 0)
	crew.spawn("scoopie", 0, 100)
	assert_eq(sf.robots().size(), 0, "the flat API stays empty on the globe")
	assert_eq(sf.robot_total(), 1, "robot_total reads the crew")
	var ob := Objectives.new()
	ob.world = _FakeWorld.new(sf)
	assert_eq(ob.value_of({"type": "robot", "key": "any"}), 1.0)
	assert_eq(ob.value_of({"type": "robot", "key": "scoopie"}), 1.0)
	ob.world.free()
	ob.free()


## QA #2: painted Command zones on the globe count for "Send your robot to work" and survive a reload.
func test_globe_zones_count_and_save() -> void:
	var crew: SphereCrew = _crew()
	var before: int = Goals.zone_hex_count()
	crew.set_zone_cell("clean", 101, true)
	crew.set_zone_cell("clean", 102, true)
	crew.set_zone_cell("haul", 102, true)
	assert_eq(Goals.zone_hex_count() - before, 2, "two distinct painted cells")
	var d: Dictionary = JSON.parse_string(JSON.stringify(crew.to_dict()))
	var crew2: SphereCrew = _crew()
	crew2.from_dict(d)
	assert_eq(crew2.zone_cells().size(), 2)
	assert_true((crew2.zones["clean"] as Dictionary).has(101))


class _FakeWorld extends Node:
	var fleet: Node

	func _init(f: Node) -> void:
		fleet = f


## QA #8: the globe's Command view had no controller scheme: A paints, X erases, Y cycles roles.
func test_globe_command_pad_paints_and_cycles() -> void:
	var sc := SphereCommand.new()
	var cam := SphereCam.new()
	cam.view = "command"
	sc.cam = cam
	add_child_autofree(sc)
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	sc._unhandled_input(a)
	assert_true(sc.using_pad)
	assert_eq(sc._pad_paint, 1)
	a.pressed = false
	sc._unhandled_input(a)
	assert_eq(sc._pad_paint, 0)
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	var r0: String = sc.role
	sc._unhandled_input(y)
	assert_eq(sc.role, r0, "[v6crew] with only cleaners there is one job: nothing to cycle")
	var crew := SphereCrew.new()  # [v6crew] Y cycles the jobs you have robots for
	crew.visuals = false
	crew.set_process(false)
	add_child_autofree(crew)
	crew.units.append({"role": "water"})
	sc.crew = crew
	sc._unhandled_input(y)
	assert_ne(sc.role, r0, "Y picks the next role")
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(10, 0)
	sc._unhandled_input(mm)
	assert_false(sc.using_pad, "the mouse takes over again")
	cam.free()
