extends GutTest
## RuinLights: a ruined town's few lamps that still glow after dark, with a cap on real lights.


func _heads(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append([Transform3D(Basis(), Vector3(float(i) * 10.0, 5.0, 0.0)), Color(1.0, 0.86, 0.62)])
	return out


func _lights(n: int, share: float, cap: int) -> RuinLights:
	var rl := RuinLights.new()
	add_child_autofree(rl)
	rl.setup(_heads(n), share, 4471, cap)
	return rl


func test_only_a_share_of_the_lamps_stays_alive() -> void:
	var rl: RuinLights = _lights(200, 0.25, 6)
	assert_between(rl.alive_count(), 30, 70, "about one lamp in four")


func test_real_lights_are_capped() -> void:
	var rl: RuinLights = _lights(200, 0.25, 6)
	assert_eq(rl.light_count(), 6)
	rl.apply(1.0, Vector3.ZERO)
	var on: int = 0
	for c: Node in rl.get_children():
		if c is OmniLight3D and (c as OmniLight3D).visible:
			on += 1
			assert_false((c as OmniLight3D).shadow_enabled, "no shadows from the pool lights")
	assert_eq(on, 6, "never more real lights than the cap")


func test_lights_follow_the_eye_and_go_out_by_day() -> void:
	var rl: RuinLights = _lights(200, 0.25, 2)
	rl.apply(1.0, Vector3(1990.0, 5.0, 0.0))
	var far_x: float = (rl.get_node("Pool0") as Node3D).position.x
	rl.apply(1.0, Vector3(0.0, 5.0, 0.0))
	assert_lt((rl.get_node("Pool0") as Node3D).position.x, far_x, "the pool moved to the lamps near the eye")
	rl.apply(0.0, Vector3.ZERO)
	assert_false((rl.get_node("Pool0") as Node3D).visible, "off by day")
	assert_false((rl.get_node("Heads") as Node3D).visible)


func test_darkness_follows_local_time() -> void:
	assert_almost_eq(RuinLights.darkness(0.5), 0.0, 0.001, "noon")
	assert_almost_eq(RuinLights.darkness(0.0), 1.0, 0.001, "midnight")
	assert_gt(RuinLights.darkness(0.76), 0.3, "dusk already glows")
