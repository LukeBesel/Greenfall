class_name OrbitSave
extends RefCounted
## [orbB] The walkable globe's save (GameState.orbit), next to the flat district state, which an
## orbit run never rewrites until phase F. Layout (schema 2):
##   schema      int (this file's SCHEMA)
##   planet_id   "verdance" | "ochre" | ... (GlobeSpec), freq: grid subdivision frequency
##   seed        survey / terrain seed
##   cells_n     cell count (10·freq²+2)
##   planet      PlanetData.to_dict() (survey junk/state, packed)
##   cells       SphereCells.to_dict() (junk, state, level, flags, packed bytes)
##   field       SphereField.to_dict() (found parts, unlocked cells)
##   sites       [{cell, index}] the hub pads, in order (index 0 = start site)
##   hubs        {site index (str): {"level": int}} per-hub state (hub level for now)
##   hexes_paid  {cell (str): true} first-clean bonuses paid
##   hex_levels  HexLevels.persist() (sparse on the globe)
##   day_t       seconds of planet rotation
##   lumi        {at: [dx, dy, dz, h], fwd: [x, y, z], cargo: Patch cargo dict}
##   cubes       [JunkCube dict + at: [dx, dy, dz, h], basis: 9 floats]
##   migrated    "flat_v<N>" when it came from a flat save (OrbitMigrate)
## Every position is a unit direction plus height above the ground there (OrbitPlanet.to_dirh),
## never a flat x/z: it survives terrain and site changes and any planet size.

const SCHEMA: int = 2


## Upgrades an older orbit dict in place, one step at a time. Returns it.
static func migrate(od: Dictionary) -> Dictionary:
	var v: int = int(od.get("schema", 0))
	if od.is_empty():
		return od
	if v < 2:
		# schema 1 (B1 skeleton): Verdance only, no site list, no hub states. Sites are re-derived
		# from the survey (same seed and size give the same pads).
		if not od.has("planet_id"):
			od["planet_id"] = "verdance"
		if not od.has("freq"):
			od["freq"] = GlobeSpec.VERDANCE_FREQ
		if not od.has("hubs"):
			od["hubs"] = {}
		v = 2
	od["schema"] = v
	return od


static func sites_to_array(sites: Array[Dictionary]) -> Array:
	var out: Array = []
	for s: Dictionary in sites:
		out.append({"cell": int(s["cell"]), "index": int(s.get("index", out.size()))})
	return out


## The saved pad cells in order, or [] (re-derive).
static func site_cells(od: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for e: Variant in od.get("sites", []):
		if e is Dictionary:
			out.append(int((e as Dictionary).get("cell", -1)))
	return out


static func hub_level(od: Dictionary, site_index: int) -> int:
	var h: Variant = (od.get("hubs", {}) as Dictionary).get(str(site_index))
	return int((h as Dictionary).get("level", 1)) if h is Dictionary else 1
