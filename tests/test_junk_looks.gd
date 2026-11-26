extends GutTest
## [art3] Junk looks (planet/junk_looks.gd, data/junk_looks.json) only change what is drawn. These
## pin what the rest of the game relies on: every look names a real junk model and a real kit
## piece, a look is fitted onto its host's base (so the piece's own seat holds), the pick is the
## same from run to run, and the litter carpet's kinds match its atlas.


func test_every_look_names_a_junk_model_and_a_kit_piece() -> void:
	var looks: Dictionary = JunkLooks.data().get("looks", {})
	assert_gt(looks.size(), 5, "looks are listed")
	for model: String in looks:
		assert_true(AssetLib.has_model(model), "host model exists: " + model)
		var total: float = 0.0
		for v: Dictionary in looks[model]:
			total += float(v.get("share", 0.0))
			assert_not_null(JunkLooks.kit_mesh(str(v["mesh"]), 0), "kit piece lod0: " + str(v["mesh"]))
			assert_not_null(JunkLooks.kit_mesh(str(v["mesh"]), 1), "kit piece lod1: " + str(v["mesh"]))
		assert_lte(total, 1.0, "shares of %s leave room for the model itself or fill it" % model)


func test_a_look_sits_on_its_hosts_base_and_centre() -> void:
	for look: String in JunkLooks.all_looks():
		var host: AABB = AssetLib.model_aabb(JunkLooks.host(look))
		var box: AABB = JunkLooks.look_aabb(look, "")
		assert_almost_eq(box.position.y, host.position.y, 0.002, look + " stands on the host's base")
		assert_almost_eq(box.get_center().x, host.get_center().x, 0.002, look + " centred in x")
		assert_almost_eq(box.get_center().z, host.get_center().z, 0.002, look + " centred in z")
		assert_gte(JunkLooks.lie_drop(look), 0.0, look + " is never pushed up")
		var limit: float = maxf(host.size.length() * 0.577, JunkLooks.MAX_SIZE)
		assert_lte(box.size.length() * 0.577, limit + 0.001, look + " is drawn no bigger than its model (StartArea's 0.6 m rule, with the 1.1 scale jitter)")
		var near: Mesh = JunkLooks.look_mesh(look, 0)
		var far: Mesh = JunkLooks.look_mesh(look, 1)
		assert_eq(near.get_surface_count(), 1, look + " is one draw")
		assert_lt(JunkLod._tris(near), 360, look + " near mesh stays within the Low budget")
		assert_lt(JunkLod._tris(far), JunkLod._tris(near), look + " far mesh is lighter")


func test_pick_is_stable_and_follows_the_shares() -> void:
	var n: Dictionary = {}
	for k: int in 4000:
		var a: String = JunkLooks.pick("Television_01", k)
		assert_eq(a, JunkLooks.pick("Television_01", k))
		n[a] = int(n.get(a, 0)) + 1
	var share: float = float(JunkLooks.variants("Television_01")[0]["share"])
	assert_almost_eq(float(n.get("Television_01#0", 0)) / 4000.0, share, 0.04)
	assert_eq(JunkLooks.pick("old_tyre", 5), "", "a model without looks draws as itself")


func test_dressed_scan_keeps_its_shape() -> void:
	var src: Mesh = AssetLib.model_mesh_lite("trashbag", 320)
	var out: Mesh = JunkLooks.dressed(src, "trashbag")
	assert_eq(out.get_surface_count(), src.get_surface_count())
	assert_eq(JunkLod._tris(out), JunkLod._tris(src))
	assert_true(out.get_aabb().is_equal_approx(src.get_aabb()))
	assert_true(out.surface_get_material(0) is ShaderMaterial)


func test_litter_kinds_match_the_atlas() -> void:
	assert_eq(SphereLitter.KINDS.size(), 16, "4 x 4 atlas cells")
	assert_eq(SphereLitter.ITEM_SLOTS.size(), SphereLitter.LOGIC_MESHES - 4, "nine tiny-item draws map onto the item meshes")
	for s: int in SphereLitter.ITEM_SLOTS:
		assert_between(s, 1, 3)
