class_name GardenGround
extends RefCounted
## What lies under each of a Garden's slots, from the towns loaded on the globe. A cell's slots
## are kept as they were (their order is what the save holds). A slot on a town's street,
## sidewalk and kerb or the yard pad (checked at the slot and MOUND_R round it) takes a planter
## (B41, plants/garden_planters.gd): a box on the street and the pad, a tree pit on the sidewalk
## and kerbs; the plant stands on the planter's soil. A slot whose centre lies inside a building
## takes nothing. The lots' kit ground patches (8 cm concrete plates on sand) are open ground with
## the mound and the plant on top of the plates; their kerb band takes a tree pit. Cached once the
## town is in (Garden clears the cache when a site is built).

const PAVED: Array[int] = [CityLayout.Surface.ROAD, CityLayout.Surface.SIDEWALK, CityLayout.Surface.BUILDING, CityLayout.Surface.YARD]
const MOUND_R: float = 0.7
const LOT_HALF: float = 9.0  # a town's lot ground patch (18 x 18 m)
const LOT_KERB_M: float = 0.8
const PLATE_TOP: float = 0.12

## Slot -> [on paving, lift (m), inside a building, GardenPlanters.Kind, the town's street axis].
var cache: Dictionary = {}
var _garden: Garden


func _init(garden: Garden) -> void:
	_garden = garden


## Slot s's ground: [on paving, lift (m), inside a building, planter kind, street axis].
func info(s: int) -> Array:
	if cache.has(s):
		return cache[s]
	var towns: Array = _towns()
	var out: Array = [false, 0.0, false, GardenPlanters.Kind.NONE, Vector3.ZERO]
	if towns.is_empty():
		return out  # no town loaded here yet: open ground (asked again when a site is built)
	var p: Vector3 = _garden.slot_pos[s]
	var centre: int = -1
	for t: Array in towns:
		var vs: TownSite = t[0]
		var loc: Vector3 = (t[1] as Transform3D) * p
		if Vector2(loc.x, loc.z).length() > vs.town_r + MOUND_R:
			continue
		out[4] = vs.global_transform.basis.x
		centre = maxi(centre, paved_surface(vs.layout, loc.x, loc.z))
		for o: Vector2 in [Vector2.ZERO, Vector2(MOUND_R, 0), Vector2(-MOUND_R, 0), Vector2(0, MOUND_R), Vector2(0, -MOUND_R)]:
			if paved(vs.layout, loc.x + o.x, loc.z + o.y):
				out[0] = true
		var lots: Variant = vs.get("_lots")
		for lot: Dictionary in lots if lots is Array else []:
			var d: Vector2 = (Vector2(loc.x, loc.z) - (lot["c"] as Vector2)).abs()
			var m: float = maxf(d.x, d.y)
			if m < LOT_HALF + MOUND_R:
				if m > LOT_HALF - LOT_KERB_M - MOUND_R:
					out[0] = true  # the patch's kerb band
				else:
					out[1] = PLATE_TOP
	out[2] = centre == CityLayout.Surface.BUILDING
	if bool(out[0]) and not bool(out[2]):
		out[3] = planter_kind(centre)
		out[1] = GardenPlanters.soil_top(int(out[3]))
	cache[s] = out
	return out


## Test and dev hook: sets slot s's ground as if a town said so.
func set_known(s: int, on_paving: bool, in_building: bool = false, kind: int = GardenPlanters.Kind.NONE) -> void:
	cache[s] = [on_paving, GardenPlanters.soil_top(kind), in_building, kind, Vector3.ZERO]


## The planter a paved slot takes by the surface at its centre (-1: open ground beside paving).
static func planter_kind(centre: int) -> int:
	if centre == CityLayout.Surface.ROAD or centre == CityLayout.Surface.YARD:
		return GardenPlanters.Kind.BOX
	return GardenPlanters.Kind.PIT


## Paving in a town layout at site-local (x, z): its streets (only round blocks the town kept),
## sidewalks and kerbs, the yard pad and building footprints.
static func paved(lay: CityLayout, x: float, z: float) -> bool:
	return paved_surface(lay, x, z) >= 0


## The paved surface (CityLayout.Surface) at site-local (x, z), or -1 for open ground.
static func paved_surface(lay: CityLayout, x: float, z: float) -> int:
	if lay == null:
		return -1
	var srf: int = lay.surface_at(x, z)
	if not srf in PAVED:
		return -1
	return srf if srf == CityLayout.Surface.YARD or lay.wild or lay.blocks.has(lay.block_key_at(x, z)) else -1


## [TownSite, inverse of its transform] for every loaded town on the globe.
func _towns() -> Array:
	var out: Array = []
	var sm: SiteManager = _garden.site_manager
	if sm == null:
		return out
	for pf: Variant in sm.prefabs:
		if not (pf is SitePrefab) or not is_instance_valid(pf) or (pf as SitePrefab).content == null:
			continue
		for c: Node in (pf as SitePrefab).content.get_children():
			if c is TownSite and (c as TownSite).layout != null and (c as Node3D).is_inside_tree():
				out.append([c, (c as Node3D).global_transform.affine_inverse()])
	return out
