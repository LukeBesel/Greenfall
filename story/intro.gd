class_name Intro
extends Node
## The opening film of a new game (under two minutes, letterboxed; Space / A pauses, Esc / B
## skips; it can be watched again from the pause menu for a while, and from the Codex after that).
## [v11film] Rewritten and re-shot (owner: "fully revamp the starting scene... a legit animation
## of something bad happening... the entire story makes full sense and is emotional"). One chain a
## child can follow, told by pictures and by WREN, the ship, who is the only voice:
##   1. Every night: dead brown Verdance below; the ark Cradle, its decks of small lit windows (the
##      people asleep); in the garden dome on its back Lumi looks down for green, finds none, and
##      goes back to the tray of seedlings, the last plants there are.
##   2. The storm: a streak past the glass; meteors rake the ship; one kills the engines, one
##      breaks the dome. The air and the garden pour out into space. WREN tells Lumi to take the
##      tray to the pod, and then she lets the pod go herself, because she cannot keep it safe and
##      cannot follow.
##   3. The fall, without a word: fire, a streak over the ruined town, the crash, dust.
##   4. One small robot: the hatch, eyes coming on in the dark, 4% battery, a world of trash.
##      WREN's voice gets through once: fix the workbench, find parts, build a signal tower so
##      they can talk again. It breaks off in the middle. Lumi turns to the old workbench, and
##      the camera settles behind it as the game hands over the controls, with no cut.
## The shots are data: data/intro_shots.json holds every shot's length, camera move, ease, fades,
## subtitle lines, sounds and cues; this file moves the actors (_in_<id> sets a shot up from
## nothing, _run_<id> poses it every frame from the shot's own clock, _cue_<name> fires once).
## Because every shot sets itself up, the film can start anywhere (dev: --intro-at=SECONDS,
## --intro-shot=ID), and tools/intro_capture.gd can render it as frames. See docs/ADJUSTING.md
## "The opening film".
## Story lines go through the game's one subtitle line (ui/subtitles.gd); a shot grows when a
## language's lines need longer to read. Off-world shots play on a SpaceStage (its own little 3D
## world); from the "sky" shot on the film plays on the real planet, in the pod site's frame.
## The pod the film crashes IS the game's pod (placed at the impact), so nothing is swapped at the
## end. Skipping at any moment leaves the same world as watching to the end.

signal finished

var _cover: CanvasLayer  # [first]
var world: Node
var running: bool = false
## True from _finish() until the hand-off has given the camera and controls back.
var ending: bool = false
var _waiting: bool = false
## [intro3] WREN's brief was played inside the intro (the objectives only reveal their card).
var brief_played: bool = false
## Dev (tools/intro_preview.gd): no planet here, so the film stops before its first world shot.
var stage_only: bool = false

var _cam: Camera3D
var _prev_cam: Camera3D
var _layer: CanvasLayer
var _stage_layer: CanvasLayer
var _stage: SpaceStage
var _fade: ColorRect
var _title: Label
var _title_sub: Label
var _skip: Label
var _battery: Control
var _battery_pct: Label
var _battery_cells: Array[ColorRect] = []
var _bars: Array[ColorRect] = []
var _pod: Node3D
var _fire: Node3D
var _site: Node3D
var _pauser: StoryPause
## Watching the film again (pause menu, Codex). [v11film] A rewatch must never change the save
## or the world, so it now plays with the game stopped: the tree is paused and the film runs on
## its own (this node processes always). The real Lumi is not touched (a stand-in plays its
## part), the film's pod and crash site are the film's own, and everything the film hides (the
## real pod, the HUD and every other screen layer, guide beams, robots) is shown again after.
var _replay: bool = false
var _replay_pod: Node3D
var _replay_site: Node3D
## The stand-in Lumi of a rewatch (a body with a PatchModel), or null.
var _actor: Node3D
var _actor_model: PatchModel
## What a rewatch hid, to show again.
var _replay_hidden: Array = []
var _replay_keep: Dictionary = {}
var _own_subs: Subtitles
## Emitted when a rewatch is over and the world is as it was.
signal replay_finished
## Emitted the moment a rewatch hands the game back (same frame: tools/rewatch_check.gd compares).
signal replay_restored
## The pause menu offers the film again for this long (seconds of play); the Codex always does.
const REWATCH_S: float = 1800.0
## A rewatch is offered while Lumi is this close to the pod (metres): the film is shot round it,
## and the ground there has to be loaded.
const REWATCH_NEAR_M: float = 120.0
var _skipped: bool = false
var _hold_tray: bool = false
var _flicker: float = 0.0
## Film time in seconds (stops while paused; the frame capture reads it).
var _t: float = 0.0

# --- The film's own state ------------------------------------------------------------------
var _table: Dictionary = {}
var _shots: Array = []
var _si: int = -1
var _lt: float = 0.0
var _cue_i: int = 0
var _line_i: int = 0
var _sfx_i: int = 0
var _film: bool = false
## The game's pod stands in its crash site (from the impact on).
var _placed: bool = false
var _trauma: float = 0.0
var _look_pt := Vector3.ZERO
var _look_set: bool = false
var _cam_start := Transform3D()
var _fov_start: float = 55.0
var _acc: Dictionary = {}  # per-shot timers ("note", "puff", ...)
var _site_rest := Transform3D()
var _pod_yaw: float = POD_YAW
var _trail: CPUParticles3D
var _fx_nodes: Array[Node] = []
var _ark_p0 := Vector3.ZERO
var _ark_v := Vector3.ZERO
var _ark_t0: float = 0.0
var _pod_p0 := Vector3.ZERO
var _handoff_done: bool = false
var _warm: int = 0
var _land_t: float = -100.0
## The game's pod, built ahead (hidden) under the fade into the first world shot, so the crash
## itself costs nothing: a stall on that frame would land on the film's biggest beat.
var _real_site: Node3D

const POD_POS := Vector3(6.0, 0.0, 9.5)
## The landed pod's yaw in the site frame when nothing else says (the game's own pod is measured).
const POD_YAW: float = 0.5
## Where the pod comes from, as an offset from the landing point (site frame, metres).
const FALL_FROM := Vector3(-120, 95, 80)
const WREN_CLEAR := 2
const WREN_GLITCH := 0
const TABLE_PATH := "res://data/intro_shots.json"
const FIRE_SHADER := preload("res://art/shaders/cine_fire.gdshader")
## Old --intro-from=N phases, as shot ids.
const PHASE_SHOTS: Array[String] = ["planet", "storm", "apart", "sky", "impact", "hatch"]


## Builds the pod prop (also used after the intro as a landmark, and by the cinematic sets).
## [intro2] Rebuilt in story/escape_pod.gd: a real door opening, no overlapping faces.
static func build_pod() -> Node3D:
	var pod: Node3D = EscapePod.build()
	GlimDirector.cling_to(pod)  # [v4calm] item 43: Glim holds on to the pod until he's repaired
	return pod


## Re-entry fire for a pod falling base first: it trails up the pod (+Y) and past its nose.
## [v9intro] A soft white-hot bow glow under the heat shield and two streaming sheaths of fire
## (art/shaders/cine_trail.gdshader). It was three hard nested cones, which from behind read as
## a bullseye. Drive it with set_fire(fire, 0..1, time).
static func build_fire() -> Node3D:
	var f := Node3D.new()
	f.name = "ReentryFire"
	var bow := MeshInstance3D.new()
	bow.name = "Bow"
	bow.mesh = ProcMesh.sphere(1.0, 20, 12)
	# A hot cushion under the heat shield: from behind, the pod hides its middle and it shows as a
	# crescent of glow round the base (a ball centred on the pod whited the whole pod out).
	bow.material_override = SpaceStage.glow_mat(Color(1.0, 0.84, 0.58), 2.0, 1.6)
	bow.scale = Vector3(1.4, 0.6, 1.4)
	bow.position = Vector3(0, -0.5, 0)
	bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(bow)
	var specs: Array = [
		# bottom radius, top radius, height, strength, speed, hot, cool, alpha-blended body?
		[1.1, 0.4, 6.5, 0.95, 4.0, Color(1.0, 0.72, 0.3), Color(0.8, 0.22, 0.06), true],
		[1.2, 0.5, 7.5, 1.5, 4.5, Color(1.0, 0.93, 0.75), Color(1.0, 0.45, 0.12), false],
		[1.75, 0.2, 15.0, 0.85, 3.0, Color(1.0, 0.62, 0.25), Color(0.85, 0.2, 0.06), false],
	]
	for k: int in specs.size():
		var sp: Array = specs[k]
		var cm := CylinderMesh.new()
		cm.bottom_radius = float(sp[0])
		cm.top_radius = float(sp[1])
		cm.height = float(sp[2])
		cm.radial_segments = 20
		cm.rings = 8
		cm.cap_top = false
		cm.cap_bottom = false
		var c := MeshInstance3D.new()
		c.name = "Sheath%d" % k
		c.mesh = cm
		var tm: ShaderMaterial = SpaceStage.trail_mat(sp[5], sp[6], float(sp[3]), false, float(sp[4]))
		if bool(sp[7]):
			tm.shader = FIRE_SHADER  # a solid body of fire under the glow: it holds against a bright sky
			tm.render_priority = -1
		c.material_override = tm
		c.set_meta("strength", float(sp[3]))
		c.position = Vector3(0, cm.height * 0.5 - 0.25, 0)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(c)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.light_energy = 5.0
	glow.omni_range = 12.0
	glow.position = Vector3(0, 0.6, 0)
	f.add_child(glow)
	return f


## How hard the re-entry fire burns (k 0..1): it swells from nothing and breathes, it never pops.
static func set_fire(fire: Node3D, k: float, t: float) -> void:
	if fire == null or not is_instance_valid(fire):
		return
	k = clampf(k, 0.0, 1.0)
	fire.visible = k > 0.002
	var breathe: float = 1.0 + 0.06 * sin(t * 17.0) + 0.04 * sin(t * 29.3 + 1.0)
	for c: Node in fire.get_children():
		if c is OmniLight3D:
			(c as OmniLight3D).light_energy = 5.5 * k * breathe
		elif c.name == "Bow":
			((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("strength", 1.6 * k * breathe)
		elif c is MeshInstance3D:
			var m: ShaderMaterial = (c as MeshInstance3D).material_override
			m.set_shader_parameter("strength", float(c.get_meta("strength", 1.0)) * k * breathe)
			(c as Node3D).scale = Vector3(1.0, lerpf(0.35, 1.0, k) * (1.0 + 0.05 * sin(t * 11.0 + c.get_index())), 1.0)
			(c as Node3D).position.y = ((c as MeshInstance3D).mesh as CylinderMesh).height * 0.5 * (c as Node3D).scale.y - 0.25


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


## Places the pod landmark in its crash site (the game's own pod on the globe).
func place_pod() -> void:
	_free_falling_pod()
	if place_pod_fn.is_valid():  # [orbE] the globe places its own pod (same spot, its colliders)
		if _real_site and is_instance_valid(_real_site):
			_real_site.visible = true
			_real_site.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			if _site and is_instance_valid(_site):
				_site.queue_free()
			_site = null
			_pod = null
			place_pod_fn.call()
		_real_site = null
		_adopt_pod()
		return
	_own_crash_site()


## Build the game's pod now and keep it out of sight (and still) until the film's pod lands.
func _prebuild_pod() -> void:
	if _replay or _placed or not place_pod_fn.is_valid() or (_real_site and is_instance_valid(_real_site)):
		return
	var t0: int = Time.get_ticks_usec()
	place_pod_fn.call()
	var s: Variant = world.get_meta("orbit_pod", null) if world.has_meta("orbit_pod") else null
	if s is Node3D and is_instance_valid(s):
		_real_site = s
		_real_site.visible = false
		_real_site.process_mode = Node.PROCESS_MODE_DISABLED
	if DevHooks.has("intro"):
		print("[intro] the game's pod built ahead in %.1f ms (hidden until the crash)" % ((Time.get_ticks_usec() - t0) / 1000.0))


## The game's pod (slice_orbit._place_pod) as the film's pod from now on.
func _adopt_pod() -> void:
	var s: Variant = world.get_meta("orbit_pod", null) if world.has_meta("orbit_pod") else null
	if s is Node3D and is_instance_valid(s):
		_site = s
		_pod = (s as Node).get("pod") as Node3D
	_measure_pod()
	if DevHooks.has("intro") and yard_fn.is_valid():
		# Dev: where the yard's things stand in the pod's frame (x right of the door, -z out of it).
		var inv: Basis = Basis(Vector3.UP, _pod_yaw).inverse()
		var txt: String = ""
		for n: String in ["bench", "shack", "bin", "depot", "door", "stations", "generator", "signal_tower", "rocket_pad", "lamps_0"]:
			var p: Variant = yard_fn.call(n)
			if p is Vector3:
				var q: Vector3 = inv * (_v(p) - POD_POS)
				txt += "%s (%.1f, %.1f, %.1f)  " % [n, q.x, q.y, q.z]
		print("[intro] pod yaw %.2f; in the pod's frame: %s" % [_pod_yaw, txt])


## A crash site of the film's own (the Codex replay, and worlds without a pod of their own).
func _own_crash_site() -> void:
	if _site and is_instance_valid(_site):
		return
	var host: Node = self if _replay else world  # a rewatch's landing is the film's own
	if _pod == null or not is_instance_valid(_pod):
		_pod = build_pod()
		host.add_child(_pod)
	_pod.visible = true
	_site = CrashSite.attach(host, _pod, _w(POD_POS), POD_YAW)
	if _replay:
		(_site as CrashSite).set_stage(0)  # as it fell, whatever has been mended since
	if site_xf != Transform3D.IDENTITY:  # [orbE] lie on the globe's pad, not the world's flat plane
		_site.global_basis = site_xf.basis.orthonormalized()
	EscapePod.set_open(_pod, true, CrashSite.LEAN.x)
	_measure_pod()


## Which way the landed pod's door faces, as a yaw in the site frame (the door shots turn with it).
func _measure_pod() -> void:
	_pod_yaw = POD_YAW
	if _pod and is_instance_valid(_pod) and _pod.is_inside_tree():
		var door: Vector3 = site_xf.basis.orthonormalized().inverse() * (-_pod.global_basis.z)
		door.y = 0.0
		if door.length() > 0.01:
			_pod_yaw = atan2(-door.x, -door.z)
	if _site and is_instance_valid(_site):
		_site_rest = _site.global_transform


func _free_falling_pod() -> void:
	if _fire and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null
	if _pod and is_instance_valid(_pod) and (_site == null or not is_instance_valid(_site)):
		_pod.queue_free()
		_pod = null


# --- [orbE] Round planet: the in-world shots in the pod site's frame -----------------------
## The world shots are written in flat coordinates around POD_POS (+Y up). On the globe, site_xf
## maps them onto the pod anchor's frame (origin on the pad, +Y the local up), so every shot and
## Lumi's drift stay level on the curve. The globe slice sets it with site_for_anchor(pod anchor).
var site_xf := Transform3D.IDENTITY
## [orbE] On the globe: the pod anchor's frame when the intro starts (anchors settle while
## loading), the globe's own pod placement, and the globe camera's hand-off.
var site_fn: Callable  # () -> Transform3D
var place_pod_fn: Callable  # () -> void
var cam_reset_fn: Callable  # () -> void
## [v9intro] Where a yard anchor stands in the world ("bench", "bin", ...), or null: lets a shot
## frame the cleanup station by name (data/intro_shots.json "target").
var yard_fn: Callable  # (name: String) -> Variant


static func site_for_anchor(anchor: Transform3D) -> Transform3D:
	return anchor * Transform3D(Basis(), -POD_POS)


func _w(v: Vector3) -> Vector3:  # intro (flat) coordinates -> world
	return site_xf * v


func _v(p: Vector3) -> Vector3:  # world -> intro coordinates
	return site_xf.affine_inverse() * p


func _up() -> Vector3:
	return site_xf.basis.y.normalized()


## The body the film moves: Lumi itself, or the stand-in of a rewatch.
func _lumi() -> Node3D:
	return _actor if _actor and is_instance_valid(_actor) else world.patch as Node3D


func _model() -> PatchModel:
	if _actor and is_instance_valid(_actor):
		return _actor_model
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


## Every line the intro says, in order: [text, speaker] ("wren" = WREN; she is the film's only
## voice), plus an optional "tail": the signal breaks up on the last words (heavy glitch on that
## span only). Kept in one place so tests can check the subtitle timing rule against all of them.
## [v11film] Rewritten (owner: "make sure the entire story makes full sense and is emotional and
## not cheesy... dialog needs to make sense"). There was a storybook narrator ("Then, one night,
## the sky came apart"), a joke from WREN, jargon ("Hull breach in the vault bay!") and a pod that
## was blown off by accident. Now WREN says, in order: what they look down at every night and why
## the people sleep; what Lumi keeps; the warning; the order; her choice to let the pod go; why
## she cannot follow; a promise that breaks up. Then her one last message on the ground.
static func lines() -> Dictionary:
	var out: Dictionary = {
		"first": [TranslationServer.translate("Still no green down there, Lumi."), "wren"],
		"wait": [TranslationServer.translate("Nothing can grow in all that trash. So the people sleep up here, and we wait."), "wren"],
		"keep": [TranslationServer.translate("Three hundred years. And you have kept the last plants alive."), "wren"],
		"glass": [TranslationServer.translate("Lumi. Come away from the glass."), "wren"],
		"breach": [TranslationServer.translate("The glass is breaking! Take the tray. Get to the pod!"), "wren"],
		"send": [TranslationServer.translate("I can't keep you safe here. I have to let you go."), "wren"],
		"engines": [TranslationServer.translate("My engines are gone. I can't come after you."), "wren"],
		"find": [TranslationServer.translate("Lumi— I will find you— I will find—"), "wren", "tail"],
	}
	# [intro3] At the crash WREN gets ONE last message through before the relay dies: onboarding's
	# brief (data/objectives.json "brief"), its last words breaking up in a [glitch] span. She is
	# silent after that until the signal tower is built.
	var brief: Array = brief_lines()
	for i: int in brief.size():
		out["brief_%d" % i] = [TranslationServer.translate(str(brief[i])), "wren"]
	return out


## The brief's raw lines from data/objectives.json (translated when shown).
static func brief_lines() -> Array:
	var f := FileAccess.open("res://data/objectives.json", FileAccess.READ)
	if f == null:
		return []
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return []
	return ((d as Dictionary).get("brief", {}) as Dictionary).get("lines", [])


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


# --- The shot table ------------------------------------------------------------------------

## data/intro_shots.json as a dictionary ("shots": the list in playing order).
static func load_table() -> Dictionary:
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return {"shots": []}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {"shots": []}


## How long a line of lines() is on screen (all its chunks, fades and gaps).
static func line_time(key: String) -> float:
	var l: Array = lines().get(key, ["", ""])
	var text: String = str(l[0])
	if l.size() > 2 and str(l[2]) == "tail":
		text = glitch_tail(text)
	return Subtitles.total_time(text)


## The table's shots with their real times: "d" (the length, grown where the shot's lines need
## longer to read than "dur": one line at a time, each after the one before), "t0" and "t1".
## Negative cue seconds are turned into seconds from the shot's start.
static func timeline(table: Dictionary, time_of: Callable = Callable()) -> Array:
	var out: Array = []
	var t: float = 0.0
	for raw: Variant in table.get("shots", []):
		var s: Dictionary = (raw as Dictionary).duplicate(true)
		var d: float = float(s.get("dur", 3.0))
		var cursor: float = 0.0
		for l: Variant in s.get("lines", []):
			var len_s: float = float(time_of.call(str(l[1]))) if time_of.is_valid() else line_time(str(l[1]))
			cursor = maxf(cursor, float(l[0])) + len_s
		d = maxf(d, cursor + 0.25) if cursor > 0.0 else d
		s["d"] = d
		s["t0"] = t
		s["t1"] = t + d
		var cues: Array = []
		for c: Variant in s.get("cues", []):
			cues.append([float(c[0]) if float(c[0]) >= 0.0 else d + float(c[0]), str(c[1])])
		cues.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		s["cues"] = cues
		t += d
		out.append(s)
	return out


## The film's length in seconds for the current language.
static func film_length() -> float:
	var tl: Array = timeline(load_table())
	return float(tl[-1]["t1"]) if not tl.is_empty() else 0.0


static func eased(name_: String, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match name_:
		"linear": return u
		"in": return u * u
		"out": return 1.0 - (1.0 - u) * (1.0 - u)
		"in_cubic": return u * u * u
		"out_cubic": return 1.0 - pow(1.0 - u, 3.0)
		"out_quint": return 1.0 - pow(1.0 - u, 5.0)
		"inout_cubic": return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) * 0.5
		"smoother": return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	return u * u * (3.0 - 2.0 * u)  # "inout"


static func _v3(a: Variant, d := Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


static func _pair(a: Variant, d0: float, d1: float) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2(d0, d1)


func _shot_index(id: String) -> int:
	for i: int in _shots.size():
		if str(_shots[i]["id"]) == id:
			return i
	return -1


func _p(key: String, d: float) -> float:
	return float((_shots[_si].get("p", {}) as Dictionary).get(key, d))


func _pv(key: String, d: Vector3) -> Vector3:
	return _v3((_shots[_si].get("p", {}) as Dictionary).get(key), d)


# --- Play ----------------------------------------------------------------------------------

## True while the pause menu should offer "Watch the opening again": the film is over, the
## game is young (REWATCH_S of play) and Lumi is near the pod. The Codex offers it at any time.
static func rewatch_offered(w: Node) -> bool:
	if w == null or not bool(GameState.flags.get("intro_done", false)):
		return false
	if float(GameState.stats.get("time_played", 0.0)) > REWATCH_S:
		return false
	var it: Variant = w.get("intro")
	return it is Intro and (it as Intro).can_replay()


## The game's own crash site (the pod Lumi fell in), or null.
func _game_site() -> Node3D:
	if _site and is_instance_valid(_site):
		return _site
	var s: Variant = world.get_meta("orbit_pod", null) if world and world.has_meta("orbit_pod") else null
	return s as Node3D if s is Node3D and is_instance_valid(s) else null


## A rewatch can start now: nothing else owns the screen and Lumi is near the pod.
func can_replay() -> bool:
	if running or ending or _waiting or world == null or world.get("patch") == null:
		return false
	var site: Node3D = _game_site()
	return site != null and (world.patch as Node3D).global_position.distance_to(site.global_position) <= REWATCH_NEAR_M


## Watch the whole film again (pause menu, Codex). The game is stopped while it plays, a stand-in
## plays Lumi and the film brings its own pod; afterwards everything is shown as it was. Nothing
## in the save or the world changes (tools/check_rewatch.sh).
func replay() -> void:
	if not can_replay():
		return
	_replay = true
	_skipped = false
	_bars.clear()
	_battery_cells.clear()
	if _site == null or not is_instance_valid(_site):
		_adopt_pod()  # a loaded game: the pod was placed by the world, not by this film
	_replay_pod = _pod
	_replay_site = _site
	_site = null
	_pod = null
	var tree: SceneTree = get_tree()
	_replay_keep = {
		"paused": tree.paused,
		"mode": process_mode,
		"vfx": Vfx.process_mode,
		"tunes": Tunes.context(),
		"subs": Subtitles.current,
		"cinematic": world.get("music") != null and bool(world.music.get("_cinematic")),
		# The film's song counts its plays in the save: a rewatch is not a play.
		"songs": (GameState.flags["songs"] as Dictionary).duplicate(true) if GameState.flags.get("songs") is Dictionary else null,
	}
	process_mode = Node.PROCESS_MODE_ALWAYS
	Vfx.process_mode = Node.PROCESS_MODE_ALWAYS  # the film's sparks and steam
	Audio.film_plays = true  # the film's own sounds play though the game is stopped
	tree.paused = true
	# Out of the picture while the film plays: the real pod and Lumi, every screen layer, the
	# guide beams and outlines, the robots.
	_replay_hidden.clear()
	var gone: Array = [_replay_site, world.patch]
	gone.append_array(tree.get_nodes_in_group("guide_3d"))
	gone.append_array(tree.get_nodes_in_group("robot"))
	for n: Node in tree.root.find_children("*", "CanvasLayer", true, false):
		if n != self and not is_ancestor_of(n):
			gone.append(n)
	for n: Variant in gone:
		if n is Node and is_instance_valid(n) and (n is Node3D or n is CanvasLayer) and bool((n as Node).get("visible")):
			_replay_hidden.append(n)
			(n as Node).set("visible", false)
	_actor = Node3D.new()
	_actor.name = "FilmLumi"
	_actor_model = PatchModel.new()
	_actor.add_child(_actor_model)
	add_child(_actor)
	_own_subs = Subtitles.new()
	_own_subs.world = world
	add_child(_own_subs)
	print("[intro] replay")
	play()


## The end of a rewatch: the film's own things go, and everything it hid is shown again.
func _end_replay() -> void:
	if _site and is_instance_valid(_site) and _site != _replay_site:
		_site.remove_from_group("crash_site")
		_site.queue_free()  # the film's own landing (its pod with it)
	elif _pod and is_instance_valid(_pod) and _pod != _replay_pod:
		_pod.queue_free()
	_pod = _replay_pod
	_site = _replay_site
	if _actor and is_instance_valid(_actor):
		_actor.queue_free()
	_actor = null
	_actor_model = null
	if _own_subs and is_instance_valid(_own_subs):
		remove_child(_own_subs)
		_own_subs.queue_free()
	_own_subs = null
	Subtitles.current = _replay_keep.get("subs") as Subtitles
	for n: Variant in _replay_hidden:
		if is_instance_valid(n):
			(n as Node).set("visible", true)
	_replay_hidden.clear()
	var sd: Variant = world.get("sky_director") if world else null
	if sd is SkyDirector and (sd as SkyDirector).sphere:
		(sd as SkyDirector).call("_apply_sphere")  # the game's own sky again, before the world shows
	Vfx.process_mode = int(_replay_keep.get("vfx", Node.PROCESS_MODE_INHERIT)) as Node.ProcessMode
	process_mode = int(_replay_keep.get("mode", Node.PROCESS_MODE_INHERIT)) as Node.ProcessMode
	if _replay_keep.get("songs") is Dictionary:
		GameState.flags["songs"] = _replay_keep["songs"]
	elif _replay_keep.has("songs"):
		GameState.flags.erase("songs")
	get_tree().paused = bool(_replay_keep.get("paused", false))
	Audio.film_plays = false
	_placed = true
	_replay = false
	replay_restored.emit()


func play() -> void:
	# [intro2] Start once the loading screen has gone (its black cover stays up meanwhile).
	var ld: LoadingScreen = get_node_or_null("/root/Loader") as LoadingScreen
	if ld and ld.busy():
		_waiting = true
		_set_player_enabled(false)
		_prebuild_stage()  # [v11film] behind the loading screen: the film's first frame costs nothing
		await ld.wait_done()
		_waiting = false
	if site_fn.is_valid():  # [orbE]
		site_xf = site_fn.call()
	running = true
	_skipped = false
	_placed = false
	_handoff_done = false
	_trauma = 0.0
	_flicker = 0.0
	if DevHooks.has("intro-frames"):  # dev: the film as a frame sequence (tools/intro_capture.gd)
		var cap := IntroCapture.new()
		cap.intro = self
		add_child(cap)
	var patch: Node3D = world.patch
	if not _replay:  # a rewatch stops the whole game instead, and has hidden what must not show
		_set_player_enabled(false)
		_hold_lumi(true)
		if world.get("hud") != null:
			world.hud.visible = false
	if world.get("music") != null:
		world.music.set_cinematic(true)
	_tunes_start()  # [tunes] The Fall of LM-1 from the first frame (before the motif, which it replaces)
	Audio.music_sting("motif")  # [sound] the Greenfall motif; the Homecoming ending quotes it
	_table = load_table()
	_shots = timeline(_table)
	_build_overlay()
	_drop_cover()  # [first]
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.08
	_cam.far = 6000.0
	add_child(_cam)  # the film's own (it runs while the game is stopped in a rewatch)
	if _prev_cam and is_instance_valid(_prev_cam):
		_cam.global_transform = _prev_cam.global_transform
	_cam.current = true
	patch.visible = false
	_lumi().visible = false
	var model: PatchModel = _model()
	if model:
		model.sleeping = true
	if not _replay:
		# No pod stands on Verdance before the film's pod lands: the yard's stand-in pod (and its
		# smoke column) steps aside now; the yard drops it for good once the real pod is placed.
		for n: Node in get_tree().get_nodes_in_group("crash_site"):
			if n is Node3D and n != _site:
				(n as Node3D).visible = false
	# Where to start: the top, or a dev seek (--intro-at=S, --intro-shot=ID, --intro-from=PHASE).
	var at: float = 0.0
	if DevHooks.has("intro-at"):
		at = DevHooks.get_f("intro-at", 0.0)
	elif DevHooks.has("intro-shot"):
		at = float(_shots[maxi(0, _shot_index(DevHooks.get_s("intro-shot", "planet")))]["t0"])
	elif DevHooks.has("intro-from"):
		var ph: int = clampi(int(DevHooks.get_f("intro-from", 0.0)), 0, PHASE_SHOTS.size() - 1)
		at = float(_shots[maxi(0, _shot_index(PHASE_SHOTS[ph]))]["t0"])
	print("[intro] start at %.1fs of %.1fs (%d shots)" % [at, float(_shots[-1]["t1"]), _shots.size()])
	if DevHooks.has("intro"):
		for s: Dictionary in _shots:
			print("[intro] shot %-10s %6.1f - %6.1f s  (%s)" % [s["id"], s["t0"], s["t1"], s["set"]])
	seek(at)
	_warm = 3 if _stage != null and at < 1.0 else 0
	_film = not DevHooks.has("intro-scout")


## Jump the film to second `at`: the shot there sets itself up from nothing.
func seek(at: float) -> void:
	_t = clampf(at, 0.0, float(_shots[-1]["t1"]) - 0.01)
	var i: int = 0
	while i < _shots.size() - 1 and _t >= float(_shots[i]["t1"]):
		i += 1
	_enter(i, _t - float(_shots[i]["t0"]))
	_pose(0.0)


func _process(delta: float) -> void:
	if not running:
		return
	var td: Node = Tunes.director()  # [tunes] the song holds still while the cinematic is paused
	if td and Tunes.context() == "intro":
		td.call("set_paused", _pauser != null and _pauser.paused)
	if not _film:
		return
	if _warm > 0 and _stage and is_instance_valid(_stage):
		# [v11film] Three frames under the black of the fade-in: the vault is drawn once in each
		# of its states, so its shaders are compiled now and not at the first cut to it.
		_warm -= 1
		if _warm > 0:
			_stage.warm_view(2 - _warm)
		else:
			_enter(_si, _lt)
			_pose(0.0)
		return
	_t += delta
	if DevHooks.has("intro-skip-at") and _t >= DevHooks.get_f("intro-skip-at", 0.0):  # dev: tests skip here
		skip()
		return
	# Walk into the next shot(s); the last shot's end is the film's end.
	while _t >= float(_shots[_si]["t1"]):
		if stage_only and _si < _shots.size() - 1 and str(_shots[_si + 1]["set"]) == "world":
			_film = false
			running = false
			print("[intro] stage-only preview ends at %.1fs" % _t)
			finished.emit()
			return
		if _si >= _shots.size() - 1:
			_film = false
			_finish()
			return
		_fire_cues(INF)  # a slow frame must not swallow a cue
		_enter(_si + 1, 0.0)
	_lt = _t - float(_shots[_si]["t0"])
	_pose(delta)


## One frame of the current shot: cues, actors, camera, fades.
func _pose(delta: float) -> void:
	var s: Dictionary = _shots[_si]
	var d: float = float(s["d"])
	var u: float = clampf(_lt / d, 0.0, 1.0)
	_fire_cues(_lt)
	var fn: String = "_run_" + str(s["id"])
	if has_method(fn):
		call(fn, _lt, u, delta)
	if _placed and _in_world():
		_site_settle(_t - _land_t)  # the pod rocks to rest and its smoke column grows
	_trauma = maxf(0.0, _trauma - delta * 1.1)
	_aim_camera(s, u, delta)
	if _hold_tray and _stage:
		var lumi: PatchModel = _stage.lumi
		_stage.tray.global_position = lumi.claw_point() + Vector3(0, 0.02, 0)
		_stage.tray.global_rotation = Vector3(0, lumi.global_rotation.y, 0)
	# Fades are part of the shot: in from, and out to, the shot's fade colour.
	var a: float = 0.0
	var fi: float = float(s.get("fade_in", 0.0))
	var fo: float = float(s.get("fade_out", 0.0))
	if fi > 0.0 and _lt < fi:
		a = 1.0 - eased("inout", _lt / fi)
	if fo > 0.0 and _lt > d - fo:
		a = maxf(a, eased("inout", (_lt - (d - fo)) / fo))
	var fc: Vector3 = _v3(s.get("fade_col"), Vector3.ZERO)
	_fade.color = Color(fc.x, fc.y, fc.z, a)
	_film_dust(s, u)
	# Low battery: the core and eyes stutter, the readout blinks.
	if _flicker > 0.0:
		var model: PatchModel = _model()
		var g: float = 0.22 + 0.12 * sin(_t * 3.0) + 0.05 * sin(_t * 13.0)
		if model:
			model.core_glow = maxf(0.08, g)
		var on: bool = fmod(_t, 1.0) < 0.6
		_battery_pct.modulate.a = 1.0 if on else 0.35
		_battery_cells[0].color = Color(1.0, 0.35, 0.25, 0.9 if on else 0.4)


## [v10guide] Critic 23: on the planet the film's sky is the dead world's dusty one (the shot's
## "dust", default FILM_DUST); it clears over the hand-off into the game's own sky.
const FILM_DUST: float = 1.0


func _film_dust(s: Dictionary, u: float) -> void:
	var sd: Variant = world.get("sky_director") if world else null
	if not (sd is SkyDirector):
		return
	var d: float = float(s.get("dust", FILM_DUST)) if str(s["set"]) == "world" else 0.0
	if str(s["id"]) == "handoff":
		d *= 1.0 - u
	(sd as SkyDirector).film_dust = d
	if _replay and (sd as SkyDirector).sphere:
		(sd as SkyDirector).call("_apply_sphere")  # the game is stopped: its sky does not update itself


func _enter(i: int, lt: float) -> void:
	_si = i
	_lt = lt
	_cue_i = 0
	_line_i = 0
	_sfx_i = 0
	_acc.clear()
	_look_set = false
	var s: Dictionary = _shots[i]
	# Entering mid-shot (a seek): what was due before `lt` is skipped, not fired late.
	for c: Variant in s["cues"]:
		if float(c[0]) < lt - 0.001:
			_cue_i += 1
	for l: Variant in s.get("lines", []):
		if float(l[0]) < lt - 0.001:
			_line_i += 1
	for x: Variant in s.get("sfx", []):
		if float(x[0]) < lt - 0.001:
			_sfx_i += 1
	var set_: String = str(s["set"])
	if set_ == "world":
		_close_stage()
	else:
		_open_stage()
		_stage.show_set(set_)
		_stage.shake = 0.0
	_cam_start = _cam.global_transform if _cam else Transform3D()
	_fov_start = _cam.fov if _cam else 55.0
	var fn: String = "_in_" + str(s["id"])
	var t0: int = Time.get_ticks_usec()
	if has_method(fn):
		call(fn)
	if DevHooks.has("intro") and Time.get_ticks_usec() - t0 > 8000:
		print("[intro] shot %s set up in %.1f ms" % [s["id"], (Time.get_ticks_usec() - t0) / 1000.0])


func _fire_cues(lt: float) -> void:
	var s: Dictionary = _shots[_si]
	var cues: Array = s["cues"]
	while _cue_i < cues.size() and float(cues[_cue_i][0]) <= lt:
		var fn: String = "_cue_" + str(cues[_cue_i][1])
		_cue_i += 1
		if has_method(fn):
			call(fn)
	var ls: Array = s.get("lines", [])
	while _line_i < ls.size() and float(ls[_line_i][0]) <= lt:
		_say(str(ls[_line_i][1]))
		_line_i += 1
	var sfx: Array = s.get("sfx", [])
	while _sfx_i < sfx.size() and float(sfx[_sfx_i][0]) <= lt:
		var x: Array = sfx[_sfx_i]
		_sfx_i += 1
		_snd(str(x[1]), float(x[2]) if x.size() > 2 else 1.0, float(x[3]) if x.size() > 3 else 0.0)


func _snd(name_: String, pitch: float = 1.0, db: float = 0.0, fallback: String = "blip") -> void:
	Audio.play(name_ if Audio.has_sound(name_) else fallback, pitch, db)


## True once every `every` seconds of the current shot (a steady, repeatable rhythm for puffs).
func _tick(key: String, every: float, delta: float) -> bool:
	var v: float = float(_acc.get(key, 0.0)) + delta
	if v >= every:
		_acc[key] = v - every
		return true
	_acc[key] = v
	return false


# --- Camera --------------------------------------------------------------------------------

func _in_world() -> bool:
	return str(_shots[_si]["set"]) == "world"


## Where a named subject is, in the current set's space (the world shots: site coordinates).
func _anchor(name_: String) -> Vector3:
	if _in_world():
		match name_:
			"pod":
				return _v(_pod.global_position) if _pod and is_instance_valid(_pod) else POD_POS
			"lumi":
				return _v(_lumi().global_position)
			"glim":
				var g: Node3D = _glim()
				return _v(g.global_position) if g else POD_POS + Vector3(0, 1.4, 0)
			"":
				return POD_POS
		return _yard(name_)
	var st: SpaceStage = _stage
	match name_:
		"ark": return st.ark.global_position
		"pod": return st.vault_pod.global_position if str(_shots[_si]["set"]) == "vault" else st.pod.global_position
		"lumi": return st.lumi.global_position
	return SpaceStage.VAULT_AT if str(_shots[_si]["set"]) == "vault" else Vector3.ZERO


## The way a subject faces, level, in the current set's space.
func _facing_of(name_: String) -> Vector3:
	var f := Vector3(0, 0, -1)
	if _in_world() and name_ == "lumi":
		f = site_xf.basis.orthonormalized().inverse() * (-_lumi().global_basis.z)
	elif not _in_world() and name_ == "lumi":
		f = -_stage.lumi.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)


## A yard anchor in site coordinates (the bench, the bin); out past the door when it isn't there.
func _yard(name_: String) -> Vector3:
	if yard_fn.is_valid():
		var p: Variant = yard_fn.call(name_)
		if p is Vector3:
			return _v(p)
	return POD_POS + _door() * 9.0 + _door().cross(Vector3.UP) * 4.0


## The way the landed pod's door faces (site coordinates, level).
func _door() -> Vector3:
	return Vector3(-sin(_pod_yaw), 0.0, -cos(_pod_yaw))


## A point given in the landed pod's frame (x right of the door, -z out of the door), in site
## coordinates.
func _pod_pt(v: Vector3) -> Vector3:
	return POD_POS + Basis(Vector3.UP, _pod_yaw) * v


func _glim() -> Node3D:
	if _pod and is_instance_valid(_pod):
		return _pod.get_node_or_null(GlimDirector.STUCK_NAME) as Node3D
	return null


func _aim_camera(s: Dictionary, u: float, delta: float) -> void:
	var c: Dictionary = s.get("cam", {})
	var e: float = eased(str(c.get("ease", "inout")), u)
	var world_shot: bool = _in_world()
	var xf: Transform3D
	var fov2: Vector2 = _pair(c.get("fov"), 50.0, 50.0)
	var fov: float = lerpf(fov2.x, fov2.y, e)
	var mode: String = str(c.get("mode", ""))
	if mode == "handoff":
		# From wherever the last shot left the camera to the game's own camera, exactly.
		var to: Transform3D = _prev_cam.global_transform if _prev_cam and is_instance_valid(_prev_cam) else _cam_start
		if _replay:
			# The game camera is wherever the player left it: settle behind the film's Lumi instead.
			var lp: Vector3 = _end_spot()
			var lf: Vector3 = _end_facing()
			to = Transform3D(Basis(), _w(lp - lf * 5.6 + Vector3(0, 3.4, 0))).looking_at(_w(lp + lf * 2.0 + Vector3(0, 0.9, 0)), _up())
		xf = _cam_start.interpolate_with(to, e)
		fov = lerpf(_fov_start, _prev_cam.fov if _prev_cam and is_instance_valid(_prev_cam) and not _replay else _fov_start, e)
		_cam.global_transform = xf
		_cam.fov = fov
		return
	var pos: Vector3
	var look: Vector3
	if mode == "over_shoulder":
		# Behind Lumi's shoulder, looking past it at a target (the old cleanup station).
		var lumi: Vector3 = _anchor("lumi")
		var tgt: Vector3 = _anchor(str(c.get("target", "bench")))
		var to_t: Vector3 = tgt - lumi
		to_t.y = 0.0
		to_t = to_t.normalized() if to_t.length() > 0.1 else _door()
		var side: Vector3 = to_t.cross(Vector3.UP)
		var back: Vector2 = _pair(c.get("back"), 2.6, 1.9)
		var sd: Vector2 = _pair(c.get("side"), 1.0, 0.75)
		var upv: Vector2 = _pair(c.get("up"), 1.3, 1.2)
		var aim: Vector2 = _pair(c.get("aim"), 0.55, 0.8)
		pos = lumi - to_t * lerpf(back.x, back.y, e) + side * lerpf(sd.x, sd.y, e) + Vector3(0, lerpf(upv.x, upv.y, e), 0)
		look = (lumi + Vector3(0, 0.9, 0)).lerp(tgt + Vector3(0, 1.0, 0), lerpf(aim.x, aim.y, e))
	elif mode == "orbit":
		# Round a subject: `angle` in degrees from its front (180 = behind it), at a radius and height.
		var ctr: Vector3 = _anchor(str(c.get("center", "lumi")))
		var f: Vector3 = _facing_of(str(c.get("center", "lumi")))
		var rt: Vector3 = f.cross(Vector3.UP)
		var ang: Vector2 = _pair(c.get("angle"), 30.0, 180.0)
		var rad: Vector2 = _pair(c.get("radius"), 3.0, 6.0)
		var hgt: Vector2 = _pair(c.get("height"), 1.0, 3.0)
		var lup: Vector2 = _pair(c.get("look_up"), 0.8, 1.0)
		var ahead: Vector2 = _pair(c.get("ahead"), 0.0, 2.0)
		var a: float = deg_to_rad(lerpf(ang.x, ang.y, e))
		pos = ctr + (f * cos(a) + rt * sin(a)) * lerpf(rad.x, rad.y, e) + Vector3(0, lerpf(hgt.x, hgt.y, e), 0)
		look = ctr + Vector3(0, lerpf(lup.x, lup.y, e), 0) + f * lerpf(ahead.x, ahead.y, e)
	else:
		var from: Vector3 = _v3(c.get("from"))
		var to2: Vector3 = _v3(c.get("to"), from)
		var lf: Vector3 = _v3(c.get("look_from"))
		var lt2: Vector3 = _v3(c.get("look_to"), lf)
		var off: Vector3 = from.lerp(to2, e)
		var loff: Vector3 = lf.lerp(lt2, e)
		if str(c.get("frame", "")) == "pod":
			var b := Basis(Vector3.UP, _pod_yaw)
			off = b * off
			loff = b * loff
		pos = _anchor(str(c.get("anchor", ""))) + off
		look = _anchor(str(c.get("look_anchor", ""))) + loff
	# The aim trails a moving subject a little, so the camera follows instead of being bolted on.
	var lag: float = float(c.get("look_lag", 0.0))
	if lag > 0.0 and _look_set and delta > 0.0:
		_look_pt = _look_pt.lerp(look, 1.0 - exp(-delta / lag))
	else:
		_look_pt = look
	_look_set = true
	look = _look_pt
	var up: Vector3 = Vector3.UP
	if world_shot:
		pos = _w(pos)
		look = _w(look)
		up = _up()
	if pos.distance_to(look) < 0.01:
		look = pos + Vector3(0, 0, -1)
	xf = Transform3D(Basis(), pos).looking_at(look, up)
	var roll: Vector2 = _pair(c.get("roll"), 0.0, 0.0)
	var r: float = deg_to_rad(lerpf(roll.x, roll.y, e))
	# Hand-held sway (slow) and shake from hits (fast, decaying): rotations, plus a small shove.
	var hand: float = deg_to_rad(float(c.get("hand", 0.0)))
	var sw: Vector3 = Vector3(sin(_t * 0.9) + sin(_t * 1.7 + 1.0) * 0.5, sin(_t * 1.1 + 2.0) + sin(_t * 2.3) * 0.5, sin(_t * 0.7 + 0.5)) * hand
	var tr2: float = _trauma * _trauma
	var sh: Vector3 = SpaceStage.shake_offset(_t, tr2)
	xf.basis = xf.basis * Basis.from_euler(Vector3(sw.x + sh.x * 0.022, sw.y + sh.y * 0.022, r + sw.z * 0.5 + sh.z * 0.03))
	xf.origin += xf.basis * Vector3(sh.y, sh.x, 0.0) * 0.07
	if world_shot:
		_cam.global_transform = xf
		_cam.fov = fov
	else:
		_stage.set_cam(xf, fov)
		_stage.shake = 0.0


# --- Subtitles -------------------------------------------------------------------------------

## The world's subtitle line (or the intro's own if the world has none).
func _subs() -> Subtitles:
	if _own_subs and is_instance_valid(_own_subs):
		return _own_subs  # a rewatch: the game's own line is stopped with the game
	if Subtitles.current and is_instance_valid(Subtitles.current):
		return Subtitles.current
	var s := Subtitles.new()
	s.world = world
	add_child(s)
	return s


## Queue one of lines().
func _say(key: String) -> void:
	var all: Dictionary = lines()
	if not all.has(key):
		return
	var l: Array = all[key]
	var text: String = str(l[0])
	if l.size() > 2 and str(l[2]) == "tail":
		text = glitch_tail(text)
	_subs().queue_line(text, str(l[1]))
	if key == "brief_0" and not _replay:
		GameState.flags["onboard_brief"] = true  # the objectives don't replay it
		brief_played = true


# =============================================================================================
# The shots. _in_<id> sets a shot up from nothing; _run_<id>(lt, u, delta) poses it each frame
# (lt = seconds into the shot, u = 0..1 through it); _cue_<name> fires once at its second.
# =============================================================================================

# --- Act 1: every night, the same look down ---------------------------------------------------

## How far the storm has got with the ark: 0 calm, 1 the engines are hit (dead, dark, half the
## windows out), 2 the dome is broken too (alarm, air and leaves streaming out).
func _ark_state(stage: int) -> void:
	var ark: CradleShip = _stage.ark
	ark.alarm = 1.0 if stage >= 1 else 0.0
	ark.thrust = 0.0 if stage >= 1 else 1.0
	ark.power = [1.0, 0.6, 0.42][clampi(stage, 0, 2)]
	ark.breach = 1.0 if stage >= 2 else 0.0
	_stage.set_alarm(1.0 if stage >= 1 else 0.0)


func _space_base() -> void:
	var st: SpaceStage = _stage
	_ark_state(0)
	st.ark.visible = true
	st.ark.scale = Vector3.ONE
	st.ark.rotation = Vector3(0, -PI * 0.5, 0)  # flies toward +X
	for k: int in 6:
		st.ark.release_pod(k, false)
	st.pod.visible = false
	var far: Node3D = st.pod.get_node_or_null("FarGlow") as Node3D
	if far:
		far.visible = false
	st.motes_on = true
	st.motes_vel = Vector3.ZERO
	st.env.ambient_light_color = Color(0.32, 0.36, 0.45)
	st.fill.light_energy = 0.55 * _p("fill", 1.0)  # the planet's warm bounce from below
	set_fire(_stage_fire(), 0.0, 0.0)
	_planet(_p("planet_scale", 1.0), _pv("planet_top", Vector3(0, -60, -120)))


## The stage's planet, `k` times its size, with its highest point at `top`: far below for the long
## fall (the ark's low orbit is only 60 m up, and a falling pod would reach the ground in seconds).
func _planet(k: float, top: Vector3) -> void:
	_stage.planet.scale = Vector3.ONE * k
	_stage.planet.position = top - Vector3(0, SpaceStage.PLANET_R * k, 0)


func _ark_glide(lt: float) -> void:
	_stage.ark.position = _pv("ark_from", Vector3.ZERO) + Vector3(_p("ark_speed", 2.0) * lt, 0, 0)


func _in_planet() -> void:
	_space_base()
	_title.modulate.a = 0.0
	_title_sub.modulate.a = 0.0


func _run_planet(lt: float, _u: float, _delta: float) -> void:
	_ark_glide(lt)


func _cue_title_in() -> void:
	_title.text = "GREENFALL"
	var tw := _title.create_tween().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_title_sub, "modulate:a", 0.8, 1.8).set_delay(0.5)


func _cue_title_out() -> void:
	var tw := _title.create_tween().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 0.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_title_sub, "modulate:a", 0.0, 0.8)


## The vault set as the story stands: 0 a quiet night, 1 the glass is broken (alarm, wind, half
## the lamps out).
func _vault_base(broken: bool) -> void:
	var st: SpaceStage = _stage
	st.set_alarm(1.0 if broken else 0.0)
	st.vault_breach = 1.0 if broken else 0.0
	st.vault_wind = 1.0 if broken else 0.0
	st.vault_power = 0.5 if broken else 1.0
	if not broken:
		st.vault_clear_fx()
	if broken:  # the alarm's red is in the air of the room, not only in its sweeping lamp
		st.env.ambient_light_color = Color(0.55, 0.22, 0.18)
		st.env.ambient_light_energy = 0.55
	st.motes_on = false
	st.lumi.visible = true
	st.lumi.sleeping = false
	st.lumi.holding = false
	st.lumi.position = WINDOW_SPOT
	st.lumi.rotation = Vector3.ZERO
	st.lumi.set_happy(0.2 if broken else 0.5)
	st.lumi.look_toward(null)
	st.tray.visible = true
	st.tray.position = Vector3(0, 0.84, 0)
	st.tray.rotation = Vector3.ZERO
	st.vault_pod.position = Vector3(0, 0, 3.95)
	st.vault_pod.visible = true
	_hold_tray = false
	_tray_glow(0.75)
	EscapePod.set_open(st.vault_pod, true)
	# The door's eye mark at the film's exposure (it bloomed into a white disc).
	(st.vault_pod.get_meta("glyph") as StandardMaterial3D).emission_energy_multiplier = 0.8


## Where Lumi stands at the glass, and at the planter table (facing the tray).
const WINDOW_SPOT := Vector3(0.1, 0.15, -3.7)
const TABLE_SPOT := Vector3(-0.25, 0.15, -1.0)
const TABLE_YAW: float = PI - 0.24


func _tray_glow(e: float) -> void:
	var m: Variant = _stage.tray.get_meta("leaf", null)
	if m is StandardMaterial3D:
		(m as StandardMaterial3D).emission_energy_multiplier = e


func _in_window() -> void:
	_vault_base(false)
	var v: Vector3 = SpaceStage.VAULT_AT
	_stage.lumi.look_toward(v + Vector3(0.6, 0.5, -30.0))


func _run_window(lt: float, _u: float, _delta: float) -> void:
	var lumi: PatchModel = _stage.lumi
	var v: Vector3 = SpaceStage.VAULT_AT
	lumi.position.y = 0.15 + sin(lt * 1.1) * 0.012
	var turn_at: float = _p("turn_at", 4.6)
	if lt >= _p("droop_at", 3.2) and lt < turn_at:
		# Nothing green tonight either: the head sinks.
		lumi.look_toward(v + Vector3(0.2, -1.2, -9.0))
		lumi.set_happy(0.25)
	elif lt >= turn_at:
		# Round to the tray, where there is something to do.
		var k: float = eased("inout", (lt - turn_at) / 1.3)
		lumi.rotation.y = lerp_angle(0.0, PI, k)
		lumi.look_toward(v + Vector3(0, 0.9, 0) if k > 0.5 else null)
		lumi.set_happy(0.5)


func _in_ark() -> void:
	_space_base()


func _run_ark(lt: float, _u: float, _delta: float) -> void:
	_ark_glide(lt)


func _in_tend() -> void:
	_vault_base(false)
	var lumi: PatchModel = _stage.lumi
	lumi.position = TABLE_SPOT
	lumi.rotation = Vector3(0, TABLE_YAW, 0)
	lumi.set_happy(1.0)
	lumi.look_toward(SpaceStage.VAULT_AT + Vector3(0, 0.95, 0))


func _run_tend(lt: float, _u: float, delta: float) -> void:
	_hum(lt, delta)


## Lumi sways and hums to the seedlings, and they answer: every note, the leaves glow a little
## brighter and the whole tray shivers.
func _hum(t: float, delta: float) -> void:
	var st: SpaceStage = _stage
	st.lumi.rotation.z = sin(t * 2.2) * 0.06
	st.lumi.position.y = 0.15 + sin(t * 1.1) * 0.015
	var since: float = float(_acc.get("since", 9.0)) + delta
	if _tick("note", 0.8, delta):
		since = 0.0
		_snd("beep", 1.0 + 0.4 * (0.5 + 0.5 * sin(t * 5.3)), -15.0)  # Lumi's own voice, three notes over and over
	_acc["since"] = since
	var pulse: float = exp(-since * 3.2)
	_tray_glow(0.7 + 0.7 * pulse)
	var n: int = 0
	for c: Node in st.tray.get_children():
		if c is Node3D and c.get_child_count() > 0 and not (c is MeshInstance3D):
			n += 1
			(c as Node3D).scale = Vector3.ONE * (1.0 + 0.09 * pulse * (0.6 + 0.4 * sin(n * 1.7)))


# --- Act 2: the storm --------------------------------------------------------------------------

func _in_omen() -> void:
	_vault_base(false)
	var lumi: PatchModel = _stage.lumi
	lumi.position = TABLE_SPOT
	lumi.rotation = Vector3(0, TABLE_YAW, 0)
	lumi.set_happy(0.6)
	lumi.look_toward(SpaceStage.VAULT_AT + Vector3(0, 0.95, 0))


## The first one goes by outside the glass: its light sweeps the room and Lumi looks up.
func _cue_first_streak() -> void:
	var v: Vector3 = SpaceStage.VAULT_AT
	_stage.meteor(v + Vector3(-70, 62, -60), v + Vector3(95, 8, -44), 1.5, 2.6)
	_snd("whoosh", 0.38, -7.0)
	_snd("groan", 0.7, -12.0)
	_acc["sweep"] = _lt
	var lumi: PatchModel = _stage.lumi
	lumi.rotation.z = 0.0
	lumi.set_happy(0.3)
	lumi.shudder(0.25)


func _cue_more_streaks() -> void:
	var v: Vector3 = SpaceStage.VAULT_AT
	for i: int in 3:
		_stage.meteor(v + Vector3(-80 + i * 22, 70 - i * 6, -75 + i * 9), v + Vector3(70 + i * 20, 14 + i * 5, -50 - i * 6), 1.3 + 0.25 * i, 1.6 + 0.5 * i)
	_snd("whoosh", 0.5, -10.0)


func _run_omen(lt: float, _u: float, _delta: float) -> void:
	var lumi: PatchModel = _stage.lumi
	var v: Vector3 = SpaceStage.VAULT_AT
	var sw: float = lt - float(_acc.get("sweep", INF))
	if sw >= 0.0:
		# Its eyes follow the light across the glass, then stay on the sky.
		var k: float = clampf(sw / 1.4, 0.0, 1.0)
		lumi.look_toward(v + Vector3(lerpf(-5.0, 6.0, k), 3.6, -6.0))
		# The streak's light: a hard warm sweep over the room.
		var flash: float = exp(-pow((sw - 0.55) / 0.3, 2.0))
		_stage.env.ambient_light_color = Color(0.3, 0.36, 0.42).lerp(Color(1.0, 0.72, 0.45), 0.8 * flash)
		_stage.env.ambient_light_energy = 0.4 + 1.3 * flash


func _in_storm() -> void:
	_space_base()
	_ark_p0 = _pv("ark_from", Vector3(-14, 0, 0))
	_ark_v = Vector3(_p("ark_speed", 1.6), 0, 0)
	_ark_t0 = float(_shots[_si]["t0"])


func _ark_storm() -> Vector3:
	return _ark_p0 + _ark_v * (_t - _ark_t0)


func _run_storm(lt: float, _u: float, delta: float) -> void:
	_stage.ark.position = _ark_storm()
	var first: float = float(_acc.get("barrage_at", INF))
	if lt >= first and _tick("meteor", _p("barrage_gap", 0.3), delta) and int(_acc.get("n", 0)) < int(_p("barrage", 13.0)):
		var n: int = int(_acc.get("n", 0))
		_acc["n"] = n + 1
		_storm_meteor(n)
	# The engines after their hit: fire, black smoke and sparks pour out of the block.
	if lt > float(_acc.get("engines", INF)):
		_ark_wounds(lt, delta, 0.0, _p("fx_size", 1.0))


## The ark after the storm, in every shot that shows it: its engine block burns and pours out black
## smoke (a ragged trail behind it, the way it came), hot bits spit out of it now and then, and,
## once the dome is broken (`vent` > 0), the garden's air and leaves stream out of the hole.
func _ark_wounds(lt: float, delta: float, vent: float, size_k: float = 1.0) -> void:
	var st: SpaceStage = _stage
	var e: Vector3 = st.ark.engine_world()
	var back: Vector3 = (st.ark.global_basis * Vector3(0, 0, 1)).normalized()
	var j := Vector3(sin(lt * 9.1), cos(lt * 7.3), sin(lt * 5.7 + 1.0))
	if _tick("smoke", 0.08, delta):
		# Grey-brown, not black: black smoke vanishes against black space.
		# (A shot can keep it close to the ship: `smoke_drift`, `smoke_life`; the camera of `apart`
		# falls back through where a long trail would be.)
		st.puff(e + back * 1.5 + j * 1.6 * size_k, back * _p("smoke_drift", 3.2) + j * 0.9, Color(0.5, 0.45, 0.4, 0.5), 3.4 * size_k, _p("smoke_life", 3.2))
	if _tick("fire", 0.06, delta):
		st.puff(e + back * 0.6 + j * 0.9 * size_k, back * 2.2 + j * 1.2, Color(1.0, 0.48, 0.16, 0.55), 1.5 * size_k, 0.8)
	if _tick("spark", 0.55, delta):
		st.debris(e + j, 2, 7.0, 0.35, back)
	if vent > 0.0:
		_vent_dome(lt, delta, vent, size_k)


## Meteor n of the barrage: they rake across the frame from behind the ark, some of them close.
func _storm_meteor(n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + n * 31
	var ark: Vector3 = _stage.ark.position
	var near: bool = n % 3 == 1
	var a := ark + Vector3(rng.randf_range(-95, -35), rng.randf_range(34, 66), rng.randf_range(-46, 8) + (30.0 if near else 0.0))
	var b := a + Vector3(125, -104, rng.randf_range(-6, 26))
	_stage.meteor(a, b, rng.randf_range(1.3, 1.9), rng.randf_range(0.9, 1.6) * (1.8 if near else 1.0))
	if near:
		_snd("whoosh", rng.randf_range(0.7, 0.95), -9.0)
		_trauma = maxf(_trauma, 0.35)


func _cue_barrage() -> void:
	_acc["barrage_at"] = _lt
	_acc["meteor"] = 10.0  # the first one at once


## One finds the engine block: a flash, the blue glow dies, the lights down the hull go red.
func _cue_engine_meteor() -> void:
	var hit: Vector3 = _stage.ark.engine_world() + _ark_v * 0.7
	_stage.meteor(hit + Vector3(-52, 44, 18), hit, 0.7, 1.7)


func _cue_engine_hit() -> void:
	var st: SpaceStage = _stage
	_acc["engines"] = _lt
	st.blast(st.ark.engine_world(), 1.7, Color(0.7, 0.85, 1.0))
	st.debris(st.ark.engine_world(), 18, 9.0, 1.0, Vector3(-1.0, 0.2, 0.3))
	st.shake = 0.0
	_ark_state(1)
	_trauma = 0.9
	_snd("thud", 0.42, 1.0)
	_snd("crunch", 0.55, -3.0)
	_snd("groan", 0.6, -4.0)
	_snd("siren", 1.0, -10.0)


## The one that will hit the dome: launched now, it lands as the next shot's "dome_hit" cue fires.
func _cue_hit_meteor() -> void:
	var next: Dictionary = _shots[mini(_si + 1, _shots.size() - 1)]
	var flight: float = float(_shots[_si]["d"]) - _lt + 0.5
	for c: Variant in next["cues"]:
		if str(c[1]) == "dome_hit":
			flight = float(_shots[_si]["d"]) - _lt + float(c[0])
	var hit: Vector3 = _stage.ark.breach_world() + _ark_v * flight
	_stage.meteor(hit + Vector3(-58, 50, 34), hit, flight, 1.5)


func _in_hit() -> void:
	if _ark_v == Vector3.ZERO:  # seeked straight here
		_space_base()
		_ark_p0 = Vector3(-14, 0, 0)
		_ark_v = Vector3(_p("ark_speed", 1.6), 0, 0)
		_ark_t0 = float(_shots[_si]["t0"]) - 5.0
	_ark_state(1)
	_stage.motes_on = true


func _run_hit(lt: float, _u: float, delta: float) -> void:
	var st: SpaceStage = _stage
	st.ark.position = _ark_storm()
	var hit_at: float = float(_acc.get("hit", INF))
	if lt > hit_at:
		# The hole opens fast, then the garden's air pours out of it: white breath, torn leaves.
		st.ark.breach = clampf((lt - hit_at) / 0.22, 0.0, 1.0)
		_vent_dome(lt, delta, 1.0)
	_ark_wounds(lt, delta, 0.0, _p("fx_size", 1.0))


## Air and leaves streaming out of the broken dome (the space set).
func _vent_dome(lt: float, delta: float, k: float, size_k: float = 1.0) -> void:
	var st: SpaceStage = _stage
	var hole: Vector3 = st.ark.breach_world()
	var out: Vector3 = (hole - st.ark.dome_world()).normalized()
	if _tick("vent", 0.06, delta):
		var j := Vector3(sin(lt * 9.0), cos(lt * 7.0), sin(lt * 5.0 + 1.0)) * 0.5
		st.puff(hole + j * 0.4 * size_k, (out + j * 0.35) * 6.5 * k, Color(0.92, 0.96, 1.0, 0.5), 1.3 * size_k)
	if _tick("leaf", 0.035, delta):
		st.leaf(hole, (out + Vector3(sin(lt * 31.0), cos(lt * 23.0), sin(lt * 17.0)) * 0.45) * (4.0 + 3.0 * absf(sin(lt * 13.0))) * k)


func _cue_dome_hit() -> void:
	var st: SpaceStage = _stage
	_acc["hit"] = _lt
	var hole: Vector3 = st.ark.breach_world()
	st.blast(hole, 1.25)
	st.debris(hole, 22, 7.0, 0.55, (hole - st.ark.dome_world()).normalized())
	st.shake = 0.0
	_ark_state(1)
	_trauma = 1.0
	_snd("thud", 0.4, 2.0)
	_snd("crunch", 0.5, -2.0)
	_snd("roar", 1.3, -8.0)  # the air going out


func _in_breach() -> void:
	_vault_base(true)
	var lumi: PatchModel = _stage.lumi
	lumi.position = TABLE_SPOT
	lumi.rotation = Vector3(0, TABLE_YAW, 0)
	lumi.look_toward(null)


func _cue_vault_shake() -> void:
	var v: Vector3 = SpaceStage.VAULT_AT
	_trauma = 0.9
	_stage.lumi.shudder(0.5)
	_stage.debris(SpaceStage.vault_hole() + Vector3(-0.4, -0.3, 0.4), 14, 3.0, 0.3, (v + Vector3(0, 1.0, 0) - SpaceStage.vault_hole()).normalized() * 0.4)
	_stage.shake = 0.0
	_snd("crunch", 1.4, -3.0)
	_snd("clink", 0.6, -6.0)


func _cue_grab_tray() -> void:
	_stage.lumi.holding = true
	_hold_tray = true
	_stage.lumi.set_happy(0.45)
	_snd("beep", 1.5, -8.0)


## Lumi's way from the planter table to the drop pod: round the table, never through it.
func _vault_path(k: float) -> Vector3:
	var a: Vector3 = TABLE_SPOT
	var c := Vector3(-1.75, 0.15, 0.9)
	var b := Vector3(-0.2, 0.2, 2.75)
	return a.lerp(c, k).lerp(c.lerp(b, k), k)


func _run_breach(lt: float, _u: float, _delta: float) -> void:
	var st: SpaceStage = _stage
	var lumi: PatchModel = st.lumi
	var v: Vector3 = SpaceStage.VAULT_AT
	var go: float = _p("go_at", 2.6)
	var k: float = eased("inout", (lt - go) / _p("go_dur", 3.0))
	var pull: Vector3 = Vector3(SpaceStage.VAULT_HOLE.x, 0.0, SpaceStage.VAULT_HOLE.z).normalized()
	lumi.position = _vault_path(k)
	# The wind has it the whole time: a drag toward the hole it has to lean against.
	var drag: float = 0.16 * exp(-lt * 1.4) + 0.035 * sin(lt * 11.0) * (1.0 - k)
	lumi.position += pull * drag
	if lt < 1.0:
		# The blast: thrown toward the hole, catching itself on the table.
		var j: float = exp(-lt * 3.5) * sin(lt * 16.0)
		lumi.position += Vector3(0, absf(j) * 0.05, 0)
		lumi.rotation.x = j * 0.16
		lumi.look_toward(SpaceStage.vault_hole())
	elif lt < go:
		# The hole, then the tray: it will not leave them. A lean back before the dash.
		lumi.look_toward(SpaceStage.vault_hole() if lt < 1.5 else v + Vector3(0, 0.9, 0))
		lumi.rotation.x = 0.1 * eased("inout", (lt - (go - 0.5)) / 0.5)
	else:
		lumi.look_toward(null)
		var ahead: Vector3 = _vault_path(minf(k + 0.06, 1.0)) - _vault_path(maxf(k - 0.02, 0.0))
		if ahead.length() > 0.001:
			lumi.rotation.y = lerp_angle(lumi.rotation.y, atan2(-ahead.x, -ahead.z), 0.25)
		# Head down into the wind.
		lumi.rotation.x = lerpf(0.1, -0.24, eased("out", (lt - go) / 0.4)) * (1.0 - eased("inout", (k - 0.85) / 0.15))
	lumi.rotation.z = 0.05 * sin(lt * 9.0) * (1.0 - k * 0.5)
	if _hold_tray:
		st.lumi.holding = true
	_alarm_sound(_delta)


## The alarm while the vault is open to space: the siren's sweep every 1.7 s over the wind.
func _alarm_sound(delta: float) -> void:
	if _tick("siren", 1.7, delta):
		_snd("siren", 1.0, -11.0)
	if _tick("wind", 2.3, delta):
		_snd("roar", 1.4, -12.0)


## Where Lumi rides in the pod (the vault set), facing the door.
const POD_SEAT := Vector3(0.0, 0.47, 3.75)


func _in_seal() -> void:
	_vault_base(true)
	var lumi: PatchModel = _stage.lumi
	lumi.holding = true
	_hold_tray = true
	lumi.set_happy(0.4)
	lumi.look_toward(null)
	lumi.position = _vault_path(1.0)
	lumi.rotation = Vector3(0, PI, 0)


func _run_seal(lt: float, _u: float, _delta: float) -> void:
	var st: SpaceStage = _stage
	var lumi: PatchModel = st.lumi
	var drop: float = lt - float(_acc.get("drop", INF))
	if drop >= 0.0:
		# The bay lets go: the pod sinks out of the room, slowly, then gone.
		var k: float = eased("in", drop / 2.6)
		st.vault_pod.position.y = -3.4 * k
		if k >= 1.0:
			st.vault_pod.visible = false
	if not lumi.visible:
		_alarm_sound(_delta)
		return
	var k2: float = eased("out", lt / 1.0)
	lumi.position = _vault_path(1.0).lerp(POD_SEAT, k2)
	# In, then round to face the room it is leaving: one long look back.
	lumi.rotation.y = lerp_angle(PI, 0.0, eased("inout", (lt - 0.5) / 0.7))
	lumi.rotation.x = 0.0
	lumi.rotation.z = 0.0
	if lt > 1.2:
		lumi.look_toward(SpaceStage.VAULT_AT + Vector3(0, 0.95, 0))
	_alarm_sound(_delta)


func _cue_seal_pod() -> void:
	var st: SpaceStage = _stage
	var shut: float = EscapePod.close_door(st.vault_pod, 0.8)
	_snd("hydraulic", 1.1, -4.0)
	var tw := st.create_tween()
	tw.tween_interval(shut * 0.72)
	tw.tween_callback(func() -> void:
		st.lumi.visible = false
		_hold_tray = false
		st.tray.visible = false)
	tw.tween_interval(shut * 0.28)
	tw.tween_callback(func() -> void:
		_snd("clunk", 0.8, -2.0, "thud")
		_trauma = maxf(_trauma, 0.35))


func _cue_drop_pod() -> void:
	_acc["drop"] = _lt
	_snd("clunk", 0.6, 0.0, "thud")
	_snd("steam", 0.8, -6.0)
	_trauma = maxf(_trauma, 0.3)


func _stage_fire() -> Node3D:
	if _stage == null:
		return null
	var f: Node3D = _stage.pod.get_node_or_null("ReentryFire") as Node3D
	if f == null:
		f = build_fire()
		_stage.pod.add_child(f)
		f.visible = false
	return f


func _in_release() -> void:
	_space_base()
	var st: SpaceStage = _stage
	_ark_state(2)
	st.ark.position = Vector3.ZERO
	st.pod.visible = true
	st.pod.scale = Vector3.ONE
	st.pod.global_transform = st.ark.pod_xform(2)  # exactly where it hangs under the keel
	_pod_p0 = st.pod.global_position
	_acc["rot0"] = st.pod.global_basis
	st.ark.release_pod(2)
	EscapePod.set_open(st.pod, false)


## WREN lets it go: the clamp opens with a small puff of gas. No bang: this is a choice.
func _cue_let_go() -> void:
	var st: SpaceStage = _stage
	_acc["go"] = _lt
	for i: int in 4:
		st.puff(st.pod.global_position + Vector3(0, 1.3, 0), Vector3(cos(i * 1.6) * 1.6, 0.6, sin(i * 1.6) * 1.6), Color(0.9, 0.93, 0.97, 0.4), 0.5)
	_trauma = maxf(_trauma, 0.25)
	_snd("clunk", 0.7, -1.0, "thud")
	_snd("steam", 1.0, -5.0)


func _run_release(lt: float, _u: float, delta: float) -> void:
	var st: SpaceStage = _stage
	# The ark cannot stop or steer: it drifts on, dark aft, the dome bleeding air.
	st.ark.position = Vector3(lt * _p("ark_speed", 1.6), 0, 0)
	var tau: float = maxf(0.0, lt - float(_acc.get("go", INF)))
	# Slow at first (it hangs a moment under the keel), then the planet has it.
	st.pod.global_position = _pod_p0 + Vector3(-0.5 * tau - 0.1 * tau * tau, -0.5 * tau - 0.55 * tau * tau, 0.5 * tau)
	var b0: Basis = _acc.get("rot0", Basis())
	st.pod.global_basis = Basis(Vector3(1, 0, 0.4).normalized(), 0.14 * tau * tau) * b0
	_ark_wounds(lt, delta, 0.8)


# --- Act 3: the long fall --------------------------------------------------------------------

func _planet_top() -> Vector3:
	return _stage.planet.global_position + Vector3(0, SpaceStage.PLANET_R * _stage.planet.scale.y, 0)


## A pod falling base first along `dir`, with a slow wobble (a capsule, not a dart).
static func fall_basis(dir: Vector3, t: float, wobble: float, spin: float) -> Basis:
	var y: Vector3 = -dir.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var b := Basis(x, y, x.cross(y))
	b = b * Basis(Vector3.UP, t * spin)
	return b * Basis(Vector3(cos(t * 1.3), 0, sin(t * 1.3)).normalized(), wobble)


## Lumi's last look at home: from beside the falling pod, up at the ark as it goes. It fills the
## sky at first, burning and bleeding air, and shrinks away while WREN's voice breaks up. (It was
## a shot from above that lost the ark off the top of the frame and the pod in the dark.)
func _in_apart() -> void:
	_space_base()
	var st: SpaceStage = _stage
	_ark_state(2)
	st.ark.position = Vector3.ZERO
	st.pod.visible = true
	st.ark.release_pod(2)
	_pod_p0 = st.ark.pod_world(2)
	EscapePod.set_open(st.pod, false)


func _run_apart(lt: float, _u: float, delta: float) -> void:
	var st: SpaceStage = _stage
	st.ark.position = Vector3(lt * _p("ark_speed", 1.2), 0, 0)
	st.ark.rotation = Vector3(0, -PI * 0.5, 0.05 * sin(lt * 0.5))  # no engines to hold it steady
	# The pod falls back and down from its bay, faster all the time; the ark sails on.
	var tau: float = lt + _p("lead", 3.5)
	var back: Vector2 = _pair((_shots[_si].get("p", {}) as Dictionary).get("fall_back"), 3.0, 0.5)
	var down: Vector2 = _pair((_shots[_si].get("p", {}) as Dictionary).get("fall_down"), 1.0, 0.45)
	st.pod.global_position = _pod_p0 + Vector3(-(back.x * tau + back.y * tau * tau), -(down.x * tau + down.y * tau * tau), _p("fall_side", 0.8) * tau)
	# Turned a little toward the lens, rocking slowly (no engines, no hand on it).
	st.pod.global_basis = Basis(Vector3.UP, _p("pod_yaw", 2.6) + 0.12 * lt) * Basis(Vector3(1, 0, 0.3).normalized(), 0.22 * sin(lt * 0.6) - 0.15)
	_ark_wounds(lt, delta, 0.8, _p("fx_size", 2.2))


func _in_reentry() -> void:
	_space_base()
	var st: SpaceStage = _stage
	st.ark.visible = false
	st.pod.visible = true
	_pod_p0 = _planet_top() + _pv("pod_from", Vector3(-16, 62, 38))
	EscapePod.set_open(st.pod, false)


func _run_reentry(lt: float, _u: float, delta: float) -> void:
	var st: SpaceStage = _stage
	var vel: Vector3 = _pv("pod_vel", Vector3(6, -7.5, -4.5))
	var dir: Vector3 = vel.normalized()
	var pos: Vector3 = _pod_p0 + vel * lt
	st.pod.global_position = pos
	var k: float = eased("inout", (lt - _p("fire_at", 0.5)) / _p("fire_grow", 3.2))
	st.pod.global_basis = fall_basis(dir, lt, 0.1 + 0.08 * k, 0.5)
	set_fire(_stage_fire(), k, _t)
	# The air thickens: specks streak past, the light warms, the camera starts to buck.
	st.motes_vel = -dir * (30.0 + 110.0 * k)
	st.env.ambient_light_color = Color(0.32, 0.36, 0.45).lerp(Color(0.5, 0.33, 0.22), k)
	_trauma = maxf(_trauma, 0.25 + 0.4 * k)
	if k > 0.15 and _tick("puff", 0.11, delta):
		var side := Vector3(sin(lt * 23.0), cos(lt * 17.0), sin(lt * 13.0 + 1.0))
		st.puff(pos - dir * (3.0 + 2.0 * absf(side.x)) + side * 0.8, -dir * 7.0, Color(1.0, 0.6, 0.3, 0.26 * k), 0.8)


# --- The real planet ---------------------------------------------------------------------------

## Everything the world shots need, for where the story stands:
##   0 = the pod is still falling (the film's own pod, burning), 1 = it has crashed (the game's
##   pod in its crash site, hatch shut), 2 = the hatch is open and Lumi is out, eyes shut,
##   3 = Lumi is awake by the door, 4 = Lumi has moved out to the spot where the game starts.
func _world_state(stage: int) -> void:
	var patch: Node3D = _lumi()
	var model: PatchModel = _model()
	if stage == 0:
		if _pod == null or not is_instance_valid(_pod):
			_pod = build_pod()
			add_child(_pod)
			(_pod.get_node("Scorch") as Node3D).visible = true
			EscapePod.set_open(_pod, false)
		if _fire == null or not is_instance_valid(_fire):
			_fire = build_fire()
			_pod.add_child(_fire)
		_ensure_trail()
		_prebuild_pod()
		patch.visible = false
		return
	if not _placed:
		_land(false)
	if stage == 1:
		EscapePod.set_open(_pod, false)
		patch.visible = false
		return
	EscapePod.set_open(_pod, true, CrashSite.LEAN.x)
	patch.visible = true
	if stage >= 4:
		_put_lumi(_end_spot(), _end_facing())
	else:
		_put_lumi(_door_spot(), _door())
	if model:
		model.sleeping = stage < 3
		model.core_glow = 0.15 if stage < 3 else 0.25
		if stage >= 3:
			model.set_happy(0.5)
	if stage >= 3:
		_flicker = 1.0
		_battery.modulate.a = 1.0


func _put_lumi(at: Vector3, facing: Vector3) -> void:
	var patch: Node3D = _lumi()
	patch.global_position = _w(at)
	if facing.length() > 0.01:
		patch.look_at(_w(at + facing), _up())
		if patch == _actor:
			return
		# The globe's motor keeps its own heading and turns the body back to it: tell it too.
		var motor: Variant = patch.get("sphere_motor")
		if motor != null and (motor as Object).has_method("face"):
			(motor as Object).call("face", patch, site_xf.basis.orthonormalized() * facing)


## The pod on its way down: k = how far out it still is along FALL_FROM (1 = FALL_FROM itself).
func _fall_pose(k: float, t: float, fire_scale: float) -> void:
	var at: Vector3 = POD_POS + FALL_FROM * k
	_pod.global_position = _w(at)
	var b: Basis = fall_basis(-FALL_FROM.normalized(), t, 0.12, 0.9)
	_pod.global_basis = site_xf.basis.orthonormalized() * b
	if _fire and is_instance_valid(_fire):
		_fire.scale = Vector3.ONE * fire_scale
		set_fire(_fire, 1.0, t)
	if _trail and is_instance_valid(_trail):
		# Each frame's smoke is spread along the stretch the pod covered in it, so the trail is one
		# ragged ribbon at any frame rate (from a point it was a row of separate dark balls).
		var now: Vector3 = _pod.global_position
		var was: Vector3 = _trail.get_meta("last", now)
		var seg: Vector3 = now - was
		if seg.length() > 0.05 and seg.length() < 80.0:
			var up_hint: Vector3 = _up() if absf(seg.normalized().dot(_up())) < 0.95 else Vector3.RIGHT
			_trail.global_transform = Transform3D(Basis.looking_at(seg.normalized(), up_hint), (now + was) * 0.5)
			_trail.emission_box_extents = Vector3(0.5, 0.5, seg.length() * 0.5 + 0.2)
		else:
			_trail.global_transform = Transform3D(Basis(), now)
			_trail.emission_box_extents = Vector3(0.5, 0.5, 0.5)
		_trail.set_meta("last", now)
		_trail.emitting = true


func _in_sky() -> void:
	_world_state(0)
	_fall_pose(_p("k_from", 2.7), 0.0, _p("fire_scale", 6.0))
	if DevHooks.has("intro-scout"):
		_scout()


## Dev (--intro-scout=DIR with --intro-shot=sky, rendered): location scouting. Holds the pod in the
## sky and saves one still from each candidate camera in `scout` of data/intro_shots.json
## ([[x, y, z], [look x, y, z], fov] around the landing point), then quits.
func _scout() -> void:
	_film = false
	var dir: String = ProjectSettings.globalize_path("res://" + DevHooks.get_s("intro-scout", "screenshots/v9/intro/scout"))
	DirAccess.make_dir_recursive_absolute(dir)
	_fade.color.a = 0.0
	_fall_pose(DevHooks.get_f("intro-scout-k", 1.2), 1.0, 3.0)
	var list: Array = _table.get("scout", [])
	await get_tree().process_frame
	for i: int in list.size():
		var c: Array = list[i]
		_cam.global_transform = Transform3D(Basis(), _w(POD_POS + _v3(c[0]))).looking_at(_w(POD_POS + _v3(c[1])), _up())
		_cam.fov = float(c[2]) if c.size() > 2 else 50.0
		_fade.color.a = 0.0
		for k: int in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_jpg("%s/scout_%02d.jpg" % [dir, i], 0.9)
		print("[intro] scout %d %s" % [i, str(c)])
	get_tree().quit()


func _run_sky(lt: float, u: float, _delta: float) -> void:
	# Seen from the air: the burning pod drops past the camera and away, down toward the ruined town.
	var k: float = lerpf(_p("k_from", 2.7), _p("k_to", 1.0), eased(str((_shots[_si].get("p", {}) as Dictionary).get("fall_ease", "linear")), u))
	_fall_pose(k, lt, lerpf(_p("fire_scale", 6.0), _p("fire_scale_to", 3.0), u))
	# The air shakes as it goes by.
	var pass_k: float = _p("pass_k", 1.95)
	if absf(k - pass_k) < 0.12:
		_trauma = maxf(_trauma, 0.75)


func _in_impact() -> void:
	if not _placed:
		_world_state(0)
		_fall_pose(_p("k_from", 1.0), 0.0, _p("fire_scale", 3.0))


func _run_impact(lt: float, _u: float, _delta: float) -> void:
	var hit: float = _p("hit_at", 1.0)
	if lt < hit:
		if not _placed:
			# A breath of quiet, then it is on us: slow while far, a streak at the end.
			var k: float = eased("in", lt / hit)
			_fall_pose(lerpf(_p("k_from", 0.9), 0.015, k), 4.8 + lt, lerpf(_p("fire_scale", 2.6), 1.3, k))
		return
	if not _placed:
		_land(true)


## The pod digs in, bounces once and rocks to rest (it does not just stop).
func _site_settle(e: float) -> void:
	if _site == null or not is_instance_valid(_site):
		return
	var xf: Transform3D = _site_rest
	if e < 2.5:
		var up: Vector3 = _up()
		var bounce: float = exp(-e * 5.0) * cos(e * 13.0) * 0.16
		var rock: float = exp(-e * 3.2) * sin(e * 10.0) * 0.07
		var axis: Vector3 = (site_xf.basis.orthonormalized() * FALL_FROM.cross(Vector3.UP)).normalized()
		xf.basis = Basis(axis, rock) * xf.basis
		xf.origin += up * (bounce - exp(-e * 7.0) * 0.1)
	_site.global_transform = xf
	_plume_rise(clampf(e / 7.0, 0.0, 1.0))


## The tall smoke column over the crash grows up out of it instead of standing there at once.
func _plume_rise(k: float) -> void:
	if _site == null or not is_instance_valid(_site):
		return
	var plume: Node3D = _site.get_node_or_null("Plume") as Node3D
	if plume:
		var s: float = lerpf(0.03, 1.0, eased("out", k))
		var w: float = maxf(s, 0.08)  # as wide as it is tall, in its own shape: a column, not a cone of light
		plume.scale = Vector3(w, s, w)
		plume.position = Vector3(0, CrashSite.PLUME_H * 0.5 * s + 1.2, 0)


## The crash: the falling pod is gone in the flash and the game's own pod stands in the furrow.
func _land(with_fx: bool) -> void:
	_placed = true
	_land_t = _t if with_fx else -100.0
	var t0: int = Time.get_ticks_usec()
	if _trail and is_instance_valid(_trail):
		_trail.emitting = false
	if _replay or not place_pod_fn.is_valid():
		if _fire and is_instance_valid(_fire):
			_fire.queue_free()
		_fire = null
		_own_crash_site()
	else:
		place_pod()
	if _pod and is_instance_valid(_pod):
		EscapePod.set_open(_pod, false)
	if not with_fx:
		return
	_impact_fx()
	if DevHooks.has("intro"):
		print("[intro] crash at %.2fs: pod swap and effects in %.1f ms" % [_t, (Time.get_ticks_usec() - t0) / 1000.0])
	_tunes_land()  # [tunes]
	_snd("thud", 0.5, 4.0)
	_snd("crunch", 0.6, 0.0)
	_trauma = 1.15


func _in_dust() -> void:
	_world_state(1)


func _cue_glim_flare() -> void:
	var g: Node3D = _glim()
	if g and g.has_method("flare"):
		g.call("flare", 1.5)
		_snd("buzz", 1.9, -16.0)


func _in_hatch() -> void:
	_world_state(1)


func _cue_open_hatch() -> void:
	var pod: Node3D = _pod
	EscapePod.open_door(pod, func(p: Vector3, _d: Vector3) -> void:
		Vfx.burst("steam", pod.global_transform * p, Color(0.92, 0.94, 0.97, 0.75), 0.35), 1.0, CrashSite.LEAN.x)


func _run_hatch(lt: float, _u: float, _delta: float) -> void:
	var patch: Node3D = _lumi()
	var at: float = _p("out_at", 3.4)
	var model: PatchModel = _model()
	if lt < _p("show_at", 2.2):
		patch.visible = false
		return
	# In the dark of the cabin first: two eyes come on. Then out, slowly, low on power.
	patch.visible = true
	if model and not bool(_acc.get("woke", false)):
		model.sleeping = true
		model.core_glow = 0.15
	var k: float = eased("inout", (lt - at) / _p("out_dur", 2.6))
	var p: Vector3 = _pod_pt(Vector3(0, 0.36, -0.2)).lerp(_door_spot(), k)
	p.y += sin(k * PI) * 0.05
	_put_lumi(p, _door())


func _cue_eyes_open() -> void:
	# A quick, natural flutter: open, shut, open a little longer, shut, then awake.
	var model: PatchModel = _model()
	if model == null:
		return
	_acc["woke"] = true
	var tw := create_tween()
	for step: Array in [[false, 0.07], [true, 0.16], [false, 0.1], [true, 0.12]]:
		tw.tween_callback(func() -> void:
			model.sleeping = bool(step[0])
			if not step[0]:
				_snd("blip", 0.65 + float(step[1]), -9.0))
		tw.tween_interval(float(step[1]))
	tw.tween_callback(func() -> void:
		model.sleeping = false
		model.set_happy(0.3)
		model.core_glow = 0.25
		_snd("servo", 0.8, -8.0))


func _cue_battery() -> void:
	_flicker = 1.0
	_battery.create_tween().tween_property(_battery, "modulate:a", 1.0, 0.5)
	_snd("beep", 0.5, -10.0)


func _in_look() -> void:
	_world_state(3)
	var model: PatchModel = _model()
	if model:
		model.look_toward(null)
		model.set_happy(0.3)


func _cue_look_left() -> void:
	var model: PatchModel = _model()
	if model:
		model.sleeping = false
		model.look_toward(_w(_pod_pt(Vector3(-5, 0.6, -4.3))))


func _cue_look_right() -> void:
	var model: PatchModel = _model()
	if model:
		model.look_toward(_w(_pod_pt(Vector3(5, 0.6, -4.3))))


func _cue_look_far() -> void:
	var model: PatchModel = _model()
	if model:
		model.look_toward(_w(_pod_pt(Vector3(0, 2.5, -40.0))))
		model.set_happy(0.2)


func _in_voice() -> void:
	_world_state(3)
	var model: PatchModel = _model()
	if model:
		model.look_toward(_w(_pod_pt(Vector3(0, 2.5, -40.0))))
		model.set_happy(0.2)


## A voice out of the static: Lumi's head comes up to the sky it fell from.
func _cue_hear() -> void:
	var model: PatchModel = _model()
	_snd("buzz", 1.5, -14.0)  # static, then her voice
	if model:
		model.look_toward(_w(_pod_pt(Vector3(-2.0, 30.0, -8.0))))
		model.set_happy(0.75)
		model.flash()
		model.shudder(0.2)


func _run_voice(lt: float, _u: float, _delta: float) -> void:
	# It rises a little toward the voice, as if that could bring it closer.
	var k: float = eased("inout", (lt - 0.6) / 2.2)
	_put_lumi(_door_spot() + Vector3(0, 0.14 * k, 0), _door())


func _in_bench() -> void:
	_world_state(3)
	var model: PatchModel = _model()
	if model:
		model.look_toward(_w(_pod_pt(Vector3(-2.0, 30.0, -8.0))))
		model.set_happy(0.6)


func _cue_look_station() -> void:
	var model: PatchModel = _model()
	if model:
		model.look_toward(_w(_yard(str(_table.get("end_face", "bench"))) + Vector3(0, 1, 0)))


func _run_bench(lt: float, _u: float, _delta: float) -> void:
	# Its first move on Verdance: out from the door, turning toward the old workbench WREN speaks
	# of, to the spot where the game will start.
	var k: float = eased("inout", (lt - _p("go_at", 3.0)) / _p("go_dur", 3.2))
	var a0: float = atan2(-_door().x, -_door().z)
	var a1: float = atan2(-_end_facing().x, -_end_facing().z)
	var a: float = lerp_angle(a0, a1, eased("inout", (lt - _p("go_at", 3.0) + 0.4) / _p("go_dur", 3.2)))
	var p: Vector3 = _door_spot().lerp(_end_spot(), k)
	p.y += sin(k * PI) * 0.04
	_put_lumi(p, Vector3(-sin(a), 0, -cos(a)))
	var model: PatchModel = _model()
	var gone: float = lt - float(_acc.get("gone", INF))
	if model and gone >= 0.0:
		# The voice is cut off: the head sinks, and after a breath comes up again, to the bench.
		model.look_toward(_w(_end_spot() + _end_facing() * 1.2 + Vector3(0, -0.4, 0)) if gone < 1.3 else null)
		model.set_happy(0.2 if gone < 1.3 else 0.5)
	elif model and k > 0.9:
		model.look_toward(null)


func _in_alone() -> void:
	_world_state(4)
	var model: PatchModel = _model()
	if model:
		model.look_toward(null)
		model.set_happy(0.5)


## The signal dies in the middle of her sentence.
func _cue_relay_drop() -> void:
	_acc["gone"] = _lt
	_snd("buzz", 0.7, -10.0)


## Where Lumi stops outside the door after drifting out.
func _door_spot() -> Vector3:
	return _pod_pt(_v3(_table.get("door_spot"), Vector3(0, 0.05, -2.3)))


## Where the game starts: Lumi stands here after the film, watched or skipped.
func _end_spot() -> Vector3:
	return _pod_pt(_v3(_table.get("end_spot"), Vector3(1.5, 0.05, -4.2)))


## The way Lumi faces there: toward the yard anchor "end_face" (the old workbench, its first job).
func _end_facing() -> Vector3:
	var f: Vector3 = _yard(str(_table.get("end_face", "bench"))) - _end_spot()
	f.y = 0.0
	return f.normalized() if f.length() > 0.5 else _door()


func _in_handoff() -> void:
	_world_state(4)
	# Lumi stands where the game starts and the game camera takes its place behind it; the film's
	# camera then travels to exactly that view, so the hand-over has no cut and no jump.
	_stand_lumi()
	_handoff_done = true


func _run_handoff(lt: float, _u: float, _delta: float) -> void:
	var d: float = float(_shots[_si]["d"])
	var k: float = eased("inout", (lt - (d - _p("bars_out", 1.1))) / _p("bars_out", 1.1))
	_set_bars(1.0 - k)
	_battery.modulate.a = 1.0 - k
	_skip.modulate.a = 1.0 - k


## Lumi on the game's start spot by the pod, facing the old workbench, the game camera behind it.
func _stand_lumi() -> void:
	var patch: Node3D = _lumi()
	patch.visible = true
	_put_lumi(_end_spot(), _end_facing())
	if patch == _actor:
		return  # a rewatch never moves the real Lumi or the game camera
	if site_xf != Transform3D.IDENTITY and patch.has_method("place_on_sphere"):  # [orbE] stand on the globe
		patch.call("place_on_sphere", patch.global_position, site_xf.basis.orthonormalized() * _end_facing())
	if world.get("cam") != null and world.cam.has_method("hand_off"):
		world.cam.hand_off(patch.rotation.y)
	elif cam_reset_fn.is_valid():  # [orbE] the globe's SphereCam behind Lumi
		cam_reset_fn.call()


# --- World effects ---------------------------------------------------------------------------

static func _soft_mat() -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	# Plain billboards with keep_scale, as art/vfx.gd does: particle billboards drew not-yet-born
	# particles (zero scale) as full squares.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Soft billboard particles: born small and clear, swelling, fading out (never cut off).
func _puffs(amount: int, life: float, col: Color, size: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _soft_mat()
	p.mesh = q
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size * 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(0.25, 0.8))
	sc.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.12, col)
	ramp.add_point(0.5, Color(col.r, col.g, col.b, col.a * 0.6))
	p.color_ramp = ramp
	p.gravity = -_up() * 0.6
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_fx_nodes.append(p)
	return p


## The smoke the burning pod leaves across the sky.
func _ensure_trail() -> void:
	if _trail and is_instance_valid(_trail):
		return
	_trail = _puffs(190, 3.8, Color(0.3, 0.27, 0.25, 0.62), 6.0, false)
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_trail.emission_box_extents = Vector3(0.5, 0.5, 0.5)
	_trail.direction = Vector3.UP
	_trail.spread = 180.0
	_trail.initial_velocity_min = 0.3
	_trail.initial_velocity_max = 1.4
	_trail.gravity = _up() * 0.4
	_trail.emitting = false


## The hit: a flash, a ring of dust racing out along the ground, a column thrown up, flying bits.
func _impact_fx() -> void:
	var at: Vector3 = _w(POD_POS)
	var up: Vector3 = _up()
	var frame := Basis(site_xf.basis.orthonormalized())
	var ring: CPUParticles3D = _puffs(64, 3.8, Color(0.55, 0.46, 0.37, 0.78), 4.4, true)
	ring.global_transform = Transform3D(frame, at + up * 0.5)
	ring.direction = Vector3(1, 0, 0)
	ring.spread = 180.0
	ring.flatness = 0.92
	ring.initial_velocity_min = 5.0
	ring.initial_velocity_max = 11.0
	ring.damping_min = 3.2
	ring.damping_max = 4.4
	ring.gravity = up * 0.25
	ring.emitting = true
	var column: CPUParticles3D = _puffs(34, 4.6, Color(0.46, 0.39, 0.32, 0.8), 4.6, true)
	column.global_transform = Transform3D(frame, at + up * 0.8)
	column.direction = Vector3(0, 1, 0)
	column.spread = 32.0
	column.initial_velocity_min = 4.0
	column.initial_velocity_max = 12.0
	column.damping_min = 2.2
	column.damping_max = 3.2
	column.gravity = -up * 0.4
	column.emitting = true
	var flash := MeshInstance3D.new()
	flash.mesh = ProcMesh.sphere(1.0, 20, 12)
	var fm: ShaderMaterial = SpaceStage.glow_mat(Color(1.0, 0.82, 0.55), 2.6, 0.95)
	flash.material_override = fm
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	_fx_nodes.append(flash)
	flash.global_position = at + up * 1.0
	flash.scale = Vector3.ONE * 1.5
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 9.0
	light.omni_range = 26.0
	flash.add_child(light)
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 4.5, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(fm, "shader_parameter/strength", 0.0, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_property(light, "light_energy", 0.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	for i: int in 5:
		var a: float = TAU * i / 5.0
		Vfx.burst("bits", at + up * 0.5 + frame * Vector3(cos(a), 0, sin(a)) * 1.2, Color(0.4, 0.38, 0.34), 1.0)
	Vfx.burst("dust", at + up * 0.4, Color(0.6, 0.55, 0.48, 0.8), 1.6)


func _clear_fx() -> void:
	for n: Node in _fx_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_fx_nodes.clear()
	_trail = null


# --- Overlay ------------------------------------------------------------------------------

## The off-world stage, built but not drawn yet (its sets load a few plant models: done behind
## the loading screen, not in the film's first frame).
func _prebuild_stage() -> void:
	if _stage and is_instance_valid(_stage):
		return
	var t0: int = Time.get_ticks_usec()
	_stage_layer = CanvasLayer.new()
	_stage_layer.layer = 2
	_stage_layer.visible = false
	add_child(_stage_layer)
	_stage = SpaceStage.new()
	_stage_layer.add_child(_stage)
	_stage.set_live(false)
	if DevHooks.has("intro"):
		print("[intro] stage built in %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))


func _open_stage() -> void:
	if _stage and is_instance_valid(_stage) and _stage_layer.visible:
		return
	_prebuild_stage()
	_stage_layer.visible = true
	_stage.set_live(true)
	# The game world isn't on screen while the stage is: skip rendering it.
	get_viewport().disable_3d = true


func _close_stage() -> void:
	get_viewport().disable_3d = false
	if _stage_layer and is_instance_valid(_stage_layer):
		_stage_layer.queue_free()
	_stage_layer = null
	_stage = null
	_hold_tray = false


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_layer.add_child(root)
	# The fade lies under the bars: a fade to white is the picture going white, not the letterbox.
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		_bars.append(bar)
	_set_bars(1.0)
	# The title sits in the upper third, clear of the ark and the subtitle line.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 104
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_title = UITheme.label("", 64, Color(1, 1, 1))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 0)
	_title.modulate.a = 0.0
	box.add_child(_title)
	_title_sub = UITheme.label("", 16, Color(0.55, 1.0, 0.72))  # room for a tagline under the title; empty for now
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_sub.modulate.a = 0.0
	box.add_child(_title_sub)
	_skip = UITheme.label("", 12, Color(1, 1, 1, 0.45))
	Settings.bind_text(_skip, func() -> String: return StoryPause.hint())  # [deck] [intro2]
	_pauser = StoryPause.new()
	_layer.add_child(_pauser)
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -260
	_skip.offset_top = 24
	root.add_child(_skip)
	_build_battery(root)


## Letterbox bars: k = 1 fully in, 0 slid away.
func _set_bars(k: float) -> void:
	var h: float = float(_table.get("letterbox_px", 70.0)) * clampf(k, 0.0, 1.0)
	if _bars.size() >= 2:
		_bars[0].offset_bottom = h
		_bars[1].offset_top = -h


## Low-battery readout (top left, under the letterbox): five cells, one red, and 4%.
func _build_battery(root: Control) -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(48, 96)
	box.add_theme_constant_override("separation", 4)
	box.modulate.a = 0.0
	root.add_child(box)
	_battery = box
	# [v11film] The picture alone (a low battery reads without words): it carried two lines of
	# jargon nobody had been taught yet ("BLOOM CORE", "GREEN LIGHT · NONE DETECTED").
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
		skip()


## Skip the rest of the film (also what Esc does). Safe at any moment.
func skip() -> void:
	if not running or _skipped:
		return
	if _pauser:
		_pauser.set_paused(false)
	_skipped = true
	_finish()


# --- The end: one world, however the film ended ----------------------------------------------

func _finish() -> void:
	if not running:
		return
	running = false
	ending = true
	_film = false
	_hold_tray = false
	var sd: Variant = world.get("sky_director") if world else null
	if sd is SkyDirector:  # [v10guide] the game's own sky, watched or skipped
		(sd as SkyDirector).film_dust = 0.0
	_flicker = 0.0
	if not _replay:
		GameState.flags["intro_done"] = true
	_tunes_land(1.2 if _skipped else 4.0)  # [tunes]
	if _skipped:
		_subs().clear()
		_title.modulate.a = 0.0
		_title_sub.modulate.a = 0.0
		_skip.modulate.a = 0.0
		_battery.modulate.a = 0.0
	_report_subtitles()
	# Watched to the end: the last shot already stands on the game's own view. Nothing to hide.
	if _handoff_done and not _skipped and not _replay:
		_apply_end_state()
		_fade.color.a = 0.0
		_done()
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color", Color(0, 0, 0, 1), 0.4)
	tw.tween_callback(_apply_end_state)
	tw.tween_property(_fade, "color", Color(0, 0, 0, 0), 0.8)
	tw.tween_callback(_done)


## Everything the game needs after the film, the same whether it was watched or skipped: the pod
## in its crash site with the hatch open, Lumi awake on the start spot facing out of the door, the
## game camera behind it, HUD and controls back, the film's own things gone.
func _apply_end_state() -> void:
	ending = false
	var patch: Node3D = world.patch
	var was_replay: bool = _replay
	_close_stage()
	_clear_fx()
	if _cam:
		_cam.queue_free()
		_cam = null
	for b: ColorRect in _bars:
		b.visible = false
	_title.visible = false
	_title_sub.visible = false
	_skip.visible = false
	_battery.visible = false
	if was_replay:
		# A rewatch: everything back as it was. The real Lumi, pod, camera and HUD were never moved.
		if _prev_cam and is_instance_valid(_prev_cam):
			_prev_cam.current = true
		if world.get("music") != null:
			world.music.set_cinematic(bool(_replay_keep.get("cinematic", false)))
		var td: Node = Tunes.director()
		if td:
			td.call("set_paused", false)
		Tunes.set_context(str(_replay_keep.get("tunes", "play")))
		_end_replay()
		print("[intro] rewatch over after %.1fs (skipped=%s): the world is as it was" % [_t, _skipped])
		return
	var model: PatchModel = _model()
	if not _placed:
		_placed = true
		place_pod()
	if _site and is_instance_valid(_site):
		_site.global_transform = _site_rest
		_plume_rise(1.0)
	if _pod and is_instance_valid(_pod):
		EscapePod.set_open(_pod, true, CrashSite.LEAN.x)
	_stand_lumi()
	patch.visible = true
	_hold_lumi(false)
	if model:
		model.sleeping = false
		model.set_happy(0.6)
		model.look_toward(null)
		model.core_glow = CoreCharge.glow_for_flags()
	var modal: bool = world.has_method("any_modal_open") and world.any_modal_open()
	if _prev_cam and is_instance_valid(_prev_cam) and not modal:
		_prev_cam.current = true
	if world.get("hud") != null and not modal:
		world.hud.visible = true
	if world.get("music") != null:
		world.music.set_cinematic(false)
	var td2: Node = Tunes.director()  # [tunes] back to the background shuffle
	if td2:
		td2.call("set_paused", false)
	Tunes.set_context("play")
	if not modal:
		_set_player_enabled(true)
	print("[intro] finished after %.1fs (skipped=%s, input restored=%s)" % [_t, _skipped, not modal])
	if DevHooks.has("intro"):
		print("[intro] end state: %s" % JSON.stringify(end_state()))


func _done() -> void:
	if _layer and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_bars.clear()
	_battery_cells.clear()
	if _replay_keep.is_empty():
		finished.emit()
	else:  # a rewatch: nothing in the game should start because of it
		_replay_keep.clear()
		replay_finished.emit()
	if DevHooks.has("intro-quit") and not DevHooks.has("rewatch-check"):  # dev: tools/check_intro.sh
		get_tree().quit()


## What the film left behind, for tests: it must not depend on when (or whether) it was skipped.
func end_state() -> Dictionary:
	var patch: Node3D = world.patch
	var model: PatchModel = _model()
	var at: Vector3 = _v(patch.global_position)
	var fwd: Vector3 = site_xf.basis.orthonormalized().inverse() * (-patch.global_basis.z)
	var hatch: Node3D = _pod.get_node_or_null("Hatch") as Node3D if _pod and is_instance_valid(_pod) else null
	var cam: Camera3D = get_viewport().get_camera_3d()
	return {
		"lumi": [snappedf(at.x, 0.05), snappedf(at.y, 0.05), snappedf(at.z, 0.05)],
		"facing": [snappedf(fwd.x, 0.05), snappedf(fwd.z, 0.05)],
		"lumi_visible": patch.visible,
		"eyes_open": model != null and not model.sleeping,
		"pod_placed": _pod != null and is_instance_valid(_pod) and _site != null and is_instance_valid(_site),
		"hatch_open": hatch != null and hatch.rotation.x < -1.0,
		"hud": world.get("hud") != null and bool(world.hud.visible),
		"game_camera": cam != null and cam == _prev_cam,
		"camera_to_lumi": snappedf(cam.global_position.distance_to(patch.global_position), 0.1) if cam else -1.0,
		"intro_done": bool(GameState.flags.get("intro_done", false)),
		"tunes": Tunes.context(),
		"busy": busy(),
	}


## A cinematic owns Lumi: no idle fidgets, no dozing, eyes and gaze left to the film (player/patch.gd).
func _hold_lumi(on: bool) -> void:
	if world.patch.get("cine_hold") != null:
		world.patch.set("cine_hold", on)


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
	var patch: Node = world.patch
	if patch.get("input") is PlayerInput:
		(patch.input as PlayerInput).enabled = on
	if world.get("cam") != null:
		world.cam.input_enabled = on
	elif world.get("orbit") != null and world.get("orbit").has_method("set_input"):  # [orbE] the globe
		world.get("orbit").call("set_input", on)
