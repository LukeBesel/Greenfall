extends GutTest
## [intro2] Escape pod and crash site: the pod builds with its named parts, the door opens to the
## lean-corrected angle, and the crash site mends with upgrades (no extra save state).

var _up: Dictionary


func before_each() -> void:
	_up = GameState.upgrades.duplicate(true)


func after_each() -> void:
	GameState.upgrades = _up


func test_pod_parts() -> void:
	var pod: Node3D = EscapePod.build()
	add_child_autofree(pod)
	for n: String in ["Body", "Hatch", "Scorch", "PodLight", "Spill", "Beacon", "Fin0"]:
		assert_not_null(pod.get_node_or_null(n), n)
	EscapePod.set_open(pod, true, 0.2)
	assert_almost_eq((pod.get_node("Hatch") as Node3D).rotation.x, EscapePod.OPEN - 0.2, 0.001)
	EscapePod.set_open(pod, false)
	assert_eq((pod.get_node("Hatch") as Node3D).rotation.x, 0.0)


func test_stage_follows_upgrades() -> void:
	GameState.upgrades = {}
	assert_eq(CrashSite.stage_for_upgrades(), 0)
	GameState.upgrades = {"scoop": 1}
	assert_eq(CrashSite.stage_for_upgrades(), 1)
	GameState.upgrades = {"scoop": 2, "speed": CrashSite.REPAIR_LEVELS}
	assert_eq(CrashSite.stage_for_upgrades(), 2)


func test_site_mends_on_upgrade() -> void:
	GameState.upgrades = {}
	var root := Node3D.new()
	add_child_autofree(root)
	var site: CrashSite = CrashSite.attach(root, EscapePod.build(), Vector3.ZERO, 0.5)
	assert_eq(site.stage, 0)
	assert_true((site.pod.get_node("Smoke") as CPUParticles3D).emitting)
	GameState.upgrades = {"scoop": CrashSite.REPAIR_LEVELS}
	EventBus.upgrade_bought.emit("scoop", CrashSite.REPAIR_LEVELS)
	assert_eq(site.stage, 2)
	var m: ShaderMaterial = (site.pod.get_node("Body") as MeshInstance3D).mesh.surface_get_material(0)
	assert_lt(float(m.get_shader_parameter("heat")), 0.1, "repaired paint is clean")
	assert_true((site.pod.get_node("HoverGlow") as Node3D).visible, "restored pods hover-glow")
	GameState.upgrades = {"scoop": CrashSite.PLANTER_LEVELS}
	EventBus.upgrade_bought.emit("scoop", CrashSite.PLANTER_LEVELS)
	assert_eq(site.stage, 3)
	assert_true((site.pod.get_node("Planter") as Node3D).visible)
	assert_false((site.pod.get_node("Smoke") as CPUParticles3D).emitting)
