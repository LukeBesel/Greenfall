class_name BenchTiers
extends RefCounted
## [v1guide] Workbench tiers (owner, 2026-11-08 #24, #28): the later workbench tabs (Bots, Research,
## Requests) open by upgrading the workbench itself, not on their own. Tier 1 is the repaired bench
## (Upgrades + Build). Each later tier is bought in the Upgrades tab (Base, first row) and opens
## its tabs for good. Tiers live in data/workbench.json "tiers"; the tier in
## GameState.flags["bench_tier"] (global: one bench design for every base).
##
## Saves from before the tiers keep what they could already use: the first time a save without the
## flag asks, the tier is worked out from what was opened or done (bench_tabs, robots built,
## research done, contracts done) and stored.

const PATH: String = "res://data/workbench.json"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func tiers() -> Array:
	return cfg().get("tiers", [])


static func max_tier() -> int:
	return maxi(1, tiers().size())


static func def(t: int) -> Dictionary:
	var ts: Array = tiers()
	return ts[t - 1] if t >= 1 and t <= ts.size() else {}


static func tier() -> int:
	if not GameState.flags.has("bench_tier"):
		GameState.flags["bench_tier"] = legacy_tier()  # once per save: later robots don't raise it
	return clampi(int(GameState.flags["bench_tier"]), 1, max_tier())


## The tier a save from before the tiers gets: the highest tier whose tabs it had already used.
static func legacy_tier() -> int:
	var seen: Array = GameState.flags.get("bench_tabs", [])
	var used := func(tab: String, stat: String) -> bool:
		var v: Variant = GameState.stats.get(stat, 0.0)
		return tab in seen or ((v is float or v is int) and float(v) >= 1.0)
	var out: int = 1
	for i: int in range(2, max_tier() + 1):
		for tab: Variant in def(i).get("tabs", []):
			var stat: String = {"bots": "robots_built", "research": "research_done", "contracts": "contracts_done"}.get(str(tab), "")
			if stat != "" and bool(used.call(str(tab), stat)):
				out = i
	return out


## The tier that opens `tab` (1 for the tabs a repaired bench has; 0 if no tier lists it).
static func tier_for_tab(tab: String) -> int:
	for i: int in range(1, max_tier() + 1):
		if tab in def(i).get("tabs", []):
			return i
	return 0


static func tab_open(tab: String) -> bool:
	var need: int = tier_for_tab(tab)
	return need == 0 or tier() >= need


static func next_def() -> Dictionary:
	return def(tier() + 1)


static func next_cost() -> Dictionary:
	return next_def().get("cost", {})


## "" when the next tier can be bought now (cost aside); else what it waits for, readable.
static func block_reason(w: Node = null) -> String:
	var nd: Dictionary = next_def()
	if nd.is_empty():
		return TranslationServer.translate("Fully upgraded.")
	for c: Variant in nd.get("requires", []):
		if c is Array and not UpgradesScreen.cond_ok(c as Array, w):
			return requirement_text(c as Array)
	return ""


static func requirement_text(c: Array) -> String:
	match str(c[0]):
		"tower":
			return TranslationServer.translate("Build the signal tower first.")
		"hub_level":
			return TranslationServer.translate("Rebuild the base to level %d first.") % int(c[1])
		"bench_tier":
			return TranslationServer.translate("Upgrade the workbench first.")
		"stat":
			if str(c[1]) == "hexes_cleaned":
				return TranslationServer.translate("Clean %d hexes first.") % int(c[2])
	return TranslationServer.translate("Not yet. Keep playing.")


static func can_buy(w: Node = null) -> bool:
	return not next_def().is_empty() and block_reason(w) == "" and GameState.can_afford_all(next_cost())


## Buys the next tier: pays, opens its tabs, says which. False when it can't.
static func buy(w: Node = null) -> bool:
	if not can_buy(w) or not GameState.spend_all(next_cost()):
		return false
	var t: int = tier() + 1
	GameState.flags["bench_tier"] = t
	GameState.inc_stat("bench_tiers")
	for rid: Variant in def(t).get("grants_research", []):  # the Bot Bay brings Salvage Logic: robots right away
		Research.gift(str(rid))
	var names: Array[String] = []
	for tab: Variant in def(t).get("tabs", []):
		for td: Dictionary in UpgradesScreen.TABS:
			if str(td["id"]) == str(tab):
				names.append(TranslationServer.translate(str(td["name"])))
	EventBus.toast.emit(TranslationServer.translate("%s installed. New workbench tab: %s") % [TranslationServer.translate(str(def(t).get("name", ""))), ", ".join(names)], "goal")
	return true
