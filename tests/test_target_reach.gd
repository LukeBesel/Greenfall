extends GutTest
## [v4world] Owner playtest 3 #55: every target on the globe is reachable. TargetReach on a
## real globe field with building footprints in the keep-out (as the towns register them).

var _grid: SphereGrid
var _terrain: SphereTerrain
var _cells: SphereCells
var _field: SphereField
var _ko: YardKeepOut
var _t: TargetReach
var _dir: Vector3  # an open, dry, flat spot
var _fr: Transform3D


func before_all() -> void:
	_grid = SphereGrid.for_hex_size(7, 10.0)
	_terrain = SphereTerrain.new(_grid, 4471)
	_cells = SphereCells.new(_grid.cell_count())
	_field = SphereField.new(_grid, _terrain, _cells, 4471)
	_ko = YardKeepOut.new()
	_ko.radius = _terrain.R
	_field.keep_out = _ko.blocks
	_t = TargetReach.for_field(_field)
	# A spot whose ground leads out in every way (searched near a fixed direction).
	var base: Vector3 = Vector3(0.3, 0.8, 0.2).normalized()
	for k: int in 200:
		var d: Vector3 = (base + Vector3(sin(k * 1.7), cos(k * 2.3), sin(k * 0.9)) * 0.01 * k).normalized()
		if _t.why(d) == "" and _t.reach(d) == "" and _flat(d, 40.0):
			_dir = d
			break
	_fr = Transform3D(SphereGrid.frame(_dir), _terrain.ground(_dir))
	# A 14 x 10 m building right on the spot, and a courtyard walled in by four blocks 30 m east.
	_ko.add_world("b", [[_fr, Rect2(-7, -5, 14, 10)]])
	var cx: float = 30.0
	_ko.add_world("court", [
		[_fr, Rect2(cx - 12, -12, 24, 4)], [_fr, Rect2(cx - 12, 8, 24, 4)],
		[_fr, Rect2(cx - 12, -12, 4, 24)], [_fr, Rect2(cx + 8, -12, 4, 24)]])


func _flat(d: Vector3, r: float) -> bool:
	var f: Basis = SphereGrid.frame(d)
	for k: int in 16:
		var a: float = TAU * k / 16.0
		for rr: float in [r * 0.5, r]:
			var q: Vector3 = (d * _terrain.R + (f.x * cos(a) + f.z * sin(a)) * rr).normalized()
			if _t.why(q) != "":
				return false
	return true


func _at(x: float, z: float) -> Vector3:
	return _fr * Vector3(x, 0, z)


func test_found_an_open_spot() -> void:
	assert_ne(_dir, Vector3.ZERO, "the test needs open ground")


func test_inside_a_building_is_unreachable() -> void:
	assert_true(_ko.in_building(_at(0, 0)), "the footprint is in the keep-out")
	assert_eq(_t.why(_at(0, 0)), "building")
	assert_ne(_t.reach(_at(0, 0)), "", "a target in the middle of a building can't be reached")


func test_next_to_a_wall_is_reachable() -> void:
	assert_eq(_t.reach(_at(9.0, 0)), "", "a target 1 m off the grown footprint is fine")
	assert_eq(_t.reach(_at(7.5, 0)), "", "within reach of open ground counts (Lumi reaches 2 m)")


func test_open_spot_leaves_the_building() -> void:
	var s: Vector3 = _t.open_spot(_at(0, 0))
	assert_false(_ko.in_building(s), "moved out of the footprint")
	assert_eq(_t.reach(s), "", "and onto reachable ground")
	assert_lt(_fr.origin.distance_to(s), 12.0, "the nearest open ground, not somewhere far")
	var alt: float = s.length() - (_terrain.R + _terrain.height(s.normalized()))
	assert_almost_eq(alt, 0.0, 0.05, "on the ground")


func test_walled_courtyard_is_shut() -> void:
	var c: Vector3 = _at(30, 0)
	assert_eq(_t.why(c), "", "the courtyard's own ground is free")
	assert_eq(_t.reach(c), "shut", "but walled in on every side")
	var s: Vector3 = _t.open_spot(c)
	assert_eq(_t.reach(s), "", "open_spot leads out of the courtyard")
	var lp: Vector3 = _fr.affine_inverse() * s
	assert_false(absf(lp.x - 30.0) < 8.0 and absf(lp.z) < 8.0, "not left inside the courtyard")


func test_water_is_unreachable() -> void:
	var c: int = _grid.cell_at(_at(-25, 0))
	var was: int = _field.hex_water[c]
	_field.hex_water[c] = 1
	assert_eq(_t.why(_grid.centers[c]), "water")
	var s: Vector3 = _t.open_spot(_grid.centers[c])
	assert_ne(_grid.cell_at(s), c, "moved onto dry ground")
	_field.hex_water[c] = was


func test_keep_out_version_bumps() -> void:
	var v: int = _ko.version
	_ko.add_world("later", [[_fr, Rect2(50, 50, 4, 4)]])
	assert_gt(_ko.version, v, "callers can tell footprints were added")
