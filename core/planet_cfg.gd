class_name PlanetCfg
extends RefCounted
## [v7planet] One place for "which planet is this, and what does its data say" (owner items 62
## and 71: more planets built the way Verdance was, everything adjustable). data/planets.json is
## keyed by planet id; its "_default" block holds what a planet gets when its own block leaves a
## key out, the same pattern as data/life.json. A planet block repeats only what it changes.
## See docs/NEW_PLANET.md (the recipe) and docs/ADJUSTING.md.
##
##   PlanetCfg.entry(id)            "_default" with the planet's block deep-merged on top ({} if unknown)
##   PlanetCfg.value(id, key, def)  one top-level key of that
##   PlanetCfg.uses_towns(id)       the planet's hubs are VerdanceSite towns (site_kit "towns"),
##                                  not a planet's own site prefabs (site_kit "prefab", `sites`)
##   PlanetCfg.is_dev(id)           a dev/test planet ("dev": true): reachable by --orbit-planet only
##   PlanetCfg.ids()                every planet id in the file (dev ones with include_dev)
##   PlanetCfg.current              the planet the globe is built for (SliceOrbit sets it)
##   PlanetCfg.use_planet(id)       points the per-planet lookups (life, hubs, sky, sound) at it
##   PlanetCfg.problems(id)         what a planet's data lacks or gets wrong ([] when fine)

const PATH: String = "res://data/planets.json"
const SITE_KITS: Array[String] = ["towns", "prefab"]
const PLANET_THEMES := preload("res://audio/planet_themes.gd")  # the built-in scores

## The planet the globe slice is built for ("" before the first globe).
static var current: String = ""


static func all() -> Dictionary:
	return PlanetEnvs.all()


## Every planet id in the file, in file order. Dev planets only with include_dev.
static func ids(include_dev: bool = false) -> Array[String]:
	var out: Array[String] = []
	for k: Variant in all():
		var id: String = str(k)
		if id.begins_with("_") or not (all()[k] is Dictionary):
			continue
		if not include_dev and is_dev(id):
			continue
		out.append(id)
	return out


static func has(id: String) -> bool:
	return id != "" and not id.begins_with("_") and all().get(id) is Dictionary


static func defaults() -> Dictionary:
	var d: Variant = all().get("_default", {})
	return d if d is Dictionary else {}


## "_default" with the planet's own block on top (dictionaries merge key by key, all the way
## down; lists and values replace). "id" is filled in. {} for an unknown id.
static func entry(id: String) -> Dictionary:
	if not has(id):
		return {}
	var out: Dictionary = defaults().duplicate(true)
	out.erase("_doc")
	deep_merge(out, all()[id] as Dictionary)
	out["id"] = id
	return out


static func value(id: String, key: String, def: Variant = null) -> Variant:
	var e: Dictionary = entry(id) if has(id) else defaults()
	return e.get(key, def)


## One block (a dictionary key) for a planet: "_default".<key> with the planet's on top.
static func block(id: String, key: String) -> Dictionary:
	var out: Dictionary = {}
	var d: Variant = defaults().get(key)
	if d is Dictionary:
		out = (d as Dictionary).duplicate(true)
	var p: Variant = (all().get(id, {}) as Dictionary).get(key) if all().get(id) is Dictionary else null
	if p is Dictionary:
		deep_merge(out, p as Dictionary)
	return out


static func deep_merge(into: Dictionary, over: Dictionary) -> void:
	for k: Variant in over:
		var v: Variant = over[k]
		if v is Dictionary and into.get(k) is Dictionary:
			var sub: Dictionary = (into[k] as Dictionary).duplicate(true)
			deep_merge(sub, v as Dictionary)
			into[k] = sub
		else:
			into[k] = (v as Dictionary).duplicate(true) if v is Dictionary else (v.duplicate(true) if v is Array else v)


static func is_dev(id: String) -> bool:
	return has(id) and bool((all()[id] as Dictionary).get("dev", false))


## How the planet's hubs are built: "towns" (VerdanceSite: towns, hinterland, harbours, the start
## yard) or "prefab" (the planet's own site scripts, listed in its `sites`). An entry without
## site_kit is "prefab" when it lists `sites`, else "_default".site_kit ("towns"). Unknown ids
## and "" are Verdance's ("towns").
static func site_kit(id: String) -> String:
	if not has(id):
		return "towns"
	var own: Dictionary = all()[id]
	if own.has("site_kit"):
		return str(own["site_kit"])
	if own.has("sites"):
		return "prefab"
	return str(defaults().get("site_kit", "towns"))


static func uses_towns(id: String) -> bool:
	return site_kit(id) == "towns"


## The land between hub towns (planet/sites/hinterland.gd): on for "towns" planets unless the
## entry says "hinterland": false.
static func has_hinterland(id: String) -> bool:
	return uses_towns(id) and bool(value(id, "hinterland", true))


## The planet's name as data gives it (English; tr() at display).
static func name_of(id: String) -> String:
	return str(value(id, "name", id.capitalize()))


## The globe's look (ground textures and tints): "_default".look with the planet's on top.
static func look(id: String) -> Dictionary:
	return block(id, "look")


## Points every per-planet lookup at the planet the globe is built for. Safe to call again.
## Verdance gets exactly what it had before (its block, or the "verdance" fallbacks).
static func use_planet(id: String) -> void:
	current = id
	LifeCfg.use_planet(id)
	HubPlan.active_planet = id  # the start yard is built before HubPurpose comes up; it reads the plan


## The current globe's planet, or `fallback` before any globe was built.
static func current_or(fallback: String = "verdance") -> String:
	return current if current != "" else fallback


# --- Checks (tests/test_planet_data.gd, docs/NEW_PLANET.md) ------------------------------------

## What a planet's data lacks or gets wrong: [] when it can be built. English, for tests and tools.
static func problems(id: String) -> Array[String]:
	var out: Array[String] = []
	if not has(id):
		out.append("%s: no block in %s" % [id, PATH])
		return out
	var own: Dictionary = all()[id]
	var e: Dictionary = entry(id)
	if str(own.get("name", "")) == "":
		out.append("%s: no name" % id)
	var g: Variant = own.get("globe")
	if not (g is Dictionary) or not ((g as Dictionary).has("frequency") or (g as Dictionary).has("radius")):
		out.append("%s: no globe {frequency or radius, hub_count}" % id)
	elif not (g as Dictionary).has("hub_count"):
		out.append("%s: globe has no hub_count" % id)
	var kit: String = site_kit(id)
	if not SITE_KITS.has(kit):
		out.append("%s: site_kit '%s' is not one of %s" % [id, kit, SITE_KITS])
	if SiteBuilders.sites_of(id).is_empty():
		out.append("%s: no site prefabs (site_kit '%s')" % [id, kit])
	var hubs_n: int = int(GlobeSpec.of(id)["hub_count"])
	var hs: Variant = own.get("hubs", [])
	if kit == "towns" and (not (hs is Array) or (hs as Array).is_empty()):
		out.append("%s: a towns planet needs hubs[] (names, towns, landmarks)" % id)
	if hs is Array and not (hs as Array).is_empty():
		var homes: int = 0
		var orders: Dictionary = {}
		var sites_seen: Dictionary = {}
		for h: Variant in hs:
			if not (h is Dictionary):
				continue
			var hd: Dictionary = h
			var hid: String = str(hd.get("id", "?"))
			if not hd.has("site") or not hd.has("order") or str(hd.get("name", "")) == "":
				out.append("%s hub %s: needs site, order and name" % [id, hid])
				continue
			homes += 1 if bool(hd.get("home", false)) else 0
			var site: int = int(hd["site"])
			if site < 0 or site >= hubs_n:
				out.append("%s hub %s: site %d is outside the globe's %d hubs" % [id, hid, site, hubs_n])
			if sites_seen.has(site):
				out.append("%s hub %s: site %d used twice" % [id, hid, site])
			sites_seen[site] = true
			if orders.has(int(hd["order"])):
				out.append("%s hub %s: order %d used twice" % [id, hid, int(hd["order"])])
			orders[int(hd["order"])] = true
			var town: String = str(hd.get("town", ""))
			if kit == "towns" and town != "" and not HubPlan.TOWN_NAMES.has(town):
				out.append("%s hub %s: town '%s' is not one of %s" % [id, hid, town, HubPlan.TOWN_NAMES.keys()])
			var lm: Variant = hd.get("landmark", {})
			var kind: String = str((lm as Dictionary).get("kind", "")) if lm is Dictionary else ""
			if kit == "towns" and kind == "":
				out.append("%s hub %s: no landmark.kind" % [id, hid])
			elif kind != "" and not landmark_kinds().has(kind):
				out.append("%s hub %s: landmark '%s' is not one of %s" % [id, hid, kind, landmark_kinds()])
		if homes != 1:
			out.append("%s: %d home hubs (needs exactly one, \"home\": true, at site 0)" % [id, homes])
		var hd0: Dictionary = (e.get("hub_defaults", {}) as Dictionary) if e.get("hub_defaults") is Dictionary else {}
		if int(hd0.get("main_path", 1)) > (hs as Array).size():
			out.append("%s: hub_defaults.main_path %d is more than its %d hubs" % [id, int(hd0.get("main_path", 1)), (hs as Array).size()])
	# Sound: a theme the built-in score knows, from the planet's block or "_default".
	var th: String = SoundCfg.theme_of(id)
	if not PLANET_THEMES.IDS.has(th):
		out.append("%s: sound theme '%s' unknown (data/sound.json planets.%s.theme or planets._default.theme)" % [id, th, id])
	# Campaign planets are in the Homeward list (the system map, the leave gate, the economy);
	# dev planets never are.
	var k: int = Homeward.planet_index(id)
	if is_dev(id) and k >= 0:
		out.append("%s: a dev planet must not be in data/homeward.json planets (players would see it)" % id)
	elif not is_dev(id) and k < 0:
		out.append("%s: not in data/homeward.json planets (no leave gate, no economy, not on the map)" % id)
	return out


## Landmark kinds a hub may name: the art-kit models plus StreetDressing's older ones.
static func landmark_kinds() -> Array[String]:
	var out: Array[String] = HubLandmarks.kinds().duplicate()
	for k: String in ["old_bus", "lighthouse"]:
		if not out.has(k):
			out.append(k)
	return out
