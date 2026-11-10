class_name FrontierView
extends RefCounted
## The names the later planets' site code (planets/*) still uses for the mesh batcher, from
## when it lived with the frontier district visuals. It is MaterialBatch (planet/material_batch.gd) now.


class Batch:
	extends MaterialBatch


static func _beam_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	return MaterialBatch.beam_xf(a, b, thick)
