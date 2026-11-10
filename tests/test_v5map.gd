extends GutTest
## [v5text] Map leftovers: the survey's glyphs don't cover each other on the start hub, the survey
## card shows the HUD's planet %, and a world carries one system map.

const HUB := Vector3(0, 0, 1)
## Half-widths of the painted art inside the 64 px glyph textures (ui/map_glyphs.gd).
const LUMI_HALF_PX: float = 23.0 * 1.15  # the Lumi pin is drawn 1.15x
const SPROUT_LEFT_PX: float = -25.0
const SPROUT_RIGHT_PX: float = 26.0
const PLUME_HALF_PX: float = 17.0


func test_glyphs_on_the_start_hub_stand_side_by_side() -> void:
	for zoom: float in [1.4, 2.6, 3.2, 4.3]:
		var lay: Dictionary = GlobeView.glyph_layout(HUB, [HUB, Vector3(1, 0, 0)], HUB, zoom)
		var lumi_c: float = float(lay["lumi_px"]) * 1.15
		assert_lt(lumi_c + LUMI_HALF_PX, SPROUT_LEFT_PX, "zoom %.1f: Lumi is clear of the sprout" % zoom)
		assert_true(bool(lay["plume_visible"]), "zoom %.1f: the plume shows" % zoom)
		assert_gt(float(lay["plume_px"]) - PLUME_HALF_PX, SPROUT_RIGHT_PX, "zoom %.1f: the plume is clear of the sprout" % zoom)


func test_far_zoom_hides_the_plume_on_a_crowded_hub() -> void:
	var lay: Dictionary = GlobeView.glyph_layout(HUB, [HUB], HUB, 6.0)
	assert_false(bool(lay["plume_visible"]), "the least important glyph goes first")
	assert_lt(float(lay["lumi_px"]), 0.0, "Lumi still stands beside the sprout")
	# A pod with nothing near it stays on the map at any zoom, and nothing is nudged.
	var alone: Dictionary = GlobeView.glyph_layout(Vector3(1, 0, 0), [Vector3(0, 1, 0)], HUB, 6.0)
	assert_true(bool(alone["plume_visible"]))
	assert_eq(float(alone["plume_px"]), 0.0)
	assert_eq(float(alone["lumi_px"]), 0.0, "Lumi alone stands on his own hex")
	# No pod at all.
	assert_false(bool(GlobeView.glyph_layout(HUB, [HUB], Vector3.ZERO, 3.0)["plume_visible"]))


func test_lumi_steps_back_onto_his_hex_when_he_leaves_the_hub() -> void:
	var away: Vector3 = HUB.rotated(Vector3.UP, 0.6)  # ~1.1 km on Verdance
	var lay: Dictionary = GlobeView.glyph_layout(away, [HUB], HUB, 3.2)
	assert_eq(float(lay["lumi_px"]), 0.0)
	assert_gt(float(lay["plume_px"]), 0.0, "the pod still shares the hub with its sprout")


func test_glyphs_keep_their_screen_size_within_limits() -> void:
	assert_almost_eq(GlobeView.glyph_scale(3.2), 1.0, 0.001)
	assert_lt(GlobeView.glyph_scale(1.4), 0.6, "smaller on the globe when zoomed in")
	assert_almost_eq(GlobeView.glyph_scale(6.0), 1.3, 0.001, "capped zoomed out")
	assert_almost_eq(GlobeView.glyph_scale(3.2, true), 1.0, 0.001, "hand-held: the same at the default zoom")
	assert_gt(GlobeView.glyph_scale(1.4, true), GlobeView.glyph_scale(1.4), "hand-held zooms less, so glyphs shrink less")


func test_glyphs_hide_on_the_far_side_only() -> void:
	var to_cam := Vector3(0, 0, 1)
	assert_true(GlobeView.faces_camera(Vector3(0, 0, 1.006), to_cam), "facing the camera")
	assert_true(GlobeView.faces_camera(Vector3(0.9, 0, 0.44), to_cam), "near the limb, still in view")
	assert_false(GlobeView.faces_camera(Vector3(1, 0, 0), to_cam), "on the limb")
	assert_false(GlobeView.faces_camera(Vector3(0, 0, -1), to_cam), "behind the globe")


func test_survey_card_shows_the_hud_planet_percent() -> void:
	var g := GlobeView.new()
	autofree(g)
	# Flat survey (no provider): its own whole-planet count.
	var flat: Array = g.headline(250, 1000)
	assert_eq(str(flat[0]), "25.000 %")
	assert_almost_eq(float(flat[2]), 0.25, 0.0001)
	# Round game: the HUD's number, digit for digit, and a line that says what it measures.
	for f: float in [0.0, 0.00002, 0.00261, 0.0421, 0.5]:
		g.planet_fraction_fn = func() -> float: return f
		var head: Array = g.headline(250, 1000)
		assert_eq(str(head[0]), "%s %%" % HUD.fmt_small_pct(f * 100.0), "same digits as the HUD at %f" % f)
		assert_almost_eq(float(head[2]), f, 0.000001, "the bar follows the same number")
		assert_ne(str(head[1]), str(flat[1]), "the line under it names the HUD's meaning")
	assert_eq(HUD.fmt_small_pct(0.261), "0.261")
	assert_eq(HUD.fmt_small_pct(0.0), "0.0000")


func test_a_world_has_one_system_map() -> void:
	var w := Node.new()
	add_child_autofree(w)
	var a: SystemMap = SystemMap.shared(w)
	var b: SystemMap = SystemMap.shared(w)
	assert_same(a, b, "the orbit set-up and the Homeward campaign get the same node")
	assert_eq(a.world, w)
	var n: int = 0
	for c: Node in w.get_children():
		if c is SystemMap:
			n += 1
	assert_eq(n, 1)
	# The Homeward director joins a world that already has the orbit set-up's map.
	var d: HomewardDirector = HomewardDirector.new()
	autofree(d)
	d.world = w
	d.map = SystemMap.shared(w)
	assert_same(d.map, a)
