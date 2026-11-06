extends GutTest

var field: HexField


func before_each() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field = HexField.new(5, 3.2, 99)
	field.generate(types)


func test_hex_math_roundtrip() -> void:
	for a: Vector2i in Hex.spiral(4):
		var w: Vector2 = Hex.axial_to_world(a, 3.2)
		assert_eq(Hex.world_to_axial(w, 3.2), a)
	assert_eq(Hex.spiral(3).size(), Hex.count_in_radius(3))


func test_generation_deterministic() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var g := HexField.new(5, 3.2, 99)
	g.generate(types)
	assert_eq(g.piece_count(), field.piece_count())
	assert_eq(g.piece_pos[10], field.piece_pos[10])


func test_hub_hexes_start_clean_and_empty() -> void:
	var center: int = field.axial_to_id[Vector2i.ZERO]
	assert_true(field.is_clean(center))
	assert_eq(field.hex_pieces[center].size(), 0)


func test_pieces_live_in_their_hex() -> void:
	for pid: int in field.piece_count():
		assert_eq(field.hex_at(field.piece_pos[pid]), field.piece_hex[pid])


func test_removing_all_pieces_cleans_hex_once() -> void:
	var hid: int = field.piece_hex[0]
	var flips: int = 0
	for pid: int in field.hex_pieces[hid]:
		if field.remove_piece(pid):
			flips += 1
	assert_eq(flips, 1)
	assert_true(field.is_clean(hid))
	assert_eq(field.cleaned_count, 1)


func test_scoop_target_in_front_only() -> void:
	var pid: int = 0
	var p: Vector3 = field.piece_pos[pid]
	var origin: Vector3 = p + Vector3(0, 0, 1.0)
	assert_ne(field.find_scoop_target(origin, Vector3(0, 0, -1), 2.0, 1.4), -1)
	# Facing away: the piece directly behind must not be chosen if it's the only candidate nearby.
	var away: int = field.find_scoop_target(origin, Vector3(0, 0, 1), 0.5, 0.2)
	assert_ne(away, pid)


func test_compartment_overflow_rules() -> void:
	var c := Compartment.new()
	c.reserve(9.0)
	c.add("metal", 9.0)
	assert_true(c.can_accept(10.0))
	c.reserve(1.6)
	assert_false(c.can_accept(10.0))
	c.add("metal", 1.6)
	assert_false(c.in_perfect_band(10.0, [0.9, 1.0]))
	var taken: Dictionary = c.take_all()
	assert_almost_eq(float(taken["metal"]), 10.6, 0.001)
	assert_true(c.is_empty())
