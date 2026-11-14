extends GutTest
## [photo] Photo mode: filters, poses, open guards and a full open/close restore round trip.


class StubPatch extends Node3D:
	var model: PatchModel


class StubIntro extends Node:
	var running: bool = false

	func busy() -> bool:
		return running


class StubWorld extends Node3D:
	var patch: StubPatch
	var hud: CanvasLayer
	var sky_director: SkyDirector
	var intro: StubIntro
	var launching: bool = false
	var modal: bool = false

	func any_modal_open() -> bool:
		return modal


func _world() -> StubWorld:
	var w := StubWorld.new()
	add_child_autofree(w)
	w.patch = StubPatch.new()
	w.add_child(w.patch)
	w.patch.model = PatchModel.new()
	w.patch.add_child(w.patch.model)
	w.hud = CanvasLayer.new()
	w.add_child(w.hud)
	w.intro = StubIntro.new()
	w.add_child(w.intro)
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = PhysicalSkyMaterial.new()
	env.sky = sky
	env.glow_intensity = 0.55
	var sun := DirectionalLight3D.new()
	w.add_child(sun)
	w.sky_director = SkyDirector.new()
	w.add_child(w.sky_director)
	w.sky_director.setup(env, sun)
	w.sky_director.time_of_day = 0.4
	w.sky_director._apply()
	return w


func test_filters_cover_the_presets() -> void:
	var names: Array[String] = PhotoFilters.names()
	assert_eq(names.size(), 8)
	for n: String in ["Natural", "Golden Hour", "Dawn Mist", "Neon Night", "Film", "Mono", "Holo Blue", "Bloom"]:
		assert_has(names, n)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/photo_grade.gdshader")
	for id: String in PhotoFilters.ORDER:
		var v: Dictionary = PhotoFilters.values(id)
		for k: String in ["contrast", "saturation", "warmth", "vignette", "grain", "glow", "split", "mono"]:
			assert_true(v.has(k), "%s has %s" % [id, k])
		assert_between(float(v["contrast"]), 0.6, 1.5)
		assert_between(float(v["saturation"]), 0.0, 1.6)
		PhotoFilters.apply(mat, v)
	assert_eq(float(PhotoFilters.values("mono")["mono"]), 1.0)
	assert_eq(PhotoFilters.index_of("nope"), 0)


func test_poses_and_eyes() -> void:
	var ids: Array[String] = PhotoPoser.pose_ids()
	assert_gte(ids.size(), 11, "at least 10 expressive poses plus the plain hover")
	var seen: Dictionary = {}
	var p := PhotoPoser.new()
	autofree(p)
	var keys: Array = p.target("idle", 0.0).keys()
	for id: String in ids:
		assert_false(seen.has(id), "unique pose id " + id)
		seen[id] = true
		var d: Dictionary = p.target(id, 1.3)
		assert_eq(d.keys().size(), keys.size(), id)
		for k: String in d:
			var v: Variant = d[k]
			if v is float:
				assert_false(is_nan(v), "%s.%s finite" % [id, k])
	assert_ne(p.target("wave", 0.2)["sh_r"], p.target("idle", 0.2)["sh_r"])
	assert_gt(float(p.target("cheer", 0.0)["happy"]), 0.9, "happy pose shows ^ ^ eyes")
	for e: Array in PhotoPoser.EYES:
		if e[0] != "auto":
			assert_false(PhotoPoser.eye_values(str(e[0])).is_empty(), "eye option " + str(e[0]))


func test_poser_restores_lumi_exactly() -> void:
	var m := PatchModel.new()
	add_child_autofree(m)
	m._process(0.016)
	var before: Dictionary = {}
	var nodes: Array[Node3D] = [m._float, m._head, m._arm_r, m._arm_l, m._arm_r.get_meta("elbow"), m._arm_r.get_meta("wrist")]
	for n: Node3D in nodes:
		before[n] = n.transform
	var p := PhotoPoser.new()
	add_child_autofree(p)
	p.attach(m)
	assert_eq(m.process_mode, Node.PROCESS_MODE_ALWAYS, "Lumi keeps animating while paused")
	for pose: String in ["wave", "sit", "holo", "scan", "sleepy"]:
		p.pose = pose
		for i: int in 20:
			p._process(0.05)
	assert_ne(m._arm_r.transform, before[m._arm_r])
	p.restore()
	for n: Node3D in nodes:
		assert_eq(n.transform, before[n], "restored " + str(n.name))
	assert_eq(m.process_mode, Node.PROCESS_MODE_INHERIT)


func test_cannot_open_during_flights_and_cinematics() -> void:
	var w: StubWorld = _world()
	var pm := PhotoMode.new()
	pm.world = w
	add_child_autofree(pm)
	var had: Variant = GameState.flags.get("yard_global")
	GameState.flags["yard_global"] = {}
	assert_eq(pm.block_reason(), "locked", "[camp3] no photo mode before Blink, the camera bot, is built")
	YardBuilds.mark_built(CameraBot.ID)
	assert_eq(pm.block_reason(), "")
	w.launching = true
	assert_string_contains(pm.block_reason(), "rocket")
	w.launching = false
	w.intro.running = true
	assert_string_contains(pm.block_reason(), "cinematic")
	w.intro.running = false
	w.hud.visible = false
	assert_string_contains(pm.block_reason(true), "cinematic")
	w.hud.visible = true
	w.modal = true
	assert_eq(pm.block_reason(), "modal")
	assert_eq(pm.block_reason(true), "", "the pause menu path is allowed")
	w.modal = false
	assert_false(pm.is_open)
	if had == null:
		GameState.flags.erase("yard_global")
	else:
		GameState.flags["yard_global"] = had


func test_open_close_restores_everything() -> void:
	var w: StubWorld = _world()
	var pm := PhotoMode.new()
	pm.world = w
	add_child_autofree(pm)
	var tree: SceneTree = get_tree()
	var env: Environment = w.sky_director.env
	var time0: float = w.sky_director.time_of_day
	var fog0: float = env.fog_density
	var glow0: float = env.glow_intensity
	var sun_rot0: Vector3 = w.sky_director.sun.rotation
	var model: PatchModel = w.patch.model
	var xf0: Transform3D = model.transform
	var arm0: Transform3D = model._arm_r.transform
	pm.open()
	assert_true(pm.is_open)
	assert_true(tree.paused, "the world pauses")
	assert_true(tree.root.disable_3d, "the photo camera renders instead")
	assert_false(w.hud.visible, "HUD hidden by default")
	pm.set_value("time_override", true)
	pm.set_value("time", 0.8)
	pm.set_value("weather", 3)
	pm.set_value("filter", PhotoFilters.index_of("neon"))
	pm.set_value("pose", PhotoPoser.pose_ids().find("hero"))
	pm.set_value("turn", 90.0)
	for i: int in 10:
		pm._poser._process(0.05)
	assert_almost_eq(w.sky_director.time_of_day, 0.8, 0.001)
	assert_gt(env.glow_intensity, glow0)
	assert_ne(model.transform, xf0)
	pm.close()
	assert_false(pm.is_open)
	assert_false(tree.paused)
	assert_false(tree.root.disable_3d)
	assert_true(w.hud.visible)
	assert_almost_eq(w.sky_director.time_of_day, time0, 0.0001)
	assert_almost_eq(env.fog_density, fog0, 0.00001)
	assert_almost_eq(env.glow_intensity, glow0, 0.00001)
	assert_eq(w.sky_director.sun.rotation, sun_rot0)
	assert_eq(model.transform, xf0)
	assert_eq(model._arm_r.transform, arm0)
	assert_eq(model.process_mode, Node.PROCESS_MODE_INHERIT)


func test_shot_paths_are_timestamped_pngs() -> void:
	var p: String = PhotoMode.next_shot_path()
	assert_true(p.begins_with("user://screenshots/greenfall_"), p)
	assert_true(p.ends_with(".png"))
	assert_true(Settings.REBINDABLE.any(func(e: Array) -> bool: return e[0] == "photo_mode"))
	assert_true(InputMap.has_action("photo_mode"))
