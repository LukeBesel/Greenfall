class_name TideSuns
extends Node3D
## [planet-tidewell] The binary star as seen from Tidewell (mid-distance orbit): the warm primary
## stays on the scene's main DirectionalLight (it keeps the shadows and the PhysicalSky disc),
## the smaller orange companion gets a second, unshadowed DirectionalLight and its own sky disc
## (a far billboard with a soft, thin halo). Both rise and set together at a fixed separation, so
## the ocean shows two sun glints. Values come from SolarSystem.suns_for("tidewell") when the
## home branch's systems/solar_system.gd exists, else data/solar_system.json, else the canon
## fallback (owner rule, Nov 7).

const PLANET := "tidewell"
const SKY_DIST: float = 1800.0

var world: Node
var sun: DirectionalLight3D
var companion: DirectionalLight3D
var suns: Dictionary = {}
var _disc: MeshInstance3D
var _disc_mat: ShaderMaterial
var _sep_yaw: float = 14.0
var _sep_pitch: float = -3.0
var _sky_scale_a: float = 1.0


## {a: {color, size, energy}, b: {color, size, energy}, separation_deg}. Never fails.
static func read_suns(planet_id: String) -> Dictionary:
	var out: Dictionary = {
		"a": {"color": Color(1.0, 0.95, 0.85), "size": 0.9, "energy": 0.95},
		"b": {"color": Color(1.0, 0.62, 0.38), "size": 0.5, "energy": 0.23},
		"separation_deg": 14.0,
	}
	var path := "res://systems/solar_system.gd"
	if ResourceLoader.exists(path):
		var s: Script = load(path)
		if s and s.has_method("suns_for"):
			var r: Variant = s.call("suns_for", planet_id)
			if r is Dictionary and (r as Dictionary).has("a"):
				return _merge(out, r)
	if FileAccess.file_exists("res://data/solar_system.json"):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/solar_system.json"))
		if j is Dictionary:
			var d: Dictionary = j
			var pl: Dictionary = (d.get("planets", {}) as Dictionary).get(planet_id, {}) if d.get("planets") is Dictionary else {}
			var src: Dictionary = {"a": d.get("star_a", {}), "b": d.get("star_b", {})}
			if pl.has("sun_separation"):
				src["separation_deg"] = pl["sun_separation"]
			elif pl.has("separation_deg"):
				src["separation_deg"] = pl["separation_deg"]
			return _merge(out, src)
	return out


static func _merge(base: Dictionary, src: Dictionary) -> Dictionary:
	for k: String in ["a", "b"]:
		var s: Variant = src.get(k, {})
		if not (s is Dictionary):
			continue
		var b: Dictionary = base[k]
		for f: String in ["size", "energy"]:
			if (s as Dictionary).has(f):
				b[f] = float(s[f])
		var c: Variant = (s as Dictionary).get("color", null)
		if c is Color:
			b["color"] = c
		elif c is Array and (c as Array).size() >= 3:
			b["color"] = Color(float(c[0]), float(c[1]), float(c[2]))
		if (s as Dictionary).has("dir"):
			b["dir"] = s["dir"]
	for f: String in ["separation_deg", "separation", "sun_separation"]:
		if src.has(f):
			base["separation_deg"] = float(src[f])
	return base


func setup(p_world: Node, p_sun: DirectionalLight3D) -> void:
	world = p_world
	sun = p_sun
	suns = read_suns(PLANET)
	_sep_yaw = float(suns.get("separation_deg", 14.0))
	companion = DirectionalLight3D.new()
	companion.name = "CompanionSun"
	companion.shadow_enabled = false
	companion.light_color = suns["b"]["color"]
	companion.light_specular = 0.6
	companion.light_volumetric_fog_energy = 0.4
	companion.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(companion)
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = preload("res://planet/planets/tidewell/sun_disc.gdshader")
	_disc_mat.set_shader_parameter("color", suns["b"]["color"])
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_disc = MeshInstance3D.new()
	_disc.name = "CompanionDisc"
	_disc.mesh = q
	_disc.material_override = _disc_mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.extra_cull_margin = 4000.0
	add_child(_disc)
	var sd: Node = world.get("sky_director")
	if sd and sd.get("sky_mat") is PhysicalSkyMaterial:
		_sky_scale_a = float(suns["a"]["size"])


func _process(_delta: float) -> void:
	if sun == null:
		return
	# The companion trails the primary along the same arc (fixed separation), so they rise and
	# set together. Light energy scales with the primary's daylight (SkyDirector sets it).
	var b: Basis = Basis(Vector3.UP, deg_to_rad(_sep_yaw)) * sun.global_transform.basis * Basis(Vector3.RIGHT, deg_to_rad(_sep_pitch))
	companion.global_transform = Transform3D(b, Vector3.ZERO)
	var a_e: float = float(suns["a"]["energy"])
	var b_e: float = float(suns["b"]["energy"])
	sun.light_energy *= a_e  # SkyDirector rewrites it every frame, so this never accumulates
	companion.light_energy = sun.light_energy * b_e / maxf(a_e, 0.01)
	companion.visible = sun.visible and companion.light_energy > 0.01
	var sd: Node = world.get("sky_director")
	if sd and sd.get("sky_mat") is PhysicalSkyMaterial:
		(sd.get("sky_mat") as PhysicalSkyMaterial).sun_disk_scale = 1.2 * _sky_scale_a
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var to_b: Vector3 = companion.global_transform.basis.z.normalized()  # light shines along -Z
	_disc.visible = to_b.y > -0.05
	var ang: float = deg_to_rad(0.55) * float(suns["b"]["size"])  # apparent radius
	var s: float = tan(ang) * SKY_DIST * 2.0 * 6.0  # the quad includes the halo (6x the disc)
	_disc.global_position = cam.global_position + to_b * SKY_DIST
	_disc.look_at(cam.global_position, Vector3.UP if absf(to_b.y) < 0.98 else Vector3.FORWARD)
	_disc.scale = Vector3(s, s, 1.0)
	var day: float = clampf(sun.light_energy / 2.0, 0.0, 1.0)
	_disc_mat.set_shader_parameter("energy", 0.6 + 2.4 * day)
