class_name TitleCinematic
extends Node
## [pod2] The title screen's slow cinematic behind the menu (owner): the camera starts high over the
## junk-covered district, drifts over the crash site (the smoking, sparking pod), then glides down to
## Lumi, who cleans nearby piece by piece (beam, the piece lifts and vanishes, a little hop). Then it
## rises again and the loop starts over; cleaned pieces quietly come back while the camera is high.
## main_menu.gd builds the district; this adds the crash site and the cleaning, and drives the
## camera and Lumi. Low preset: fewer pieces. Dev: --title-t=SECONDS starts the loop at a time,
## --title-hold keeps the camera there (screenshots).

const LOOP: float = 72.0
const POD_AT := Vector3(-8.5, 0.0, 10.0)
## Camera keys: [time, position, look-at]. The close orbit round Lumi runs between CLOSE_A and CLOSE_B.
const CLOSE_A: float = 34.0
const CLOSE_B: float = 62.0

var menu: Node3D
var cam: Camera3D
var pivot: Node3D
var model: PatchModel

var _t: float = 0.0
var _site: CrashSite
var _pieces: Array[Dictionary] = []
var _target: int = -1
var _beam_k: float = 0.0
var _hop: float = 0.0
var _home := Vector3.ZERO


func setup(menu_: Node3D, cam_: Camera3D, pivot_: Node3D, model_: PatchModel) -> void:
	menu = menu_
	cam = cam_
	pivot = pivot_
	model = model_
	_t = DevHooks.get_f("title-t", 0.0)
	# The crash site, damaged (smoke, sparks), its door open toward the clearing.
	var pod: Node3D = EscapePod.build()
	_site = CrashSite.attach(menu, pod, POD_AT, -2.3)
	_site.set_stage(0)
	EscapePod.set_open(pod, true, CrashSite.LEAN.x)
	# Pieces for Lumi to clean, in a loose ring round the clearing.
	var ids: Array[String] = ["can_rusted", "plastic_bottle_gallon", "trashbag", "cardboard_box_01", "old_tyre", "can_rusted", "plastic_bottle_gallon"]
	var n: int = 4 if Settings.quality <= 0 else ids.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in n:
		if not AssetLib.has_model(ids[i]):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh(ids[i])
		var a: float = -0.9 + 1.8 * float(i) / maxf(n - 1, 1) + rng.randf_range(-0.1, 0.1)
		var r: float = rng.randf_range(1.4, 2.2)
		var lie: bool = rng.randf() < 0.5 and ids[i] != "old_tyre"
		mi.position = Vector3(sin(a) * r, 0.03 if lie else 0.0, -cos(a) * r)
		mi.rotation = Vector3(PI * 0.5 if lie else 0.0, rng.randf() * TAU, 0.0)
		menu.add_child(mi)
		_pieces.append({"node": mi, "home": mi.transform, "gone": false})
	_home = pivot.position


func _key(t: float) -> Array:
	# High over the district -> over the crash site -> down toward Lumi.
	var keys: Array = [
		[0.0, Vector3(26, 24, -28), Vector3(-2, 0, 6)],
		[12.0, Vector3(6, 14, -14), POD_AT + Vector3(0, 0.5, 0)],
		[22.0, POD_AT + Vector3(5.5, 3.2, -5.0), POD_AT + Vector3(0, 1.2, 0)],
		[30.0, Vector3(3.0, 2.6, -6.0), Vector3(-1.5, 0.9, 1.0)],
		[CLOSE_A, Vector3(1.6, 1.2, -3.4), Vector3(0, 0.62, 0)],
	]
	for k: int in keys.size() - 1:
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var u: float = (t - float(a[0])) / (float(b[0]) - float(a[0]))
			u = u * u * (3.0 - 2.0 * u)
			return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u)]
	return [keys[-1][1], keys[-1][2]]


## [v7look] The title is one slow drifting shot (owner: the old high passes put huge untextured
## skyline blocks right at the lens and the pod far below): low over the clearing, Lumi cleaning in
## the right half, the smoking crash site behind him, the trashed district and the skyline beyond,
## into the low sun. A gentle sway and push keep it alive; nothing cuts.
const DRIFT_FROM := Vector3(4.0, 2.1, -5.0)  # the pod and Lumi land right of centre, clear of the menu
const DRIFT_LOOK := Vector3(-5.0, 1.4, 12.0)


func _drift(t: float) -> Array:
	var sway: float = sin(t * TAU / LOOP)
	var push: float = 0.5 - 0.5 * cos(t * TAU / LOOP)
	var pos: Vector3 = DRIFT_FROM + Vector3(sway * 0.9, 0.25 * sin(t * 0.11), push * 0.9)
	return [pos, DRIFT_LOOK + Vector3(sway * 0.9, 0.0, 0.0)]


func step(delta: float) -> void:
	if not DevHooks.has("title-hold"):  # screenshots hold the camera at --title-t
		_t = fmod(_t + delta, LOOP)
	var pos: Vector3
	var look: Vector3
	var hoff: float = 0.0
	if not DevHooks.has("title-old"):
		var d: Array = _drift(_t)
		cam.position = d[0]
		cam.look_at(d[1], Vector3.UP)
		cam.h_offset = 0.0
		_clean(delta)
		return
	if _t < CLOSE_A:
		var kk: Array = _key(_t)
		pos = kk[0]
		look = kk[1]
		hoff = -0.75 * smoothstep(26.0, CLOSE_A, _t)
	elif _t < CLOSE_B:
		# Close: a slow swing across the front of Lumi (the old title framing), following it.
		var s: float = _t - CLOSE_A
		var a: float = 0.42 - s * 0.012
		var c: Vector3 = Vector3(pivot.position.x, 0.62, pivot.position.z)
		pos = c + Vector3(sin(a) * 3.5, 0.55 + sin(_t * 0.21) * 0.08, -cos(a) * 3.5)
		look = c
		hoff = -0.75
	else:
		# Rise back up and out to the opening frame.
		var u: float = (_t - CLOSE_B) / (LOOP - CLOSE_B)
		u = u * u * (3.0 - 2.0 * u)
		var c2: Vector3 = Vector3(pivot.position.x, 0.62, pivot.position.z)
		var from: Vector3 = c2 + Vector3(sin(0.42 - (CLOSE_B - CLOSE_A) * 0.012) * 3.5, 0.55, -cos(0.42 - (CLOSE_B - CLOSE_A) * 0.012) * 3.5)
		var to: Array = _key(0.0)
		pos = from.lerp(to[0], u)
		look = c2.lerp(to[1], u)
		hoff = lerpf(-0.75, 0.0, u)
	cam.position = pos
	cam.look_at(look, Vector3.UP)
	cam.h_offset = hoff
	_clean(delta)


## Lumi's little cleaning loop: float to a piece, beam it up, hop, next. Pieces respawn while the
## camera is high (start of the loop).
func _clean(delta: float) -> void:
	if _t < 2.0:
		for p: Dictionary in _pieces:
			if p["gone"]:
				p["gone"] = false
				var n: Node3D = p["node"]
				n.transform = p["home"]
				n.visible = true
	_hop = maxf(0.0, _hop - delta * 2.5)
	var bob: float = sin(_t * 1.3) * 0.06 + sin(_hop * PI) * 0.18
	if _t < (26.0 if DevHooks.has("title-old") else 4.0):
		# Camera still high (the old path): Lumi idles in the clearing.
		pivot.position = pivot.position.lerp(_home + Vector3(0, 0.32 + bob, 0), minf(1.0, delta * 1.5))
		model.beam_at(null)
		return
	if _target < 0:
		for i: int in _pieces.size():
			if not _pieces[i]["gone"]:
				_target = i
				_beam_k = 0.0
				break
	if _target < 0:
		# All clean: drift home, happy.
		pivot.position = pivot.position.lerp(_home + Vector3(0, 0.32 + bob, 0), minf(1.0, delta * 1.5))
		model.beam_at(null)
		model.look_toward(cam.global_position)
		return
	var p: Dictionary = _pieces[_target]
	var node: Node3D = p["node"]
	var home: Transform3D = p["home"]
	var spot: Vector3 = home.origin * 0.55  # hover between the clearing and the piece
	pivot.position = pivot.position.lerp(Vector3(spot.x, 0.32 + bob, spot.z), minf(1.0, delta * 1.2))
	var flat := Vector3(home.origin.x - pivot.position.x, 0, home.origin.z - pivot.position.z)
	if flat.length() > 0.05:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(-flat.x, -flat.z), minf(1.0, delta * 3.0))
	model.look_toward(node.global_position)
	if pivot.position.distance_to(Vector3(spot.x, pivot.position.y, spot.z)) < 0.15:
		_beam_k += delta / 2.2
		model.beam_at(node.global_position)
		var to: Vector3 = model.claw_point()
		node.global_position = home.origin.lerp(to, smoothstep(0.15, 1.0, _beam_k)) + Vector3(0, sin(_beam_k * PI) * 0.25, 0)
		node.scale = Vector3.ONE * clampf(1.0 - smoothstep(0.55, 1.0, _beam_k), 0.01, 1.0)
		if _beam_k >= 1.0:
			node.visible = false
			p["gone"] = true
			_target = -1
			_hop = 1.0
			model.beam_at(null)
			model.hopper_pulse(0.9)
			model.flash()
	else:
		model.beam_at(null)
