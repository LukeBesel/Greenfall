class_name SitePrefab
extends Node3D
## [orbD] One hub (or landmark) site on a walkable globe: the node SiteBuilders.build_site returns.
## It sits at the site's transform (origin on the level pad, +Y = surface normal, x east, z south)
## and holds the planet's own prefab built in site-local metres, plus:
## - anchors: Marker3D children under "Anchors" named depot, bench, rocket_pad, door (and any extra
##   ones a builder adds). anchor(name) / anchor_xf(name) find them; the defaults keep to the
##   prefab's clear core, so the hub's own machines never land inside a building.
## - collision: one StaticBody3D (layer 1, which SphereMotor's ground ray reads) with trimesh
##   shapes of the prefab's solid meshes, unless the builder made its own bodies.
## - set_stage(level 1..5) / set_restoration(0..1): live re-dress. Builders that can re-dress in
##   place (a `place` site's set_state, a sites script's restyle_site) do;
##   the rest are rebuilt.

signal rebuilt
## Anchors moved out of the prefab's geometry (SiteReach.fix_anchors): re-read them.
signal anchors_moved(names: PackedStringArray)

const ANCHORS: Array[String] = ["depot", "bench", "rocket_pad", "door"]
## Meshes lower than this (m) get no collider: decals, puddles, ground patches and thin litter.
const MIN_COLLIDE_H: float = 0.9

## [orbD] The start yard's machines and Hub builds (owner rules: the
## yard starts with only the pod, the broken bench and the bin; interactables at least 3 m apart;
## the lane north out of the yard, |x| < 2.5 m, stays open). East: depot, bin, stations, radio,
## signal tower. West: bench (shack over it), generator, composter, locker, camera
## bot, nursery. The pod sits behind Lumi's spawn at (0, 6). Lamps on the yard's corners.
const START_YARD_ANCHORS: Dictionary = {
	"pod": [Vector3(0, 0, 9.8), 0.0],
	# [v1yard] The trash bin (the depot and its bin's reach) on the west side, 5.5 m from the bench,
	# in a marked, lit bay on the pad's edge: trash, bin and bench a few steps apart.
	"depot": [Vector3(-8.0, 0, 2.0), PI * 0.5],
	"bin": [Vector3(-8.0, 0, -1.3), PI * 0.5],
	"stations": [Vector3(16.5, 0, 1.5), 0.0],  # out on the street east of the yard (flat: "keep the base yard free")
	"radio": [Vector3(5.0, 0, -1.5), -PI * 0.5],
	"signal_tower": [Vector3(8.0, 0, -7.5), -PI * 0.5],
	"telescope": [Vector3(4.8, 0, -9.0), 0.0],
	"shack": [Vector3(-7.35, 0, 7.5), PI * 0.5],  # over the bench: the flat lean-to has it 0.65 m in from its centre
	"fabricator": [Vector3(-6.0, 0, -9.6), 0.0],
	"generator": [Vector3(-5.0, 0, 9.5), PI],
	"composter": [Vector3(8.5, 0, 3.8), -PI * 0.5],  # [v1yard] east, where the depot was
	"locker": [Vector3(8.5, 0, 0.2), -PI * 0.5],
	"camera_bot": [Vector3(-5.0, 0, -2.0), PI * 0.5],
	"nursery": [Vector3(-7.5, 0, -5.5), PI * 0.5],
	"lamps_0": [Vector3(-3.6, 0, -10.0), 0.0],
	"lamps_1": [Vector3(3.6, 0, -10.0), 0.0],
	"lamps_2": [Vector3(-10.2, 0, 10.2), 0.0],
	"lamps_3": [Vector3(10.2, 0, 10.2), 0.0],
}

var planet_id: String = ""
var site_id: String = ""
var kind: String = "hub"
var stage: int = 1
var restoration: float = 0.0
var size_m: float = 90.0
var clear_core_m: float = 12.0
## The globe site this stands on (SphereTerrain.reserve_site), {} in a preview.
var site: Dictionary = {}
## Builds the content under the given parent: func(parent: Node3D, stage: int, restoration: float) -> Node3D.
var builder: Callable
## Re-dresses in place: func(content: Node3D, stage: int, restoration: float) -> bool (false: rebuild).
var restyler: Callable
var content: Node3D
var anchors_root: Node3D
var body: StaticBody3D
var build_ms: int = 0
var is_built: bool = false
## [orbD] A start site: the yard's anchors (START_YARD_ANCHORS) fill in where the
## planet's own prefab has none.
var start_yard: bool = false
## Anchors the planet's own builder laid out (anchors()): fix_anchors leaves them where they are.
var designed := PackedStringArray()


func _init() -> void:
	anchors_root = Node3D.new()
	anchors_root.name = "Anchors"
	add_child(anchors_root)


## Builds (or rebuilds) the content and its collision.
func build() -> void:
	var t0: int = Time.get_ticks_msec()
	is_built = false
	designed = PackedStringArray()
	if content:
		content.free()
		content = null
	if body:
		body.free()
		body = null
	var holder := Node3D.new()
	holder.name = "Content"
	add_child(holder)
	if builder.is_valid():
		await builder.call(holder, stage, restoration)
	content = holder
	if not _has_own_bodies(holder):
		body = collision_for(holder, self)
	_default_anchors()
	build_ms = Time.get_ticks_msec() - t0
	is_built = true
	rebuilt.emit()


func set_stage(l: int) -> void:
	l = clampi(l, 1, 5)
	if l == stage:
		return
	stage = l
	_restyle()


func set_restoration(r: float) -> void:
	r = clampf(r, 0.0, 1.0)
	if absf(r - restoration) < 0.001:
		return
	restoration = r
	_restyle()


func set_state(l: int, r: float) -> void:
	stage = clampi(l, 1, 5)
	restoration = clampf(r, 0.0, 1.0)
	_restyle()


func _restyle() -> void:
	if content and restyler.is_valid() and bool(restyler.call(content, stage, restoration)):
		return
	build()


# --- Anchors ----------------------------------------------------------------------------------

## Adds (or moves) a named anchor at a site-local position facing yaw (radians, 0 = -Z north).
func set_anchor(nm: String, pos: Vector3, yaw: float = 0.0) -> Marker3D:
	var m: Marker3D = anchors_root.get_node_or_null(nm) as Marker3D
	if m == null:
		m = Marker3D.new()
		m.name = nm
		anchors_root.add_child(m)
	m.position = pos
	m.rotation = Vector3(0, yaw, 0)
	return m


func anchor(nm: String) -> Marker3D:
	return anchors_root.get_node_or_null(nm) as Marker3D


## Global transform of an anchor (the site origin if it is missing).
func anchor_xf(nm: String) -> Transform3D:
	var m: Marker3D = anchor(nm)
	return m.global_transform if m and m.is_inside_tree() else (global_transform * m.transform if m else global_transform)


## Site-local anchor transform (works before the node is in the tree).
func anchor_local(nm: String) -> Transform3D:
	var m: Marker3D = anchor(nm)
	return m.transform if m else Transform3D.IDENTITY


func anchor_names() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Node in anchors_root.get_children():
		out.append(String(c.name))
	return out


## Fills the standard anchors a builder did not set, inside the clear core: the depot east of
## the centre, the bench west, the pod door south and the rocket pad north.
func _default_anchors() -> void:
	var r: float = maxf(clear_core_m, 9.0)
	var defaults: Dictionary = {
		"depot": [Vector3(r * 0.5, 0, r * 0.3), -PI * 0.5],
		"bench": [Vector3(-r * 0.5, 0, r * 0.3), PI * 0.5],
		"door": [Vector3(0, 0, r * 0.7), 0.0],
		"rocket_pad": [Vector3(0, 0, -r * 0.65), 0.0],
	}
	if content:  # a builder's own anchors win: func anchors() -> {name: [Vector3, yaw]}
		for c: Node in content.get_children():
			if c.has_method("anchors"):
				var own: Dictionary = c.call("anchors")
				for nm: String in own:
					set_anchor(nm, own[nm][0], own[nm][1])
					designed.append(nm)
	if start_yard:
		for nm: String in START_YARD_ANCHORS:
			if anchor(nm) == null:
				var e: Array = START_YARD_ANCHORS[nm]
				set_anchor(nm, e[0], e[1])
	for nm: String in defaults:
		if anchor(nm) == null:
			set_anchor(nm, defaults[nm][0], defaults[nm][1])


# --- Collision --------------------------------------------------------------------------------

static func _has_own_bodies(n: Node) -> bool:
	return not n.find_children("*", "StaticBody3D", true, false).is_empty()


## One StaticBody3D under `owner_node` with a trimesh shape per solid mesh of `root` (in the
## owner's space). MultiMeshes (junk, plants, litter) get none.
static func collision_for(root: Node3D, owner_node: Node3D) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "SiteBody"
	sb.collision_layer = 1
	sb.collision_mask = 0
	owner_node.add_child(sb)
	var inv: Transform3D = owner_node.global_transform.affine_inverse() if owner_node.is_inside_tree() else Transform3D.IDENTITY
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null or not mi.visible:
			continue
		var ab: AABB = mi.mesh.get_aabb()
		if ab.size.y < MIN_COLLIDE_H or mi.has_meta("no_collide"):
			continue
		var shape: Shape3D = mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = _rel_xf(mi, owner_node, inv)
		sb.add_child(cs)
	return sb


static func _rel_xf(n: Node3D, owner_node: Node3D, inv: Transform3D) -> Transform3D:
	if n.is_inside_tree() and owner_node.is_inside_tree():
		return inv * n.global_transform
	var xf: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p and p != owner_node:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
