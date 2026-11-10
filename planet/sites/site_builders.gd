class_name SiteBuilders
extends RefCounted
## [orbD] Which prefab each hub of a planet gets and how to build it. Everything comes from the
## planet's definition: its "sites" table lists the prefabs and `sites_script` builds them.
##
## The sites script is static. SiteBuilders uses the first of these hooks it finds:
##   build_site(parent, site_id, stage 1-5, restoration, opts)   may await; gets every option
##   build_async(parent, site_id, stage 1-5, restoration)        yields behind the loading screen
##   build(...) / place(...)                                     four or five arguments, in the
##       order the signature shows (site id or parent first; a fifth Dictionary gets {seed})
## and, to change a built site in place:
##   restyle_site(content, stage 1-5, restoration) -> bool
##   else a child of the content with set_state(stage 0-2, restoration)
## Stage is always the base level 1..5 here; a `place` builder's 0..2 is mapped (1 -> 0, 2-3 -> 1,
## 4-5 -> 2). A planet id of "" means the planet being played.


## The definition of a planet id ("" = the current planet), or null when it is not registered.
static func definition(planet_id: String = "") -> PlanetDefinition:
	return Planets.current() if planet_id == "" else Planets.by_id(planet_id)


## The planet's "sites" table ({} when it has none).
static func table(planet_id: String = "") -> Dictionary:
	var def: PlanetDefinition = definition(planet_id)
	return def.table("sites") if def else {}


## The planet's site prefab list: [{id, kind, size_m, clear_core_m, ...}], hubs first.
static func sites_of(planet_id: String = "") -> Array:
	var out: Array = []
	var raw: Variant = table(planet_id).get("sites", [])
	for s: Variant in raw if raw is Array else []:
		if s is Dictionary:
			out.append((s as Dictionary).duplicate())
	var hubs: Array = out.filter(func(d: Dictionary) -> bool: return str(d.get("kind", "hub")) == "hub")
	var rest: Array = out.filter(func(d: Dictionary) -> bool: return str(d.get("kind", "hub")) != "hub")
	return hubs + rest


static func find(planet_id: String, site_id: String) -> Dictionary:
	for d: Dictionary in sites_of(planet_id):
		if str(d.get("id", "")) == site_id:
			return d
	return {}


## The prefab a hub gets: hub 0 the planet's first hub site; the others cycle through the hub
## sites that are not `start_only`.
static func site_for_hub(planet_id: String, hub_index: int) -> String:
	var list: Array = sites_of(planet_id)
	if list.is_empty():
		return ""
	var hubs: Array = list.filter(func(d: Dictionary) -> bool: return str(d.get("kind", "hub")) == "hub")
	if hubs.is_empty():
		hubs = list
	if hub_index == 0:
		return str(hubs[0]["id"])
	var cycle: Array = hubs.filter(func(d: Dictionary) -> bool: return not bool(d.get("start_only", false)))
	if cycle.is_empty() or cycle.size() == hubs.size():
		return str(hubs[hub_index % hubs.size()]["id"])
	return str(cycle[(hub_index - 1) % cycle.size()]["id"])


## Flat pad radius (m) of the planet's hubs after the first, or `fallback` when its table has none.
static func hub_pad_m(planet_id: String, fallback: float) -> float:
	return float(table(planet_id).get("hub_pad_m", fallback))


## Whether the planet's start yard keeps junk off its pad piece by piece (YardKeepOut).
static func has_yard_keep_out(planet_id: String = "") -> bool:
	return bool(table(planet_id).get("yard_keep_out", false))


## Builds what the planet puts on the land between its sites (the sites script's
## build_surroundings(ctx) hook), or returns null when the planet has none. ctx: {parent, grid,
## terrain, cells, hubs (unit directions), seed, keep_out, focus}.
static func build_surroundings(planet_id: String, ctx: Dictionary) -> Node3D:
	var def: PlanetDefinition = definition(planet_id)
	if def == null:
		return null
	return PlanetDefinition.call_hook(def.sites_script, "build_surroundings", [ctx]) as Node3D


## Builds a hub site prefab on a globe (or in a preview) and returns its SitePrefab.
##   site_root    any Node3D; set to `site.transform` (the pad's frame) when the site has one, and
##                the prefab is added under it, built in site-local metres (+Y up, y = 0 on the pad)
##   site         SphereTerrain.reserve_site's result ({transform, flat, blend, cells, ...}) plus
##                optional keys: planet (id, default the current planet), prefab (site id, default
##                the planet's site for hub_index), hub_index, seed, name
##   stage        base level 1..5 (ruin 1, fixed up 2-3, futuristic 4-5)
##   restoration  0..1 (mean hex level of the hub's region)
## The prefab has anchors (depot, bench, rocket_pad, door), collision, set_stage/set_restoration.
## Builders run synchronously unless a BuildBudget is open (then await prefab.rebuilt).
static func build_site(site_root: Node3D, site: Dictionary, stage: int, restoration: float) -> SitePrefab:
	var def: PlanetDefinition = definition(str(site.get("planet", "")))
	var pid: String = String(def.id) if def else str(site.get("planet", ""))
	var hub_i: int = int(site.get("hub_index", 0))
	var p := SitePrefab.new()
	p.planet_id = pid
	p.site_id = str(site.get("prefab", site_for_hub(pid, hub_i)))
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
	var opts: Dictionary = {"hub_index": hub_i, "seed": int(site.get("seed", def.world_seed if def else 0)), "name": str(site.get("name", ""))}
	if site.get("water_fn") is Callable:  # [v3city] towns keep off the lakes
		opts["water"] = site["water_fn"]
	if site.has("flat") and bool(table(pid).get("fill_pad", false)):
		opts["flat"] = float(site["flat"])  # [v3city] the site fills its pad
	if site.get("globe_ctx") is Dictionary:
		opts["globe"] = site["globe_ctx"]
	configure(p, opts)  # a planet without this site or a sites script gets a bare pad with the default anchors
	p.build()
	return p


## Wires prefab.builder / restyler for prefab.planet_id / prefab.site_id.
static func configure(p: SitePrefab, opts: Dictionary = {}) -> bool:
	var d: Dictionary = find(p.planet_id, p.site_id)
	if d.is_empty():
		push_warning("SiteBuilders: no site '%s' on '%s'" % [p.site_id, p.planet_id])
		return false
	p.kind = str(d.get("kind", "hub"))
	p.size_m = float(d.get("size_m", 90.0))
	p.clear_core_m = float(d.get("clear_core_m", 12.0))
	var sid: String = p.site_id
	var def: PlanetDefinition = definition(p.planet_id)
	var scr: Script = def.sites_script if def else null
	if scr == null:
		push_warning("SiteBuilders: no sites script for '%s' on '%s'" % [sid, p.planet_id])
		return false
	p.builder = func(parent: Node3D, st: int, r: float) -> void:
		if PlanetDefinition.has_hook(scr, "build_site"):
			await scr.call("build_site", parent, sid, st, r, opts)
			return
		if PlanetDefinition.has_hook(scr, "build_async"):  # [orbE] yields behind the loading screen
			await scr.call("build_async", parent, sid, st, r)
			return
		_call_external(scr, parent, sid, st, r, opts)
	p.restyler = func(content: Node3D, st: int, r: float) -> bool:
		if PlanetDefinition.has_hook(scr, "restyle_site"):
			return bool(scr.call("restyle_site", content, st, r))
		for c: Node in content.get_children():
			if c.has_method("set_state"):  # a `place` site: stage 0..2
				c.call("set_state", place_stage(st), r)
				return true
		return false
	return true


## A `place` builder's stage (0 ruin, 1 restored, 2 futuristic) from a base level.
static func place_stage(level: int) -> int:
	return 0 if level <= 1 else (1 if level <= 3 else 2)


## Calls the planet's static build/place with the argument order its signature uses.
static func _call_external(scr: Script, parent: Node3D, sid: String, st: int, r: float, opts: Dictionary) -> void:
	for m: Dictionary in scr.get_script_method_list():
		var nm: String = str(m.get("name", ""))
		if nm != "build" and nm != "place":
			continue
		var args: Array = m.get("args", [])
		if args.size() < 4:
			continue
		var first_string: bool = int((args[0] as Dictionary).get("type", TYPE_NIL)) == TYPE_STRING
		var stage_v: int = place_stage(st) if nm == "place" else st
		var call_args: Array = [sid, parent, stage_v, r] if first_string else [parent, sid, stage_v, r]
		if args.size() >= 5 and int((args[4] as Dictionary).get("type", TYPE_NIL)) == TYPE_DICTIONARY:
			call_args.append({"seed": int(opts.get("seed", hash(sid) % 100000))})
		scr.callv(nm, call_args)
		return
	push_warning("SiteBuilders: %s has no static build/place(…4 args)" % scr.resource_path)
