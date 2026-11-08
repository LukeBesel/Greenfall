class_name PlanetEnvs
extends RefCounted
## [planet-rime] Registry of the campaign planets' environment scripts (data/planets.json, a dict
## keyed by planet id). Each entry names an `env` script with static entry points:
##   dev_hub(planet: PlanetData) -> int          which hub the --planet-env dev hook loads
##   prepare_field(field: HexField) -> void       before HexField.generate (biome junk set)
##   dress_view(view: FieldView) -> void          before FieldView.setup (ground layers, fx)
##   apply(world: Node, field: HexField, kind: Dictionary) -> void   once the scene is built
## Missing entry points are skipped, so an env only needs apply().

const PATH := "res://data/planets.json"

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty() and FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_cache = d
	return _cache


## The planet's entry (with "id" filled in), or {} if unknown.
static func entry(id: String) -> Dictionary:
	var e: Variant = all().get(id, {})
	if not (e is Dictionary) or (e as Dictionary).is_empty():
		if id != "":
			push_warning("PlanetEnvs: no planet '%s' in %s" % [id, PATH])
		return {}
	var out: Dictionary = (e as Dictionary).duplicate(true)
	out["id"] = id
	return out


## Calls a static entry point of the entry's env script; returns its result (null if absent).
static func call_env(e: Dictionary, fn: String, args: Array) -> Variant:
	if e.is_empty():
		return null
	var path: String = str(e.get("env", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scr: Script = load(path)
	if scr == null:
		return null
	var found: bool = false
	for m: Dictionary in scr.get_script_method_list():
		if str(m.get("name", "")) == fn:
			found = true
			break
	if not found:
		return null
	return scr.callv(fn, args)


## The hub the dev hook loads: the env's dev_hub(planet), else the current one.
static func dev_hub(e: Dictionary, planet: PlanetData) -> int:
	var h: Variant = call_env(e, "dev_hub", [planet])
	return int(h) if h is int else GameState.current_hub


# --- [orbD] Hub sites on the walkable globes ------------------------------------------------

## Defaults when a planet's entry has no `globe` block yet (owner, Nov 8: radius vs Verdance's
## 1.84 km and hub count by area). data/planets.json `globe` {radius_m, hub_count} wins.
const GLOBE_DEFAULTS: Dictionary = {
	"verdance": {"radius_scale": 1.0, "hub_count": 10},
	"ochre": {"radius_scale": 0.85, "hub_count": 8},
	"tidewell": {"radius_scale": 1.1, "hub_count": 12},
	"rime": {"radius_scale": 1.2, "hub_count": 13},
	"anvil": {"radius_scale": 1.35, "hub_count": 16},
}
const VERDANCE_R: float = 1840.0


## A planet's globe size: {radius_m, hub_count}. Reads `globe` from data/planets.json (any of
## radius_m / radius_scale / hub_count / hubs), else the owner's defaults.
static func globe(id: String) -> Dictionary:
	var d: Dictionary = GLOBE_DEFAULTS.get(id, GLOBE_DEFAULTS["verdance"])
	var e: Variant = all().get(id)
	if e is Dictionary and (e as Dictionary).get("globe") is Dictionary:
		var g: Dictionary = GlobeSpec.of(id)  # orbB's per-planet sizes (frequency is the truth)
		return {"radius_m": VERDANCE_R * float(g["frequency"]) / float(GlobeSpec.VERDANCE_FREQ), "hub_count": int(g["hub_count"])}
	return {"radius_m": VERDANCE_R * float(d["radius_scale"]), "hub_count": int(d["hub_count"])}


## Builds a hub site prefab on a globe (or in a preview) and returns its SitePrefab.
##   site_root    any Node3D; set to `site.transform` (the pad's frame) when the site has one, and
##                the prefab is added under it, built in site-local metres (+Y up, y = 0 on the pad)
##   site         SphereTerrain.reserve_site's result ({transform, flat, blend, cells, ...}) plus
##                optional keys: planet (id, default verdance), prefab (site id, default the
##                planet's site for hub_index), hub_index, seed, name
##   stage        base level 1..5 (ruin 1, fixed up 2-3, futuristic 4-5)
##   restoration  0..1 (mean hex level of the hub's region)
## The prefab has anchors (depot, bench, rocket_pad, door), collision, set_stage/set_restoration.
## Builders run synchronously unless a BuildBudget is open (then await prefab.rebuilt).
static func build_site(site_root: Node3D, site: Dictionary, stage: int, restoration: float) -> SitePrefab:
	var pid: String = str(site.get("planet", "verdance"))
	var hub_i: int = int(site.get("hub_index", 0))
	var p := SitePrefab.new()
	p.planet_id = pid
	p.site_id = str(site.get("prefab", SiteBuilders.site_for_hub(pid, hub_i)))
	p.name = "Site_%s_%d" % [p.site_id, hub_i]
	p.site = site
	p.stage = clampi(stage, 1, 5)
	p.restoration = clampf(restoration, 0.0, 1.0)
	p.start_yard = hub_i == 0  # the start yard's machines need their anchors on every planet
	if site.has("transform"):
		if site_root.is_inside_tree():
			site_root.global_transform = site["transform"]
		else:
			site_root.transform = site["transform"]
	site_root.add_child(p)
	var opts: Dictionary = {"hub_index": hub_i, "seed": int(site.get("seed", 4471)), "name": str(site.get("name", ""))}
	if site.get("water_fn") is Callable:  # [v3city] Verdance's towns keep off the lakes
		opts["water"] = site["water_fn"]
	if site.has("flat") and pid in ["verdance", ""]:
		opts["flat"] = float(site["flat"])  # [v3city] the town fills its pad
	if site.get("globe_ctx") is Dictionary:
		opts["globe"] = site["globe_ctx"]
	if SiteBuilders.configure(p, opts):
		p.build()
	return p
