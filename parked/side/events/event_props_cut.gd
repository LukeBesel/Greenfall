# Snippets cut from systems/event_props.gd (EventProps) in task M3-13 with the cut world events: the
# supply crate and its parachute (Supply Drop), the hiccup marker (Robot Hiccup) and the visiting
# animals (Wildlife Visit). They use EventProps._mi, _no_shadow and glow_mat.

## Cradle supply crate: rounded steel box, cyan light strips, stencil, a lid that can pop.
static func crate() -> Node3D:
	var n := Node3D.new()
	n.name = "Crate"
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.2, 0.36, 0.48), 0.92, 0.15, 17.0, 0.35)
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
	var lab: Label3D = EggProps.label(TranslationServer.translate("CRADLE · SUPPLY"), 22, Color(0.85, 0.95, 1.0), Vector3(0, 0.38, 0.365))
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
