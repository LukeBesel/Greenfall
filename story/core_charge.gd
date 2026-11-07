class_name CoreCharge
extends Node
## Lumi's Bloom Core: the charge (0..1) its green-light core gets back from the life it grows.
## Fed by blooms (stats.plants_bloomed), this district's hex levels (plants/hex_levels.gd) and
## progress toward the Verdance Bloom milestone (systems/bloom.gd: Thriving hexes / districts /
## planet fraction). It never drops. 100% is exactly the Verdance Bloom, which plays the finale
## (story/bloom_finale.gd: the ark comes home). Milestone beats, each once:
##   25%  WREN's signal clears; a memory of the ark's garden deck (off-world flashback).
##   50%  Lumi's glow brightens for good (PatchModel.core_glow).
##   75%  That night the ark is seen as a moving star crossing the sky; afterwards it crosses
##        every night.
##  100%  The core is full (the Bloom finale).
## State: flags.core_charge (float, max so far), flags.core_beats (Array of reached milestones).
## Dev: --core-charge=0.6 sets the stored charge; --core-beat=25|50|75|100 plays that beat.

const START := 0.04
const BEATS: Array[int] = [25, 50, 75, 100]
const CHECK_S := 1.5
## Weights: blooms, hex level points, Verdance Bloom progress (sum with START is 1.0).
const W_BLOOMS := 0.16
const BLOOMS_FULL := 40.0
const W_LEVELS := 0.2
const LEVELS_FULL := 300.0
const W_BLOOM := 0.6
const GLOW_DIM := 0.85
const GLOW_BRIGHT := 1.35

var world: Node
## Shown charge (eases toward the stored value).
var shown: float = START

var _t: float = 0.0
var _pending: Array[int] = []
var _busy: bool = false
var _star: Node3D


# --- Pure helpers (tests) ----------------------------------------------------------------

## Charge from the inputs. bloom_progress = 0..1 toward the Verdance Bloom. Never reaches 1.0
## until that milestone is actually done, so the finale and "core full" stay the same moment.
static func compute(blooms: float, level_points: float, bloom_progress: float, bloom_done: bool) -> float:
	if bloom_done:
		return 1.0
	var c: float = START + W_BLOOMS * clampf(blooms / BLOOMS_FULL, 0.0, 1.0) \
		+ W_LEVELS * clampf(level_points / LEVELS_FULL, 0.0, 1.0) + W_BLOOM * clampf(bloom_progress, 0.0, 1.0)
	return minf(c, 0.99)


## Smooth progress toward the Verdance Bloom from a Bloom.measure() dict (the milestone's own
## conditions, plus Thriving hexes as a stand-in for whole districts so it moves steadily).
static func bloom_progress(m: Dictionary) -> float:
	var ms: Dictionary = {}
	for x: Dictionary in Bloom.milestones():
		if str(x.get("id", "")) == "verdance_bloom":
			ms = x
	var p: float = Bloom.progress(ms, m) if not ms.is_empty() else 0.0
	var per_district: float = float(Bloom.cfg().get("thriving_district_ratio", 0.6)) * float(Bloom.cfg().get("default_land_hexes", 230))
	var need: float = 3.0 * per_district
	return clampf(maxf(p, float(m.get("thriving_hexes", 0)) / maxf(need, 1.0)), 0.0, 1.0)


static func stored() -> float:
	return float(GameState.flags.get("core_charge", START))


static func beats_done() -> Array:
	var v: Variant = GameState.flags.get("core_beats")
	if not (v is Array):
		v = []
		GameState.flags["core_beats"] = v
	# Saves come back from JSON as floats: keep whole numbers.
	var arr: Array = v
	for i: int in arr.size():
		if arr[i] is float:
			arr[i] = int(arr[i])
	return arr


## Raises the stored charge (never lowers it). Returns milestones newly crossed (in order).
static func store(c: float) -> Array[int]:
	var old: float = stored()
	var now: float = maxf(old, clampf(c, 0.0, 1.0))
	GameState.flags["core_charge"] = now
	var out: Array[int] = []
	for b: int in BEATS:
		if now * 100.0 >= float(b) - 0.001 and not (b in beats_done()):
			beats_done().append(b)
			out.append(b)
	return out


## Lumi's core glow for the saved state: a little dim until the 50% beat, bright after.
static func glow_for_flags() -> float:
	return GLOW_BRIGHT if (50 in beats_done()) else GLOW_DIM


# --- Live node ---------------------------------------------------------------------------

func _ready() -> void:
	if DevHooks.has("core-charge"):
		GameState.flags["core_charge"] = clampf(DevHooks.get_f("core-charge", START), 0.0, 1.0)
	if not GameState.flags.has("core_charge"):
		GameState.flags["core_charge"] = START
	shown = stored()
	(func() -> void:
		var model: PatchModel = _model()
		if model:
			model.core_glow = glow_for_flags()).call_deferred()
	if GameState.flags.get("bloom_finale_seen", false) and world:
		(func() -> void: BloomFinale.park_ark(world, Vector3(0, 0, 3))).call_deferred()
	if DevHooks.has("core-beat"):
		var b: int = int(DevHooks.get_f("core-beat", 25.0))
		_busy = true  # hold the regular queue so the requested beat plays first
		get_tree().create_timer(DevHooks.get_f("core-beat-delay", 3.0)).timeout.connect(func() -> void:
			_busy = false
			_play(b))


func _model() -> PatchModel:
	if world == null or world.get("patch") == null:
		return null
	return world.patch.get("model") as PatchModel


func measure() -> float:
	var blooms: float = float(GameState.stats.get("plants_bloomed", 0.0))
	var levels: float = 0.0
	if world and world.get("hex_levels") != null:
		var hl: HexLevels = world.hex_levels
		for id: int in hl.levels:
			levels += float(hl.levels[id])
	var bl: Node = world.get_node_or_null("Bloom") if world else null
	var m: Dictionary = (bl as Bloom).measure_now() if bl is Bloom else {}
	return compute(blooms, levels, bloom_progress(m), Bloom.is_done("verdance_bloom"))


func _process(delta: float) -> void:
	shown = lerpf(shown, stored(), clampf(delta * 2.0, 0.0, 1.0))
	_update_star()
	_t += delta
	if _t < CHECK_S or world == null:
		return
	_t = 0.0
	for b: int in store(measure()):
		_pending.append(b)
	if not _pending.is_empty() and not _busy and _quiet():
		_play(_pending.pop_front())


## Nothing else owns the screen right now.
func _quiet() -> bool:
	if world.has_method("any_modal_open") and world.any_modal_open():
		return false
	if bool(world.get("launching")):
		return false
	var intro: Variant = world.get("intro")
	if intro is Intro and (intro as Intro).busy():
		return false
	var fs: Variant = world.get("first_seed")
	if fs is FirstSeed and bool((fs as FirstSeed).get("_active")):
		return false
	return not BloomFinale.playing


func _play(beat: int) -> void:
	if _busy:
		return
	_busy = true
	print("[core] beat %d%%" % beat)
	match beat:
		25:
			await _beat_memory()
		50:
			await _beat_glow()
		75:
			await _beat_ark_star()
		100:
			EventBus.toast.emit(tr("Bloom Core 100%. Lumi's core is full of green light."), "story")
			var bl: Node = world.get_node_or_null("Bloom")
			if DevHooks.get_f("core-beat", 0.0) == 100.0 and bl is Bloom:
				(bl as Bloom).play_finale(true)
	_busy = false


# --- 25%: the signal clears, a memory of the garden deck ---------------------------------

func _beat_memory() -> void:
	var c := Cine.new()
	c.world = world
	world.add_child(c)
	c.begin()
	var p: Vector3 = (world.patch as Node3D).global_position
	var model: PatchModel = _model()
	var front: Vector3 = -(world.patch as Node3D).global_transform.basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.1 else Vector3.FORWARD
	var side: Vector3 = front.cross(Vector3.UP).normalized()
	c.cam.global_transform = Transform3D(Basis(), p + front * 2.6 + side * 0.9 + Vector3(0, 1.2, 0)).looking_at(p + Vector3(0, 0.8, 0), Vector3.UP)
	if model:
		model.flash()
		model.set_happy(1.0)
	Audio.play("chime", 1.2, -8.0)
	c.caption(tr("Bloom Core  25%"))
	c.wren(tr("There. The relay just locked on. Lumi, I can hear you properly now. Clear as the old days."), 1)
	if await c.hold(4.6):
		await c.end()
		return
	c.fade_to(1.0, 0.6)
	if await c.hold(0.7):
		await c.end()
		return
	var st: SpaceStage = c.open_stage()
	st.show_set("garden")
	c.memory_tint(true)
	var g: Vector3 = SpaceStage.GARDEN_AT
	var lumi: PatchModel = st.lumi
	lumi.reparent(st.root_of("garden"), false)
	lumi.position = Vector3(0.6, 0.15, 1.2)
	lumi.rotation.y = 0.6
	lumi.set_happy(1.0)
	st.env.adjustment_saturation = 0.8
	st.shot(g + Vector3(5.5, 2.4, 7.5), g + Vector3(0.3, 1.0, 1.0), g + Vector3(3.2, 1.6, 4.6), g + Vector3(0.4, 0.9, 1.0), 11.0, 44.0, 40.0)
	c.fade_to(0.0, 1.2)
	c.caption(tr("A memory  ·  the garden deck of the Cradle"))
	var t: float = 0.0
	var said: int = 0
	while t < 10.5 and not c.skipped:
		t += get_process_delta_time()
		lumi.beam_at(g + Vector3(0.1 + sin(t * 0.8) * 0.3, 0.1, 0.3))
		if t > 1.0 and said == 0:
			said = 1
			c.wren(tr("Remember the garden deck? You watered every bed twice, just to be sure."), 2)
		if t > 5.8 and said == 1:
			said = 2
			c.wren(tr("Every patch you grow down there is one more bed like these. You're not lost, Lumi. You're replanting."), 2)
		await get_tree().process_frame
	lumi.beam_at(null)
	await c.end()
	EventBus.toast.emit(tr("Bloom Core 25%: WREN's signal is clear now."), "story")


# --- 50%: the glow comes back -------------------------------------------------------------

func _beat_glow() -> void:
	var model: PatchModel = _model()
	var p: Vector3 = (world.patch as Node3D).global_position
	if model:
		var tw := model.create_tween()
		tw.tween_property(model, "core_glow", 2.4, 0.5)
		tw.tween_property(model, "core_glow", GLOW_BRIGHT, 1.6)
		model.flash()
		model.set_happy(1.0)
	Vfx.burst("big_sparkle", p + Vector3(0, 1.0, 0), Color(0.5, 1.0, 0.85), 1.2)
	Vfx.burst("sparkle", p + Vector3(0, 0.6, 0), Color(0.7, 1.0, 0.6), 1.0)
	Audio.play("fanfare", 1.3, -10.0)
	EventBus.toast.emit(tr("Bloom Core 50%: Lumi's glow is back, brighter than it has been in years."), "story")
	if world.get("wren") != null:
		world.wren.line_started.emit(tr("Half charged. You're glowing, Lumi. Properly glowing. I'd forgotten you could be this bright."), 2)
	await get_tree().create_timer(2.0).timeout


# --- 75%: the ark crosses the night sky ---------------------------------------------------

func _beat_ark_star() -> void:
	var c := Cine.new()
	c.world = world
	world.add_child(c)
	c.begin()
	c.fade_to(1.0, 0.8)
	if await c.hold(0.9):
		await c.end()
		return
	var sd: SkyDirector = world.get("sky_director") as SkyDirector
	var tod: float = sd.time_of_day if sd else 0.0
	var froze: bool = sd.frozen if sd else false
	if sd:
		sd.frozen = true
		sd.time_of_day = 0.02
	var patch: Node3D = world.patch
	var p: Vector3 = patch.global_position
	var model: PatchModel = _model()
	# Low behind Lumi, looking up past it at the sky.
	var fwd: Vector3 = -patch.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var cam_pos: Vector3 = p - fwd * 3.2 + Vector3(0, 0.55, 0) + right * 0.8
	var look: Vector3 = p + fwd * 20.0 + Vector3(0, 13.0, 0)
	c.cam.global_transform = Transform3D(Basis(), cam_pos).looking_at(look, Vector3.UP)
	c.cam.fov = 58.0
	c.caption(tr("That night..."))
	c.fade_to(0.0, 1.4)
	var star: Node3D = _build_star(4.0)
	world.add_child(star)
	var basis: Basis = c.cam.global_transform.basis
	var f: Vector3 = -basis.z
	var r: Vector3 = basis.x
	var u: Vector3 = basis.y
	var t: float = 0.0
	var dur: float = 14.0
	var said: int = 0
	while t < dur and not c.skipped:
		t += get_process_delta_time()
		var k: float = clampf((t - 1.5) / (dur - 2.0), 0.0, 1.0)
		var dir: Vector3 = (f + r * lerpf(-0.75, 0.75, k) + u * (0.18 + 0.12 * sin(k * PI))).normalized()
		star.global_position = c.cam.global_position + dir * 420.0
		if model:
			model.look_toward(p + dir * 30.0)
		if t > 2.5 and said == 0:
			said = 1
			c.caption("")
			c.wren(tr("Lumi, look up. That light. West to east, steady, not twinkling."), 2)
			if model:
				model.set_happy(1.0)
		if t > 7.0 and said == 1:
			said = 2
			c.wren(tr("That's the Cradle. When your core lit up, the ark heard it. She turned around. We're coming back for you."), 2)
			Audio.play("chime", 0.9, -10.0)
		await get_tree().process_frame
	await c.end()
	star.queue_free()
	if sd:
		sd.time_of_day = tod
		sd.frozen = froze
	if model:
		model.look_toward(null)
	EventBus.toast.emit(tr("Bloom Core 75%: the Cradle is on its way home. Look for it crossing the night sky."), "story")


## The ark seen from the ground: a bright steady point with a soft halo (no fog on it).
static func _build_star(size: float = 3.0) -> Node3D:
	var n := Node3D.new()
	n.name = "ArkStar"
	var core := MeshInstance3D.new()
	core.mesh = ProcMesh.sphere(0.45 * size, 10, 6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 1.0, 1.0)
	m.disable_fog = true
	core.material_override = m
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var halo := Sprite3D.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 1.0, 0.95, 0.9))
	grad.set_color(1, Color(0.3, 0.9, 1.0, 0.0))
	g.gradient = grad
	g.width = 64
	g.height = 64
	halo.texture = g
	halo.pixel_size = 0.12 * size
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.shaded = false
	halo.transparent = true
	halo.no_depth_test = false
	halo.modulate = Color(1, 1, 1, 0.85)
	n.add_child(halo)
	return n


## After the 75% beat the ark crosses the sky every night, west to east.
func _update_star() -> void:
	if not (75 in beats_done()) or world == null:
		if _star:
			_star.visible = false
		return
	var sd: SkyDirector = world.get("sky_director") as SkyDirector
	var cam: Camera3D = get_viewport().get_camera_3d()
	if sd == null or cam == null or _busy:
		if _star:
			_star.visible = false
		return
	# Night runs from 0.8 through midnight to 0.2.
	var n: float = fmod(sd.time_of_day + 0.2, 1.0) / 0.4
	if n > 1.0:
		if _star:
			_star.visible = false
		return
	if _star == null:
		_star = _build_star(2.4)
		world.add_child(_star)
	_star.visible = true
	var a: float = lerpf(PI, 0.0, n)
	var e: float = deg_to_rad(25.0 + 40.0 * sin(n * PI))
	_star.global_position = cam.global_position + Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e) * 0.4 - 0.3).normalized() * 420.0
