class_name RobotKit
extends Node3D
## [drones] Builder part meshes fitted onto a RobotVisual (procedural, same toolkit and style as
## the base models). fit() measures the built body (its bounding box without wheels, arm and head)
## and places the parts around it, so every part works on every body type and Mk look:
##   Chassis  side rails / cargo plates / sealed covers / Maker fairings
##   Head     big lens / visor bar / periscope / chatter dome / Maker gem lens (on the head node)
##   Mobility treads / quad rotor / walker legs / hover skirt / Maker pods (wheels are hidden)
##   Tool     wide scoop / sieve / long forks / tow hook / seed drill / mist fan / jet (at the tool tip)
##   Topper   antenna, top hat, flag, bobble plant, cone, propeller cap, clover, Maker crest
## Mk I/II parts are painted metal; Mk III/IV parts are glossy shells with one thin light line.
## The kit also owns the visual root offset (lift for rotors/legs/skirts plus RobotPersona's
## idle offsets) and animates its moving bits.

const NODE_NAME: String = "BuilderKit"

var visual: RobotVisual
var lift: float = 0.0
## Written by RobotPersona each frame: extra offset / tilt of the whole model.
var anim_dy: float = 0.0
var anim_rot := Vector3.ZERO
## Speed used when the kit is not on a Robot (builder preview).
var preview_speed: float = 0.0
var working: bool = false

var _spin: Array[Node3D] = []      # rotor blades / propeller / drill: spin about local Y
var _legs: Array[Node3D] = []      # leg pivots (meta "ph", "side")
var _bobble: Array[Node3D] = []    # spring toppers
var _flags: Array[Node3D] = []     # fluttering flags
var _rollers: Array[Node3D] = []   # tread sprockets
var _float: Array[Node3D] = []     # gentle bob (Maker gem, clover, crest)
var _blink: Array[StandardMaterial3D] = []
var _t: float = 0.0
var _sleek: bool = false
var _role: String = "clean"
var _head_id: String = ""

# Body bounds (in _body space).
var _lo := Vector3(-0.3, 0.1, -0.35)
var _hi := Vector3(0.3, 0.7, 0.35)


## Builds (or rebuilds) the kit for a visual. Safe to call on an empty build (keeps the root node
## so personality offsets still work).
static func fit(v: RobotVisual, build: Dictionary, role: String) -> RobotKit:
	if v == null or v._body == null:
		return null
	var old: Node = v._body.get_node_or_null(NODE_NAME)
	if old:
		v._body.remove_child(old)
		old.queue_free()
	var k := RobotKit.new()
	k.name = NODE_NAME
	k.visual = v
	k._role = role
	k._sleek = v.look in ["modern", "hover"]
	v._body.add_child(k)
	v.set_meta("kit", k)
	k._measure()
	for slot: String in RobotBuilder.SLOTS:
		var id: String = str(build.get(slot, ""))
		if id != "":
			k._add(slot, id)
	return k


static func of(v: RobotVisual) -> RobotKit:
	if v == null or not v.has_meta("kit"):
		return null
	var k: Variant = v.get_meta("kit")
	return k as RobotKit if is_instance_valid(k) else null


# --- Measuring -----------------------------------------------------------------------------

func _excluded(n: Node) -> bool:
	var stop: Array = [visual._arm, visual._head, visual._emitter]
	stop.append_array(visual._wheels)
	stop.append_array(visual._rings)
	stop.append_array(visual._floaters)
	var p: Node = n
	while p != null and p != visual._body:
		if p in stop:
			return true
		p = p.get_parent()
	return false


func _rel(n: Node3D) -> Transform3D:
	var xf: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p != visual._body and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _measure() -> void:
	var have: bool = false
	var lo := Vector3.ONE * 1e9
	var hi := -Vector3.ONE * 1e9
	for mi: Node in visual._body.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or _excluded(m) or m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var bb: AABB = _rel(m) * m.mesh.get_aabb()
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
		have = true
	if have:
		_lo = lo
		_hi = hi


func _wheel_info() -> Dictionary:
	# Track geometry from the wheels: side x, front/back z, radius.
	var xs: float = 0.0
	var zmin: float = 1e9
	var zmax: float = -1e9
	var r: float = 0.0
	for w: Node3D in visual._wheels:
		xs = maxf(xs, absf(w.position.x))
		zmin = minf(zmin, w.position.z)
		zmax = maxf(zmax, w.position.z)
		r = maxf(r, float(w.get_meta("r", 0.12)))
	if visual._wheels.is_empty():
		return {}
	return {"x": xs, "z0": zmin, "z1": zmax, "r": r}


func _head_anchor() -> Dictionary:
	# Head node + its rough size (in head space), else a spot on the body front-top.
	var h: Node3D = visual._head
	if h != null:
		var lo := Vector3.ONE * 1e9
		var hi := -Vector3.ONE * 1e9
		for mi: Node in h.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			if m.mesh == null:
				continue
			var xf: Transform3D = m.transform
			var p: Node = m.get_parent()
			while p != null and p != h and p is Node3D:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var bb: AABB = xf * m.mesh.get_aabb()
			lo = lo.min(bb.position)
			hi = hi.max(bb.end)
		if lo.x < 1e8:
			return {"node": h, "lo": lo, "hi": hi}
	var eye: Node3D = visual._eye
	var c: Vector3 = Vector3(0, _hi.y - 0.08, _lo.z + 0.05)
	if eye != null and eye.get_parent() == visual._body:
		c = eye.position + Vector3(0, 0.02, 0.04)
	var n := Node3D.new()
	n.position = c
	add_child(n)
	return {"node": n, "lo": Vector3(-0.12, -0.06, -0.08), "hi": Vector3(0.12, 0.06, 0.08)}


# --- Materials -----------------------------------------------------------------------------

func _shell(c: Color) -> Material:
	if _sleek:
		return visual._gloss(c, 0.3, 0.0, 0.6)
	if visual.look == "restored":
		return visual._worn(c, 0.95, 0.2, 0.3, 0.05)
	return visual._worn(c, 0.75, 0.55, 0.45)


func _white() -> Material:
	return _shell(Color(0.95, 0.94, 0.92) if _sleek else Color(0.86, 0.84, 0.78))


func _dark() -> Material:
	return visual._gloss(Color(0.07, 0.08, 0.09), 0.35, 0.4, 0.3) if _sleek else Mats.metal("dark_steel")


func _line(c: Color) -> StandardMaterial3D:
	# One thin light line per part: brighter on the sleek tiers, a dim lamp on salvage.
	return visual._glow(c, 2.2 if _sleek else 1.1)


func _accent() -> Color:
	return RobotBuilder.CREW_COLORS.get(_role, Color(1.0, 0.7, 0.26))


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	return visual._mi(parent, mesh, mat, pos, rot, scl)


func _node(parent: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	return visual._node(parent, pos, rot)


func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, segs: int = 8) -> MeshInstance3D:
	return visual._rod(parent, a, b, r, mat, segs)


func _rbox(size: Vector3, r: float, seg: int = 2) -> ArrayMesh:
	return RobotVisual._rbox(size, r, seg)


# --- Parts ---------------------------------------------------------------------------------

func _add(slot: String, id: String) -> void:
	match slot:
		"chassis": _chassis(id)
		"head": _head_part(id)
		"mobility": _mobility(id)
		"tool": _tool(id)
		"topper": _topper(id)


func _chassis(id: String) -> void:
	var w: float = maxf(absf(_lo.x), absf(_hi.x))
	var cz: float = (_lo.z + _hi.z) * 0.5
	var lz: float = (_hi.z - _lo.z)
	var my: float = lerpf(_lo.y, _hi.y, 0.45)
	var h: float = _hi.y - _lo.y
	match id:
		"light_frame":
			# Twin slim side rails on standoffs and a front bumper hoop.
			var tube: Material = _white() if _sleek else Mats.metal("chrome")
			for sx: float in [-1.0, 1.0]:
				var x: float = sx * (w + 0.045)
				_rod(self, Vector3(x, my, cz - lz * 0.42), Vector3(x, my, cz + lz * 0.42), 0.014, tube, 10)
				_rod(self, Vector3(x, my + h * 0.22, cz - lz * 0.36), Vector3(x, my + h * 0.22, cz + lz * 0.3), 0.011, tube, 10)
				for z: float in [-0.34, 0.0, 0.34]:
					_rod(self, Vector3(sx * w, my + 0.02, cz + lz * z), Vector3(x, my, cz + lz * z), 0.008, _dark(), 6)
					_rod(self, Vector3(x, my, cz + lz * z * 0.9), Vector3(x, my + h * 0.22, cz + lz * z * 0.9), 0.008, tube, 6)
				_mi(self, ProcMesh.box(Vector3(0.006, 0.012, lz * 0.6)), _line(_accent()), Vector3(x + sx * 0.012, my, cz))
			_rod(self, Vector3(-w - 0.045, my, cz - lz * 0.42), Vector3(w + 0.045, my, cz - lz * 0.42), 0.014, tube, 10)
		"cargo_hull":
			# Thick side plates with bolted ribs, a rear cargo rack.
			var plate: Material = _shell(Color(0.55, 0.58, 0.6) if not _sleek else Color(0.82, 0.83, 0.84))
			for sx: float in [-1.0, 1.0]:
				var x: float = sx * (w + 0.03)
				_mi(self, _rbox(Vector3(0.05, h * 0.42, lz * 0.82), 0.02, 2), plate, Vector3(x, my, cz))
				for z: float in [-0.3, 0.0, 0.3]:
					_mi(self, _rbox(Vector3(0.062, h * 0.36, 0.035), 0.01, 1), _dark(), Vector3(x, my, cz + lz * z))
				_mi(self, ProcMesh.box(Vector3(0.006, 0.01, lz * 0.7)), _line(_accent()), Vector3(x + sx * 0.03, my + h * 0.16, cz))
			var rz: float = _hi.z + 0.04
			_mi(self, _rbox(Vector3(w * 1.7, 0.03, 0.12), 0.01, 1), _dark(), Vector3(0, my - h * 0.05, rz))
			for sx: float in [-0.6, 0.0, 0.6]:
				_rod(self, Vector3(sx * w, my - h * 0.05, rz + 0.05), Vector3(sx * w, my + h * 0.2, rz + 0.05), 0.012, _dark(), 6)
			_rod(self, Vector3(-0.6 * w, my + h * 0.2, rz + 0.05), Vector3(0.6 * w, my + h * 0.2, rz + 0.05), 0.012, _dark(), 6)
		"sealed_shell":
			# Smooth rounded side covers over the wheel wells with one seam line, a front cowl.
			var cover: Material = _shell(Color(0.3, 0.55, 0.62) if not _sleek else Color(0.93, 0.93, 0.91))
			for sx: float in [-1.0, 1.0]:
				var x: float = sx * (w + 0.018)
				_mi(self, _rbox(Vector3(0.04, h * 0.5, lz * 0.9), 0.02, 3), cover, Vector3(x, lerpf(_lo.y, _hi.y, 0.38), cz))
				_mi(self, ProcMesh.box(Vector3(0.005, 0.006, lz * 0.8)), _line(Color(0.4, 0.9, 1.0)), Vector3(x + sx * 0.021, lerpf(_lo.y, _hi.y, 0.5), cz))
			_mi(self, _rbox(Vector3(w * 1.7, h * 0.2, 0.05), 0.025, 3), cover, Vector3(0, lerpf(_lo.y, _hi.y, 0.3), _lo.z - 0.02))
		"maker_shell":
			var pearl: Material = visual._gloss(Color(0.97, 0.96, 0.94), 0.16, 0.1, 1.0)
			var gold: Material = visual._gloss(Color(1.0, 0.78, 0.38), 0.2, 1.0, 0.0)
			for sx: float in [-1.0, 1.0]:
				var x: float = sx * (w + 0.03)
				_mi(self, ProcMesh.sphere(0.5, 28, 12), pearl, Vector3(x, my, cz), Vector3.ZERO, Vector3(0.07, minf(h * 0.42, 0.2), minf(lz * 0.8, 0.5)))
				_mi(self, ProcMesh.box(Vector3(0.008, 0.008, minf(lz * 0.62, 0.38))), gold, Vector3(x + sx * 0.03, my + minf(h * 0.06, 0.04), cz))
				_mi(self, ProcMesh.box(Vector3(0.005, 0.005, minf(lz * 0.5, 0.3))), visual._glow(Color(0.35, 0.95, 1.0), 2.2), Vector3(x + sx * 0.033, my - minf(h * 0.04, 0.025), cz))
			_mi(self, ProcMesh.torus(0.05, 0.065, 20, 4), gold, Vector3(0, my, _lo.z - 0.01), Vector3(90, 0, 0))
			_mi(self, ProcMesh.cyl(0.05, 0.05, 0.006, 18), visual._glow(Color(0.35, 0.95, 1.0), 2.5), Vector3(0, my, _lo.z - 0.012), Vector3(90, 0, 0))


func _head_part(id: String) -> void:
	_head_id = id
	var a: Dictionary = _head_anchor()
	var hn: Node3D = a["node"]
	var lo: Vector3 = a["lo"]
	var hi: Vector3 = a["hi"]
	var hw: float = maxf(hi.x - lo.x, 0.12)
	var front: float = lo.z - 0.005
	var cy: float = (lo.y + hi.y) * 0.5
	var root := _node(hn, Vector3.ZERO)
	root.name = "KitHead"
	match id:
		"big_eye":
			var r: float = clampf(hw * 0.32, 0.05, 0.085)
			_mi(root, ProcMesh.cyl(r * 1.25, r * 1.35, 0.05, 24), _dark(), Vector3(0, cy, front - 0.02), Vector3(90, 0, 0))
			_mi(root, ProcMesh.torus(r * 1.1, r * 1.22, 28, 4), _white(), Vector3(0, cy, front - 0.046), Vector3(90, 0, 0))
			_mi(root, ProcMesh.cyl(r, r, 0.01, 24), Mats.glass(Color(0.04, 0.06, 0.09, 0.9), 0.02), Vector3(0, cy, front - 0.047), Vector3(90, 0, 0))
			_mi(root, ProcMesh.torus(r * 0.42, r * 0.5, 22, 3), _line(Color(0.4, 0.95, 1.0)), Vector3(0, cy, front - 0.053), Vector3(90, 0, 0))
			_mi(root, ProcMesh.sphere(r * 0.16, 10, 5), Mats.lamp(Color(1, 1, 1), 3.0), Vector3(r * 0.35, cy + r * 0.35, front - 0.054))
		"focus_visor":
			_mi(root, _rbox(Vector3(hw * 1.08, 0.05, 0.035), 0.016, 2), visual._gloss(Color(0.02, 0.03, 0.04), 0.05, 0.3, 1.0), Vector3(0, cy + 0.01, front - 0.012))
			_mi(root, ProcMesh.box(Vector3(hw * 0.86, 0.007, 0.004)), _line(Color(1.0, 0.62, 0.25)), Vector3(0, cy + 0.01, front - 0.031))
			for sx: float in [-1.0, 1.0]:
				_mi(root, ProcMesh.cyl(0.022, 0.022, 0.03, 12), _white(), Vector3(sx * hw * 0.55, cy + 0.01, front + 0.01), Vector3(0, 0, 90))
		"periscope":
			var top: float = hi.y
			_rod(root, Vector3(hw * 0.2, top - 0.01, (lo.z + hi.z) * 0.5), Vector3(hw * 0.2, top + 0.2, (lo.z + hi.z) * 0.5), 0.016, _dark(), 10)
			_mi(root, ProcMesh.cyl(0.024, 0.024, 0.04, 12), _white(), Vector3(hw * 0.2, top + 0.09, (lo.z + hi.z) * 0.5))
			_mi(root, _rbox(Vector3(0.07, 0.06, 0.11), 0.02, 2), _white(), Vector3(hw * 0.2, top + 0.23, (lo.z + hi.z) * 0.5 - 0.03))
			_mi(root, ProcMesh.cyl(0.022, 0.022, 0.006, 16), _line(Color(0.4, 0.95, 1.0)), Vector3(hw * 0.2, top + 0.23, (lo.z + hi.z) * 0.5 - 0.088), Vector3(90, 0, 0))
		"chatter_dome":
			var top2: float = hi.y
			var gl := _mi(root, ProcMesh.hemisphere(hw * 0.32, 22, 8), visual._glass(), Vector3(0, top2 - 0.005, (lo.z + hi.z) * 0.5))
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mi(root, ProcMesh.torus(hw * 0.31, hw * 0.34, 24, 4), _dark(), Vector3(0, top2 - 0.004, (lo.z + hi.z) * 0.5))
			var dot: StandardMaterial3D = Mats.lamp(Color(1.0, 0.45, 0.6), 2.0)
			_blink.append(dot)
			_mi(root, ProcMesh.sphere(0.018, 10, 5), dot, Vector3(0, top2 + hw * 0.12, (lo.z + hi.z) * 0.5))
			for sx: float in [-1.0, 1.0]:
				_mi(root, ProcMesh.cyl(0.035, 0.035, 0.012, 18), _dark(), Vector3(sx * (hw * 0.5 + 0.004), cy, (lo.z + hi.z) * 0.5), Vector3(0, 0, 90))
				for k: int in 2:
					_mi(root, ProcMesh.torus(0.01 + k * 0.012, 0.014 + k * 0.012, 16, 3), _white(), Vector3(sx * (hw * 0.5 + 0.011), cy, (lo.z + hi.z) * 0.5), Vector3(0, 0, 90))
		"maker_optic":
			var gold: Material = visual._gloss(Color(1.0, 0.78, 0.38), 0.2, 1.0, 0.0)
			_mi(root, ProcMesh.torus(hw * 0.52, hw * 0.56, 32, 4), gold, Vector3(0, hi.y + 0.01, (lo.z + hi.z) * 0.5), Vector3(8, 0, 0), Vector3(1, 1, 0.8))
			var gem := _node(root, Vector3(0, cy + 0.01, front - 0.07))
			gem.set_meta("base", gem.position)
			_float.append(gem)
			_mi(gem, ProcMesh.sphere(0.035, 8, 4), visual._gloss(Color(0.75, 0.97, 1.0), 0.05, 0.2, 1.0), Vector3.ZERO, Vector3(0, 0, 45), Vector3(1, 1.3, 0.7))
			_mi(gem, ProcMesh.torus(0.045, 0.05, 24, 3), visual._glow(Color(0.35, 0.95, 1.0), 2.5), Vector3.ZERO, Vector3(90, 0, 0))


func _mobility(id: String) -> void:
	var wi: Dictionary = _wheel_info()
	for w: Node3D in visual._wheels:
		w.visible = false
	var w: float = maxf(absf(_lo.x), absf(_hi.x))
	var cz: float = (_lo.z + _hi.z) * 0.5
	var lz: float = _hi.z - _lo.z
	var ground: float = 0.0 if not visual.hover else _lo.y - 0.06
	match id:
		"treads":
			var r: float = float(wi.get("r", 0.11)) if not wi.is_empty() else 0.1
			var x: float = (float(wi.get("x", w * 0.85)) if not wi.is_empty() else w * 0.85)
			var z0: float = float(wi.get("z0", cz - lz * 0.35)) if not wi.is_empty() else cz - lz * 0.3
			var z1: float = float(wi.get("z1", cz + lz * 0.35)) if not wi.is_empty() else cz + lz * 0.3
			if visual.hover:
				r = 0.07
			var y: float = ground + r
			for sx: float in [-1.0, 1.0]:
				var tr_ := _node(self, Vector3(sx * x, y, (z0 + z1) * 0.5))
				var len_: float = (z1 - z0) + r * 2.0
				_mi(tr_, ProcMesh.capsule(r, len_), Mats.rubber(Color(0.07, 0.07, 0.075)), Vector3.ZERO, Vector3(90, 0, 0), Vector3(0.05 / r, 1, 1))
				var n_cleat: int = int(len_ / 0.07)
				for i: int in n_cleat:
					var zz: float = -len_ * 0.5 + r + (len_ - 2.0 * r) * float(i) / maxf(n_cleat - 1, 1)
					_mi(tr_, ProcMesh.box(Vector3(0.1, 0.014, 0.025)), Mats.rubber(Color(0.11, 0.11, 0.115)), Vector3(0, r - 0.002, zz))
					_mi(tr_, ProcMesh.box(Vector3(0.1, 0.014, 0.025)), Mats.rubber(Color(0.11, 0.11, 0.115)), Vector3(0, -r + 0.002, zz))
				for zz: float in [-(len_ * 0.5 - r), (len_ * 0.5 - r)]:
					var sp := _node(tr_, Vector3(sx * 0.051, 0, zz))
					sp.set_meta("r", r)
					_rollers.append(sp)
					_mi(sp, ProcMesh.cyl(r * 0.7, r * 0.7, 0.012, 16), _white() if _sleek else _shell(Color(0.95, 0.72, 0.2)), Vector3.ZERO, Vector3(0, 0, 90))
					_mi(sp, ProcMesh.box(Vector3(0.014, r * 1.2, 0.02)), _dark(), Vector3.ZERO)
				_mi(tr_, _rbox(Vector3(0.012, r * 0.9, len_ - r * 2.2), 0.005, 1), _white() if _sleek else _shell(Color(0.95, 0.72, 0.2)), Vector3(sx * 0.052, 0, 0))
				_mi(tr_, ProcMesh.box(Vector3(0.004, 0.008, len_ - r * 2.6)), _line(_accent()), Vector3(sx * 0.06, r * 0.25, 0))
		"rotor":
			lift = 0.16
			var arm_y: float = lerpf(_lo.y, _hi.y, 0.62)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var c := Vector3(sx * (w + 0.13), arm_y, cz + sz * lz * 0.42)
					_rod(self, Vector3(sx * w * 0.7, arm_y - 0.02, cz + sz * lz * 0.25), c, 0.016, _dark(), 8)
					_mi(self, ProcMesh.torus(0.13, 0.15, 32, 4), _white(), c, Vector3.ZERO, Vector3(1, 1.6, 1))
					_mi(self, ProcMesh.torus(0.148, 0.152, 32, 3), _line(_accent()), c + Vector3(0, 0.018, 0))
					_mi(self, ProcMesh.cyl(0.022, 0.026, 0.05, 12), _dark(), c)
					var blades := _node(self, c + Vector3(0, 0.02, 0))
					blades.set_meta("spd", 38.0 * (1.0 if sx * sz > 0.0 else -1.0))
					_spin.append(blades)
					for k: int in 2:
						_mi(blades, ProcMesh.box(Vector3(0.24, 0.006, 0.035)), visual._gloss(Color(0.12, 0.13, 0.14), 0.4, 0.2, 0.0), Vector3.ZERO, Vector3(0, 90.0 * k, 6))
		"legs":
			lift = 0.1
			var hip_y: float = _lo.y + 0.06 if not visual.hover else _lo.y
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var hip := _node(self, Vector3(sx * w * 0.9, hip_y, cz + sz * lz * 0.36))
					hip.set_meta("ph", 0.0 if sx * sz > 0.0 else PI)
					_legs.append(hip)
					_mi(hip, ProcMesh.sphere(0.04, 14, 7), _dark(), Vector3.ZERO)
					var knee := Vector3(sx * 0.12, 0.02, 0)
					var foot := Vector3(sx * 0.14, -(hip_y - ground) - lift + 0.02, 0)
					_rod(hip, Vector3.ZERO, knee, 0.022, _white(), 10)
					_mi(hip, ProcMesh.sphere(0.026, 12, 6), _dark(), knee)
					_rod(hip, knee, foot, 0.016, _dark(), 8)
					_mi(hip, ProcMesh.cyl(0.035, 0.045, 0.02, 14), _white(), foot)
					_mi(hip, ProcMesh.torus(0.03, 0.034, 16, 3), _line(_accent()), knee + Vector3(0, 0, 0), Vector3(0, 0, 90))
		"hover_skirt", "maker_glider":
			lift = 0.08 if id == "hover_skirt" else 0.12
			var y2: float = ground + 0.07
			if id == "hover_skirt":
				_mi(self, _rbox(Vector3(w * 2.15, 0.07, lz * 1.02), 0.035, 3), _dark(), Vector3(0, y2, cz))
				_mi(self, _rbox(Vector3(w * 2.2, 0.025, lz * 1.06), 0.012, 2), _white(), Vector3(0, y2 + 0.045, cz))
				_mi(self, ProcMesh.box(Vector3(w * 2.0, 0.005, 0.005)), _line(Color(0.4, 0.95, 1.0)), Vector3(0, y2 - 0.02, _lo.z - 0.002))
				var wash := _mi(self, ProcMesh.cyl(w * 0.95, w * 1.1, 0.002, 28), visual._additive(Color(0.35, 0.85, 1.0, 0.12)), Vector3(0, ground - lift + 0.01, cz), Vector3.ZERO, Vector3(1, 1, lz / maxf(w * 2.0, 0.1)))
				wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				var pearl: Material = visual._gloss(Color(0.97, 0.96, 0.94), 0.16, 0.1, 1.0)
				for sx: float in [-1.0, 1.0]:
					var pod := _node(self, Vector3(sx * w * 0.8, y2, cz))
					pod.set_meta("base", pod.position)
					_float.append(pod)
					_mi(pod, ProcMesh.capsule(0.07, lz * 0.85), pearl, Vector3.ZERO, Vector3(90, 0, 0))
					_mi(pod, ProcMesh.box(Vector3(0.004, 0.004, lz * 0.6)), visual._glow(Color(0.35, 0.95, 1.0), 2.4), Vector3(sx * 0.07, 0, 0))
					_mi(pod, ProcMesh.cyl(0.05, 0.05, 0.004, 18), visual._glow(Color(0.35, 0.95, 1.0), 1.8), Vector3(0, -0.07, 0))
					_rod(self, Vector3(sx * w * 0.55, _lo.y + 0.05, cz), Vector3(sx * w * 0.8, y2 + 0.05, cz), 0.014, visual._gloss(Color(1.0, 0.78, 0.38), 0.2, 1.0, 0.0), 8)


## Tool tip in the tool parent's space.
func _tool_tip(parent: Node3D) -> Vector3:
	var tip: Vector3 = visual.emitter_point
	if _role == "haul":
		tip = visual.fork_point + Vector3(0, 0.05, 0.05)
	elif _role == "water":
		tip = visual.nozzle_point
	if parent != visual._body:
		tip = _rel(parent).affine_inverse() * tip
	return tip


func _tool(id: String) -> void:
	var parent: Node3D = visual._arm if visual._arm != null and _role != "water" else self
	var tip: Vector3 = _tool_tip(parent)
	var root := _node(parent, tip)
	root.name = "KitTool"
	var w: float = maxf(absf(_lo.x), absf(_hi.x))
	match id:
		"wide_scoop", "fine_sieve":
			var bw: float = w * 2.3
			var body_m: Material = _shell(Color(1.0, 0.55, 0.2)) if not _sleek else _white()
			_mi(root, _rbox(Vector3(bw, 0.025, 0.2), 0.01, 1), body_m, Vector3(0, -0.04, -0.06), Vector3(-10, 0, 0))
			_mi(root, _rbox(Vector3(bw, 0.1, 0.02), 0.01, 1), body_m, Vector3(0, 0.0, 0.03))
			for sx: float in [-1.0, 1.0]:
				_mi(root, _rbox(Vector3(0.02, 0.1, 0.2), 0.008, 1), body_m, Vector3(sx * bw * 0.5, -0.0, -0.05))
			_mi(root, ProcMesh.box(Vector3(bw * 0.9, 0.005, 0.005)), _line(_accent()), Vector3(0, -0.05, -0.165))
			if id == "fine_sieve":
				for i: int in 7:
					_mi(root, ProcMesh.box(Vector3(0.006, 0.006, 0.18)), _dark(), Vector3(-bw * 0.42 + bw * 0.84 * i / 6.0, -0.022, -0.06), Vector3(-10, 0, 0))
				_mi(root, ProcMesh.box(Vector3(bw * 0.86, 0.006, 0.006)), _dark(), Vector3(0, -0.018, -0.1))
			else:
				for i: int in 6:
					_mi(root, ProcMesh.box(Vector3(0.025, 0.012, 0.04)), Mats.metal("steel"), Vector3(-bw * 0.42 + bw * 0.84 * i / 5.0, -0.06, -0.17))
		"long_forks":
			for sx: float in [-0.15, 0.15]:
				_mi(root, _rbox(Vector3(0.055, 0.02, 0.42), 0.006, 1), _dark() if not _sleek else _white(), Vector3(sx, -0.05, -0.2))
				_mi(root, ProcMesh.box(Vector3(0.004, 0.006, 0.36)), _line(_accent()), Vector3(sx, -0.038, -0.2))
		"tow_hook":
			_mi(root, ProcMesh.cyl(0.05, 0.05, 0.14, 18), _shell(Color(0.95, 0.7, 0.2)) if not _sleek else _white(), Vector3(0, 0.12, 0.02), Vector3(0, 0, 90))
			_mi(root, ProcMesh.torus(0.05, 0.056, 18, 3), _line(_accent()), Vector3(0.072, 0.12, 0.02), Vector3(0, 0, 90))
			_rod(root, Vector3(0, 0.08, -0.01), Vector3(0, -0.06, -0.12), 0.006, _dark(), 6)
			_mi(root, ProcMesh.torus(0.022, 0.032, 14, 5), Mats.metal("chrome"), Vector3(0, -0.08, -0.13), Vector3(0, 90, 0))
		"seed_drill":
			var drill := _node(root, Vector3(0, -0.02, -0.08))
			drill.set_meta("spd", 9.0)
			drill.set_meta("work_only", true)
			_spin.append(drill)
			_mi(drill, ProcMesh.cyl(0.05, 0.008, 0.2, 16), Mats.metal("chrome"), Vector3(0, -0.1, 0))
			for i: int in 4:
				_mi(drill, ProcMesh.torus(0.012 + 0.009 * (3 - i), 0.02 + 0.009 * (3 - i), 14, 3), Mats.metal("steel"), Vector3(0, -0.04 - i * 0.04, 0), Vector3(8, i * 40.0, 0))
			_mi(root, ProcMesh.cyl(0.06, 0.06, 0.05, 16), _shell(Color(0.35, 0.7, 0.3)) if not _sleek else _white(), Vector3(0, 0.0, -0.08))
			_mi(root, ProcMesh.torus(0.058, 0.064, 18, 3), _line(Color(0.55, 1.0, 0.5)), Vector3(0, -0.026, -0.08))
		"mist_sprayer":
			var tipw := Vector3(0, 0.0, -0.02)
			_mi(root, _rbox(Vector3(0.3, 0.035, 0.05), 0.012, 2), _white(), tipw)
			for i: int in 5:
				_mi(root, ProcMesh.cyl(0.008, 0.012, 0.025, 8), _line(Color(0.45, 0.85, 1.0)), tipw + Vector3(-0.12 + i * 0.06, 0, -0.035), Vector3(-80, 0, 0))
		"jet_nozzle":
			_mi(root, ProcMesh.cyl(0.03, 0.022, 0.2, 14), _white(), Vector3(0, 0, -0.08), Vector3(90, 0, 0))
			_mi(root, ProcMesh.torus(0.022, 0.03, 16, 3), _line(Color(0.45, 0.85, 1.0)), Vector3(0, 0, -0.18), Vector3(90, 0, 0))
			_mi(root, ProcMesh.cyl(0.036, 0.036, 0.03, 14), _dark(), Vector3(0, 0, 0.01), Vector3(90, 0, 0))


func _topper(id: String) -> void:
	var parent: Node3D = self
	var pos := Vector3(0, _hi.y, (_lo.z + _hi.z) * 0.5 + 0.08)
	if visual._head != null:
		var a: Dictionary = _head_anchor()
		parent = a["node"]
		pos = Vector3((a["lo"].x + a["hi"].x) * 0.5 - 0.02, a["hi"].y - 0.005, (a["lo"].z + a["hi"].z) * 0.5 + 0.02)
		var hw: float = a["hi"].x - a["lo"].x
		if _head_id == "chatter_dome":
			pos.y += hw * 0.34
		elif _head_id == "periscope":
			pos.x -= hw * 0.3
		elif _head_id == "maker_optic":
			pos.y += 0.02
	var root := _node(parent, pos)
	root.name = "KitTopper"
	var acc: Color = _accent()
	match id:
		"antenna":
			_rod(root, Vector3.ZERO, Vector3(0.0, 0.2, 0.0), 0.005, _dark(), 6)
			for i: int in 3:
				_mi(root, ProcMesh.torus(0.007, 0.013, 10, 3), _white(), Vector3(0, 0.03 + i * 0.012, 0))
			var bulb: StandardMaterial3D = Mats.lamp(acc, 2.2)
			_blink.append(bulb)
			_mi(root, ProcMesh.sphere(0.022, 12, 6), bulb, Vector3(0, 0.215, 0))
			root.set_meta("k", 1.0)
			_bobble.append(root)
		"top_hat":
			var felt := StandardMaterial3D.new()
			felt.albedo_color = Color(0.06, 0.06, 0.07)
			felt.roughness = 0.8
			_mi(root, ProcMesh.cyl(0.085, 0.085, 0.01, 22), felt, Vector3(0, 0.005, 0))
			_mi(root, ProcMesh.cyl(0.055, 0.06, 0.11, 22), felt, Vector3(0, 0.065, 0))
			_mi(root, ProcMesh.cyl(0.0605, 0.0605, 0.02, 22), visual._gloss(acc.darkened(0.2), 0.4, 0.0, 0.0), Vector3(0, 0.022, 0))
			root.rotation_degrees = Vector3(0, 0, -8)
		"crew_flag":
			_rod(root, Vector3.ZERO, Vector3(0, 0.34, 0), 0.006, Mats.metal("chrome"), 6)
			_mi(root, ProcMesh.sphere(0.012, 8, 4), _line(acc), Vector3(0, 0.345, 0))
			var flag := _node(root, Vector3(0, 0.3, 0))
			var fm := StandardMaterial3D.new()
			fm.albedo_color = acc
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			fm.roughness = 0.7
			var pm := PrismMesh.new()
			pm.size = Vector3(0.11, 0.17, 0.004)
			_mi(flag, pm, fm, Vector3(0, -0.02, 0.085), Vector3(0, 90, -90))
			_flags.append(flag)
		"bobble_plant":
			var spring := _node(root, Vector3.ZERO)
			spring.set_meta("k", 1.6)
			_bobble.append(spring)
			for i: int in 6:
				_mi(spring, ProcMesh.torus(0.012, 0.018, 12, 3), Mats.metal("steel"), Vector3(0, 0.012 + i * 0.012, 0), Vector3(8 if i % 2 == 0 else -8, 0, 0))
			var leaf := visual._gloss(Color(0.42, 0.85, 0.35), 0.5, 0.0, 0.2)
			_mi(spring, ProcMesh.cyl(0.004, 0.005, 0.07, 6), leaf, Vector3(0, 0.11, 0))
			for sx: float in [-1.0, 1.0]:
				_mi(spring, ProcMesh.sphere(0.03, 12, 6), leaf, Vector3(sx * 0.03, 0.15, 0), Vector3(0, 0, sx * 35.0), Vector3(1.2, 0.35, 0.7))
			_mi(spring, ProcMesh.sphere(0.012, 8, 4), visual._gloss(Color(1.0, 0.85, 0.3), 0.4, 0.0, 0.0), Vector3(0, 0.152, 0))
		"traffic_cone":
			var orange := _shell(Color(1.0, 0.42, 0.1))
			_mi(root, ProcMesh.box(Vector3(0.12, 0.012, 0.12)), orange, Vector3(0, 0.006, 0))
			_mi(root, ProcMesh.cyl(0.008, 0.05, 0.15, 16), orange, Vector3(0, 0.085, 0))
			_mi(root, ProcMesh.cyl(0.026, 0.034, 0.03, 16), visual._gloss(Color(0.95, 0.95, 0.95), 0.4, 0.0, 0.0), Vector3(0, 0.09, 0))
			root.rotation_degrees = Vector3(6, 0, 10)
		"propeller_cap":
			_mi(root, ProcMesh.hemisphere(0.07, 18, 6), _shell(acc), Vector3(0, 0, 0), Vector3.ZERO, Vector3(1, 0.7, 1))
			_mi(root, ProcMesh.cyl(0.006, 0.006, 0.05, 6), _dark(), Vector3(0, 0.07, 0))
			var prop := _node(root, Vector3(0, 0.095, 0))
			prop.set_meta("spd", 6.0)
			prop.set_meta("speed_scaled", true)
			_spin.append(prop)
			for k: int in 2:
				_mi(prop, ProcMesh.box(Vector3(0.14, 0.004, 0.03)), _shell(Color(1.0, 0.8, 0.2) if k == 0 else Color(0.4, 0.7, 1.0)), Vector3(0.07 if k == 0 else -0.07, 0, 0), Vector3(12 if k == 0 else -12, 0, 0))
		"lucky_clover":
			var cl := _node(root, Vector3(0, 0.1, 0))
			cl.set_meta("base", cl.position)
			_float.append(cl)
			var green := visual._glow(Color(0.45, 1.0, 0.5), 1.3)
			for k: int in 4:
				var a: float = TAU * k / 4.0 + PI / 4.0
				_mi(cl, ProcMesh.sphere(0.024, 12, 6), green, Vector3(cos(a), 0, sin(a)) * 0.026, Vector3(0, -rad_to_deg(a), 0), Vector3(1.3, 0.25, 0.9))
			_mi(cl, ProcMesh.cyl(0.003, 0.003, 0.06, 5), green, Vector3(0.0, -0.03, 0.01), Vector3(20, 0, 0))
		"maker_crest":
			var cr := _node(root, Vector3(0, 0.12, 0))
			cr.set_meta("base", cr.position)
			_float.append(cr)
			var spin := _node(cr, Vector3.ZERO)
			spin.set_meta("spd", 0.8)
			_spin.append(spin)
			_mi(spin, ProcMesh.torus(0.07, 0.078, 32, 4), visual._gloss(Color(1.0, 0.78, 0.38), 0.2, 1.0, 0.0), Vector3.ZERO, Vector3(80, 0, 0))
			_mi(spin, ProcMesh.sphere(0.014, 10, 5), visual._glow(Color(0.35, 0.95, 1.0), 2.5), Vector3(0, 0.074, 0))


# --- Animation -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if visual == null:
		return
	_t += delta
	var spd: float = preview_speed
	var bot: Robot = visual.get_parent() as Robot
	if bot:
		spd = Vector3(bot.velocity.x, 0, bot.velocity.z).length()
		working = float(bot.get("_busy")) > 0.0
	# Whole-model offset: part lift (rotors hover a little) plus the personality's idle motion.
	var hov: float = lift
	if lift > 0.0 and _spin.size() >= 4:
		hov += sin(_t * 2.4) * 0.02
	visual.position.y = lerpf(visual.position.y, hov + anim_dy, clampf(delta * 10.0, 0.0, 1.0))
	visual.rotation = visual.rotation.lerp(anim_rot, clampf(delta * 8.0, 0.0, 1.0))
	for s: Node3D in _spin:
		var k: float = float(s.get_meta("spd", 1.0))
		if s.get_meta("work_only", false):
			k *= 1.0 if working else 0.05
		if s.get_meta("speed_scaled", false):
			k *= 0.4 + spd * 2.0
		s.rotate_object_local(Vector3.UP, k * delta)
	for i: int in _legs.size():
		var leg: Node3D = _legs[i]
		var ph: float = float(leg.get_meta("ph", 0.0))
		var amp: float = clampf(spd * 0.35, 0.0, 0.45)
		leg.rotation.x = sin(_t * (4.0 + spd * 5.0) + ph) * amp + (sin(_t * 1.2 + i) * 0.04 if working else 0.0)
	for r: Node3D in _rollers:
		r.rotation.x -= spd * delta / maxf(float(r.get_meta("r", 0.1)) * 0.7, 0.03)
	for b: Node3D in _bobble:
		var kk: float = float(b.get_meta("k", 1.0))
		b.rotation.x = sin(_t * 6.0 * kk) * (0.04 + clampf(spd, 0.0, 2.0) * 0.06)
		b.rotation.z = cos(_t * 4.7 * kk) * 0.05
	for f: Node3D in _flags:
		f.rotation.y = sin(_t * (5.0 + spd * 4.0)) * 0.25 + clampf(spd, 0.0, 2.0) * 0.2
	for fl: Node3D in _float:
		var base: Vector3 = fl.get_meta("base", fl.position)
		fl.position = base + Vector3(0, sin(_t * 1.8 + base.x * 7.0) * 0.012, 0)
	for m: StandardMaterial3D in _blink:
		m.emission_energy_multiplier = 1.2 + (1.6 if fmod(_t, 2.2) < 0.18 else 0.0)
