class_name OldTownBurst
extends Node3D
## The pumping station's burst main (CityOldTown builds one at the torn pipe end): water under
## pressure. While broken: a white jet 14 m up (burst_water.gdshader on a lathe-turned column), a
## curtain of water falling back round it, flung droplets, drifting mist, a ring of splashes, and
## the flooded forecourt (street_flood.gdshader: ripples, sky sheen, a dark wet rim). Shut down:
## the jet and the water go, a yellow cap closes the main and the ground stays damp.
## Site-local metres; this node sits on the ground under the burst.

const JET_H: float = 14.0
const PIPE_Y: float = 1.6
## The flood's middle (from the burst) and its half-sizes; junk keeps off KEEP_OFF discs over it.
const FLOOD_AT := Vector3(-1.0, 0.0, 2.5)
const FLOOD_R := Vector2(11.0, 7.5)
const KEEP_OFF: Array[Vector3] = [Vector3(-5.6, 2.5, 5.2), Vector3(-1.0, 2.5, 6.6), Vector3(3.6, 2.5, 5.2)]  # x, z, radius
const WATER_SHADER: String = "res://planets/verdance/sites/burst_water.gdshader"
const FLOOD_SHADER: String = "res://planets/verdance/sites/street_flood.gdshader"

var broken: Node3D
var shut: Node3D
var _flood: ShaderMaterial


func build(cap_material: Material) -> void:
	broken = Node3D.new()
	broken.name = "BurstMain"
	add_child(broken)
	shut = Node3D.new()
	shut.name = "CappedMain"
	add_child(shut)
	var top := Vector3(0, PIPE_Y, 0)
	# The jet: tight and solid where it leaves the pipe, tearing open as it climbs and slows.
	broken.add_child(_water("Jet", top, [Vector2(0.34, 0.0), Vector2(0.4, 2.0), Vector2(0.5, 6.0), Vector2(0.8, 10.0), Vector2(1.5, 12.8), Vector2(2.3, JET_H)],
		{"speed": 2.6, "density": 0.86, "opacity": 0.96, "grain": Vector2(8.0, 3.2), "fade_out": 0.22}))
	# A looser skin round it, so the column is never one clean tube.
	broken.add_child(_water("JetSkin", top, [Vector2(0.5, 0.2), Vector2(0.62, 3.0), Vector2(0.85, 7.5), Vector2(1.5, 11.5), Vector2(2.6, 13.6)],
		{"speed": 2.0, "density": 0.5, "opacity": 0.7, "grain": Vector2(11.0, 2.4), "fade_out": 0.35}))
	# The water coming back down: a bell from the head of the jet to the ground.
	broken.add_child(_water("Curtain", Vector3.ZERO, [Vector2(1.2, PIPE_Y + JET_H - 0.4), Vector2(2.7, PIPE_Y + JET_H - 1.2), Vector2(3.7, 12.0), Vector2(4.4, 8.0), Vector2(4.9, 3.5), Vector2(5.2, 0.1)],
		{"speed": 1.5, "density": 0.42, "opacity": 0.55, "grain": Vector2(26.0, 2.0), "fade_out": 0.1, "fade_in": 0.12}))
	var soft: Texture2D = EscapePod._soft_tex()
	var white := Color(0.96, 0.99, 1.0, 0.95)
	# Droplets thrown up with the jet, and the rain off its head.
	broken.add_child(_spray("Droplets", top, soft, 140, 3.2, Vector3.UP, 7.0, 13.0, 17.5, Vector3(0, -9.8, 0), 0.1, 0.3, white))
	var rain: CPUParticles3D = _spray("Rain", top + Vector3(0, JET_H - 1.0, 0), soft, 220, 1.9, Vector3.UP, 85.0, 1.5, 5.5, Vector3(0, -9.8, 0), 0.07, 0.22, white)
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	rain.emission_sphere_radius = 1.6
	broken.add_child(rain)
	# Mist off the head, drifting downwind, and a low bank of it over the flood.
	broken.add_child(_spray("Mist", top + Vector3(0, JET_H - 2.0, 0), soft, 22, 4.5, Vector3(1, 0.2, 0.3), 60.0, 0.6, 1.8, Vector3(0.5, -0.4, 0.2), 3.5, 6.5, Color(1, 1, 1, 0.2)))
	broken.add_child(_spray("GroundMist", Vector3(0, 0.8, 0), soft, 18, 4.0, Vector3.UP, 85.0, 0.5, 1.6, Vector3(0.3, 0.15, 0.1), 3.0, 6.0, Color(1, 1, 1, 0.22)))
	# Where the curtain hits the flood: a ring of short splashes.
	var splash: CPUParticles3D = _spray("Splash", Vector3(0, 0.15, 0), soft, 90, 0.55, Vector3.UP, 38.0, 2.0, 4.6, Vector3(0, -9.8, 0), 0.12, 0.42, white)
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	splash.emission_ring_axis = Vector3.UP
	splash.emission_ring_radius = 5.4
	splash.emission_ring_inner_radius = 3.6
	splash.emission_ring_height = 0.05
	broken.add_child(splash)
	_flood = ShaderMaterial.new()
	_flood.shader = load(FLOOD_SHADER)
	_flood.set_shader_parameter("radii", FLOOD_R)
	_flood.set_shader_parameter("source", Vector2(-FLOOD_AT.x, -FLOOD_AT.z))
	broken.add_child(_sheet("Flood", FLOOD_AT + Vector3(0, 0.09, 0), FLOOD_R * 1.65, _flood))
	var damp: ShaderMaterial = _flood.duplicate()
	damp.set_shader_parameter("water", 0.0)
	damp.set_shader_parameter("radii", FLOOD_R * 0.8)
	shut.add_child(_sheet("Damp", FLOOD_AT + Vector3(0, 0.08, 0), FLOOD_R * 1.35, damp))
	var cap := BuildingDetail.Geo.new()
	cap.mat(BuildingDetail.K_METAL, Color(0.93, 0.68, 0.1))
	cap.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.5, -0.6)), 0.74, 0.74, 0.5, 14)
	cap.mat(BuildingDetail.K_METAL, Color(0.78, 0.8, 0.8))
	cap.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.5, -0.9)), 0.82, 0.82, 0.14, 14)
	var cmi := MeshInstance3D.new()
	cmi.name = "Cap"
	cmi.mesh = cap.mesh()
	cmi.material_override = cap_material
	cmi.set_meta("no_collide", true)
	shut.add_child(cmi)


func set_broken(on: bool) -> void:
	if broken:
		broken.visible = on
		for p: Node in broken.get_children():
			if p is CPUParticles3D:
				(p as CPUParticles3D).emitting = on
	if shut:
		shut.visible = not on


## A surface turned round the y axis from a profile of (radius, height) points, UV.y running from
## the first point to the last (the way the water moves), with the water shader set by `params`.
func _water(nm: String, at: Vector3, profile: Array, params: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: int = 20
	var total: float = 0.0
	for i: int in profile.size() - 1:
		total += ((profile[i + 1] as Vector2) - (profile[i] as Vector2)).length()
	var run: float = 0.0
	for i: int in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var len_ab: float = (b - a).length()
		var slope := Vector2(b.y - a.y, a.x - b.x).normalized()  # outward normal in (radial, up)
		for j: int in segs:
			var corners: Array = []
			for c: Vector2i in [Vector2i(0, j), Vector2i(1, j), Vector2i(1, j + 1), Vector2i(0, j + 1)]:
				var q: Vector2 = a if c.x == 0 else b
				var ang: float = TAU * float(c.y) / float(segs)
				var dir := Vector3(cos(ang), 0.0, sin(ang))
				corners.append([dir * q.x + Vector3(0, q.y, 0), dir * slope.x + Vector3(0, slope.y, 0),
					Vector2(float(c.y) / float(segs), (run + (0.0 if c.x == 0 else len_ab)) / total)])
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(corners[idx][1])
				st.set_uv(corners[idx][2])
				st.add_vertex(corners[idx][0])
		run += len_ab
	var m := ShaderMaterial.new()
	m.shader = load(WATER_SHADER)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	return mi


## A flat sheet at `at`, `half` metres each way, its UV in metres from its middle.
func _sheet(nm: String, at: Vector3, half: Vector2, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(pts[idx])
		st.add_vertex(Vector3(pts[idx].x, 0.0, pts[idx].y))
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	return mi


func _spray(nm: String, at: Vector3, tex: Texture2D, amount: int, life: float, dir: Vector3, spread: float, v0: float, v1: float,
		grav: Vector3, s0: float, s1: float, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = nm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.disable_receive_shadows = true
	q.material = m
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = true  # gravity is the site's "down", not the world's
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = grav
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	p.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.12, Color(1, 1, 1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-14, -18, -14), Vector3(28, 36, 28))
	return p
