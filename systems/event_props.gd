class_name EventProps
extends RefCounted
## Cheap procedural visuals for world events (systems/events.gd): supply crate with parachute,
## light beacons, glowing hex curtains and zone rings, rain, puddles, the visiting animals, the
## hiccup marker. Unshaded additive glow where the "futuristic" look fits, worn paint elsewhere.


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


## Flat glowing ring on the ground (zones: supply crate, audit, part signal).
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


## Cradle supply crate: rounded steel box, cyan light strips, stencil, a lid that can pop.
static func crate() -> Node3D:
	var n := Node3D.new()
	n.name = "Crate"
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.86, 0.88, 0.9), 0.92, 0.15, 17.0, 0.35)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var cyan := Mats.lamp(Color(0.37, 0.9, 1.0), 2.6)
	_mi(n, ProcMesh.rounded_box(Vector3(0.95, 0.62, 0.72), 0.06, 2), paint, Vector3(0, 0.31, 0))
	for x: float in [-0.43, 0.43]:
		_mi(n, ProcMesh.box(Vector3(0.06, 0.64, 0.74)), steel, Vector3(x, 0.31, 0))
	_mi(n, ProcMesh.box(Vector3(0.97, 0.035, 0.74)), cyan, Vector3(0, 0.2, 0))
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.62, -0.36)
	n.add_child(lid)
	_mi(lid, ProcMesh.rounded_box(Vector3(0.99, 0.08, 0.76), 0.03, 2), paint, Vector3(0, 0.04, 0.36))
	_mi(lid, ProcMesh.box(Vector3(0.5, 0.02, 0.1)), cyan, Vector3(0, 0.09, 0.36))
	var lab: Label3D = EggProps.label("CRADLE · SUPPLY", 22, Color(0.12, 0.2, 0.26), Vector3(0, 0.38, 0.365))
	n.add_child(lab)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(0.4, 0.9, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 3.5
	glow.position = Vector3(0, 1.0, 0)
	n.add_child(glow)
	return n


## Striped parachute canopy with rigging lines down to the crate (origin = crate top).
static func parachute() -> Node3D:
	var n := Node3D.new()
	n.name = "Chute"
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(1.0, 0.55, 0.2)
	cloth.roughness = 0.8
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.92)
	white.roughness = 0.8
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	var canopy := Node3D.new()
	canopy.position = Vector3(0, 2.3, 0)
	n.add_child(canopy)
	for k: int in 8:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5
		sm.height = 1.5
		sm.is_hemisphere = true
		sm.radial_segments = 4
		sm.rings = 6
		seg.mesh = sm
		seg.material_override = cloth if k % 2 == 0 else white
		seg.rotation_degrees = Vector3(0, k * 45.0, 0)
		seg.scale = Vector3(1, 0.7, 1)
		canopy.add_child(seg)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.85, 0.85, 0.8)
	for k: int in 6:
		var a: float = TAU * k / 6.0
		var top := Vector3(cos(a) * 1.35, 2.3, sin(a) * 1.35)
		n.add_child(EggProps.strut(Vector3(0, 0.05, 0), top, 0.012, line_mat))
	return n


## Hiccup marker: a bobbing warning glyph with a spinning gear ring.
static func hiccup_marker(col: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Hiccup"
	var lab := Label3D.new()
	lab.text = "!"
	lab.font_size = 96
	lab.outline_size = 18
	lab.modulate = col
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.pixel_size = 0.006
	lab.position = Vector3(0, 0.25, 0)
	n.add_child(lab)
	var ring := _mi(n, ProcMesh.torus(0.32, 0.4, 8, 4), glow_mat(col, 0.9, 1.5), Vector3.ZERO, Vector3(90, 0, 0))
	ring.name = "Ring"
	_no_shadow(ring)
	return n


## Rain: streaks around a moving centre (set position each frame) plus splashes.
static func rain() -> Node3D:
	var n := Node3D.new()
	n.name = "Rain"
	var drops := CPUParticles3D.new()
	drops.name = "Drops"
	drops.amount = 900
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
	splash.amount = 160
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


# --- Visiting animals ---------------------------------------------------------------------------

## A small stylised animal (fur colour + bioluminescent accents). Faces -Z. "Body" child bobs.
static func animal(body: String, fur: Color, glow: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Animal"
	var b := Node3D.new()
	b.name = "Body"
	n.add_child(b)
	var furm := StandardMaterial3D.new()
	furm.albedo_color = fur
	furm.roughness = 0.9
	var belly := StandardMaterial3D.new()
	belly.albedo_color = fur.lightened(0.45)
	belly.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = fur.darkened(0.6)
	dark.roughness = 0.7
	var lit: StandardMaterial3D = Mats.lamp(glow, 3.0)
	var eye: StandardMaterial3D = Mats.lamp(Color(0.05, 0.05, 0.06), 0.0)
	eye.roughness = 0.1
	match body:
		"deer":
			_mi(b, ProcMesh.capsule(0.22, 0.95), furm, Vector3(0, 0.95, 0), Vector3(90, 0, 0))
			for p: Vector3 in [Vector3(-0.13, 0.42, -0.3), Vector3(0.13, 0.42, -0.3), Vector3(-0.13, 0.42, 0.3), Vector3(0.13, 0.42, 0.3)]:
				_mi(b, ProcMesh.cyl(0.035, 0.045, 0.85, 6), dark, p)
			_mi(b, ProcMesh.cyl(0.08, 0.1, 0.5, 8), furm, Vector3(0, 1.3, -0.45), Vector3(-35, 0, 0))
			_mi(b, ProcMesh.capsule(0.11, 0.34), furm, Vector3(0, 1.55, -0.62), Vector3(70, 0, 0))
			for x: float in [-1.0, 1.0]:
				var ant := Node3D.new()
				ant.position = Vector3(0.07 * x, 1.68, -0.58)
				b.add_child(ant)
				_mi(ant, ProcMesh.cyl(0.015, 0.025, 0.4, 5), dark, Vector3(0.08 * x, 0.18, 0), Vector3(0, 0, -25 * x))
				_mi(ant, ProcMesh.cyl(0.012, 0.015, 0.2, 5), dark, Vector3(0.12 * x, 0.32, -0.06), Vector3(30, 0, -60 * x))
				_mi(ant, ProcMesh.sphere(0.04, 8, 4), lit, Vector3(0.17 * x, 0.38, -0.1))
				_mi(b, ProcMesh.sphere(0.026, 8, 4), eye, Vector3(0.08 * x, 1.6, -0.74))
			for k: int in 6:
				_mi(b, ProcMesh.sphere(0.035, 6, 3), lit, Vector3((k % 2 - 0.5) * 0.36, 1.05 + (k % 3) * 0.04, -0.3 + k * 0.12))
		"heron":
			_mi(b, ProcMesh.capsule(0.16, 0.6), furm, Vector3(0, 0.95, 0.05), Vector3(70, 0, 0))
			for x: float in [-0.06, 0.06]:
				_mi(b, ProcMesh.cyl(0.015, 0.015, 0.75, 5), dark, Vector3(x, 0.38, 0.05))
			_mi(b, ProcMesh.cyl(0.04, 0.05, 0.55, 6), furm, Vector3(0, 1.35, -0.12), Vector3(-15, 0, 0))
			_mi(b, ProcMesh.sphere(0.08, 10, 5), furm, Vector3(0, 1.62, -0.18))
			_mi(b, ProcMesh.cyl(0.005, 0.03, 0.3, 5), Mats.lamp(Color(1.0, 0.75, 0.3), 0.6), Vector3(0, 1.6, -0.38), Vector3(-90, 0, 0))
			for x: float in [-1.0, 1.0]:
				_mi(b, ProcMesh.sphere(0.018, 6, 3), eye, Vector3(0.06 * x, 1.64, -0.23))
				_mi(b, ProcMesh.box(Vector3(0.03, 0.22, 0.45)), lit, Vector3(0.15 * x, 0.95, 0.12), Vector3(20, 0, 0))
		"hedgehog":
			_mi(b, ProcMesh.sphere(0.24, 12, 6), dark, Vector3(0, 0.22, 0.02), Vector3.ZERO, Vector3(1, 0.8, 1.25))
			_mi(b, ProcMesh.sphere(0.13, 10, 5), belly, Vector3(0, 0.17, -0.25), Vector3.ZERO, Vector3(1, 0.9, 1.3))
			_mi(b, ProcMesh.sphere(0.03, 6, 3), eye, Vector3(0, 0.17, -0.42))
			for k: int in 14:
				var a: float = TAU * k / 14.0
				_mi(b, ProcMesh.cyl(0.0, 0.03, 0.14, 5), furm, Vector3(cos(a) * 0.17, 0.32 + sin(a * 2.0) * 0.04, sin(a) * 0.22 + 0.05), Vector3(-20 * sin(a), 0, 35 * cos(a)))
				_mi(b, ProcMesh.sphere(0.018, 5, 3), lit, Vector3(cos(a) * 0.21, 0.38 + sin(a * 2.0) * 0.04, sin(a) * 0.27 + 0.05))
		"hare":
			_mi(b, ProcMesh.sphere(0.2, 12, 6), furm, Vector3(0, 0.25, 0.05), Vector3.ZERO, Vector3(0.9, 0.95, 1.3))
			_mi(b, ProcMesh.sphere(0.12, 10, 5), furm, Vector3(0, 0.43, -0.22))
			for x: float in [-1.0, 1.0]:
				_mi(b, ProcMesh.capsule(0.04, 0.32), furm, Vector3(0.05 * x, 0.66, -0.18), Vector3(-10, 0, 12 * x))
				_mi(b, ProcMesh.capsule(0.022, 0.24), lit, Vector3(0.05 * x, 0.67, -0.205), Vector3(-10, 0, 12 * x))
				_mi(b, ProcMesh.sphere(0.022, 6, 3), eye, Vector3(0.07 * x, 0.46, -0.31))
			_mi(b, ProcMesh.sphere(0.07, 8, 4), Mats.lamp(glow.lightened(0.4), 2.0), Vector3(0, 0.3, 0.32))
		_:  # fox
			_mi(b, ProcMesh.capsule(0.15, 0.62), furm, Vector3(0, 0.38, 0), Vector3(90, 0, 0))
			for p: Vector3 in [Vector3(-0.08, 0.15, -0.18), Vector3(0.08, 0.15, -0.18), Vector3(-0.08, 0.15, 0.2), Vector3(0.08, 0.15, 0.2)]:
				_mi(b, ProcMesh.cyl(0.025, 0.03, 0.3, 6), dark, p)
			_mi(b, ProcMesh.sphere(0.12, 10, 5), furm, Vector3(0, 0.52, -0.32))
			_mi(b, ProcMesh.cyl(0.0, 0.06, 0.16, 6), belly, Vector3(0, 0.49, -0.46), Vector3(-90, 0, 0))
			for x: float in [-1.0, 1.0]:
				_mi(b, ProcMesh.cyl(0.0, 0.05, 0.13, 4), furm, Vector3(0.07 * x, 0.66, -0.3), Vector3(0, 0, -12 * x))
				_mi(b, ProcMesh.sphere(0.02, 6, 3), eye, Vector3(0.055 * x, 0.56, -0.42))
			var tail := Node3D.new()
			tail.name = "Tail"
			tail.position = Vector3(0, 0.42, 0.32)
			b.add_child(tail)
			_mi(tail, ProcMesh.capsule(0.08, 0.42), furm, Vector3(0, 0.08, 0.16), Vector3(60, 0, 0))
			_mi(tail, ProcMesh.sphere(0.075, 8, 4), lit, Vector3(0, 0.2, 0.33))
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 0.8
	light.omni_range = 2.2
	light.position = Vector3(0, 0.8, 0)
	n.add_child(light)
	return n
