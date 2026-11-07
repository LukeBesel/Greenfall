class_name BloomFinale
extends Node3D
## Post-game story beat: "Verdance Bloom". Lumi's Bloom Core is full (story/core_charge.gd) and the
## planet is green enough: the ark Cradle comes home. A letterboxed cinematic: the ark descends out
## of the sky over Lumi, opens its seed bays and lowers a beam of light; Lumi waves; glowing seed
## pods fall and burst into petals; WREN and the Cradle speak; the Seed Ark loop opens. The ark
## stays parked over the district (CoreCharge re-places it on later loads). Always hands the
## camera, HUD and controls back.

## True while the finale owns the screen (CoreCharge waits for it).
static var playing: bool = false

# l10n:begin
const LINES: Array[Array] = [
	["Lumi. Stop for a second. Look up.", 3.5],
	["Your core just hit full. Every bloom on Verdance is shining green, and the Cradle can see all of it.", 6.0],
	["CRADLE:  GREEN DETECTED.  SEED-KEEPER LM-1 LOCATED.  BEGINNING DESCENT.", 5.5],
	["Three hundred years we waited up there for proof the soil remembered how. You were the proof.", 6.0],
	["CRADLE:  WELCOME HOME, SMALL ROBOT.  ...WELCOME HOME, VERDANCE.", 5.0],
	["It called you small. From the Cradle, that's a compliment. I checked.", 4.5],
	["The seed bays are open. From now on every bloom, anywhere on Verdance, fills the next Seed Ark wave.", 6.0],
	["Nothing is waiting to end, {name}. Nobody is keeping score. We're home. We just keep planting.", 5.5],
]
# l10n:end
## Where the ark parks, relative to the district spawn.
const PARK := Vector3(-6.0, 62.0, -70.0)

var world: Node
var _bars: Array[ColorRect] = []
var _letterbox: CanvasLayer
var _cam: Camera3D
var _prev_cam: Camera3D
var _ark: CradleShip
var _beam: MeshInstance3D
var _restored: bool = false


func _total_time() -> float:
	var t: float = 0.0
	for l: Array in LINES:
		t += float(l[1])
	return t


## The parked ark (also used by CoreCharge on later loads).
static func park_ark(parent: Node, center: Vector3) -> CradleShip:
	var ark := CradleShip.new()
	ark.name = "CradleParked"
	ark.scale = Vector3.ONE * 1.6
	parent.add_child(ark)
	ark.global_position = center + PARK
	ark.rotation.y = 0.4
	ark.thrust = 0.3
	return ark


func play() -> void:
	playing = true
	print("[finale] the Cradle comes home")
	_letterbox = CanvasLayer.new()
	_letterbox.layer = 25
	add_child(_letterbox)
	for top: bool in [true, false]:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.anchor_right = 1.0
		r.anchor_top = 0.0 if top else 1.0
		r.anchor_bottom = 0.0 if top else 1.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letterbox.add_child(r)
		_bars.append(r)
	if world.get("music") != null:
		world.music.set_cinematic(true)
	world.hud.visible = false
	world.cam.input_enabled = false
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	_set_bars(90.0)
	Audio.play("fanfare", 0.7, -8.0)
	var patch: Node3D = world.patch
	var c: Vector3 = patch.global_position
	var model: PatchModel = patch.get("model") as PatchModel
	# The ark: from high in the sky down to its parking spot over the district.
	var old: Node = world.get_node_or_null("CradleParked")
	if old:
		old.free()
	_ark = park_ark(world, c)
	var park: Vector3 = _ark.global_position
	_ark.global_position = park + Vector3(-160, 220, -260)
	_ark.thrust = 1.6
	var desc := _ark.create_tween()
	desc.tween_interval(3.0)
	desc.tween_property(_ark, "global_position", park, 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	desc.parallel().tween_property(_ark, "thrust", 0.3, 16.0)
	# Our own camera: low beside Lumi, looking up past it toward the ark.
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 1200.0
	world.add_child(_cam)
	_cam.current = true
	var name_s: String = str(GameState.flags.get("patch_name", "Lumi"))
	var total: float = _total_time()
	var line_i: int = 0
	var next_line: float = 0.0
	var t: float = 0.0
	var waved: bool = false
	while t < total:
		t += get_process_delta_time()
		if t >= next_line and line_i < LINES.size():
			var l: Array = LINES[line_i]
			world.wren.line_started.emit(tr(str(l[0])).format({"name": name_s}), 2)
			if line_i == 2 or line_i == 6 or line_i == 7:
				_seed_rain(8 if line_i != 6 else 14)
			if line_i == 4:
				_open_beam(c)
			next_line += float(l[1])
			line_i += 1
		var k: float = t / total
		var yaw: float = 0.6 + k * 1.6
		var cam_pos: Vector3 = c + Vector3(sin(yaw), 0, cos(yaw)) * lerpf(5.5, 7.5, k) + Vector3(0, lerpf(0.8, 1.8, k), 0)
		var look: Vector3 = (c + Vector3(0, 1.0, 0)).lerp(_ark.global_position, clampf(0.62 - absf(k - 0.45) * 0.6, 0.25, 0.62))
		_cam.global_position = cam_pos
		_cam.look_at(look, Vector3.UP)
		if model:
			model.look_toward(_ark.global_position)
			# Lumi waves up at the ark when it says welcome home.
			if line_i >= 5 and not waved:
				waved = true
				model.set_happy(1.0)
				model.flash()
				Audio.play("chirp" if Audio.has_sound("chirp") else "blip", 1.4, -6.0)
			if waved and line_i <= 6:
				model.holding = fmod(t, 0.8) < 0.4
		await get_tree().process_frame
	_restore()
	GameState.flags["bloom_finale_seen"] = true  # [beat] only once it has played through
	Audio.music_sting("level_up")
	# [beat] The end credits roll once, after the first finale; then the game simply carries on.
	if not GameState.flags.get("credits_seen", false):
		GameState.flags["credits_seen"] = true
		await get_tree().create_timer(1.5).timeout
		var roll: CreditsRoll = CreditsRoll.play(world)
		print("[finale] credits rolling")
		await roll.finished
		print("[finale] credits done; the game goes on")
	EventBus.toast.emit(tr("The Cradle is home. The Seed Ark is open: every bloom on Verdance counts toward the next wave. Progress shows on the hologram (M)."), "story")
	await get_tree().create_timer(1.0).timeout
	queue_free()


func _restore() -> void:
	if _restored:
		return
	_restored = true
	playing = false
	_set_bars(0.0)
	var model: PatchModel = world.patch.get("model") as PatchModel
	if model:
		model.holding = false
		model.look_toward(null)
	if _beam and is_instance_valid(_beam):
		_beam.queue_free()
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	if _cam and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	world.hud.visible = true
	world.cam.input_enabled = true
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = true
	if world.get("music") != null:
		world.music.set_cinematic(false)


func _exit_tree() -> void:
	if playing and not _restored:
		_restore()


func _set_bars(h: float) -> void:
	for k: int in _bars.size():
		var tw := create_tween()
		tw.tween_property(_bars[k], "offset_bottom" if k == 0 else "offset_top", h if k == 0 else -h, 0.8)


## A soft cyan beam from the ark's belly down to Lumi.
func _open_beam(c: Vector3) -> void:
	var top: Vector3 = _ark.pod_world(2)
	var h: float = maxf(top.y - c.y, 1.0)
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 3.5
	cm.height = h
	cm.radial_segments = 24
	cm.cap_top = false
	cm.cap_bottom = false
	_beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.3, 0.9, 1.0, 0.0)
	m.disable_fog = true
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	# Tilt the cylinder so its axis runs from Lumi up to the ark.
	var axis: Vector3 = (top - c).normalized()
	var b := Basis()
	b.y = axis
	b.x = axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	b.z = b.x.cross(b.y).normalized()
	_beam.global_transform = Transform3D(b, (top + c) * 0.5)
	_beam.scale = Vector3(1, (top - c).length() / h, 1)
	_beam.create_tween().tween_property(m, "albedo_color:a", 0.16, 1.5)
	Audio.play("chime", 0.8, -6.0)


## Glowing seed pods drift down from the ark around Lumi and burst into petals on landing.
func _seed_rain(count: int) -> void:
	var c: Vector3 = (world.patch as Node3D).global_position
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 1.0, 0.55)
	mat.emission_energy_multiplier = 3.0
	var from: Vector3 = _ark.global_position if _ark else c + Vector3(0, 50, 0)
	for k: int in count:
		var pod := MeshInstance3D.new()
		pod.mesh = ProcMesh.sphere(0.18, 10, 5)
		pod.material_override = mat
		add_child(pod)
		var a: float = randf() * TAU
		var land: Vector3 = c + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 14.0)
		pod.global_position = from + Vector3(randf_range(-8, 8), randf_range(-4.0, 0.0), randf_range(-8, 8))
		var tw := pod.create_tween()
		tw.tween_interval(randf_range(0.0, 2.5))
		tw.tween_property(pod, "global_position", land + Vector3(0, 0.3, 0), randf_range(3.2, 4.4)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Vfx.burst("big_sparkle", land + Vector3(0, 0.4, 0), Color(0.75, 1.0, 0.6), 0.6)
			Vfx.burst("confetti", land + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.9), 0.4)
			Audio.play("chime", randf_range(1.1, 1.6), -12.0)
			pod.queue_free())
