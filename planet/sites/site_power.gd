class_name SitePower
extends RefCounted
## [orbD] Street power at hub sites on the walkable globe: the flat rule (planet/street_power.gd,
## world3) unchanged. Every street lamp head and every powered dressing light of a Verdance site
## starts dead and comes on when its globe cell's hex level reaches Sustained, or round the base
## (30 m) once that hub reaches level 3, with PowerFx's flicker. A StreetPower lives in each
## site's own frame; it finds its lights' cells through CellLookup, a tiny HexField whose
## owner_hex maps site-local points to globe cell ids (what HexLevels keys on the globe).
## The globe's one difference: a site's own cells are hub cells, which HexLevels never tracks, so a
## light standing on one follows the best-levelled land cell within three rings of it (the streets
## round the site), and every light of the site is on from hub level 4.


## owner_hex for site-local points: the globe cell under them (StreetPower calls nothing else).
class CellLookup:
	extends HexField
	var grid: SphereGrid
	var site: Node3D

	func _init(p_grid: SphereGrid, p_site: Node3D) -> void:
		super(0, 10.0, 4471)
		grid = p_grid
		site = p_site

	func owner_hex(p: Vector3) -> int:
		return grid.cell_at(site.global_transform * p) if site.is_inside_tree() else -1


## StreetPower with the site-cell fallback above (powered() is the flat rule first).
class SiteLights:
	extends StreetPower
	const SITE_ALL: int = 4
	var grid: SphereGrid
	var life: TownLife  # [v6life] the town's blocks wake up as they are cleaned and planted

	func powered(g: Dictionary) -> bool:
		if super(g):
			return true
		if life and is_instance_valid(life) and life.lights_on(g):  # [v6life]
			return true
		var h: int = int(g["hex"])
		if h < 0 or hex_levels == null or hex_levels.level_of(h) >= 0:
			return false
		if hub_level >= SITE_ALL:
			return true
		if not g.has("near"):
			g["near"] = grid.cells_around(h, 3)
		for c: int in g["near"]:
			if hex_levels.level_of(c) >= SUSTAINED:
				return true
		return false


## Builds the site's StreetPower from its CityView lamp heads and StreetDressing power groups.
## Returns null when the site has no street lights (other planets' prefabs).
static func attach(vs: Node3D, grid: SphereGrid, hex_levels: Node, hub_level: int) -> StreetPower:
	var city: Variant = vs.get("city")
	var dressing: Variant = vs.get("dressing")
	var bulbs: Array = (city as Object).get("lamp_bulbs") if city else []
	var groups: Array = (dressing as Object).get("power_groups") if dressing else []
	if bulbs.is_empty() and groups.is_empty():
		return null
	var sp := SiteLights.new()
	sp.name = "StreetPower"
	sp.grid = grid
	vs.add_child(sp)
	sp.setup(CellLookup.new(grid, vs), hex_levels as HexLevels, hub_level)
	if not bulbs.is_empty():
		sp.add_bulbs(bulbs)
	if not groups.is_empty():
		sp.add_groups(groups)
	sp.apply(false)
	var tl: Variant = vs.get_node_or_null("TownLife")  # [v6life] per block: lamps when clean, signs when planted
	if tl is TownLife:
		sp.life = tl
		(tl as TownLife).settled.connect(func() -> void: sp.apply(false))
		(tl as TownLife).stage_changed.connect(func(_k: Vector2i, _s: int) -> void: sp.apply(true))
	if DevHooks.has("power-report"):
		var t: float = DevHooks.get_f("power-report", 6.0)
		var wr: WeakRef = weakref(sp)
		var site_name: String = vs.name
		for k: int in 2:
			sp.get_tree().create_timer(t * (k + 1)).timeout.connect(func() -> void:
				var p: StreetPower = wr.get_ref() as StreetPower
				if p:
					print("[power] %s: %d lights, %d lit (hub level %d)" % [site_name, p.group_count(), p.lit_count(), p.hub_level]))
	return sp
