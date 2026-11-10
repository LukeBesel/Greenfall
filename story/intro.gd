class_name Intro
extends Node
## Opening cinematic on a fresh game (~95 s, letterboxed, skippable with Esc / Space / Enter / A).
## [intro2] Paced for reading: every story line goes through the game's one subtitle line
## (ui/subtitles.gd, one line at a time at the bottom) and each beat waits for its lines.
## Tells how Lumi got here:
##   A. Space: Verdance below, the ark Cradle glides past (title). Inside the seed vault, Lumi
##      hums to a tray of seedlings.
##   B. A meteor storm: meteors streak past, one hits, alarms go red. In the vault Lumi grabs the
##      tray and climbs into a cargo pod; the breach blows the pod out and the ark sails on.
##   C. The fall: re-entry fire around the tumbling pod, then the old junk city rushing up.
##   D. The crash beside the old shack, the hatch drops, Lumi drifts out nearly flat: eyes and
##      core flicker, a battery readout appears, and WREN explains green light and the plan.
## Phases A-C play in a SpaceStage (its own little 3D world); D plays in the game world.
## The pod stays in the world afterwards as a landmark. Dev: --intro-from=0..5 starts at a phase
## (3 = the city chase, 4 = the crash, 5 = the wake-up).

signal finished

var _cover: CanvasLayer  # [first]
var world: Node
var running: bool = false
## True from _finish() until the fade-out has handed the camera and controls back.
var ending: bool = false
var _waiting: bool = false
## [intro3] WREN's brief was played inside the intro (the objectives only reveal their card).
var brief_played: bool = false

var _cam: Camera3D
var _prev_cam: Camera3D
var _layer: CanvasLayer
var _stage_layer: CanvasLayer
var _stage: SpaceStage
var _fade: ColorRect
var _title: Label
var _skip: Label
var _battery: Control
var _battery_pct: Label
var _battery_cells: Array[ColorRect] = []
var _bars: Array[ColorRect] = []
var _pod: Node3D
var _hatch: Node3D
var _fire: Node3D
var _site: CrashSite
var _pauser: StoryPause
## [intro2] Rewatching from the Codex: the world is put back exactly as it was afterwards.
var _replay: bool = false
var _replay_xf := Transform3D()
var _replay_pod: Node3D
var _replay_site: CrashSite
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
## [intro2] Rebuilt in story/escape_pod.gd: a real door opening, no overlapping faces.
static func build_pod() -> Node3D:
	var pod: Node3D = EscapePod.build()
	GlimDirector.cling_to(pod)  # [v4calm] item 43: Glim holds on to the pod until he's repaired
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
	if place_pod_fn.is_valid():  # [orbE] the globe places its own pod (same spot, its colliders)
		if _site and is_instance_valid(_site):
			_site.queue_free()
		elif _pod and is_instance_valid(_pod):
			_pod.queue_free()
		_site = null
		_pod = null
		place_pod_fn.call()
		return
	if _pod == null:
		_pod = build_pod()
		world.add_child(_pod)
	_pod.visible = true
	_crash_pose()
	_hatch = _pod.get_node("Hatch")
	EscapePod.set_open(_pod, true, CrashSite.LEAN.x)
	PropColliders.fit(PropColliders.body(_pod, "Props"), _pod)  # [world2] the landed pod is solid
	PropColliders.push_out_pieces(_pod, world.field, world.get("view"))
	if _fire and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null


## [intro2] The pod in its crash site (furrow, lean, smoke, sparks; mends with upgrades).
func _crash_pose() -> void:
	if _site and is_instance_valid(_site):
		return
	var fire: Node = _pod.get_node_or_null("ReentryFire")
	if fire:
		fire.queue_free()
	_site = CrashSite.attach(world, _pod, _w(POD_POS), 0.5)  # [orbE]
	_site.global_basis = site_xf.basis.orthonormalized()  # [orbE] lie on the pad's own plane


# --- [orbE] Round planet: the in-world shots in the pod site's frame -----------------------
## The landing and wake shots are written in site-local coordinates around POD_POS (+Y up).
## site_xf maps them onto the pod anchor's frame (origin on the pad, +Y the local up), so every
## shot, the chase camera and Lumi's drift stay level on the curve. The slice sets it with
## site_for_anchor(pod anchor).
var site_xf := Transform3D.IDENTITY
## [orbE] The pod anchor's frame when the intro starts (anchors settle while loading), the
## slice's own pod placement at the end, and the SphereCam's hand-off.
var site_fn: Callable  # () -> Transform3D
var place_pod_fn: Callable  # () -> void
var cam_reset_fn: Callable  # () -> void


static func site_for_anchor(anchor: Transform3D) -> Transform3D:
	return anchor * Transform3D(Basis(), -POD_POS)


func _w(v: Vector3) -> Vector3:  # intro (site-local) coordinates -> world
	return site_xf * v


func _v(p: Vector3) -> Vector3:  # world -> intro coordinates
	return site_xf.affine_inverse() * p


func _up() -> Vector3:
	return site_xf.basis.y.normalized()


func _model() -> PatchModel:
	return world.patch.get("model") as PatchModel


## [first] Black cover for the frames between the scene loading and the (deferred) intro start, so
## the title screen's fade-to-black never flashes the gameplay world for a frame.
func cover_now() -> void:
	if _cover:
		return
	_cover = CanvasLayer.new()
	_cover.layer = 41
	var r := ColorRect.new()
	r.color = Color(0.02, 0.02, 0.03, 1.0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(r)
	add_child(_cover)


func _drop_cover() -> void:
	if _cover == null:
		return
	var c: CanvasLayer = _cover
	_cover = null
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(c):
		c.queue_free()


## Every line the intro says, by beat: [text, speaker] ("" = narration, "wren" = WREN), plus an
## optional "tail": the signal breaks up on the last words (heavy glitch on that span only).
## Kept in one place so tests can check the subtitle timing rule against all of them.
static func lines() -> Dictionary:
	var out: Dictionary = {
		"title": [Planets.current().name_in(TranslationServer.translate("Three hundred years ago, the last seeds left {planet} aboard the ark Cradle.")), ""],
		"vault": [TranslationServer.translate("Lumi, the ark's little seed-keeper, sang to the seedlings every night."), ""],
		"hum": [TranslationServer.translate("Humming again, Lumi? They can't hear you, you know. ...They do grow faster when you do."), "wren"],
		"storm": [TranslationServer.translate("Then, one night, the sky came apart."), ""],
		"breach": [TranslationServer.translate("Hull breach in the vault bay! Lumi, leave the trays, get clear!"), "wren"],
		"hold_on": [TranslationServer.translate("Lumi— hold on— I can't turn her around— hold on—"), "wren", "tail"],
		"fall": [TranslationServer.translate("The ark could not turn back. The pod fell for days."), ""],
	}
	# [intro3] At the crash WREN gets ONE last message through before the relay dies: onboarding's
	# brief (data/objectives.json "brief"), its last words breaking up in a [glitch] span. She is
	# silent after that until the signal tower is built.
	var brief: Array = brief_lines()
	for i: int in brief.size():
		out["brief_%d" % i] = [TranslationServer.translate(str(brief[i])), "wren"]
	return out


## The brief's raw lines from the planet's "tutorial" table (translated when shown).
static func brief_lines() -> Array:
	return (Economy.planet_table("tutorial").get("brief", {}) as Dictionary).get("lines", [])


## Rewatch the whole intro from the Codex. A temporary pod plays the landing; afterwards Lumi, the
## real crash site and the camera are restored; nothing in the save changes.
func replay() -> void:
	if running or ending or _waiting:
		return
	_replay = true
	_skipped = false
	_t = 0.0
	_bars.clear()
	_battery_cells.clear()
	_replay_xf = world.patch.global_transform
	_replay_pod = _pod
	_replay_site = _site
	if _site and is_instance_valid(_site):
		_site.visible = false
	_site = null
	print("[intro] replay")
	play()


func _end_replay() -> void:
	if _site and is_instance_valid(_site):
		_site.queue_free()  # the temporary landing (its pod with it)
	elif _pod and is_instance_valid(_pod) and _pod != _replay_pod:
		_pod.queue_free()
	_pod = _replay_pod
	_site = _replay_site
	if _site and is_instance_valid(_site):
		_site.visible = true
	if _pod and is_instance_valid(_pod):
		_hatch = _pod.get_node("Hatch")
	world.patch.global_transform = _replay_xf
	_replay = false


func play() -> void:
	# [intro2] Start once the loading screen has gone (its black cover stays up meanwhile).
	var ld: LoadingScreen = get_node_or_null("/root/Loader") as LoadingScreen
	if ld and ld.busy():
		_waiting = true
		_set_player_enabled(false)
		await ld.wait_done()
		_waiting = false
	if site_fn.is_valid():  # [orbE]
		site_xf = site_fn.call()
	running = true
	var patch: Node3D = world.patch
	_set_player_enabled(false)
	if world.get("hud") != null:
		world.hud.visible = false
	if world.get("music") != null:
		world.music.set_cinematic(true)
	_tunes_start()  # [tunes] The Fall of LM-1 from the first frame (before the motif, which it replaces)
	Audio.music_sting("motif")  # [sound] the Greenfall motif
	_build_overlay()
	_drop_cover()  # [first]
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


# --- Subtitle pacing ---------------------------------------------------------------------

## The world's subtitle line (or the intro's own if the world has none).
func _subs() -> Subtitles:
	if Subtitles.current and is_instance_valid(Subtitles.current):
		return Subtitles.current
	var s := Subtitles.new()
	s.world = world
	add_child(s)
	return s


## Queue one of lines() and return how long it will be on screen (all chunks, fades and gaps).
func _say(key: String) -> float:
	var l: Array = lines()[key]
	var text: String = str(l[0])
	if l.size() > 2 and str(l[2]) == "tail":
		text = glitch_tail(text)
	_subs().queue_line(text, str(l[1]))
	return Subtitles.total_time(text)


## Marks the last fragment of a line (after its last dash, else its last word) as breaking up.
static func glitch_tail(text: String) -> String:
	var t: String = text.strip_edges()
	var cut: int = -1
	for mark: String in ["— ", "—", "-- ", " "]:
		cut = t.rstrip("—").rfind(mark)
		if cut > 0:
			cut += mark.length()
			break
	if cut <= 0 or cut >= t.length():
		return text
	return t.substr(0, cut) + Subtitles.GLITCH_OPEN + t.substr(cut) + Subtitles.GLITCH_CLOSE


## Waits until every queued line has been shown (true if skipped meanwhile).
func _wait_lines(extra: float = 0.0) -> bool:
	var s: Subtitles = _subs()
	while s.is_busy() and not _skipped:
		await get_tree().process_frame
	if extra > 0.0 and not _skipped:
		return await _hold(extra)
	return _skipped


# --- A: the ark and the seed vault ------------------------------------------------------

func _phase_ark() -> void:
	var st: SpaceStage = _stage
	st.show_set("space")
	var ark: CradleShip = st.ark
	ark.rotation = Vector3(0, -PI * 0.5, 0)  # fly toward +X
	ark.position = Vector3(-46, 0, 0)
	ark.create_tween().tween_property(ark, "position", Vector3(10, 0, 0), 20.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	st.shot(Vector3(40, 12, 66), Vector3(-10, -8, 0), Vector3(20, 6, 46), Vector3(6, -3, 0), 20.0, 40.0, 36.0)
	_fade_to(0.0, 3.0)
	if await _hold(2.2):
		return
	_show_title("GREENFALL")
	if await _hold(1.4):
		return
	if await _hold(_say("title") + 0.6):
		return
	_hide_title()
	if await _hold(1.6):
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
		st.shot(v + Vector3(2.1, 1.45, 1.0), v + Vector3(-0.3, 0.8, -0.7), v + Vector3(1.3, 1.12, 0.4), v + Vector3(-0.25, 0.8, -0.75), 17.0, 42.0, 35.0), 0.6)
	if _skipped:
		return
	var dur: float = _say("vault") + _say("hum") + 0.8
	var hum_t: float = 0.0
	var next_note: float = 0.0
	while hum_t < dur and not _skipped:
		hum_t += get_process_delta_time()
		if hum_t >= next_note:
			next_note += 0.75
			st.note(st.lumi.global_position + Vector3(randf_range(-0.1, 0.2), 1.1, 0.2))
			Audio.play("chirp" if Audio.has_sound("chirp") else "blip", randf_range(1.2, 1.6), -19.0)
		st.lumi.rotation.z = sin(hum_t * 2.2) * 0.06
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
		ark.position = Vector3(-16, 0, 0)
		ark.create_tween().tween_property(ark, "position", Vector3(2, 0, 0), 10.0)
		st.shot(Vector3(14, -12, 40), Vector3(-6, -1, 0), Vector3(6, -9, 32), Vector3(-3, -1, 0), 10.0, 46.0, 43.0), 0.6)
	if _skipped:
		return
	var line_t: float = _say("storm")
	Audio.play("whoosh", 0.6, -6.0)
	for i: int in 12:
		var a := Vector3(randf_range(-90, -30), randf_range(30, 64), randf_range(-40, 20))
		var b := a + Vector3(120, -100, randf_range(-10, 30))
		st.meteor(a, b, randf_range(1.6, 2.3), randf_range(0.6, 1.4))
		if await _hold(0.34):
			return
	# The hit: a meteor slams into the belly near the cargo pods.
	var hit: Vector3 = ark.pod_world(2) + Vector3(0, -0.4, 0)
	st.meteor(hit + Vector3(-40, 34, 8), hit, 0.8, 1.3)
	if await _hold(0.8):
		return
	st.blast(hit, 1.8)
	st.set_alarm(1.0)
	Audio.play("thud", 0.4, 2.0)
	Audio.play("crunch", 0.5, -2.0)
	_flash_alarm()
	if await _hold(maxf(2.4, line_t - 4.9)):
		return
	if await _wait_lines():
		return
	# Vault: red alarm. Lumi takes the tray and climbs into the cargo pod.
	var v: Vector3 = SpaceStage.VAULT_AT
	await _cut(func() -> void:
		st.show_set("vault")
		st.set_alarm(1.0)
		st.shake = 0.5
		st.lumi.look_toward(null)
		st.lumi.set_happy(0.2)
		st.shot(v + Vector3(-3.0, 2.3, -2.7), v + Vector3(0, 0.9, 0.6), v + Vector3(-2.2, 1.9, -1.4), v + Vector3(0, 1.0, 1.8), 9.0, 50.0, 45.0), 0.25)
	if _skipped:
		return
	_say("breach")
	for i: int in 2:
		st.debris(v + Vector3(randf_range(-2, 2), 3.6, 3.5), 5, 2.5, 0.4)
	Audio.play("servo", 1.0, -6.0)
	if await _hold(1.6):
		return
	# Lumi will not leave them. Grab the tray.
	var lumi: PatchModel = st.lumi
	lumi.holding = true
	_hold_tray = true
	Audio.play("chirp" if Audio.has_sound("chirp") else "blip", 1.6, -6.0)
	if await _hold(1.1):
		return
	var path := lumi.create_tween()
	path.tween_property(lumi, "position", Vector3(0.9, 0.15, 0.9), 1.4).set_trans(Tween.TRANS_SINE)
	path.parallel().tween_property(lumi, "rotation:y", PI + 0.5, 1.4)
	path.tween_property(lumi, "position", Vector3(0.0, 0.25, 3.45), 1.4).set_trans(Tween.TRANS_SINE)
	path.parallel().tween_property(lumi, "rotation:y", PI, 0.8)
	if await _hold(3.0):
		return
	var shut: float = EscapePod.close_door(st.vault_pod, 0.8)
	Audio.play("hydraulic", 1.1, -4.0)
	if await _hold(shut * 0.7):
		return
	lumi.visible = false
	_hold_tray = false
	st.tray.visible = false
	if await _hold(shut * 0.3):
		return
	Audio.play("clunk" if Audio.has_sound("clunk") else "thud", 0.8, -2.0)
	st.puff(st.vault_pod.global_position + Vector3(0, 1.0, -0.9), Vector3(0, 0.6, -0.8), Color(0.9, 0.93, 0.97, 0.5), 0.5)
	if await _hold(0.9):
		return
	if await _wait_lines():
		return
	# Outside: the pod is blown loose and tumbles away; the ark sails on.
	await _cut(func() -> void:
		st.show_set("space")
		st.set_alarm(1.0)
		ark.position = Vector3(0, 0, 0)
		ark.create_tween().tween_property(ark, "position", Vector3(34, 0, 0), 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		st.pod.visible = true
		st.pod.global_transform = ark.pod_xform(2)  # exactly where it hung in the rack
		ark.release_pod(2)
		st.aim(Vector3(-8, -14, 26), st.pod.global_position, 48.0), 0.15)
	if _skipped:
		return
	st.blast(st.pod.global_position + Vector3(0, 0.5, 0), 1.0, Color(1.0, 0.85, 0.6))
	st.debris(st.pod.global_position, 18, 6.0, 0.8, Vector3(0, -1, 0))
	Audio.play("whoosh", 0.5, 0.0)
	var t: float = 0.0
	var start: Vector3 = st.pod.global_position
	var said: bool = false
	var span: float = 6.5
	while t < span and not _skipped:
		var dt: float = get_process_delta_time()
		t += dt
		st.pod.global_position = start + Vector3(-1.9 * t, -2.4 * t - 0.25 * t * t, 1.2 * t)
		st.pod.rotate_object_local(Vector3(1, 0, 0.4).normalized(), dt * 1.6)
		if randf() < 0.3:
			st.puff(st.pod.global_position + Vector3(randf_range(-0.6, 0.6), 0.8, 0), Vector3(randf_range(-1, 1), 2.0, 0), Color(0.9, 0.93, 0.97, 0.45), 0.6)
		if randf() < 0.22:
			st.puff(ark.pod_world(2), Vector3(randf_range(-2, 2), -3.0, randf_range(-1, 1)), Color(0.9, 0.93, 0.97, 0.4), 0.8)
		# The camera hangs back and lets the pod fall past while the ark recedes.
		var look: Vector3 = st.pod.global_position.lerp(ark.global_position, clampf((t - 3.0) / 3.5, 0.0, 0.55))
		st.aim(Vector3(-8, -14, 26).lerp(Vector3(-12, -24, 30), t / span), look, lerpf(48.0, 56.0, t / span))
		if t > 1.0 and not said:
			said = true
			span = maxf(span, 1.0 + _say("hold_on"))
		await get_tree().process_frame


# --- C: the fall ------------------------------------------------------------------------

func _phase_fall() -> void:
	var st: SpaceStage = _stage
	_fade_to(1.0, 0.9)
	if await _hold(1.0):
		return
	st.set_alarm(0.0)
	st.ark.visible = false
	var line_t: float = _say("fall")
	if await _hold(1.4):
		return
	# Re-entry: the pod tumbles toward Verdance wrapped in fire.
	st.show_set("space")
	st.pod.visible = true
	var fire: Node3D = build_fire()
	st.pod.add_child(fire)
	var top: Vector3 = st.planet.global_position + Vector3(0, SpaceStage.PLANET_R, 0)
	var p0: Vector3 = top + Vector3(-30, 120, 70)
	st.pod.global_position = p0
	st.env.ambient_light_color = Color(0.45, 0.3, 0.2)
	_fade_to(0.0, 1.2)
	var vel := Vector3(6.0, -7.5, -4.5)
	var dir: Vector3 = vel.normalized()
	var t: float = 0.0
	var span: float = maxf(6.5, line_t - 1.0)
	while t < span and not _skipped:
		var dt: float = get_process_delta_time()
		t += dt
		var pos: Vector3 = p0 + vel * t
		st.pod.global_position = pos
		# Nose-first into the air: the fire trails up and back.
		st.pod.look_at(pos + dir, Vector3.UP)
		st.pod.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		st.pod.rotate_object_local(Vector3.UP, t * 1.1)
		_flicker_fire(fire, t)
		st.shake = 0.3
		st.aim(pos + Vector3(-5.5, 4.5, 7.5) - dir * 1.5, pos + dir * 2.0 + Vector3(0, -2.0, 0), 52.0)
		if randf() < 0.6:
			st.puff(pos - dir * randf_range(2.0, 5.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), -dir * 6.0, Color(1.0, 0.55, 0.25, 0.35), 0.7)
		await get_tree().process_frame
	if _skipped:
		return
	if await _wait_lines():
		return
	Audio.play("whoosh", 0.35, 0.0)
	_fade_to(1.0, 0.5)
	await _hold(0.55)


# --- D: the city rushes up, the crash, the wake-up --------------------------------------

func _phase_landing() -> void:
	var patch: Node3D = world.patch
	var model: PatchModel = _model()
	var land: Vector3 = POD_POS
	_pod.visible = true
	var start: Vector3 = land + Vector3(-120, 95, 80)
	_pod.global_position = _w(start)  # [orbE]
	_fire = build_fire()
	_pod.add_child(_fire)
	# Chase shot: riding above the burning pod, the junk city rushing up below.
	_fade_to(0.0, 0.4)
	Audio.play("whoosh", 0.4, 0.0)
	var trail_t: float = 0.0
	var dur: float = 0.0 if DevHooks.get_f("intro-from", 0.0) >= 4.0 else 4.2  # 4: start at the crash
	var dir: Vector3 = (land - start).normalized()
	_cam_manual = true
	while trail_t < dur and not _skipped:
		var dt: float = get_process_delta_time()
		trail_t += dt
		var k: float = clampf(trail_t / dur, 0.0, 1.0)
		var pos: Vector3 = start.lerp(land, k * k)
		_pod.global_position = _w(pos)  # [orbE]
		_pod.look_at(_w(pos + dir), _up())
		_pod.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		_pod.rotate_object_local(Vector3.UP, trail_t * 1.6)
		_flicker_fire(_fire, trail_t)
		if k < 0.7:
			# Above and behind, looking down past the pod at the city.
			_cam.global_position = _w(pos - dir * 10.0 + Vector3(2.5, 5.0, 0))  # [orbE]
			_cam.look_at(_w(pos.lerp(land, 0.6) + Vector3(0, 6.0, 0)), _up())
			_cam.fov = 62.0
		elif _cam_manual:
			_cam_manual = false
			_cam.fov = 55.0
			_shot(land + Vector3(-13, 3.5, 15), land + Vector3(-6, 12, 6), land + Vector3(-11, 3, 13), land + Vector3(0, 1.5, 0), dur * 0.3)
		if randf() < 0.7:
			Vfx.burst("steam", _w(pos - dir * 2.0), Color(0.45, 0.42, 0.4, 0.8), 0.7)  # [orbE]
			Vfx.burst("sparkle", _w(pos), Color(1.0, 0.6, 0.25), 0.3)
		await get_tree().process_frame
	_cam_manual = false
	if _skipped:
		return
	if DevHooks.get_f("intro-from", 0.0) >= 5.0:
		# Dev: straight to the wake-up.
		_crash_pose()
		_fire.queue_free()
		_fire = null
		EscapePod.set_open(_pod, true, CrashSite.LEAN.x)
		var o_from: Vector3 = _v(_pod.global_transform * Vector3(0, 0.3, -0.3))  # [orbE] intro coordinates
		var o_to: Vector3 = _v(_pod.global_transform * Vector3(0, 0.05, -2.2))
		o_to.y = 0.05
		patch.visible = true
		patch.global_position = _w(o_to)
		patch.look_at(_w(o_to + (o_to - o_from) * Vector3(1, 0, 1)), _up())
		if model:
			model.core_glow = 0.15
		await _wake(o_from, o_to)
		return
	_crash_pose()
	_fire.queue_free()
	_fire = null
	_tunes_land()  # [tunes]
	Audio.play("thud", 0.5, 4.0)
	Audio.play("crunch", 0.6, 0.0)
	EventBus.shake_requested.emit(1.0)
	for i: int in 8:
		Vfx.burst("dust", _w(land + Vector3(randf_range(-1.8, 1.8), 0.3, randf_range(-1.8, 1.8))), Color(0.6, 0.55, 0.48, 0.8), 1.6)  # [orbE]
	Vfx.burst("bits", _w(land + Vector3(0, 0.5, 0)), Color(0.4, 0.38, 0.34), 1.0)
	_shot(land + Vector3(-11, 3, 13), land + Vector3(0, 1.5, 0), land + Vector3(-9, 2.4, 11), land + Vector3(0, 1.2, 0), 3.0)
	if await _hold(2.4):
		return
	# Close on the door: a hiss of steam, the seal pops, it drops into a ramp, warm light spills
	# out and Lumi drifts out nearly powerless.
	var front: Vector3 = _v(_pod.global_transform * Vector3(1.1, 1.05, -4.9))  # [orbE] intro coordinates
	_shot(front + Vector3(0, 0.45, 0), land + Vector3(0, 1.0, 0), front, land + Vector3(0, 0.75, 0), 8.0)
	if await _hold(1.2):
		return
	Audio.play("steam", 0.7, -2.0)
	var pod: Node3D = _pod
	var open_t: float = EscapePod.open_door(_pod, func(p: Vector3, _d: Vector3) -> void:
		Vfx.burst("steam", pod.global_transform * p, Color(0.92, 0.94, 0.97, 0.75), 0.35), 1.0, CrashSite.LEAN.x)
	if await _hold(0.6):
		return
	Audio.play("hydraulic", 0.8, -4.0)
	if await _hold(open_t - 0.6 + 0.5):
		return
	var out_from: Vector3 = _v(_pod.global_transform * Vector3(0, 0.3, -0.3))  # [orbE] intro coordinates
	var out_to: Vector3 = _v(_pod.global_transform * Vector3(0, 0.05, -2.2))
	out_to.y = 0.05
	patch.visible = true
	patch.global_position = _w(out_from)
	# Patch faces -Z: look along the drift so Lumi floats out face first.
	patch.look_at(_w(out_from + (out_to - out_from) * Vector3(1, 0, 1)), _up())
	if model:
		model.core_glow = 0.15
	create_tween().tween_property(patch, "global_position", _w(out_to), 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if await _hold(3.0):
		return
	await _wake(out_from, out_to)


## The low-battery wake: a quick, natural blink-awake, the battery readout, WREN explains the plan.
func _wake(out_from: Vector3, out_to: Vector3) -> void:
	var model: PatchModel = _model()
	# Face close-up: the eyes flutter open, dim. The core is nearly empty.
	var fwd: Vector3 = (out_to - out_from).normalized()
	var face_cam: Vector3 = out_to + fwd * 1.6 + Vector3(0.3, 0.75, 0)
	_shot(face_cam, out_to + Vector3(0, 0.75, 0), face_cam + Vector3(0, -0.05, 0) - fwd * 0.3, out_to + Vector3(0, 0.7, 0), 9.0)
	if await _hold(1.2):
		return
	if model:
		# Snappy flutter: open, shut, open a little longer, shut, then awake.
		for step: Array in [[false, 0.07], [true, 0.16], [false, 0.1], [true, 0.12]]:
			model.sleeping = bool(step[0])
			if not step[0]:
				Audio.play("blip", 0.65 + float(step[1]), -9.0)
			if await _hold(float(step[1])):
				return
		model.sleeping = false
		Audio.play("servo", 0.8, -8.0)
		model.set_happy(0.3)
	_flicker = 1.0
	_show_battery()
	Audio.play("error" if Audio.has_sound("error") else "blip", 0.5, -8.0)
	if await _hold(1.4):
		return
	if model:
		model.look_toward(_w(out_to + Vector3(-3, 1, 2)))  # [orbE]
	if await _hold(1.1):
		return
	if model:
		model.look_toward(_w(out_to + Vector3(3, 1, 2)))
	# WREN's one last message gets through, then the relay dies (the objectives card follows).
	var all: Dictionary = lines()
	if not all.has("brief_0"):
		await _hold(1.0)
		return
	GameState.flags["onboard_brief"] = true  # the objectives don't replay it
	brief_played = true
	if await _hold(_say("brief_0")):
		return
	if model:
		model.look_toward(null)
		model.set_happy(0.7)
		model.flash()
		Audio.play("chirp" if Audio.has_sound("chirp") else "blip", 1.3, -6.0)
	# Pull back so the battery readout and Lumi share the frame while her signal breaks up.
	_shot(_v(_cam.global_position), out_to + Vector3(0, 0.7, 0), out_to + fwd * 3.2 + Vector3(1.4, 1.5, 0.6), out_to + Vector3(0, 0.6, 0), 12.0)
	var k: int = 1
	while all.has("brief_%d" % k):
		_say("brief_%d" % k)
		k += 1
	await _wait_lines(0.4)
	if not _skipped:
		Audio.play("glitch" if Audio.has_sound("glitch") else "blip", 0.7, -10.0)  # the relay drops
		await _hold(1.2)

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
	_title.offset_top -= 40
	_title.offset_bottom -= 40
	_title.modulate.a = 0.0
	root.add_child(_title)
	_skip = UITheme.label("", 12, Color(1, 1, 1, 0.45))
	Settings.bind_text(_skip, func() -> String: return StoryPause.hint())  # [deck] [intro2]
	_pauser = StoryPause.new()
	_layer.add_child(_pauser)
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -260
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
	box.add_child(UITheme.label("B L O O M   C O R E", 15, Color(1, 1, 1, 0.85)))  # [qafix] QA #27: was 12 px at 60%
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
	box.add_child(UITheme.label(tr("GREEN LIGHT  ·  NONE DETECTED"), 15, Color(1.0, 0.6, 0.4, 0.95)))  # [qafix] QA #27


func _show_battery() -> void:
	create_tween().tween_property(_battery, "modulate:a", 1.0, 0.5)


func _show_title(t: String) -> void:
	_title.text = t
	create_tween().tween_property(_title, "modulate:a", 1.0, 1.6)


func _hide_title() -> void:
	create_tween().tween_property(_title, "modulate:a", 0.0, 1.2)


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
	_cam_from = Transform3D(Basis(), _w(from)).looking_at(_w(from_look), _up())  # [orbE] site frame
	_cam_to = Transform3D(Basis(), _w(to)).looking_at(_w(to_look), _up())
	_cam_dur = maxf(dur, 0.01)
	_cam_t = 0.0
	if _cam:
		_cam.global_transform = _cam_from


func _process(delta: float) -> void:
	if not running:
		return
	var td: Node = Tunes.director()  # [tunes] the song holds still while the cinematic is paused
	if td and Tunes.context() == "intro":
		td.call("set_paused", _pauser != null and _pauser.paused)
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
		var g: float = 0.22 + 0.12 * sin(_t * 3.0) - (0.15 if randf() < 0.08 else 0.0)
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
	# [intro2] Space / A pauses and resumes (owner playtest #2); Esc / B skips.
	if StoryPause.is_pause_event(event):
		get_viewport().set_input_as_handled()
		if _pauser:
			_pauser.toggle()
	elif StoryPause.is_skip_event(event):
		get_viewport().set_input_as_handled()
		if _pauser:
			_pauser.set_paused(false)
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
	if not _replay:
		place_pod()
		if _v(patch.global_position).distance_to(POD_POS) > 6.0 or _skipped or not patch.visible:
			patch.global_position = _w(Vector3(0, 0.05, 3.0))
		if patch.has_method("place_on_sphere"):  # [orbE] stand on the ground (test stand-ins have no motor)
			var fwd: Vector3 = -patch.global_basis.z
			fwd -= _up() * fwd.dot(_up())
			patch.call("place_on_sphere", patch.global_position, fwd.normalized() if fwd.length() > 0.01 else -site_xf.basis.z)
	GameState.flags["intro_done"] = true
	_tunes_land(1.2 if _skipped else 4.0)  # [tunes]
	if _skipped:
		_subs().clear()
	_report_subtitles()
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void:
		ending = false
		if _replay:
			_end_replay()
		if _fire and is_instance_valid(_fire):
			_fire.queue_free()
		_fire = null
		_close_stage()
		patch.visible = true
		if model:
			model.sleeping = false
			model.set_happy(0.6)
			model.look_toward(null)
			model.core_glow = CoreCharge.glow_for_flags()
		# [first] Behind the black: put the gameplay camera right behind Lumi so the first frame
		# doesn't glide in from wherever the rig was parked during the cinematic.
		if cam_reset_fn.is_valid():  # [orbE] the SphereCam behind Lumi
			cam_reset_fn.call()
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
		var td2: Node = Tunes.director()  # [tunes] back to the background shuffle
		if td2:
			td2.call("set_paused", false)
		Tunes.set_context("play")
		for b: ColorRect in _bars:
			b.visible = false
		_title.visible = false
		_skip.visible = false
		_battery.visible = false
		if not modal:
			_set_player_enabled(true)
		print("[intro] finished after %.1fs (skipped=%s, input restored=%s)" % [_t, _skipped, not modal]))
	tw.tween_property(_fade, "color:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		_layer.queue_free()
		finished.emit())


## [tunes] The Fall of LM-1 (audio/songs/fall_of_lm1.mp3) scores the intro from its first frame.
## Without the file the synth score and the motif play as before.
func _tunes_start() -> void:
	var td: Node = Tunes.director()
	if td:
		td.call("intro_start")
	print("[intro] score: %s" % (Tunes.now_playing() if Tunes.now_playing() != "" else "synth"))


## The pod has landed: the song fades out under the impact and the quiet wake-up.
func _tunes_land(fade: float = 4.0) -> void:
	var td: Node = Tunes.director()
	if td and Tunes.context() == "intro" and Tunes.now_playing() != "":
		print("[intro] song fades out at %.1fs (song at %.1fs)" % [_t, float(td.call("position"))])
		td.call("intro_land", fade)


## [intro2] Dev check: how long each intro line was really on screen against the reading rule.
func _report_subtitles() -> void:
	var log_: Array[Dictionary] = _subs().shown_log
	if log_.is_empty():
		return
	var worst: float = INF
	var short: int = 0
	for e: Dictionary in log_:
		var margin: float = float(e["shown"]) - float(e["need"])
		worst = minf(worst, margin)
		if margin < -0.05:
			short += 1
	print("[intro] subtitles: %d lines shown one at a time, tightest margin %+.2fs, %d short" % [log_.size(), worst, short])


## The intro (or its fade-out) still owns the camera and controls.
func busy() -> bool:
	return running or ending or _waiting


func _set_player_enabled(on: bool) -> void:
	(world.orbit as SliceOrbit).set_input(on)  # [orbE] Lumi's input and the SphereCam
