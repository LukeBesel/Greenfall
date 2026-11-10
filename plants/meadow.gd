class_name Meadow
extends RefCounted
## Unit-height grass tuft and wildflower meshes for restored ground (vertex colour = blade shade;
## the caller's shader scales and sways them). Used by planet site scripts that lay ground cover.

## A tuft of curved, tapering blades.
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b: int in 16:
		var a: float = TAU * b / 16.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var base: Vector3 = out * rng.randf_range(0.0, 0.32)
		_blade(st, base, out, rng.randf_range(0.5, 1.0), rng.randf_range(0.05, 0.085), rng.randf_range(0.2, 0.6), Color.BLACK)
	st.generate_normals()
	return st.commit()


static func _blade(st: SurfaceTool, base: Vector3, out: Vector3, h: float, w: float, lean: float, col: Color) -> void:
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	var pts: Array[Vector3] = []
	var ws: Array[float] = [1.0, 0.85, 0.55, 0.0]
	var ts: Array[float] = [0.0, 0.35, 0.7, 1.0]
	for t: float in ts:
		pts.append(base + out * lean * t * t + Vector3(0.0, h * t, 0.0))
	for i: int in 3:
		var a0: Vector3 = pts[i] - side * w * ws[i]
		var a1: Vector3 = pts[i] + side * w * ws[i]
		var b0: Vector3 = pts[i + 1] - side * w * ws[i + 1]
		var b1: Vector3 = pts[i + 1] + side * w * ws[i + 1]
		for v: Vector3 in [a0, b0, a1, a1, b0, b1]:
			st.set_color(col)
			st.add_vertex(v)


## Two or three stems with flat, five-petal heads (painted red: the shader picks the colour) and a
## few leaves at the base.
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for f: int in 3:
		var a: float = TAU * f / 3.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		var base: Vector3 = out * rng.randf_range(0.03, 0.12)
		var h: float = rng.randf_range(0.65, 1.0)
		var lean: float = rng.randf_range(0.05, 0.18)
		_blade(st, base, out, h, 0.018, lean, Color.BLACK)
		var top: Vector3 = base + out * lean + Vector3(0.0, h, 0.0)
		var r: float = rng.randf_range(0.2, 0.27)
		var tilt: Basis = Basis(out.cross(Vector3.UP).normalized(), -0.35)
		for k: int in 5:
			var pa: float = TAU * k / 5.0
			var c0: Vector3 = top
			var c1: Vector3 = top + tilt * (Vector3(cos(pa - 0.42), 0.0, sin(pa - 0.42)) * r * 0.55)
			var c2: Vector3 = top + tilt * (Vector3(cos(pa), 0.05, sin(pa)) * r)
			var c3: Vector3 = top + tilt * (Vector3(cos(pa + 0.42), 0.0, sin(pa + 0.42)) * r * 0.55)
			for v: Vector3 in [c0, c1, c2, c0, c2, c3]:
				st.set_color(Color.RED)
				st.add_vertex(v + Vector3(0.0, 0.01, 0.0))
	for l: int in 4:
		var a2: float = TAU * l / 4.0 + 0.4
		_blade(st, Vector3.ZERO, Vector3(cos(a2), 0.0, sin(a2)), 0.35, 0.05, 0.25, Color.BLACK)
	st.generate_normals()
	return st.commit()


## A seedling: a short stem with two round seed leaves (unit height ~1).
