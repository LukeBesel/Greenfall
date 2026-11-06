class_name Intro
extends Node
## Opening cinematic on a fresh game (~55 s, letterboxed, skippable with Esc / Space / Enter / A).
## Tells how Lumi got here:
##   A. Space: Verdance below, the ark Cradle glides past (title). Inside the seed vault, Lumi
##      hums to a tray of seedlings.
##   B. A meteor storm: meteors streak past, one hits, alarms go red. In the vault Lumi grabs the
##      tray and climbs into a cargo pod; the breach blows the pod out and the ark sails on.
##   C. The fall: re-entry fire around the tumbling pod, then the old junk city rushing up.
##   D. The crash beside the old shack, the hatch drops, Lumi drifts out nearly flat: eyes and
##      core flicker, a battery readout appears, and WREN explains green light and the plan.
## Phases A-C play in a SpaceStage (its own little 3D world); D plays in the game world.
## The pod stays in the world afterwards as a landmark. Dev: --intro-from=0..3 starts at a phase.

signal finished

var world: Node
var running: bool = false
## True from _finish() until the fade-out has handed the camera and controls back.
var ending: bool = false

var _cam: Camera3D
var _prev_cam: Camera3D
var _layer: CanvasLayer
var _stage_layer: CanvasLayer
var _stage: SpaceStage
var _fade: ColorRect
var _title: Label
var _sub: Label
var _skip: Label
var _battery: Control
var _battery_pct: Label
var _battery_cells: Array[ColorRect] = []
var _bars: Array[ColorRect] = []
var _pod: Node3D
var _hatch: Node3D
var _fire: Node3D
var _skipped: bool = false
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_dur: float = 1.0
var _cam_t: float = 0.0
## The landing chase drives the camera itself.
var _cam_manual: bool = false
var _hold_tray: bool = false
var _flicker: float = 0.0
var _t: float = 0.0

const POD_POS := Vector3(6.0, 0.0, 9.5)
const WREN_CLEAR := 2
const WREN_GLITCH := 0


## Builds the pod prop (also used after the intro as a landmark, and by the cinematic sets).
static func build_pod() -> Node3D:
	var pod := Node3D.new()
	pod.name = "LandingPod"
	var shell: ShaderMaterial = Mats.worn_paint(Color(0.88, 0.88, 0.85), 0.8, 0.35, 21.0, 0.6)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var accent: ShaderMaterial = Mats.worn_paint(Color(1.0, 0.55, 0.18), 0.85, 0.3, 5.0, 0.5)
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.capsule(0.75, 2.2)
	body.material_override = shell
	body.position = Vector3(0, 0.95, 0)
	body.rotation_degrees = Vector3(0, 0, 8)
	pod.add_child(body)
	for k: int in 3:
		var fin := MeshInstance3D.new()
		fin.mesh = ProcMesh.rounded_box(Vector3(0.12, 0.7, 0.5), 0.04, 2)
		fin.material_override = dark
		var a: float = TAU * k / 3.0
		fin.position = Vector3(cos(a) * 0.72, 0.4, sin(a) * 0.72)
		fin.rotation = Vector3(0, -a, 0)
		pod.add_child(fin)
	var band := MeshInstance3D.new()
	band.mesh = ProcMesh.torus(0.72, 0.8, 32, 6)
	band.material_override = accent
	band.position = Vector3(0.06, 1.25, 0)
	band.rotation_degrees = Vector3(0, 0, 8)
	pod.add_child(band)
	var window := MeshInstance3D.new()
	window.mesh = ProcMesh.cyl(0.22, 0.22, 0.05, 24)
	window.material_override = Mats.lamp(Color(0.3, 0.85, 1.0), 1.5)
	window.position = Vector3(0.18, 1.7, -0.68)
	window.rotation_degrees = Vector3(90, 0, 8)
	pod.add_child(window)
	# Hatch (front), hinged at the bottom.
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = Vector3(0.05, 0.35, -0.72)
	pod.add_child(hatch)
	var door := MeshInstance3D.new()
	door.mesh = ProcMesh.rounded_box(Vector3(0.8, 1.1, 0.08), 0.06, 2)
	door.material_override = shell
	door.position = Vector3(0, 0.55, 0)
	hatch.add_child(door)
	var stripe := MeshInstance3D.new()
	stripe.mesh = ProcMesh.box(Vector3(0.6, 0.05, 0.02))
	stripe.material_override = Mats.lamp(Color(1.0, 0.6, 0.2), 2.0)
	stripe.position = Vector3(0, 0.9, -0.05)
	hatch.add_child(stripe)
	# Scorched crater ring.
	var scorch := MeshInstance3D.new()
	scorch.name = "Scorch"
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.08, 0.07, 0.06, 0.75)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 1.0
	scorch.mesh = ProcMesh.cyl(1.8, 1.8, 0.01, 32)
	scorch.material_override = sm
	scorch.position = Vector3(0, 0.02, 0)
	pod.add_child(scorch)
	return pod


## Re-entry plasma: nested glowing cones trailing behind (+Y) a falling pod. See _flicker_fire.
static func build_fire() -> Node3D:
	var f := Node3D.new()
	f.name = "ReentryFire"
	var cols: Array[Color] = [Color(1.0, 0.95, 0.8), Color(1.0, 0.6, 0.2), Color(0.9, 0.25, 0.08)]
	for k: int in 3:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.95 + k * 0.32
		cm.height = 3.2 + k * 2.6
		cm.radial_segments = 16
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		c.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(cols[k].r * 1.6, cols[k].g * 1.6, cols[k].b * 1.6, 0.55 - k * 0.12)
		c.material_override = m
		c.position = Vector3(0, cm.height * 0.5 - 0.6, 0)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(c)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.light_energy = 6.0
	glow.omni_range = 12.0
	f.add_child(glow)
	return f


static func _flicker_fire(fire: Node3D, t: float) -> void:
	var k: int = 0
	for c: Node in fire.get_children():
		if c is MeshInstance3D:
			var s: float = 1.0 + sin(t * (31.0 + k * 7.0)) * 0.08 + randf_range(-0.06, 0.06)
			(c as Node3D).scale = Vector3(s, 1.0 + randf_range(-0.1, 0.12), s)
			k += 1
		elif c is OmniLight3D:
			(c as OmniLight3D).light_energy = 5.0 + randf_range(-1.5, 1.5)


func should_play() -> bool:
	if DevHooks.has("intro"):
		return true
	if GameState.flags.get("intro_done", false):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	for f: String in ["shot", "autoplay", "open", "spawn-pos", "spawn-hex", "robots", "no-intro"]:
		if DevHooks.has(f):
			return false
	return true


## Places the pod landmark (called every load once the intro has happened).
func place_pod() -> void:
	if _pod == null:
		_pod = build_pod()
		world.add_child(_pod)
	_pod.visible = true
	_pod.global_position = POD_POS + Vector3(0, _ground(POD_POS), 0)
	_pod.rotation = Vector3(0, 0.5, 0)
	_hatch = _pod.get_node("Hatch")
	_hatch.rotation.x = -1.45
	if _fire and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null


func _ground(p: Vector3) -> float:
	var layout: CityLayout = world.field.layout
	return clampf(layout.height_at(p.x, p.z), 0.0, 0.3) if layout else 0.0


func _model() -> PatchModel:
	return world.patch.get("model") as PatchModel


func play() -> void:
	running = true
	var patch: Node3D = world.patch
	_set_player_enabled(false)
	if world.get("hud") != null:
		world.hud.visible = false
	if world.get("music") != null:
		world.music.set_cinematic(true)
	_build_overlay()
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 900.0
	world.add_child(_cam)
	_cam.current = true
	_pod = build_pod()
	world.add_child(_pod)
	_hatch = _pod.get_node("Hatch")
	_pod.rotation.y = 0.5
	_pod.visible = false
	patch.visible = false
	var model: PatchModel = _model()
	if model:
		model.sleeping = true
	var from: int = int(DevHooks.get_f("intro-from", 0.0))
	print("[intro] start (phase %d)" % from)
	if from <= 2:
		_open_stage()
	if from <= 0:
		await _phase_ark()
	if from <= 1 and not _skipped:
		await _phase_storm()
	if from <= 2 and not _skipped:
		await _phase_fall()
	if not _skipped:
		_close_stage()
		await _phase_landing()
	if not _skipped:
		_finish()


# --- A: the ark and the seed vault ------------------------------------------------------

func _phase_ark() -> void:
	var st: SpaceStage = _stage
	st.show_set("space")
	var ark: CradleShip = st.ark
	ark.rotation = Vector3(0, -PI * 0.5, 0)  # fly toward +X
	ark.position = Vector3(-34, 0, 0)
	ark.create_tween().tween_property(ark, "position", Vector3(6, 0, 0), 9.0)
	st.shot(Vector3(30, 9, 52), Vector3(-6, -8, 0), Vector3(16, 5, 40), Vector3(4, -4, 0), 9.0, 42.0, 38.0)
	_fade_to(0.0, 2.5)
	if await _hold(1.4):
		return
	_show_title("GREENFALL", "Three hundred years ago, the last seeds left Verdance aboard the ark Cradle.")
	if await _hold(4.2):
		return
	_hide_title()
	if await _hold(0.9):
		return
	# Inside: the seed vault. Lumi hums to the seedlings.
	await _cut(func() -> void:
		st.show_set("vault")
		var v: Vector3 = SpaceStage.VAULT_AT
		st.lumi.position = Vector3(-0.2, 0.15, -1.05)
		st.lumi.rotation.y = PI - 0.15
		st.lumi.sleeping = false
		st.lumi.set_happy(1.0)
		st.lumi.look_toward(v + Vector3(0, 0.9, 0))
		st.shot(v + Vector3(1.9, 1.35, 0.9), v + Vector3(-0.3, 0.8, -0.7), v + Vector3(1.35, 1.15, 0.45), v + Vector3(-0.25, 0.8, -0.75), 7.5, 42.0, 36.0))
	if _skipped:
		return
	_subtitle("Lumi, the ark's little seed-keeper, sang to the seedlings every night.")
	var hum_t: float = 0.0
	var next_note: float = 0.0
	var said: bool = false
	while hum_t < 5.6 and not _skipped:
		hum_t += get_process_delta_time()
		if hum_t >= next_note:
			next_note += 0.55
			st.note(st.lumi.global_position + Vector3(randf_range(-0.1, 0.2), 1.1, 0.2))
			Audio.play("chirp" if Audio.has_sound("chirp") else "blip", randf_range(1.2, 1.7), -18.0)
		st.lumi.rotation.z = sin(hum_t * 3.0) * 0.06
		if hum_t > 1.6 and not said:
			said = true
			_wren("Humming again, Lumi? They can't hear you, you know. ...They do grow faster when you do.", WREN_CLEAR)
		await get_tree().process_frame
	st.lumi.rotation.z = 0.0


# --- B: the meteor storm, the breach, the pod -------------------------------------------

func _phase_storm() -> void:
	var st: SpaceStage = _stage
	var ark: CradleShip = st.ark
	await _cut(func() -> void:
		st.show_set("space")
		st.set_alarm(0.0)
		ark.rotation = Vector3(0, -PI * 0.5, 0)
		ark.position = Vector3(-12, 0, 0)
		ark.create_tween().tween_property(ark, "position", Vector3(2, 0, 0), 6.0)
		st.shot(Vector3(10, -9, 30), Vector3(-6, -1, 0), Vector3(4, -7, 24), Vector3(-3, -1, 0), 6.0, 46.0, 44.0))
	if _skipped:
		return
	_subtitle("Then, one night, the sky came apart.")
	Audio.play("whoosh", 0.6, -6.0)
	for i: int in 9:
		var a := Vector3(randf_range(-80, -30), randf_range(30, 60), randf_range(-40, 20))
		var b := a + Vector3(110, -95, randf_range(-10, 30))
		st.meteor(a, b, randf_range(1.2, 1.8), randf_range(0.6, 1.4))
		if await _hold(0.22):
			return
	# The hit: a meteor slams into the belly near the cargo pods.
	var hit: Vector3 = ark.pod_world(2) + Vector3(0, -0.4, 0)
	st.meteor(hit + Vector3(-40, 34, 8), hit, 0.6, 1.2)
	if await _hold(0.6):
		return
	st.blast(hit, 1.6)
	st.set_alarm(1.0)
	Audio.play("thud", 0.4, 2.0)
	Audio.play("crunch", 0.5, -2.0)
	_flash_alarm()
	if await _hold(1.6):
		return
	# Vault: red alarm. Lumi takes the tray and climbs into the cargo pod.
	var v: Vector3 = SpaceStage.VAULT_AT
	await _cut(func() -> void:
		st.show_set("vault")
		st.set_alarm(1.0)
		st.shake = 0.5
		st.lumi.look_toward(null)
		st.lumi.set_happy(0.2)
		st.shot(v + Vector3(-2.9, 2.3, -2.6), v + Vector3(0, 0.9, 0.6), v + Vector3(-2.2, 1.9, -1.4), v + Vector3(0, 1.0, 1.8), 6.0, 50.0, 46.0), 0.15)
	if _skipped:
		return
	_subtitle("")
	_wren("Hull breach in the vault bay! Lumi, leave the trays, get clear!", WREN_CLEAR)
	for i: int in 2:
		st.debris(v + Vector3(randf_range(-2, 2), 3.6, 3.5), 5, 2.5, 0.4)
	Audio.play("servo", 1.0, -6.0)
	if await _hold(0.9):
		return
	# Lumi will not leave them. Grab the tray.
	var lumi: PatchModel = st.lumi
	lumi.holding = true
	_hold_tray = true
	Audio.play("chirp" if Audio.has_sound("chirp") else "blip", 1.6, -6.0)
	if await _hold(0.8):
		return
	var path := lumi.create_tween()
	path.tween_property(lumi, "position", Vector3(0.9, 0.15, 0.9), 1.0).set_trans(Tween.TRANS_SINE)
	path.parallel().tween_property(lumi, "rotation:y", PI + 0.5, 1.0)
	path.tween_property(lumi, "position", Vector3(0.0, 0.25, 3.45), 1.0).set_trans(Tween.TRANS_SINE)
	path.parallel().tween_property(lumi, "rotation:y", PI, 0.6)
	if await _hold(2.2):
		return
	var vh: Node3D = st.vault_pod.get_node("Hatch")
	vh.create_tween().tween_property(vh, "rotation:x", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	Audio.play("hydraulic", 1.1, -4.0)
	if await _hold(0.7):
		return
	lumi.visible = false
	_hold_tray = false
	st.tray.visible = false
	Audio.play("clunk" if Audio.has_sound("clunk") else "thud", 0.8, -2.0)
	if await _hold(0.5):
		return
	# Outside: the pod is blown loose and tumbles away; the ark sails on.
	await _cut(func() -> void:
		st.show_set("space")
		st.set_alarm(1.0)
		ark.position = Vector3(0, 0, 0)
		ark.create_tween().tween_property(ark, "position", Vector3(30, 0, 0), 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		st.pod.visible = true
		st.pod.global_position = ark.pod_world(2) + Vector3(0, -1.0, 0)
		st.pod.rotation = Vector3(0.3, 0.0, 0.2)
		st.aim(Vector3(-6, -12, 22), st.pod.global_position, 48.0), 0.1)
	if _skipped:
		return
	st.blast(st.pod.global_position + Vector3(0, 0.5, 0), 1.0, Color(1.0, 0.85, 0.6))
	st.debris(st.pod.global_position, 18, 6.0, 0.8, Vector3(0, -1, 0))
	Audio.play("whoosh", 0.5, 0.0)
	var t: float = 0.0
	var start: Vector3 = st.pod.global_position
	var said: bool = false
	while t < 4.6 and not _skipped:
		var dt: float = get_process_delta_time()
		t += dt
		st.pod.global_position = start + Vector3(-2.6 * t, -3.2 * t - 0.4 * t * t, 1.6 * t)
		st.pod.rotate_object_local(Vector3(1, 0, 0.4).normalized(), dt * 2.2)
		if randf() < 0.35:
			st.puff(st.pod.global_position + Vector3(randf_range(-0.6, 0.6), 0.8, 0), Vector3(randf_range(-1, 1), 2.0, 0), Color(0.9, 0.93, 0.97, 0.45), 0.6)
		if randf() < 0.25:
			st.puff(ark.pod_world(2), Vector3(randf_range(-2, 2), -3.0, randf_range(-1, 1)), Color(0.9, 0.93, 0.97, 0.4), 0.8)
		# The camera hangs back and lets the pod fall past while the ark recedes.
		var look: Vector3 = st.pod.global_position.lerp(ark.global_position, clampf((t - 2.5) / 3.0, 0.0, 0.55))
		st.aim(Vector3(-6, -12, 22).lerp(Vector3(-10, -22, 26), t / 4.6), look, lerpf(48.0, 56.0, t / 4.6))
		if t > 0.8 and not said:
			said = true
			_wren("Lumi— hold on— I can't turn her around— hold on—", WREN_GLITCH)
		await get_tree().process_frame


# --- C: the fall ------------------------------------------------------------------------

func _phase_fall() -> void:
	var st: SpaceStage = _stage
	_fade_to(1.0, 0.6)
	if await _hold(0.7):
		return
	st.set_alarm(0.0)
	st.ark.visible = false
	_subtitle("The ark could not turn back. The pod fell for days.")
	# Re-entry: the pod tumbles toward Verdance wrapped in fire.
	st.show_set("space")
	st.pod.visible = true
	var fire: Node3D = build_fire()
	st.pod.add_child(fire)
	var top: Vector3 = st.planet.global_position + Vector3(0, SpaceStage.PLANET_R, 0)
	var p0: Vector3 = top + Vector3(-30, 120, 70)
	st.pod.global_position = p0
	st.env.ambient_light_color = Color(0.45, 0.3, 0.2)
	_fade_to(0.0, 0.8)
	var vel := Vector3(8.0, -10.0, -6.0)
	var dir: Vector3 = vel.normalized()
	var t: float = 0.0
	while t < 4.6 and not _skipped:
		var dt: float = get_process_delta_time()
		t += dt
		var pos: Vector3 = p0 + vel * t
		st.pod.global_position = pos
		# Nose-first into the air: the fire trails up and back.
		st.pod.look_at(pos + dir, Vector3.UP)
		st.pod.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		st.pod.rotate_object_local(Vector3.UP, t * 1.4)
		_flicker_fire(fire, t)
		st.shake = 0.35
		st.aim(pos + Vector3(-5.5, 4.5, 7.5) - dir * 1.5, pos + dir * 2.0 + Vector3(0, -2.0, 0), 52.0)
		if randf() < 0.6:
			st.puff(pos - dir * randf_range(2.0, 5.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), -dir * 6.0, Color(1.0, 0.55, 0.25, 0.35), 0.7)
		await get_tree().process_frame
	if _skipped:
		return
	Audio.play("whoosh", 0.35, 0.0)
	_fade_to(1.0, 0.35)
	await _hold(0.4)


# --- D: the city rushes up, the crash, the wake-up --------------------------------------

func _phase_landing() -> void:
	var patch: Node3D = world.patch
	var model: PatchModel = _model()
	var land: Vector3 = POD_POS + Vector3(0, _ground(POD_POS), 0)
	_pod.visible = true
	var start: Vector3 = land + Vector3(-60, 150, 40)
	_pod.global_position = start
	_fire = build_fire()
	_pod.add_child(_fire)
	# Chase shot: riding above the burning pod, the junk city rushing up below.
	_fade_to(0.0, 0.3)
	_subtitle("")
	Audio.play("whoosh", 0.4, 0.0)
	var trail_t: float = 0.0
	var dur: float = 3.0
	var dir: Vector3 = (land - start).normalized()
	_cam_manual = true
	while trail_t < dur and not _skipped:
		var dt: float = get_process_delta_time()
		trail_t += dt
		var k: float = clampf(trail_t / dur, 0.0, 1.0)
		var pos: Vector3 = start.lerp(land, k * k)
		_pod.global_position = pos
		_pod.look_at(pos + dir, Vector3.UP)
		_pod.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		_pod.rotate_object_local(Vector3.UP, trail_t * 2.0)
		_flicker_fire(_fire, trail_t)
		if k < 0.7:
			# Above and behind, looking down past the pod at the city.
			_cam.global_position = pos - dir * 9.0 + Vector3(2.5, 4.0, 0)
			_cam.look_at(pos + dir * 30.0, Vector3.UP)
			_cam.fov = 62.0
		elif _cam_manual:
			_cam_manual = false
			_cam.fov = 55.0
			_shot(land + Vector3(-13, 3.5, 15), land + Vector3(-6, 12, 6), land + Vector3(-11, 3, 13), land + Vector3(0, 1.5, 0), dur * 0.3)
		if randf() < 0.7:
			Vfx.burst("steam", pos - dir * 2.0, Color(0.45, 0.42, 0.4, 0.8), 0.7)
			Vfx.burst("sparkle", pos, Color(1.0, 0.6, 0.25), 0.3)
		await get_tree().process_frame
	_cam_manual = false
	if _skipped:
		return
	_pod.global_position = land
	_pod.rotation = Vector3(0, 0.5, 0)
	_fire.queue_free()
	_fire = null
	Audio.play("thud", 0.5, 4.0)
	Audio.play("crunch", 0.6, 0.0)
	EventBus.shake_requested.emit(1.0)
	for i: int in 8:
		Vfx.burst("dust", land + Vector3(randf_range(-1.8, 1.8), 0.3, randf_range(-1.8, 1.8)), Color(0.6, 0.55, 0.48, 0.8), 1.6)
	Vfx.burst("bits", land + Vector3(0, 0.5, 0), Color(0.4, 0.38, 0.34), 1.0)
	_shot(land + Vector3(-11, 3, 13), land + Vector3(0, 1.5, 0), land + Vector3(-9, 2.4, 11), land + Vector3(0, 1.2, 0), 2.0)
	if await _hold(1.4):
		return
	# Close on the hatch: steam, it drops open, Lumi drifts out nearly powerless.
	var front: Vector3 = _pod.global_transform * Vector3(0, 0.8, -3.2)
	_shot(front + Vector3(0.6, 0.6, 0.0), land + Vector3(0, 1.0, 0), front + Vector3(0.3, 0.2, 0.6), land + Vector3(0, 0.8, 0), 5.0)
	if await _hold(0.6):
		return
	for i: int in 4:
		Vfx.burst("steam", _pod.global_transform * Vector3(0, 0.9, -0.8), Color(0.9, 0.92, 0.95, 0.7), 1.0)
	Audio.play("steam", 0.7, -2.0)
	if await _hold(0.6):
		return
	Audio.play("hydraulic", 0.8, -4.0)
	create_tween().tween_property(_hatch, "rotation:x", -1.45, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if await _hold(1.0):
		return
	var out_from: Vector3 = _pod.global_transform * Vector3(0, 0.3, -0.3)
	var out_to: Vector3 = _pod.global_transform * Vector3(0, 0.05, -2.2)
	out_to.y = _ground(out_to) + 0.05
	patch.visible = true
	patch.global_position = out_from
	patch.look_at(patch.global_position + (out_to - out_from) * Vector3(1, 0, 1), Vector3.UP)
	patch.rotate_object_local(Vector3.UP, PI)
	if model:
		model.core_glow = 0.25
	create_tween().tween_property(patch, "global_position", out_to, 2.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if await _hold(2.2):
		return
	# Face close-up: the eyes stutter on, dim. The core is nearly empty.
	var fwd: Vector3 = (out_to - out_from).normalized()
	var face_cam: Vector3 = out_to + fwd * 1.6 + Vector3(0.3, 0.75, 0)
	_shot(face_cam, out_to + Vector3(0, 0.75, 0), face_cam + Vector3(0, -0.05, 0) - fwd * 0.3, out_to + Vector3(0, 0.7, 0), 7.0)
	if await _hold(0.8):
		return
	if model:
		for i: int in 3:
			model.sleeping = false
			Audio.play("blip", 0.6 + i * 0.1, -8.0)
			if await _hold(0.12):
				return
			model.sleeping = true
			if await _hold(0.3):
				return
		model.sleeping = false
		Audio.play("servo", 0.8, -8.0)
		model.set_happy(0.3)
	_flicker = 1.0
	_show_battery()
	Audio.play("error" if Audio.has_sound("error") else "blip", 0.5, -8.0)
	if await _hold(1.2):
		return
	if model:
		model.look_toward(out_to + Vector3(-3, 1, 2))
	if await _hold(0.9):
		return
	if model:
		model.look_toward(out_to + Vector3(3, 1, 2))
	_wren("...Lumi? ...Lumi. The relay's barely holding, but I've got you. You're down. You're on Verdance.", WREN_GLITCH)
	if await _hold(4.4):
		return
	if model:
		model.look_toward(null)
	# Pull back so the battery readout and Lumi share the frame.
	_shot(_cam.global_position, out_to + Vector3(0, 0.7, 0), out_to + fwd * 3.2 + Vector3(1.4, 1.5, 0.6), out_to + Vector3(0, 0.6, 0), 12.0)
	_wren("Your core runs on green light, the glow living things give off. There's no green left down there. That's why you're fading.", WREN_GLITCH)
	if await _hold(5.6):
		return
	_wren("So we make some. Clean the ground, plant those seedlings. Every bloom feeds your core.", 1)
	if model:
		model.set_happy(0.7)
		model.flash()
		Audio.play("chirp" if Audio.has_sound("chirp") else "blip", 1.3, -6.0)
	if await _hold(4.2):
		return
	_wren("Fill your Bloom Core. Rebuild a launch site. Then you fly home to us. ...One can at a time.", 1)
	await _hold(4.6)


# --- Overlay ------------------------------------------------------------------------------

func _open_stage() -> void:
	_stage_layer = CanvasLayer.new()
	_stage_layer.layer = 2
	add_child(_stage_layer)
	_stage = SpaceStage.new()
	_stage_layer.add_child(_stage)
	# The game world isn't on screen while the stage is: skip rendering it.
	get_viewport().disable_3d = true


func _close_stage() -> void:
	get_viewport().disable_3d = false
	if _stage_layer and is_instance_valid(_stage_layer):
		_stage_layer.queue_free()
	_stage_layer = null
	_stage = null


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_layer.add_child(root)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 0)
		if top:
			bar.offset_bottom = 70
		else:
			bar.offset_top = -70
		root.add_child(bar)
		_bars.append(bar)
	_title = UITheme.label("", 64, Color(1, 1, 1))
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 0)
	_title.modulate.a = 0.0
	root.add_child(_title)
	_sub = UITheme.label("", 18, Color(0.9, 0.92, 0.95))
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub.offset_top = -64
	_sub.offset_bottom = -30
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.modulate.a = 0.0
	root.add_child(_sub)
	_skip = UITheme.label("Space / Esc  skip", 12, Color(1, 1, 1, 0.45))
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -170
	_skip.offset_top = 24
	root.add_child(_skip)
	_build_battery(root)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


## Low-battery readout (top left, under the letterbox): BLOOM CORE, five cells, 4%.
func _build_battery(root: Control) -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(48, 96)
	box.add_theme_constant_override("separation", 4)
	box.modulate.a = 0.0
	root.add_child(box)
	_battery = box
	box.add_child(UITheme.label("B L O O M   C O R E", 12, Color(1, 1, 1, 0.6)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 3)
	row.add_child(cells)
	for i: int in 5:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(16, 26)
		c.color = Color(1, 1, 1, 0.12)
		cells.add_child(c)
		_battery_cells.append(c)
	var nub := ColorRect.new()
	nub.custom_minimum_size = Vector2(4, 12)
	nub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nub.color = Color(1, 1, 1, 0.25)
	cells.add_child(nub)
	_battery_pct = UITheme.label("%d%%" % int(round(CoreCharge.START * 100.0)), 26, Color(1.0, 0.45, 0.3))
	row.add_child(_battery_pct)
	box.add_child(UITheme.label("GREEN LIGHT  ·  NONE DETECTED", 12, Color(1.0, 0.6, 0.4, 0.85)))


func _show_battery() -> void:
	create_tween().tween_property(_battery, "modulate:a", 1.0, 0.5)


func _show_title(t: String, sub: String) -> void:
	_title.text = t + "\n"
	var s := UITheme.label(sub, 16, Color(1, 1, 1, 0.75))
	s.name = "TitleSub"
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.grow_horizontal = Control.GROW_DIRECTION_BOTH
	s.offset_top = 30
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.modulate.a = 0.0
	_title.get_parent().add_child(s)
	create_tween().tween_property(_title, "modulate:a", 1.0, 1.2)
	create_tween().tween_property(s, "modulate:a", 1.0, 1.6)


func _hide_title() -> void:
	create_tween().tween_property(_title, "modulate:a", 0.0, 0.8)
	var s: Node = _title.get_parent().get_node_or_null("TitleSub")
	if s:
		create_tween().tween_property(s, "modulate:a", 0.0, 0.8)


## Narration caption in the bottom letterbox bar.
func _subtitle(t: String) -> void:
	_sub.text = t
	_sub.modulate.a = 0.0
	if t != "":
		create_tween().tween_property(_sub, "modulate:a", 1.0, 0.4)


## WREN speaks through the game's subtitle line (stage 0 = broken-up signal).
func _wren(t: String, stage: int) -> void:
	if world.get("wren") != null:
		world.wren.line_started.emit(t, stage)
	else:
		_subtitle("WREN:  " + t)


func _flash_alarm() -> void:
	var red := ColorRect.new()
	red.color = Color(1.0, 0.1, 0.05, 0.0)
	red.set_anchors_preset(Control.PRESET_FULL_RECT)
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(red)
	_title.get_parent().move_child(red, 0)
	var tw := red.create_tween()
	for i: int in 3:
		tw.tween_property(red, "color:a", 0.28, 0.12)
		tw.tween_property(red, "color:a", 0.0, 0.35)
	tw.tween_callback(red.queue_free)
	Audio.play("error" if Audio.has_sound("error") else "blip", 0.45, -4.0)


## A quick dip to black: run the set change at the darkest point, then fade back up.
func _cut(change: Callable, dur: float = 0.35) -> void:
	_fade_to(1.0, dur)
	if await _hold(dur):
		return
	change.call()
	_fade_to(0.0, dur)


func _fade_to(a: float, dur: float) -> void:
	create_tween().tween_property(_fade, "color:a", a, dur)


func _shot(from: Vector3, from_look: Vector3, to: Vector3, to_look: Vector3, dur: float) -> void:
	_cam_from = Transform3D(Basis(), from).looking_at(from_look, Vector3.UP)
	_cam_to = Transform3D(Basis(), to).looking_at(to_look, Vector3.UP)
	_cam_dur = maxf(dur, 0.01)
	_cam_t = 0.0
	if _cam:
		_cam.global_transform = _cam_from


func _process(delta: float) -> void:
	if not running:
		return
	_t += delta
	if _cam and not _cam_manual:
		_cam_t += delta
		var k: float = clampf(_cam_t / _cam_dur, 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		_cam.global_transform = _cam_from.interpolate_with(_cam_to, e)
	if _hold_tray and _stage:
		var lumi: PatchModel = _stage.lumi
		_stage.tray.global_position = lumi.claw_point() + Vector3(0, 0.02, 0)
		_stage.tray.global_rotation = Vector3(0, lumi.global_rotation.y, 0)
	# Low battery: the core and eyes stutter, the readout blinks.
	if _flicker > 0.0:
		var model: PatchModel = _model()
		var g: float = 0.3 + 0.15 * sin(_t * 3.0) - (0.2 if randf() < 0.08 else 0.0)
		if model:
			model.core_glow = maxf(0.05, g)
		var on: bool = fmod(_t, 1.0) < 0.6
		_battery_pct.modulate.a = 1.0 if on else 0.35
		_battery_cells[0].color = Color(1.0, 0.35, 0.25, 0.9 if on else 0.4)


## Waits s seconds; returns true if the intro was skipped meanwhile.
func _hold(s: float) -> bool:
	if _skipped:
		return true
	await get_tree().create_timer(s).timeout
	return _skipped


func _unhandled_input(event: InputEvent) -> void:
	if not running or _skipped:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		_skipped = true
		_finish()


func _finish() -> void:
	if not running:
		return
	running = false
	ending = true
	_hold_tray = false
	_flicker = 0.0
	_cam_manual = false
	var patch: Node3D = world.patch
	var model: PatchModel = _model()
	place_pod()
	if patch.global_position.distance_to(POD_POS) > 6.0 or _skipped or not patch.visible:
		patch.global_position = Vector3(0, 0.05, 3.0)
	GameState.flags["intro_done"] = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void:
		ending = false
		_close_stage()
		patch.visible = true
		if model:
			model.sleeping = false
			model.set_happy(0.6)
			model.look_toward(null)
			model.core_glow = CoreCharge.glow_for_flags()
		var modal: bool = world.has_method("any_modal_open") and world.any_modal_open()
		if _prev_cam and is_instance_valid(_prev_cam) and not modal:
			_prev_cam.current = true
		if _cam:
			_cam.queue_free()
			_cam = null
		if world.get("hud") != null and not modal:
			world.hud.visible = true
		if world.get("music") != null:
			world.music.set_cinematic(false)
		for b: ColorRect in _bars:
			b.visible = false
		_title.visible = false
		_sub.visible = false
		_skip.visible = false
		_battery.visible = false
		if not modal:
			_set_player_enabled(true)
		print("[intro] finished (skipped=%s, input restored=%s)" % [_skipped, not modal]))
	tw.tween_property(_fade, "color:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		_layer.queue_free()
		finished.emit())


## The intro (or its fade-out) still owns the camera and controls.
func busy() -> bool:
	return running or ending


func _set_player_enabled(on: bool) -> void:
	var patch: Node = world.patch
	if patch.get("input") is PlayerInput:
		(patch.input as PlayerInput).enabled = on
	if world.get("cam") != null:
		world.cam.input_enabled = on
