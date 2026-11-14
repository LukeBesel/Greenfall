class_name SkyBody
extends Node3D
## [worlds2] A big body in a Cradle Mode world's sky (data/world_looks.json sky_body): a ringed gas
## giant over the Ice Moon, a tide-pulling moon over the Ocean World, a shattered moon over the
## Rust World. A camera-facing quad (art/shaders/sky_body.gdshader) kept at a fixed direction just
## inside the camera's far plane, so it sits behind the skyline and never parallaxes.

const DIST: float = 540.0

var dir := Vector3(0, 0.4, -1).normalized()
var size_deg: float = 20.0
var director: SkyDirector
var _quads: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _offsets: Array[Vector3] = []


static func make(body: Dictionary, p_director: SkyDirector) -> SkyBody:
	var b := SkyBody.new()
	b.name = "SkyBody"
	b.director = p_director
	b.dir = WorldLook.sky_dir(body)
	b.size_deg = float(body.get("size", 20.0))
	var kind: String = str(body.get("kind", "moon"))
	b._add(body, kind, b.size_deg, Vector3.ZERO, 1.0)
	if float(body.get("twin", 0.0)) > 0.0:  # a second, smaller moon off to one side
		var tw: Dictionary = body.duplicate()
		tw["body"] = [0.9, 0.82, 0.74]
		b._add(tw, "moon", b.size_deg * 0.45, Vector3(0.11, 0.05, 0.0), 7.3)
	return b


func _add(body: Dictionary, kind: String, sz: float, offset: Vector3, seed_v: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/sky_body.gdshader")
	m.set_shader_parameter("body_col", WorldLook.col(body.get("body", []), Color(0.86, 0.86, 0.86)))
	m.set_shader_parameter("band_col", WorldLook.col(body.get("band", []), Color(0.6, 0.6, 0.62)))
	m.set_shader_parameter("ring_col", WorldLook.col(body.get("ring", []), Color(0.9, 0.88, 0.84)))
	m.set_shader_parameter("ring", 1.0 if kind in ["ringed", "shattered"] else 0.0)
	m.set_shader_parameter("grain", 1.0 if kind == "shattered" else 0.0)
	m.set_shader_parameter("bands", 1.0 if kind == "ringed" else 0.0)
	m.set_shader_parameter("disc_r", 0.3 if kind != "moon" else 0.92)
	m.set_shader_parameter("tilt", float(body.get("tilt", 0.3)))
	m.set_shader_parameter("seed", seed_v)
	var q := QuadMesh.new()
	var half: float = tan(deg_to_rad(sz) * 0.5) * DIST
	q.size = Vector2(half * 2.0, half * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 2000.0
	add_child(mi)
	_quads.append(mi)
	_mats.append(m)
	_offsets.append(offset)


func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var day: float = 1.0
	var sun_dir := Vector3(0.4, 0.8, 0.2)
	if director and director.sun:
		day = clampf(director.sun.light_energy / 3.0, 0.0, 1.0)
		sun_dir = director.sun.global_transform.basis.z  # toward the sun
	var right: Vector3 = Vector3.UP.cross(-dir).normalized()
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	var up: Vector3 = (-dir).cross(right).normalized()
	for i: int in _quads.size():
		var d: Vector3 = (dir + right * _offsets[i].x + up * _offsets[i].y).normalized()
		var pos: Vector3 = cam.global_position + d * DIST
		var b := Basis.looking_at(d, Vector3.UP)  # quad +Z faces the camera
		_quads[i].global_transform = Transform3D(b, pos)
		# The lit side faces the sun, in the quad's own frame (shader p.x = local X, p.y = local Y).
		var l2 := Vector2(sun_dir.dot(b.x), sun_dir.dot(b.y))
		if l2.length() < 0.05:
			l2 = Vector2(-0.5, 0.4)
		_mats[i].set_shader_parameter("light_dir", l2.normalized() * 0.9)
		_mats[i].set_shader_parameter("day", day)
