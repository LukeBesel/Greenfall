class_name EventProps
extends RefCounted
## Cheap procedural visuals for world events (systems/events.gd):
## light beacons, glowing hex curtains and zone rings, rain and puddles.
## Unshaded additive glow where the "futuristic" look fits, worn paint elsewhere.


static func glow_mat(col: Color, alpha: float = 1.0, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, alpha)
	m.disable_receive_shadows = true
	return m


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


static func _no_shadow(m: MeshInstance3D) -> MeshInstance3D:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A soft vertical light pillar (fades out toward the top), visible from across the district.
static func beacon(col: Color, height: float = 26.0, radius: float = 0.35) -> Node3D:
	var n := Node3D.new()
	n.name = "Beacon"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: int = 12
	for k: int in segs:
		var a0: float = TAU * k / segs
		var a1: float = TAU * (k + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0, sin(a1)) * radius
		var top := Vector3(0, height, 0)
		var c0 := Color(1, 1, 1, 0.55)
		var c1 := Color(1, 1, 1, 0.0)
		for v: Array in [[p0, c0], [p1, c0], [p1 * 0.4 + top, c1], [p0, c0], [p1 * 0.4 + top, c1], [p0 * 0.4 + top, c1]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	var beam := MeshInstance3D.new()
	beam.mesh = st.commit()
	beam.material_override = glow_mat(col, 1.0, 1.4)
	_no_shadow(beam)
	n.add_child(beam)
	var core := _mi(n, ProcMesh.cyl(radius * 0.18, radius * 0.25, height * 0.6, 8), glow_mat(col, 0.5, 2.0), Vector3(0, height * 0.3, 0))
	_no_shadow(core)
	return n


## Glowing hexagon on the ground with a short light curtain along its edge (pointy-top hexes).
static func hex_glow(size: float, col: Color, curtain: float = 1.6) -> Node3D:
	var n := Node3D.new()
	n.name = "HexGlow"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = size * 0.98
	var w: float = size * 0.09
	for k: int in 6:
		var a0: float = deg_to_rad(60.0 * k + 30.0)
		var a1: float = deg_to_rad(60.0 * (k + 1) + 30.0)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var o0: Vector3 = d0 * r
		var o1: Vector3 = d1 * r
		var i0: Vector3 = d0 * (r - w)
		var i1: Vector3 = d1 * (r - w)
		var bright := Color(1, 1, 1, 0.9)
		var soft := Color(1, 1, 1, 0.0)
		# Ground band: bright at the edge, fading inward.
		for v: Array in [[o0, bright], [o1, bright], [i1, soft], [o0, bright], [i1, soft], [i0, soft]]:
			st.set_color(v[1])
			st.add_vertex(v[0] + Vector3(0, 0.05, 0))
		# Light curtain: bright at the base, fading upward.
		var up := Vector3(0, curtain, 0)
		var base := Color(1, 1, 1, 0.38)
		for v: Array in [[o0, base], [o1, base], [o1 + up, soft], [o0, base], [o1 + up, soft], [o0 + up, soft]]:
			st.set_color(v[1])
			st.add_vertex(v[0] + Vector3(0, 0.05, 0))
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	mi.mesh = st.commit()
	mi.material_override = glow_mat(col, 1.0, 1.6)
	_no_shadow(mi)
	n.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = size * 1.1
	light.light_energy = 0.8
	light.position = Vector3(0, 2.0, 0)
	n.add_child(light)
	return n


## Flat glowing ring on the ground (zones: audit, part signal).
static func zone_ring(radius: float, col: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: int = 48
	var w: float = 0.22
	for k: int in segs:
		var a0: float = TAU * k / segs
		var a1: float = TAU * (k + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		# Dashed: every other pair of segments is dimmer, reads as a "scanned" boundary.
		@warning_ignore("integer_division")
		var a: float = 0.95 if (k / 2) % 2 == 0 else 0.35
		var bright := Color(1, 1, 1, a)
		var soft := Color(1, 1, 1, 0.0)
		for v: Array in [[d0 * radius, bright], [d1 * radius, bright], [d1 * (radius - w * 3.0), soft], [d0 * radius, bright], [d1 * (radius - w * 3.0), soft], [d0 * (radius - w * 3.0), soft]]:
			st.set_color(v[1])
			st.add_vertex(v[0] + Vector3(0, 0.06, 0))
		for v: Array in [[d0 * radius, bright], [d1 * radius, bright], [d1 * (radius + w), soft], [d0 * radius, bright], [d1 * (radius + w), soft], [d0 * (radius + w), soft]]:
			st.set_color(v[1])
			st.add_vertex(v[0] + Vector3(0, 0.06, 0))
	var mi := MeshInstance3D.new()
	mi.name = "ZoneRing"
	mi.mesh = st.commit()
	mi.material_override = glow_mat(col, 1.0, 1.5)
	return _no_shadow(mi)


## Rain: streaks around a moving centre (set position each frame) plus splashes.
static func rain() -> Node3D:
	var n := Node3D.new()
	n.name = "Rain"
	var drops := CPUParticles3D.new()
	drops.name = "Drops"
	drops.amount = int(900 * Settings.particle_scale())  # [deck]
	drops.lifetime = 1.1
	drops.preprocess = 1.0
	drops.local_coords = false
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(22, 0.5, 22)
	drops.direction = Vector3(0.12, -1, 0.05)
	drops.spread = 2.0
	drops.gravity = Vector3(0, -12, 0)
	drops.initial_velocity_min = 14.0
	drops.initial_velocity_max = 18.0
	drops.position = Vector3(0, 16, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.55)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.75, 0.85, 1.0, 0.38)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.disable_receive_shadows = true
	q.material = dm
	drops.mesh = q
	n.add_child(drops)
	var splash := CPUParticles3D.new()
	splash.name = "Splash"
	splash.amount = int(160 * Settings.particle_scale())
	splash.lifetime = 0.35
	splash.local_coords = false
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	splash.emission_box_extents = Vector3(14, 0.02, 14)
	splash.direction = Vector3(0, 1, 0)
	splash.spread = 50.0
	splash.gravity = Vector3(0, -9, 0)
	splash.initial_velocity_min = 0.8
	splash.initial_velocity_max = 1.6
	splash.scale_amount_min = 0.5
	splash.scale_amount_max = 1.0
	splash.position = Vector3(0, 0.1, 0)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.05)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.85, 0.92, 1.0, 0.5)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sq.material = sm
	splash.mesh = sq
	n.add_child(splash)
	return n


## A shimmering puddle: dark glossy water with a slowly pulsing sky-blue sheen.
static func puddle(radius: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.16, 0.22, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.6
	m.roughness = 0.04
	m.emission_enabled = true
	m.emission = Color(0.35, 0.55, 0.85)
	m.emission_energy_multiplier = 0.25
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.015
	cm.radial_segments = 20
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.scale = Vector3(1.0, 1.0, randf_range(0.55, 0.9))
	return _no_shadow(mi)
