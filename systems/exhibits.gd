class_name Exhibits
extends RefCounted
## Lumi's collection: the catalogue of every collectible on the current planet (the planet's
## "museum" table): picked-up gnomes, Biscuit's shell, the time capsule, the last broadcast, the
## memory shards, trinkets and curiosities. The Codex Collection page lists them with counts and a
## silhouette while missing (ui/codex_screen.gd). Pure helpers, no nodes.
## An exhibit: {id, name, kind, ref, shape, color, hint}. Only kinds counted here are listed; a
## table may also hold exhibits whose source is not part of this game.

const TABLE: String = "museum"
## Exhibit kinds this catalogue can count (see progress()).
const KINDS: Array[String] = ["egg", "egg_parts", "eggs", "shards", "trinkets", "flag"]

static var _list: Array = []


static func exhibits() -> Array:
	if _list.is_empty():
		_list = (Economy.planet_table(TABLE).get("exhibits", []) as Array).filter(
			func(x: Dictionary) -> bool: return str(x.get("kind", "")) in KINDS)
		Economy.drop_on_planet_change(_drop_planet_cache)
	return _list


static func _drop_planet_cache() -> void:
	_list = []


static func exhibit(id: String) -> Dictionary:
	for x: Dictionary in exhibits():
		if str(x["id"]) == id:
			return x
	return {}


## [have, total] for one exhibit.
static func progress(x: Dictionary) -> Vector2i:
	var ref: String = str(x.get("ref", ""))
	match str(x.get("kind", "")):
		"egg":
			return Vector2i(1 if EasterEggs.is_found(ref) else 0, 1)
		"egg_parts":
			var total: int = 1
			for e: Dictionary in Codex.egg_defs():
				if str(e["id"]) == ref:
					total = int(e.get("parts", 1))
			return Vector2i(mini(EggCollect.count(ref), total), total)
		"eggs":
			var n: int = 0
			var t: int = 0
			for e: Dictionary in Codex.egg_defs():
				if str(e.get("where", "")) == "new_world":
					continue
				t += 1
				n += 1 if EasterEggs.is_found(str(e["id"])) else 0
			return Vector2i(n, t)
		"shards":
			var all: Array = Economy.planet_table("shards").get("shards", [])
			return Vector2i(mini((GameState.flags.get("shards_found", []) as Array).size(), all.size()), all.size())
		"trinkets":
			return Vector2i(Collection.count(), Collection.total())
		"flag":
			return Vector2i(1 if GameState.flags.get(ref, false) else 0, 1)
	return Vector2i(0, 1)


static func is_full(x: Dictionary) -> bool:
	var p: Vector2i = progress(x)
	return p.x >= p.y


## How many exhibits are full.
static func filled() -> int:
	return exhibits().filter(func(x: Dictionary) -> bool: return is_full(x)).size()


static func hint(x: Dictionary) -> String:
	if x.has("hint"):
		return str(x["hint"])
	if str(x.get("kind", "")) in ["egg", "egg_parts"]:
		for e: Dictionary in Codex.egg_defs():
			if str(e["id"]) == str(x.get("ref", "")):
				return str(e.get("hint", ""))
	return ""
