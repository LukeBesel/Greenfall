class_name JunkMeshes
extends RefCounted
## Code-built, colorful junk shapes. Vertex color alpha 1 = takes the instance tint, alpha 0 = fixed color.
## Each mesh is roughly 0.3-0.6 m and sits with its base at y=0.

const TINT := Color(1, 1, 1, 1)
const WHITE := Color(0.97, 0.97, 0.95, 0.0)
const DARK := Color(0.16, 0.15, 0.2, 0.0)
const SILVER := Color(0.82, 0.84, 0.88, 0.0)
const ORANGE := Color(1.0, 0.55, 0.15, 0.0)

static var _cache: Dictionary = {}


static func get_mesh(shape: String) -> ArrayMesh:
	if not _cache.has(shape):
		_cache[shape] = _build(shape)
	return _cache[shape]


static func _p(mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO, color: Color = TINT, scl: Vector3 = Vector3.ONE) -> Dictionary:
	return ProcMesh.part(mesh, ProcMesh.xf(pos, rot, scl), color)


static func _build(shape: String) -> ArrayMesh:
	var parts: Array = []
	match shape:
		"can":
			# Lying on its side.
			parts.append(_p(ProcMesh.cyl(0.11, 0.11, 0.3, 14), Vector3(0, 0.11, 0), Vector3(0, 0, 90)))
			parts.append(_p(ProcMesh.cyl(0.095, 0.095, 0.02, 14), Vector3(0.155, 0.11, 0), Vector3(0, 0, 90), SILVER))
			parts.append(_p(ProcMesh.cyl(0.112, 0.112, 0.07, 14), Vector3(-0.02, 0.11, 0), Vector3(0, 0, 90), WHITE))
		"pipe":
			parts.append(_p(ProcMesh.cyl(0.07, 0.07, 0.62, 10), Vector3(0, 0.07, 0), Vector3(0, 0, 90)))
			parts.append(_p(ProcMesh.cyl(0.09, 0.09, 0.07, 10), Vector3(0.3, 0.07, 0), Vector3(0, 0, 90), SILVER))
			parts.append(_p(ProcMesh.cyl(0.09, 0.09, 0.07, 10), Vector3(-0.3, 0.07, 0), Vector3(0, 0, 90), SILVER))
		"bottle":
			parts.append(_p(ProcMesh.cyl(0.09, 0.09, 0.28, 12), Vector3(0, 0.09, 0), Vector3(0, 0, 90)))
			parts.append(_p(ProcMesh.cyl(0.035, 0.09, 0.09, 12), Vector3(0.18, 0.09, 0), Vector3(0, 0, -90)))
			parts.append(_p(ProcMesh.cyl(0.035, 0.035, 0.08, 10), Vector3(0.26, 0.09, 0), Vector3(0, 0, 90)))
			parts.append(_p(ProcMesh.cyl(0.042, 0.042, 0.035, 10), Vector3(0.31, 0.09, 0), Vector3(0, 0, 90), WHITE))
			parts.append(_p(ProcMesh.cyl(0.092, 0.092, 0.1, 12), Vector3(-0.02, 0.09, 0), Vector3(0, 0, 90), WHITE))
		"bag":
			parts.append(_p(ProcMesh.sphere(0.22, 12, 6), Vector3(0, 0.1, 0), Vector3.ZERO, TINT, Vector3(1.0, 0.5, 0.8)))
			parts.append(_p(ProcMesh.torus(0.05, 0.08, 10, 6), Vector3(0.12, 0.2, 0), Vector3(90, 0, 20)))
			parts.append(_p(ProcMesh.torus(0.05, 0.08, 10, 6), Vector3(0.18, 0.19, 0.05), Vector3(90, 30, 30)))
		"cone":
			parts.append(_p(ProcMesh.box(Vector3(0.36, 0.04, 0.36)), Vector3(0, 0.02, 0)))
			parts.append(_p(ProcMesh.cyl(0.025, 0.15, 0.46, 14), Vector3(0, 0.25, 0)))
			parts.append(_p(ProcMesh.cyl(0.077, 0.1, 0.07, 14), Vector3(0, 0.3, 0), Vector3.ZERO, WHITE))
		"jar":
			parts.append(_p(ProcMesh.cyl(0.12, 0.12, 0.22, 14), Vector3(0, 0.11, 0)))
			parts.append(_p(ProcMesh.cyl(0.1, 0.1, 0.05, 14), Vector3(0, 0.245, 0), Vector3.ZERO, SILVER))
		"tire":
			parts.append(_p(ProcMesh.torus(0.11, 0.27, 18, 8), Vector3(0, 0.08, 0), Vector3.ZERO, TINT, Vector3(1, 1.0, 1)))
			parts.append(_p(ProcMesh.cyl(0.12, 0.12, 0.06, 12), Vector3(0, 0.08, 0), Vector3.ZERO, SILVER))
		"duck":
			parts.append(_p(ProcMesh.sphere(0.13, 12, 6), Vector3(0, 0.11, 0), Vector3.ZERO, TINT, Vector3(1.3, 0.9, 1.0)))
			parts.append(_p(ProcMesh.sphere(0.085, 12, 6), Vector3(0.1, 0.24, 0)))
			parts.append(_p(ProcMesh.cyl(0.0, 0.04, 0.08, 8), Vector3(0.21, 0.23, 0), Vector3(0, 0, -90), ORANGE))
			parts.append(_p(ProcMesh.sphere(0.018, 6, 3), Vector3(0.16, 0.27, 0.05), Vector3.ZERO, DARK))
			parts.append(_p(ProcMesh.sphere(0.018, 6, 3), Vector3(0.16, 0.27, -0.05), Vector3.ZERO, DARK))
			parts.append(_p(ProcMesh.cyl(0.0, 0.06, 0.08, 6), Vector3(-0.17, 0.16, 0), Vector3(0, 0, 70)))
		"board":
			parts.append(_p(ProcMesh.box(Vector3(0.42, 0.03, 0.28)), Vector3(0, 0.015, 0)))
			parts.append(_p(ProcMesh.box(Vector3(0.1, 0.03, 0.1)), Vector3(-0.08, 0.045, 0.03), Vector3.ZERO, DARK))
			parts.append(_p(ProcMesh.box(Vector3(0.06, 0.03, 0.12)), Vector3(0.1, 0.045, -0.05), Vector3.ZERO, DARK))
			parts.append(_p(ProcMesh.cyl(0.025, 0.025, 0.07, 8), Vector3(0.12, 0.065, 0.08), Vector3.ZERO, Color(0.3, 0.5, 1.0, 0.0)))
			parts.append(_p(ProcMesh.cyl(0.02, 0.02, 0.05, 8), Vector3(-0.15, 0.055, -0.08), Vector3.ZERO, Color(1.0, 0.85, 0.2, 0.0)))
		"gadget":
			parts.append(_p(ProcMesh.rounded_box(Vector3(0.3, 0.16, 0.2), 0.04, 2), Vector3(0, 0.08, 0)))
			parts.append(_p(ProcMesh.box(Vector3(0.16, 0.1, 0.01)), Vector3(-0.03, 0.09, 0.1), Vector3.ZERO, Color(0.2, 0.25, 0.3, 0.0)))
			parts.append(_p(ProcMesh.cyl(0.012, 0.012, 0.22, 6), Vector3(0.11, 0.26, -0.04), Vector3(0, 0, -15), SILVER))
			parts.append(_p(ProcMesh.sphere(0.03, 8, 4), Vector3(0.09, 0.07, 0.1), Vector3.ZERO, Color(1.0, 0.3, 0.3, 0.0)))
		"sock":
			parts.append(_p(ProcMesh.capsule(0.06, 0.34), Vector3(0, 0.06, 0), Vector3(0, 0, 90)))
			parts.append(_p(ProcMesh.capsule(0.065, 0.22), Vector3(0.15, 0.06, 0.08), Vector3(90, 0, 0)))
			parts.append(_p(ProcMesh.cyl(0.066, 0.066, 0.05, 10), Vector3(-0.12, 0.06, 0), Vector3(0, 0, 90), WHITE))
		"rag":
			parts.append(_p(ProcMesh.rounded_box(Vector3(0.42, 0.06, 0.32), 0.03, 2), Vector3(0, 0.03, 0), Vector3(0, 0, 4)))
			parts.append(_p(ProcMesh.rounded_box(Vector3(0.2, 0.05, 0.2), 0.02, 2), Vector3(0.1, 0.07, 0.05), Vector3(8, 30, 0)))
		_:
			parts.append(_p(ProcMesh.rounded_box(Vector3(0.3, 0.3, 0.3), 0.05, 2), Vector3(0, 0.15, 0)))
	return ProcMesh.merge(parts)
