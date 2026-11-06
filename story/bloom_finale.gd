class_name BloomFinale
extends Node3D
## Post-game story beat: "Verdance Bloom". The planet has bloomed enough for the Cradle to wake.
## A short letterboxed cinematic (like story/first_seed.gd): the camera circles Patch and tilts up,
## glowing seed pods fall from orbit and burst into petals, WREN and the Cradle speak, and the
## Seed Ark loop opens. Frees itself when done.

const LINES: Array[Array] = [
	["Lumi. Stop for a second. Look up.", 3.5],
	["Something is moving in orbit. It's the Cradle. My Cradle. The seed bays are opening on their own.", 6.0],
	["CRADLE:  GROUND REPORT RECEIVED.  GREEN DETECTED.  RESUMING SEED SCHEDULE.", 5.5],
	["It hasn't said a word in three hundred years. It was waiting for proof that the soil remembered how.", 6.0],
	["CRADLE:  CARETAKER WREN.  GOOD WORK.  ...GOOD WORK, SMALL ROBOT.", 5.0],
	["It called you small. From the Cradle, that's a compliment. I checked.", 4.5],
	["From now on it sends Seed Ark waves. Every bloom, anywhere on Verdance, fills the next one.", 6.0],
	["Nothing is waiting to end, {name}. Nobody is keeping score. We just keep planting.", 5.5],
]

var world: Node
var _bars: Array[ColorRect] = []
var _letterbox: CanvasLayer


func _total_time() -> float:
	var t: float = 0.0
	for l: Array in LINES:
		t += float(l[1])
	return t


func play() -> void:
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
	var cam: CameraRig = world.cam
	var hud: CanvasLayer = world.hud
	hud.visible = false
	cam.input_enabled = false
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	_set_bars(90.0)
	Audio.play("fanfare", 0.7, -8.0)
	var start_yaw: float = cam.yaw
	var dist0: float = cam.distance
	var pitch0: float = cam.pitch
	cam.distance = 5.0
	var total: float = _total_time()
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		cam.yaw = start_yaw + v * 2.4
		cam.pitch = lerpf(-0.25, -0.08, sin(v * PI)), 0.0, 1.0, total)
	var name_s: String = str(GameState.flags.get("patch_name", "Lumi"))
	var i: int = 0
	for l: Array in LINES:
		world.wren.line_started.emit(str(l[0]).format({"name": name_s}), 2)
		if i == 1 or i == 2 or i == 6:
			_seed_rain(8 if i != 2 else 14)
		await get_tree().create_timer(float(l[1])).timeout
		i += 1
	_set_bars(0.0)
	cam.distance = dist0
	cam.pitch = pitch0
	hud.visible = true
	cam.input_enabled = true
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = true
	if world.get("music") != null:
		world.music.set_cinematic(false)
	Audio.music_sting("level_up")
	EventBus.toast.emit("The Seed Ark is open: every bloom on Verdance counts toward the next wave. Progress shows on the hologram (M).", "story")
	await get_tree().create_timer(1.0).timeout
	queue_free()


func _set_bars(h: float) -> void:
	for k: int in _bars.size():
		var tw := create_tween()
		tw.tween_property(_bars[k], "offset_bottom" if k == 0 else "offset_top", h if k == 0 else -h, 0.8)


## Glowing seed pods drift down from orbit around Patch and burst into petals on landing.
func _seed_rain(count: int) -> void:
	var c: Vector3 = (world.patch as Node3D).global_position
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 1.0, 0.55)
	mat.emission_energy_multiplier = 3.0
	for k: int in count:
		var pod := MeshInstance3D.new()
		pod.mesh = ProcMesh.sphere(0.18, 10, 5)
		pod.material_override = mat
		add_child(pod)
		var a: float = randf() * TAU
		var land: Vector3 = c + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 14.0)
		pod.global_position = land + Vector3(randf_range(-6, 6), randf_range(40.0, 60.0), randf_range(-6, 6))
		var tw := pod.create_tween()
		tw.tween_interval(randf_range(0.0, 2.5))
		tw.tween_property(pod, "global_position", land + Vector3(0, 0.3, 0), randf_range(2.2, 3.4)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Vfx.burst("big_sparkle", land + Vector3(0, 0.4, 0), Color(0.75, 1.0, 0.6), 0.6)
			Vfx.burst("confetti", land + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.9), 0.4)
			Audio.play("chime", randf_range(1.1, 1.6), -12.0)
			pod.queue_free())
