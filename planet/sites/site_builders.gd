class_name SiteBuilders
extends RefCounted
## [orbD] Which prefab each planet's hubs get and how to build it. PlanetEnvs.build_site calls
## configure(prefab) to wire a SitePrefab's builder/restyler to the planet's own site code:
##   verdance  VerdanceSite.build(parent, id, stage, restoration, opts)        (planet/sites/)
##   rime      RimeSite.place(parent, id, stage, restoration)                  (planet/sites/)
##   anvil     AnvilSites.build(site_root, id, stage 1-5, restoration)        (p_anvil)
##   ochre     OchreSites.build(id, root, stage 1-5, restoration)             (p_ochre)
##   tidewell  TideSite.place(id, root, stage 0-2, restoration, opts)         (p_seas)
## Any other planet whose data/planets.json entry lists `sites` with a `script` works too: the
## script's static build/place is called with the argument order its signature shows.
## Stage is always the base level 1..5 here; Tidewell's 0..2 is mapped (1 -> 0, 2-3 -> 1, 4-5 -> 2).

const VERDANCE_SITES: Array = [
	{"id": "start_yard", "kind": "hub", "size_m": 180, "clear_core_m": 14},
	{"id": "ruin_block", "kind": "hub", "size_m": 108, "clear_core_m": 12},
]
const RIME_SITES: Array = [
	{"id": "crater_camp", "kind": "hub", "size_m": 92, "clear_core_m": 14},
	{"id": "drill_field", "kind": "landmark", "size_m": 84, "clear_core_m": 10},
]


## The planet's site prefab list: [{id, kind, size_m, clear_core_m, script}], hubs first.
static func sites_of(planet_id: String) -> Array:
	match planet_id:
		"verdance", "":
			return _with_script(VERDANCE_SITES, "res://planet/sites/verdance_site.gd")
		"rime":
			return _with_script(RIME_SITES, "res://planet/sites/rime_site.gd")
	var e: Dictionary = PlanetEnvs.entry(planet_id)
	var raw: Variant = e.get("sites", [])
	var out: Array = []
	if raw is Array:
		for s: Variant in raw:
			if s is Dictionary:
				out.append((s as Dictionary).duplicate())
	elif raw is Dictionary:
		var scr: String = str((raw as Dictionary).get("script", ""))
		for k: String in raw:
			var v: Variant = raw[k]
			if v is Dictionary:
				var d: Dictionary = (v as Dictionary).duplicate()
				d["id"] = k
				if not d.has("script"):
					d["script"] = scr
				out.append(d)
	var hubs: Array = out.filter(func(d: Dictionary) -> bool: return str(d.get("kind", "hub")) == "hub")
	var rest: Array = out.filter(func(d: Dictionary) -> bool: return str(d.get("kind", "hub")) != "hub")
	return hubs + rest


static func _with_script(list: Array, path: String) -> Array:
	var out: Array = []
	for d: Dictionary in list:
		var c: Dictionary = d.duplicate()
		c["script"] = path
		out.append(c)
	return out


static func find(planet_id: String, site_id: String) -> Dictionary:
	for d: Dictionary in sites_of(planet_id):
		if str(d.get("id", "")) == site_id:
			return d
	return {}


## The prefab a hub gets: hub 0 the planet's first hub site; the others cycle through the hub
## sites (Verdance: ruin_block for every hub after the start yard, seeded per hub).
static func site_for_hub(planet_id: String, hub_index: int) -> String:
	var list: Array = sites_of(planet_id)
	if list.is_empty():
		return ""
	var hubs: Array = list.filter(func(d: Dictionary) -> bool: return str(d.get("kind", "hub")) == "hub")
	if hubs.is_empty():
		hubs = list
	if planet_id in ["verdance", ""]:
		return "start_yard" if hub_index == 0 else "ruin_block"
	return str(hubs[hub_index % hubs.size()]["id"])


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
	match p.planet_id:
		"verdance", "":
			p.builder = func(parent: Node3D, st: int, r: float) -> void:
				await VerdanceSite.build(parent, sid, st, r, opts)
			p.restyler = func(content: Node3D, st: int, r: float) -> bool:
				var vs: VerdanceSite = _first(content, "VerdanceSite") as VerdanceSite
				if vs == null:
					return false
				vs.set_level(st)
				vs.set_restoration(r)
				return true
		"rime":
			p.builder = func(parent: Node3D, st: int, r: float) -> void:
				RimeSite.place(parent, sid, st, r, int(opts.get("seed", 9091)))
			p.restyler = func(content: Node3D, st: int, r: float) -> bool:
				var rs: RimeSite = _first(content, "RimeSite") as RimeSite
				if rs == null:
					return false
				rs.set_level(st, false)
				rs.set_restore(r)
				return true
		_:
			var path: String = str(d.get("script", ""))
			if path == "" or not ResourceLoader.exists(path):
				push_warning("SiteBuilders: no script for '%s' on '%s'" % [sid, p.planet_id])
				return false
			var scr: Script = load(path)
			p.builder = func(parent: Node3D, st: int, r: float) -> void:
				_call_external(scr, parent, sid, st, r, opts)
			p.restyler = func(content: Node3D, st: int, r: float) -> bool:
				for c: Node in content.get_children():
					if c.has_method("set_state"):  # TideSite: stage 0..2
						c.call("set_state", tide_stage(st), r)
						return true
				return false
	return true


## TideSite's stage (0 ruin, 1 restored, 2 futuristic) from a base level.
static func tide_stage(level: int) -> int:
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
		var stage_v: int = tide_stage(st) if nm == "place" else st
		var call_args: Array = [sid, parent, stage_v, r] if first_string else [parent, sid, stage_v, r]
		if args.size() >= 5 and int((args[4] as Dictionary).get("type", TYPE_NIL)) == TYPE_DICTIONARY:
			call_args.append({"seed": int(opts.get("seed", hash(sid) % 100000))})
		scr.callv(nm, call_args)
		return
	push_warning("SiteBuilders: %s has no static build/place(…4 args)" % scr.resource_path)


static func _first(n: Node, cls_prefix: String) -> Node:
	for c: Node in n.get_children():
		if String(c.name).begins_with(cls_prefix):
			return c
	return null
