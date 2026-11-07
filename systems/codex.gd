class_name Codex
extends RefCounted
## Codex entries (data/codex.json): junk, plants, robots, memory shards and landmarks.
## Unlocked keys ("junk:metal") persist in GameState.flags["codex"] (an Array).

const PATH: String = "res://data/codex.json"
## Landmarks count as found when Patch is this close (m).
const LANDMARK_RANGE: float = 7.0

static var _cfg: Dictionary = {}
static var _entries: Array[Dictionary] = []


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func categories() -> Array:
	return cfg().get("categories", [])


## All entries in display order: {key, cat, id, name, desc, hint}.
static func entries() -> Array[Dictionary]:
	if not _entries.is_empty():
		return _entries
	var c: Dictionary = cfg()
	for id: String in Economy.junk_ids:
		var e: Dictionary = c.get("junk", {}).get(id, {})
		_add("junk", id, TranslationServer.translate(str(Economy.junk_types[id].get("name", id))), e)
	var plants: Array = Economy.read_json("res://data/plants.json").get("species", [])
	for sp: Dictionary in plants:
		var e: Dictionary = c.get("plants", {}).get(str(sp["id"]), {})
		_add("plants", str(sp["id"]), TranslationServer.translate(str(e.get("name", str(sp["id"]).capitalize()))), e)
	for id: String in Economy.robot_order:
		_add("robots", id, TranslationServer.translate(str(Economy.robots[id].get("name", id))), c.get("robots", {}).get(id, {}))
	for s: Dictionary in Economy.read_json("res://data/shards.json").get("shards", []):
		var e: Dictionary = (c.get("shards", {}).get(str(s["id"]), {}) as Dictionary).duplicate()
		e["hint"] = TranslationServer.translate("Somewhere under the junk.")
		_add("shards", str(s["id"]), TranslationServer.translate(str(s.get("title", s["id"]))), e)
	var seen: Dictionary = {}
	var lms: Array = Economy.landmarks.duplicate()
	for b: Variant in Economy.biome_sets.values():
		lms.append_array((b as Dictionary).get("landmarks", []))
	for l: Dictionary in lms:
		var lid: String = str(l["id"])
		if seen.has(lid):
			continue
		seen[lid] = true
		var e: Dictionary = c.get("landmarks", {}).get(lid, {})
		_add("landmarks", lid, TranslationServer.translate(str(e.get("name", lid.capitalize()))), e)
	# [biomes] Frontier districts and their mechanics (unlocked by planet/frontier_district.gd).
	var fr: Dictionary = c.get("frontiers", {})
	for fid: String in fr:
		_add("frontiers", fid, TranslationServer.translate(str(fr[fid].get("name", fid.capitalize()))), fr[fid])
	# [wild] Animals (unlocked on first sighting by fauna/fauna.gd).
	var an: Dictionary = c.get("animals", {})
	for aid: String in an:
		_add("animals", aid, TranslationServer.translate(str(an[aid].get("name", aid.capitalize()))), an[aid])
	# [scope] Seen through the Telescope (ui/telescope_view.gd).
	var si: Dictionary = c.get("sightings", {})
	for sid: String in si:
		_add("sightings", sid, TranslationServer.translate(str(si[sid].get("name", sid.capitalize()))), si[sid])
	return _entries


static func _add(cat: String, id: String, name: String, e: Dictionary) -> void:
	_entries.append({"key": "%s:%s" % [cat, id], "cat": cat, "id": id, "name": name,
		"desc": TranslationServer.translate(str(e.get("desc", ""))), "hint": TranslationServer.translate(str(e.get("hint", "Not found yet.")))})


static func entry(key: String) -> Dictionary:
	for e: Dictionary in entries():
		if e["key"] == key:
			return e
	return {}


static func unlocked_list() -> Array:
	var v: Variant = GameState.flags.get("codex")
	if not (v is Array):
		v = []
		GameState.flags["codex"] = v
	return v


static func is_unlocked(key: String) -> bool:
	var v: Variant = GameState.flags.get("codex")
	return v is Array and key in (v as Array)


## Returns true when newly unlocked.
static func unlock(key: String) -> bool:
	if is_unlocked(key) or entry(key).is_empty():
		return false
	unlocked_list().append(key)
	EventBus.codex_unlocked.emit(key)
	return true


static func count(cat: String = "*") -> int:
	var n: int = 0
	for k: Variant in unlocked_list():
		if cat == "*" or str(k).begins_with(cat + ":"):
			n += 1
	return n


static func total(cat: String = "*") -> int:
	var n: int = 0
	for e: Dictionary in entries():
		if cat == "*" or e["cat"] == cat:
			n += 1
	return n


## Kilograms per compartment unit of a junk type.
static func kg_per_unit(type_id: String) -> float:
	return float(cfg().get("junk", {}).get(type_id, {}).get("kg_per_unit", 1.0))


## Lifetime kg of junk removed (type "*" = all types).
static func junk_kg(type_id: String = "*") -> float:
	var d: Dictionary = GameState.stats.get("junk_removed", {})
	var kg: float = 0.0
	for t: String in d:
		if type_id == "*" or t == type_id:
			kg += float(d[t]) * kg_per_unit(t)
	return kg


## Unlocks everything the current game state shows was found. Returns new keys.
## `world` (the slice) is optional: with it, plants in the ground, robots in the fleet and
## nearby landmarks are checked too.
static func scan(world: Node = null) -> Array[String]:
	var out: Array[String] = []
	var jr: Dictionary = GameState.stats.get("junk_removed", {})
	for t: String in jr:
		if float(jr[t]) > 0.0 and unlock("junk:" + t):
			out.append("junk:" + t)
	for s: Variant in GameState.flags.get("shards_found", []):
		if unlock("shards:" + str(s)):
			out.append("shards:" + str(s))
	for id: String in Economy.robot_order:
		if GameState.flags.has("tier_" + id) and unlock("robots:" + id):
			out.append("robots:" + id)
	if world == null:
		return out
	var fleet: Variant = world.get("fleet")
	if fleet is Fleet:
		for r: Robot in (fleet as Fleet).robots():
			if unlock("robots:" + r.type_id):
				out.append("robots:" + r.type_id)
	var garden: Variant = world.get("garden")
	if garden is Garden:
		var g: Garden = garden
		var seen: Dictionary = {}
		for si: int in g.slot_species:
			if si >= 0 and not seen.has(si) and si < g.species.size():
				seen[si] = true
				var key: String = "plants:" + str(g.species[si]["id"])
				if unlock(key):
					out.append(key)
	var patch: Variant = world.get("patch")
	var field: Variant = world.get("field")
	if patch is Node3D and field is HexField:
		var p: Vector3 = (patch as Node3D).global_position
		for l: Dictionary in (field as HexField).landmarks:
			var lp: Variant = l.get("pos")
			if lp is Vector3 and Vector2(p.x - (lp as Vector3).x, p.z - (lp as Vector3).z).length() < LANDMARK_RANGE:
				var key: String = "landmarks:" + str(l["model"])
				if unlock(key):
					out.append(key)
	return out


# --- Curiosities (easter eggs, data/eggs.json) ------------------------------------------

static var _eggs: Array = []


static func egg_defs() -> Array:
	if _eggs.is_empty():
		_eggs = Economy.read_json("res://data/eggs.json").get("eggs", [])
	return _eggs


## Where an egg can turn up, for the Curiosities page.
static func egg_where(e: Dictionary) -> String:
	if bool(e.get("starter", false)):
		return TranslationServer.translate("Old Town")
	if str(e.get("where", "")) == "wild":
		var b: String = str(e.get("biome", ""))
		var bs: Dictionary = Economy.biome_set(b)
		return TranslationServer.translate("Wilderness bases") + (TranslationServer.translate(" · often %s") % TranslationServer.translate(str(bs.get("name", b.capitalize()))) if b != "" else "")
	if str(e.get("where", "")) == "frontier":  # [late]
		var fb: String = str(e.get("biome", ""))
		return TranslationServer.translate("Frontiers") + TranslationServer.translate(" · %s") % TranslationServer.translate(str(Economy.biome_set(fb).get("name", fb.capitalize().replace("_", " "))))
	if str(e.get("where", "")) == "new_world":  # [late]
		return TranslationServer.translate("Other worlds")
	return TranslationServer.translate("Any district")


## Every curiosity in data order: {id, name, found, hint, lore, toast, where, reward, parts, parts_seen}.
## Unfound entries keep their name and lore too; the page decides what to show.
static func curiosities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in egg_defs():
		var id: String = str(e["id"])
		var bits: Array[String] = []
		var rew: Dictionary = e.get("reward", {})
		for k: String in rew:
			bits.append(L10nFmt.reward(k, int(rew[k])))  # [i18n2]
		var parts: int = int(e.get("parts", 1))
		out.append({
			"id": id, "name": TranslationServer.translate(str(e.get("name", id))), "found": EasterEggs.is_found(id),
			"hint": TranslationServer.translate(str(e.get("hint", "Keep exploring."))), "lore": TranslationServer.translate(str(e.get("lore", ""))), "toast": TranslationServer.translate(str(e.get("toast", ""))),
			"where": egg_where(e), "reward": "  ".join(bits), "parts": parts,
			"parts_seen": (GameState.flags.get("egg_%s_parts" % id, []) as Array).size() if parts > 1 else 0,
		})
	return out


static func curiosities_found() -> int:
	var n: int = 0
	for e: Dictionary in egg_defs():
		if EasterEggs.is_found(str(e["id"])):
			n += 1
	return n
