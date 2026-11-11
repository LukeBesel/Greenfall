class_name HubPlan
extends RefCounted
## [v6hubs] Every hub's purpose, from the planet's data (data/planets.json "<planet>".hubs and
## hub_defaults; docs/ADJUSTING.md). Each hub has a name, a town look, a landmark, what only it
## gives (a rocket piece, a gift, stat boosts) and a short local chain that ends in waking its
## landmark. The wake restores the hub: SiteManager.set_level(i, 2) + set_built(i).
## This class is the data and the saved state (GameState.orbit["hub_plan"], per planet as the
## orbit dictionary is); planet/sites/hub_purpose.gd runs it in the world.
## State per site: {"seen": bool, "base": clean cells at first arrival, "woken": bool}.

# l10n:begin
const TOWN_NAMES: Dictionary = {
	"oldtown": "Old town",
	"downtown": "Downtown",
	"industrial": "Industrial town",
	"suburb": "Suburb",
	"harbour": "Harbour town",
	"start": "Old town",
}
# l10n:end
const FALLBACK_COST: Array = [1200.0, 2000.0, 3000.0, 4000.0, 5000.0]

## The planet whose boosts apply (set by HubPurpose when a globe comes up).
static var active_planet: String = ""
static var _data: Dictionary = {}
static var _mods: Dictionary = {}
static var _mods_for: String = "?"


static func planet_data(planet: String) -> Dictionary:
	if _data.is_empty():
		_data = Economy.read_json("res://data/planets.json")
	var d: Variant = _data.get(planet, {})
	return d if d is Dictionary else {}


## Tests: drop the cached data and boosts.
static func reload() -> void:
	_data = {}
	_reasons = {}
	_mods_for = "?"


static func defaults(planet: String) -> Dictionary:
	# [v7planet] "_default".hub_defaults (data/planets.json) with the planet's own keys on top.
	var out: Dictionary = {}
	var base: Variant = planet_data("_default").get("hub_defaults", {})
	if base is Dictionary:
		out = (base as Dictionary).duplicate(true)
	var d: Variant = planet_data(planet).get("hub_defaults", {})
	if d is Dictionary:
		PlanetCfg.deep_merge(out, d as Dictionary)
	return out


## [v6hubs] The rocket hop's tunables (hub_defaults.hop: flight, arrival title, sting); `def` when unset.
static func hop_cfg(key: String, def: Variant) -> Variant:
	var h: Variant = defaults(active_planet if active_planet != "" else PlanetCfg.current_or("verdance")).get("hop", {})  # [v7planet]
	return (h as Dictionary).get(key, def) if h is Dictionary else def


## [v6hubs] Why Lumi came to hub site (the arrival title's third line): the entry's `reason`, else
## data/story_reasons.json goal_reasons.by_id "hub_fly_<order>" (the card's reason for the flight),
## else the entry's `desc`. English; tr() at display. "" for home.
static func reason(planet: String, site: int) -> String:
	var e: Dictionary = entry(planet, site)
	if e.is_empty() or is_home(planet, site):
		return ""
	if str(e.get("reason", "")) != "":
		return str(e["reason"])
	if _reasons.is_empty():
		var gr: Variant = (Economy.read_json("res://data/story_reasons.json") as Dictionary).get("goal_reasons", {})
		var bid: Variant = (gr as Dictionary).get("by_id", {}) if gr is Dictionary else {}
		_reasons = bid if bid is Dictionary else {"_": ""}
	var r: String = str(_reasons.get("hub_fly_%d" % int(e.get("order", 0)), ""))
	return r if r != "" else str(e.get("desc", ""))


static var _reasons: Dictionary = {}


## The planet's hub entries in main-path order.
static func entries(planet: String) -> Array:
	var out: Array = []
	var hs: Variant = planet_data(planet).get("hubs", [])
	if hs is Array:
		for e: Variant in hs:
			if e is Dictionary and (e as Dictionary).has("site"):
				out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 99)) < int(b.get("order", 99)))
	return out


static func has_plan(planet: String) -> bool:
	return not entries(planet).is_empty()


static func entry(planet: String, site: int) -> Dictionary:
	for e: Dictionary in entries(planet):
		if int(e["site"]) == site:
			return e
	return {}


static func is_home(planet: String, site: int) -> bool:
	var e: Dictionary = entry(planet, site)
	return bool(e.get("home", false)) or (e.is_empty() and site == 0)


## Hubs on the main path (the start hub included).
static func main_total(planet: String) -> int:
	return mini(int(defaults(planet).get("main_path", 6)), maxi(entries(planet).size(), 1))


static func is_main(planet: String, site: int) -> bool:
	var e: Dictionary = entry(planet, site)
	return not e.is_empty() and int(e.get("order", 99)) <= main_total(planet)


static func hub_name(planet: String, site: int) -> String:
	var e: Dictionary = entry(planet, site)
	return TranslationServer.translate(str(e["name"])) if e.has("name") else ""


## The town type's display name. `actual`: the look the town really has when it differs from the
## data (a harbour where the lake reaches in).
static func town_name(planet: String, site: int, actual: String = "") -> String:
	var t: String = actual if actual != "" else str(entry(planet, site).get("town", ""))
	return TranslationServer.translate(str(TOWN_NAMES[t])) if TOWN_NAMES.has(t) else ""


static func landmark_kind(planet: String, site: int) -> String:
	var lm: Variant = entry(planet, site).get("landmark", {})
	return str((lm as Dictionary).get("kind", "")) if lm is Dictionary else ""


static func landmark_name(planet: String, site: int) -> String:
	var lm: Variant = entry(planet, site).get("landmark", {})
	var n: String = str((lm as Dictionary).get("name", "")) if lm is Dictionary else ""
	return TranslationServer.translate(n) if n != "" else TranslationServer.translate("landmark")


## The local steps of a far hub: [{do: "clean", hexes}, {do: "outposts", count}, {do: "wake"}].
## Always ends in the wake. The home hub has none.
static func chain(planet: String, site: int) -> Array:
	var e: Dictionary = entry(planet, site)
	if e.is_empty() or is_home(planet, site):
		return []
	var out: Array = []
	var own: Variant = e.get("chain", null)
	if own is Array:
		for s: Variant in own:
			if s is Dictionary and str((s as Dictionary).get("do", "")) in ["clean", "outposts"]:
				out.append(s)
	else:
		var df: Dictionary = defaults(planet)
		if int(df.get("clean_hexes", 8)) > 0:
			out.append({"do": "clean", "hexes": int(df.get("clean_hexes", 8))})
		if int(df.get("outposts", 0)) > 0:
			out.append({"do": "outposts", "count": int(df.get("outposts", 0))})
	out.append({"do": "wake"})
	return out


# --- Saved state -------------------------------------------------------------------------------

static func all_state() -> Dictionary:
	var d: Variant = GameState.orbit.get("hub_plan", null)
	if not (d is Dictionary):
		d = {}
		GameState.orbit["hub_plan"] = d
	return d


static func state(site: int) -> Dictionary:
	var all: Dictionary = all_state()
	var k: String = str(site)
	if not (all.get(k) is Dictionary):
		all[k] = {}
	return all[k]


## Read-only look at a site's state (never creates the save key).
static func peek(site: int) -> Dictionary:
	var d: Variant = GameState.orbit.get("hub_plan", null)
	var s: Variant = (d as Dictionary).get(str(site), null) if d is Dictionary else null
	return s if s is Dictionary else {}


static func woken(site: int) -> bool:
	return bool(peek(site).get("woken", false))


static func seen(site: int) -> bool:
	return bool(peek(site).get("seen", false))


## Far hubs woken on this planet.
static func woken_count(planet: String) -> int:
	var n: int = 0
	for e: Dictionary in entries(planet):
		if not is_home(planet, int(e["site"])) and woken(int(e["site"])):
			n += 1
	return n


## Bases restored on the main path, the home hub included: the HUD's "Bases n/6".
static func restored_main(planet: String) -> int:
	var n: int = 0
	for e: Dictionary in entries(planet):
		var s: int = int(e["site"])
		if is_main(planet, s) and (is_home(planet, s) or woken(s)):
			n += 1
	return n


## The next hub on the path that is not woken yet (-1: all are).
static func next_site(planet: String) -> int:
	for e: Dictionary in entries(planet):
		var s: int = int(e["site"])
		if not is_home(planet, s) and not woken(s):
			return s
	return -1


## Whether the rocket lists this hub: home, every woken or visited hub, the next hub of the main
## path, and the extras once the main path is restored.
static func listed(planet: String, site: int) -> bool:
	var e: Dictionary = entry(planet, site)
	if e.is_empty():
		return not has_plan(planet)
	if is_home(planet, site) or woken(site) or seen(site):
		return true
	if is_main(planet, site):
		return next_site(planet) == site
	return restored_main(planet) >= main_total(planet)


## Calls a static function of another helper's script if the game has it (Hub.far_cost,
## Hub.trade_mult, RocketTiers.hub_limit: v6pace's), else returns null.
static func opt_static(path: String, method: String, args: Array = []) -> Variant:
	var sc: Script = load(path) as Script if ResourceLoader.exists(path) else null
	if sc == null:
		return null
	for m: Dictionary in sc.get_script_method_list():
		if str(m.get("name", "")) == method:
			return sc.callv(method, args)
	return null


## Price of the next wake: Hub.far_cost(n) when the game has it (n = far hubs already restored),
## else data/hub.json far_hub {cost_base, cost_growth} or the far_hub_cost table. A cost dictionary.
static func wake_cost(planet: String) -> Dictionary:
	var n: int = woken_count(planet)
	var v: Variant = opt_static("res://automation/hub.gd", "far_cost", [n])
	if v is Dictionary:
		return v
	if v is BigNum:
		return {"cubes": (v as BigNum).to_float()}
	if v is float or v is int:
		return {"cubes": float(v)}
	var hj: Dictionary = Economy.read_json("res://data/hub.json")
	var fh: Variant = hj.get("far_hub", null)
	if fh is Dictionary and (fh as Dictionary).has("cost_base"):
		return {"cubes": roundf(float(fh["cost_base"]) * pow(float((fh as Dictionary).get("cost_growth", 4.0)), n))}
	var t: Variant = hj.get("far_hub_cost", FALLBACK_COST)
	var arr: Array = t if t is Array and not (t as Array).is_empty() else FALLBACK_COST
	if n < arr.size():
		return {"cubes": float(arr[n])}
	return {"cubes": roundf(float(arr[arr.size() - 1]) * pow(1.4, n - arr.size() + 1))}


## How many hubs (the start hub included) the rocket can keep restored: RocketTiers.hub_limit()
## when the game has it, else no limit.
static func rocket_limit() -> int:
	var v: Variant = opt_static("res://automation/rocket_tiers.gd", "hub_limit")
	return int(v) if v is int or v is float else 999


## True when one more wake needs a better rocket first.
static func at_limit(planet: String) -> bool:
	return woken_count(planet) + 1 >= rocket_limit()


## "Everything sells for x2.5 now." once Hub.trade_mult() exists and is above 1, else "".
static func trade_line() -> String:
	if opt_static("res://automation/hub.gd", "trade_mult") == null:
		return ""
	# Hub.trade_mult() caches the count of restored hubs for the frame; at a wake that is one short.
	var cfg: Variant = opt_static("res://automation/hub.gd", "far_cfg")
	var v: float = pow(float((cfg as Dictionary).get("sell_growth", 1.0)), float(woken_count(active_planet))) if cfg is Dictionary else 1.0
	if v > 1.001:
		var t: String = ("%.2f" % v).rstrip("0").rstrip(".")
		return TranslationServer.translate("The recycling network grew: everything sells for x%s now.") % t
	return ""


# --- The wake's rewards --------------------------------------------------------------------------

## Marks the hub woken and gives what only it gives. Returns the lines to show the player.
static func wake(planet: String, site: int) -> Array[String]:
	var out: Array[String] = []
	var e: Dictionary = entry(planet, site)
	if e.is_empty() or woken(site):
		return out
	state(site)["woken"] = true
	GameState.flags["hub_woken_%d" % site] = true
	GameState.inc_stat("hubs_woken")
	var piece: Variant = e.get("piece", null)
	if piece is Dictionary and str((piece as Dictionary).get("id", "")) != "":
		GameState.flags["rocket_piece_" + str(piece["id"])] = true
		GameState.flags["rocket_pieces"] = int(GameState.flags.get("rocket_pieces", 0)) + 1
		out.append(TranslationServer.translate("Rocket piece: %s") % TranslationServer.translate(str(piece.get("name", ""))))
	var gift: Variant = e.get("gift", null)
	if gift is Dictionary:
		out.append_array(grant(gift))
	var bs: Variant = e.get("boosts", [])
	if bs is Array:
		for b: Variant in bs:
			if b is Dictionary and str((b as Dictionary).get("text", "")) != "":
				out.append(TranslationServer.translate(str(b["text"])))
	_mods_for = "?"
	return out


static func grant(gift: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var pay: Dictionary = {}
	for c: String in ["cubes", "parts", "seeds"]:
		if float(gift.get(c, 0.0)) > 0.0:
			pay[c] = float(gift[c])
	if not pay.is_empty():
		GameState.add_all(pay)
		if pay.has("cubes"):
			out.append(TranslationServer.translate("+%s Cubes") % BigNum.from_float(float(pay["cubes"])).format())
		if pay.has("parts"):
			out.append(TranslationServer.translate("+%d Parts") % int(pay["parts"]))
		if pay.has("seeds"):
			out.append(TranslationServer.translate("+%d Seeds") % int(pay["seeds"]))
	var rid: String = str(gift.get("research", ""))
	if rid != "" and Research.exists(rid) and not Research.has(rid):
		Research.grant(rid)
		out.append(TranslationServer.translate("New: %s") % TranslationServer.translate(str(Research.def(rid).get("name", rid))))
	var did: String = str(gift.get("design", ""))
	if did != "" and not Designs.def(did).is_empty() and not Designs.is_unlocked(did):
		Designs.unlocked().append(did)
		out.append(TranslationServer.translate("New Lumi design: %s") % TranslationServer.translate(str(Designs.def(did).get("name", did))))
	var fl: String = str(gift.get("flag", ""))
	if fl != "":
		GameState.flags[fl] = true
	return out


# --- Boosts --------------------------------------------------------------------------------------

## Stat multipliers of the woken hubs on the active planet (Economy.stat calls this).
static func stat_mod(stat_id: String, value: float) -> float:
	if active_planet == "":
		return value
	var hp: Variant = GameState.orbit.get("hub_plan", null)
	if not (hp is Dictionary):
		return value
	var key: String = active_planet + ":" + str((hp as Dictionary).hash())
	if key != _mods_for:
		_mods_for = key
		_mods = {}
		for e: Dictionary in entries(active_planet):
			if not woken(int(e["site"])):
				continue
			var bs: Variant = e.get("boosts", [])
			if bs is Array:
				for b: Variant in bs:
					if b is Dictionary:
						var st: String = str((b as Dictionary).get("stat", ""))
						_mods[st] = float(_mods.get(st, 1.0)) * float((b as Dictionary).get("mult", 1.0))
	if _mods.is_empty():
		return value
	var m: float = float(_mods.get(stat_id, 1.0))
	var dot: int = stat_id.find(".")
	if dot >= 0:
		m *= float(_mods.get("*" + stat_id.substr(dot), 1.0))
	return value * m


## Lines for the stat tooltip ("no hidden multipliers").
static func breakdown(stat_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if active_planet == "":
		return out
	var dot: int = stat_id.find(".")
	var wild: String = "*" + stat_id.substr(dot) if dot >= 0 else "?"
	for e: Dictionary in entries(active_planet):
		if not woken(int(e["site"])):
			continue
		var bs: Variant = e.get("boosts", [])
		if bs is Array:
			for b: Variant in bs:
				if b is Dictionary and str((b as Dictionary).get("stat", "")) in [stat_id, wild]:
					out.append({"source": TranslationServer.translate(str(e.get("name", ""))), "text": "x%.2f" % float((b as Dictionary).get("mult", 1.0))})
	return out
