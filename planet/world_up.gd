class_name WorldUp
extends RefCounted
## [orbE] "Up" for cameras and cinematics: the local radial up on a round planet (the world's
## SphereSurface, or Lumi's), Vector3.UP on the flat game. Cameras that used Vector3.UP or
## `+ Vector3(0, h, 0)` call this so they stay level on the globe.

static func at(world: Node, p: Vector3) -> Vector3:
	if world == null:
		return Vector3.UP
	var s: Variant = world.get("surface")
	if s is SphereSurface:
		return (s as SphereSurface).up_at(p)
	var patch: Variant = world.get("patch")
	if patch is Node and (patch as Node).get("sphere") is SphereSurface:
		return ((patch as Node).get("sphere") as SphereSurface).up_at(p)
	return Vector3.UP


## A horizontal direction at p (the part of d across the local up), normalized.
static func flat(world: Node, p: Vector3, d: Vector3) -> Vector3:
	var u: Vector3 = at(world, p)
	var h: Vector3 = d - u * d.dot(u)
	return h.normalized() if h.length() > 0.0001 else Vector3.ZERO
