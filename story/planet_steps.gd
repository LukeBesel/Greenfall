class_name PlanetSteps
extends RefCounted
## [v7planet] The card's hub steps per planet (docs/NEW_PLANET.md, "The card's hub steps").
## data/objectives.json and data/goals.json are one list for the game, written for Verdance's six
## stations (hub_fly_N, hub_wake_N, rocket_tier_N). A planet whose data/planets.json says
## "hub_steps": "generated" (the "_default"; Verdance says "shared") gets its own instead, made
## from its hubs[] here, so a planet with 2 or 8 hubs never leaves the card waiting for a hub that
## does not exist:
##   for each main-path hub k = 2..main_path (hub_defaults.main_path, in hubs[] order):
##     rocket_tier_T   when the rocket in use cannot keep k hubs (data/rockets.json tiers[].hubs)
##     hub_fly_k       hubs_seen >= k-1   why: the hub's `reason`, else story_reasons
##                     goal_reasons.by_planet.<planet>.hub_fly_k, else the hub's `desc`
##     hub_wake_k      hubs_woken >= k-1  "Wake station k of N"
## They take the place of the shared hub steps in the objective chain (where the first one stood),
## and the shared hub goals are left out of the goal chain. "shared" (Verdance) changes nothing.

const KEYS: Array[String] = ["hubs_seen", "hubs_woken", "rocket_tier"]
const PREFIXES: Array[String] = ["hub_fly_", "hub_wake_", "rocket_tier_"]
const ROMAN: Array[String] = ["", "I", "II", "III", "IV", "V", "VI", "VII"]


## The planet the card is for: the globe's.
static func planet() -> String:
	return PlanetCfg.current_or("verdance")


static func generated(p: String) -> bool:
	return str(PlanetCfg.value(p, "hub_steps", "generated")) == "generated" and HubPlan.has_plan(p)


static func is_hub_step(d: Dictionary) -> bool:
	var id: String = str(d.get("id", ""))
	for pre: String in PREFIXES:
		if id.begins_with(pre):
			return true
	return str(d.get("type", "stat")) == "stat" and KEYS.has(str(d.get("key", "")))


## The planet's own hub steps, in card order.
static func steps_for(p: String) -> Array:
	var out: Array = []
	var total: int = HubPlan.main_total(p)
	var tier: int = 1
	var k: int = 1
	for e: Dictionary in HubPlan.entries(p):
		if HubPlan.is_home(p, int(e["site"])) or not HubPlan.is_main(p, int(e["site"])):
			continue
		k += 1
		while tier < RocketTiers.max_tier() and RocketTiers.hub_limit(tier) < k:
			tier += 1
			out.append({"id": "rocket_tier_%d" % tier, "type": "stat", "key": "rocket_tier", "target": tier,
				"text": "Upgrade the rocket to Mk %s" % (ROMAN[tier] if tier < ROMAN.size() else str(tier)),
				"why": _by_planet(p, "rocket_tier_%d" % tier), "_planet": p})
		out.append({"id": "hub_fly_%d" % k, "type": "stat", "key": "hubs_seen", "target": k - 1,
			"text": "Fly to the next station", "why": _fly_why(p, e, k), "_planet": p})
		out.append({"id": "hub_wake_%d" % k, "type": "stat", "key": "hubs_woken", "target": k - 1,
			"text": TranslationServer.translate("Wake station %d of %d") % [k, total],
			"why": _by_planet(p, "hub_wake_%d" % k), "_planet": p})
	return out


## The story objectives with the planet's hub steps in place of the shared ones.
static func objectives(chain: Array, p: String = "") -> Array:
	var pl: String = p if p != "" else planet()
	if not generated(pl):
		return chain
	var out: Array = []
	var at: int = -1
	for d: Variant in chain:
		if d is Dictionary and is_hub_step(d):
			if at < 0:
				at = out.size()
			continue
		out.append(d)
	if at < 0:
		at = out.size()
	var own: Array = steps_for(pl)
	for i: int in own.size():
		out.insert(at + i, own[i])
	return out


## The goal chain without the shared hub steps (the planet's own are on the objective chain).
static func goals(chain: Array, p: String = "") -> Array:
	var pl: String = p if p != "" else planet()
	if not generated(pl):
		return chain
	return chain.filter(func(d: Variant) -> bool: return not (d is Dictionary and is_hub_step(d)))


## data/story_reasons.json goal_reasons.by_planet.<planet>.<step id> ("" when none: the shared
## by-prefix line is used).
static func _by_planet(p: String, id: String) -> String:
	var gr: Variant = (Economy.read_json("res://data/story_reasons.json") as Dictionary).get("goal_reasons", {})
	var bp: Variant = (gr as Dictionary).get("by_planet", {}) if gr is Dictionary else {}
	var pd: Variant = (bp as Dictionary).get(p, {}) if bp is Dictionary else {}
	return str((pd as Dictionary).get(id, "")) if pd is Dictionary else ""


static func _fly_why(p: String, e: Dictionary, k: int) -> String:
	if str(e.get("reason", "")) != "":
		return str(e["reason"])
	var r: String = _by_planet(p, "hub_fly_%d" % k)
	return r if r != "" else str(e.get("desc", ""))
