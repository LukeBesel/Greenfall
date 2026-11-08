extends GutTest
## [v1guide] Owner playtest 2026-11-08: the objective beam stands straight on the globe (#17), WREN
## says why Lumi picks up junk (#18), the bale how-to names the key (#21).


func test_beam_and_ring_follow_the_local_up() -> void:
	for up: Vector3 in [Vector3(0.7, 0.16, -0.68).normalized(), Vector3.UP, Vector3(0, -1, 0), Vector3.FORWARD]:
		var b: Basis = Waypoint._up_basis(up)
		assert_almost_eq(b.y.dot(up), 1.0, 0.001, "ring lies flat on the local ground")
		assert_gt(b.determinant(), 0.0, "not mirrored")


func test_beam_is_a_tall_sky_beam() -> void:
	var w := Waypoint.new()
	add_child_autofree(w)
	assert_gte(Waypoint.BEAM_H, 40.0)
	assert_almost_eq(((w._beam.mesh as QuadMesh).size.y), Waypoint.BEAM_H, 0.01)
	assert_gt(Waypoint.RING_R, 1.5, "a ring you can see around the target")


func test_brief_says_why() -> void:
	var lines: Array = Intro.brief_lines()
	var all: String = " ".join(lines).to_lower()
	assert_true(all.contains("junk") and all.contains("parts") and all.contains("signal tower"), "pick up junk, find parts, build the tower")
	assert_true(all.contains("[glitch]"), "WREN still breaks up")


func test_glyphs_and_bale_howto_name_the_key() -> void:
	var g: String = "[%s]" % Settings.glyph("cube")
	assert_true(Objectives.glyphs("Press {cube} now").contains(g))
	assert_eq(Objectives.glyphs("no {such_action} here"), "no {such_action} here")
	assert_true(Objectives.bale_howto().contains(g))
	var o: Array[String] = Objectives.texts({"text": "Power", "desc": "Press {cube} for a bale"})
	assert_false(o[1].contains("{cube}"))
