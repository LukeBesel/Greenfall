class_name BenchLists
extends RefCounted
## [ui6] Row data for the workbench's list + detail tabs (ui/list_detail.gd), one provider per
## tab, all read from the systems that own the numbers (Economy upgrades, Hub, HubBuilds, Glim,
## RocketTiers, Research). [v1guide] Rows keep a fixed order (owner 2026-11-08): every open row in
## its place, plus at most two "? ?" locked rows per category.

const LOCKED_SHOWN: int = 2

# l10n:begin
const UPGRADE_CATS: Array = [["lumi", "Lumi"], ["base", "Base"], ["machines", "Machines"], ["glim", "Glim"], ["rocket", "Rocket"]]
const BUILD_CATS: Array = [["story", "Story"], ["yard", "Yard"], ["machines", "Machines"]]  # [v1guide] the signal tower first: it's the first build the story asks for
# l10n:end
const BUILD_CAT_OF: Dictionary = {
	"conveyor": "machines", "auto_baler": "machines", "recycler": "machines", "air_scrubber": "machines",
	"signal_tower": "story", "signal_jammer": "story",
}


static func _tr(s: String) -> String:
	return TranslationServer.translate(s)


static func _num(v: float) -> String:
	if absf(v - round(v)) < 0.005:
		return str(int(round(v)))
	return "%.2f" % v


static func _state(cost: Dictionary) -> String:
	return "ready" if GameState.can_afford_all(cost) else "short"


static func _price_text(cost: Dictionary) -> String:
	return Currencies.cost_text(cost)


# --- Upgrades -----------------------------------------------------------------------------

static func _upgrade_item(id: String, cat: String) -> Dictionary:
	var d: Dictionary = Economy.upgrade_defs[id]
	var lv: int = GameState.level_of(id)
	var mx: int = Economy.upgrade_max(id)
	var unit: String = _tr(str(d.get("unit", "")))
	var cost: Dictionary = {Economy.upgrade_currency(id): Economy.upgrade_cost(id).to_float()}
	var waits: bool = Economy.waits_for_district(id)  # this city's levels are sold; more open with the next
	var locked: bool = not Economy.is_unlocked(id) or waits
	var now: float = Economy.stat_with_upgrade_level(id, lv)
	var nxt: float = Economy.stat_with_upgrade_level(id, lv + 1)
	var it: Dictionary = {"id": id, "cat": cat, "icon": str(d.get("icon", "cube")), "icon_set": "ui", "name": _tr(str(d.get("name", id))),
		"desc": _tr(str(d.get("desc", ""))), "lv": lv, "max": mx, "price": cost, "_cost": Economy.upgrade_cost(id).to_float(),
		"state": "locked" if locked else ("done" if Economy.is_maxed(id) else _state(cost)),
		"table": [[_tr("Level"), "%d / %d" % [lv, mx] if mx > 0 else str(lv)], [_tr("Now"), "%s%s" % [_num(now), unit]],
			[_tr("Next"), "%s%s" % [_num(nxt), unit]], [_tr("Cost"), _price_text(cost)]],
		"requires": (_tr("More levels open in the next city") if waits else Economy.lock_reason(id)) if locked else "",
		"action": _tr("Install level %d") % (lv + 1),
		"act": func() -> bool: return Economy.buy_upgrade(id, 1) > 0}
	if str(d.get("stat", "")) == "auto_compactor":
		it["table"][1][1] = _tr("Off")
		it["table"][2][1] = _tr("On")
	return it


## [v1guide] Owner (2026-11-08 #27): every upgrade keeps its own place in the list. Rows stay in
## the bench order (data/workbench.json "upgrade_order", then the data order) whatever they cost or
## whether you can pay; the first LOCKED_SHOWN locked ones show as "? ?" teasers in their place.
static func _trim(rows: Array) -> Array:
	var out: Array = []
	var locked: int = 0
	for r: Dictionary in rows:
		if str(r["state"]) == "locked":
			locked += 1
			if locked > LOCKED_SHOWN:
				continue
		out.append(r)
	return out


## [v1guide] The fixed display order of the Lumi / machine upgrades.
static func bench_order() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in BenchTiers.cfg().get("upgrade_order", []):
		if Economy.upgrade_defs.has(str(id)) and not (str(id) in out):
			out.append(str(id))
	for id: String in Economy.upgrade_order:
		if not (id in out):
			out.append(id)
	return out


static func upgrades(world: Node) -> Array:
	var out: Array = []
	var lumi: Array = []
	var machines: Array = []
	for id: String in bench_order():  # [v1guide] fixed order
		var tab: String = str(Economy.upgrade_defs[id].get("tab", "patch"))
		if tab == "patch":
			lumi.append(_upgrade_item(id, "lumi"))
		elif tab == "hub":
			var rs: String = str(Economy.upgrade_defs[id].get("requires_station", ""))
			if rs == "" or Stations.built_in_state(rs):
				machines.append(_upgrade_item(id, "machines"))
	out.append_array(_trim(lumi))
	out.append_array(_base(world))
	out.append_array(_trim(machines))
	out.append_array(_glim())
	out.append_array(_rocket(world))
	return out


static func _base(world: Node) -> Array:
	var out: Array = []
	var bt: Dictionary = _bench_tier(world)  # [v1guide] the workbench's own tiers come first
	if not bt.is_empty():
		out.append(bt)
	var hub: Hub = world.get("hub") as Hub if world else null
	if hub:
		var nxt: Dictionary = hub.level_def(hub.level + 1)
		if not nxt.is_empty():
			var cost: Dictionary = nxt.get("cost", {})
			var gains: Array[String] = HubPanel.level_gains(hub, hub.level + 1)
			var table: Array = [[_tr("Level"), "%d / %d" % [hub.level, (hub.data.get("levels", []) as Array).size()]],
				[_tr("Now"), _tr(str(hub.level_def(hub.level).get("name", "")))]]
			if not gains.is_empty():
				table.append([_tr("Next"), gains[0]])
			table.append([_tr("Cost"), _price_text(cost)])
			out.append({"id": "hub_level", "cat": "base", "icon": "hex", "icon_set": "ui", "name": _tr(str(nxt.get("name", ""))),
				"desc": _tr(str(nxt.get("desc", ""))), "lv": hub.level, "max": (hub.data.get("levels", []) as Array).size(),
				"price": cost, "state": _state(cost) if hub.block_reason() == "" else "locked", "table": table, "requires": hub.block_reason(),
				"action": _tr("Build hub level %d") % (hub.level + 1), "act": func() -> bool: return hub.upgrade()})
	for e: Dictionary in HubBuilds.available(world, "tiered"):
		var id: String = str(e["id"])
		var reason: String = str(e.get("reason", ""))
		var short: bool = reason != "" and HubBuilds.not_enough(reason)
		out.append({"id": "hb_" + id, "cat": "base", "icon": "star", "name": _tr(str(e.get("name", id))), "desc": _tr(str(e.get("desc", ""))),
			"price": e.get("cost", {}), "state": "ready" if reason == "" else ("short" if short else "locked"),
			"table": [[_tr("Level"), str(e.get("tier", ""))], [_tr("Cost"), _price_text(e.get("cost", {}))]] if str(e.get("tier", "")) != "" else [[_tr("Cost"), _price_text(e.get("cost", {}))]],
			"requires": "" if reason == "" or short else reason, "action": _tr("Upgrade"),
			"act": func() -> bool: return HubBuilds.build(world, id)})
	return out


## [v1guide] The next workbench tier (ui/bench_tiers.gd): it opens the next tab(s).
static func _bench_tier(world: Node) -> Dictionary:
	var nd: Dictionary = BenchTiers.next_def()
	if nd.is_empty():
		return {}
	var cost: Dictionary = nd.get("cost", {})
	var why: String = BenchTiers.block_reason(world)
	var t: int = BenchTiers.tier()
	var tabs: Array[String] = []
	for tab: Variant in nd.get("tabs", []):
		for td: Dictionary in UpgradesScreen.TABS:
			if str(td["id"]) == str(tab):
				tabs.append(_tr(str(td["name"])))
	return {"id": "bench_tier", "cat": "base", "icon": "box", "icon_set": "ui", "name": _tr(str(nd.get("name", ""))),
		"desc": _tr(str(nd.get("desc", ""))), "lv": t, "max": BenchTiers.max_tier(), "price": cost,
		"state": "locked" if why != "" else _state(cost),
		"table": [[_tr("Level"), "%d / %d" % [t, BenchTiers.max_tier()]], [_tr("Opens"), ", ".join(tabs)], [_tr("Cost"), _price_text(cost)]],
		"requires": why, "action": _tr("Upgrade the workbench"),
		"act": func() -> bool: return BenchTiers.buy(world)}


static func _glim() -> Array:
	var out: Array = []
	if not Glim.is_found():
		return out
	var rows: Array = []
	for t: Dictionary in Glim.tracks():
		var id: String = str(t.get("id", ""))
		var lv: int = Glim.tier(id)
		var mx: int = Glim.max_tier(id)
		if lv >= mx:
			continue
		var why: String = Glim.block_reason(id)
		var cost: Dictionary = Glim.next_cost(id)
		rows.append({"id": "glim_" + id, "cat": "glim", "icon": "star", "name": _tr(str(t.get("name", id))), "desc": _tr(str(t.get("desc", ""))),
			"lv": lv, "max": mx, "price": cost, "_cost": float(cost.get("cubes", 0.0)),
			"state": "locked" if why != "" else _state(cost),
			"table": [[_tr("Level"), "%d / %d" % [lv, mx]], [_tr("Cost"), _price_text(cost)]],
			"requires": _tr(why) if why != "" else "", "action": _tr("Install level %d") % (lv + 1),
			"act": func() -> bool: return Glim.buy(id)})
	return _trim(rows)


static func _rocket(world: Node) -> Array:
	var out: Array = []
	if not UpgradesScreen.tab_visible("rockets", world):
		return out
	var nd: Dictionary = RocketTiers.next_def()
	if not nd.is_empty():
		var cost: Dictionary = nd.get("cost", {})
		var why: String = RocketTiers.blocker()
		out.append({"id": "rocket_tier", "cat": "rocket", "icon": "star", "name": _tr(str(nd.get("name", ""))), "desc": _tr(str(nd.get("desc", ""))),
			"lv": RocketTiers.tier(), "max": RocketTiers.max_tier(), "price": cost,
			"state": "ready" if why == "" else ("short" if not GameState.can_afford_all(cost) else "locked"),
			"table": [[_tr("Level"), "%d / %d" % [RocketTiers.tier(), RocketTiers.max_tier()]], [_tr("Cost"), _price_text(cost)]],
			"requires": why if why != "" and GameState.can_afford_all(cost) else "", "action": _tr("Upgrade the rocket"),
			"act": func() -> bool:
				var ok: bool = RocketTiers.upgrade()
				if ok and world and world.has_method("refresh_rocket"):
					world.refresh_rocket()
				return ok})
	out.append({"id": "launch_pad", "cat": "rocket", "icon": "star", "name": _tr("Launch pad"), "desc": "",
		"state": "busy", "tag": _tr("FLY"), "table": [], "requires": "", "action": "",
		"custom": func(w: Node) -> Control:
			var rp := RocketsPanel.new()
			rp.world = w
			return rp})
	return out


static func upgrades_counter() -> String:
	var have: int = 0
	var total: int = 0
	# [ui7] Only what's open to you now (unlocked, machine standing): not every level in the game.
	for id: String in bench_order():
		var d: Dictionary = Economy.upgrade_defs[id]
		if not (str(d.get("tab", "patch")) in ["patch", "hub"]) or not Economy.is_unlocked(id):
			continue
		var rs: String = str(d.get("requires_station", ""))
		if rs != "" and not Stations.built_in_state(rs):
			continue
		have += GameState.level_of(id)
		total += maxi(Economy.upgrade_max(id), GameState.level_of(id))
	return _tr("INSTALLED  %d / %d") % [have, total]


# --- Build --------------------------------------------------------------------------------

static func builds(world: Node) -> Array:
	var out: Array = []
	for e: Dictionary in HubBuilds.available(world, "one_time"):
		var id: String = str(e["id"])
		var reason: String = str(e.get("reason", ""))
		var short: bool = reason != "" and HubBuilds.not_enough(reason)
		out.append({"id": id, "cat": str(BUILD_CAT_OF.get(id, "yard")), "icon": "hex", "icon_set": "ui",
			"name": _tr(str(e.get("name", id))), "desc": _tr(str(e.get("desc", ""))), "price": e.get("cost", {}),
			"state": "ready" if reason == "" else ("short" if short else "locked"),
			"table": [[_tr("Cost"), _price_text(e.get("cost", {}))]],
			"requires": "" if reason == "" or short else reason, "action": _tr("Build"),
			"act": func() -> bool: return HubBuilds.build(world, id)})
	# [v1guide] Per category, at most LOCKED_SHOWN "? ?" rows (five locked yard rows hid the tower).
	var kept: Array = []
	for c: Array in BUILD_CATS:
		kept.append_array(_trim(out.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == str(c[0]))))
	out = kept
	# Machines that stand keep their few controls (route, move).
	var st: Stations = Stations.of(world) if world else null
	if st and (st.conveyor != null or st.baler != null or st.recycler != null):
		out.append({"id": "stations_ctl", "cat": "machines", "icon": "auto", "icon_set": "ui", "name": _tr("Bale stations"), "desc": "",
			"state": "done", "table": [], "action": "", "custom": func(_w: Node) -> Control:
				var sp := StationsPanel.new()
				for g: Node in sp.find_children("*", "GridContainer", true, false):
					(g as Control).visible = false
				return sp})
	return out


static func builds_counter(world: Node) -> String:
	return _tr("BUILT  %d") % HubBuilds.built_names(world).size()


# --- Research -----------------------------------------------------------------------------

static func research_cats() -> Array:
	var out: Array = []
	for b: Dictionary in Research.branches():
		out.append([str(b["id"]), str(b["name"])])
	return out


static func research() -> Array:
	var out: Array = []
	for id: String in Research.ids():
		var d: Dictionary = Research.def(id)
		var st: String = Research.status(id)
		var cost: Dictionary = {"cubes": Research.cost(id).to_float()}
		var fx: String = "  ·  ".join(Research.effect_lines(id))
		var table: Array = [[_tr("Effect"), fx], [_tr("Time"), Research.time_text(Research.duration(id))], [_tr("Cost"), _price_text(cost)]]
		var it: Dictionary = {"id": id, "cat": str(d.get("branch", "")), "icon": str(d.get("icon", "")), "icon_set": "research",
			"name": _tr(str(d.get("name", id))), "desc": _tr(str(d.get("desc", ""))), "price": cost, "table": table, "requires": "", "action": ""}
		match st:
			"researched":
				it["state"] = "done"
			"active":
				it["state"] = "ready"
				it["tag"] = Research.time_text(Research.remaining())
				it["table"] = [[_tr("Effect"), fx], [_tr("Left"), Research.time_text(Research.remaining())]]
				it["action"] = _tr("Cancel (refund)")
				it["price"] = {}
				it["act"] = func() -> bool: return Research.cancel(id)
			"queued":
				it["state"] = "ready"
				it["action"] = _tr("Cancel (refund)")
				it["price"] = {}
				it["act"] = func() -> bool: return Research.cancel(id)
			"locked":
				it["state"] = "locked"
				var names: Array[String] = []
				for r: String in Research.requires(id):
					if not Research.has(r):
						names.append(_tr(str(Research.def(r).get("name", r))))
				it["requires"] = ", ".join(names) if not names.is_empty() else Research.reason(id)
			_:
				var why: String = Research.reason(id)
				it["state"] = "ready" if Research.can_start(id) else ("short" if not GameState.can_afford("cubes", Research.cost(id)) else "locked")
				it["requires"] = "" if it["state"] == "ready" or it["state"] == "short" else why
				it["action"] = _tr("Research") if Research.active().is_empty() else _tr("Queue")
				it["act"] = func() -> bool: return Research.start(id)
		if st in ["active", "queued"]:
			it["state"] = "ready"
			it["_busy_tag"] = true
		out.append(it)
	# Per branch: what's on now and next, the done ones, and at most two locked rows.
	var trimmed: Array = []
	for b: Array in research_cats():
		var rows: Array = out.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == str(b[0]))
		var open: Array = rows.filter(func(r: Dictionary) -> bool: return str(r["state"]) in ["ready", "short"])
		var done: Array = rows.filter(func(r: Dictionary) -> bool: return str(r["state"]) == "done")
		var locked: Array = rows.filter(func(r: Dictionary) -> bool: return str(r["state"]) == "locked")
		trimmed.append_array(open)
		trimmed.append_array(locked.slice(0, LOCKED_SHOWN))
		trimmed.append_array(done)
	return trimmed


static func research_counter() -> String:
	var a: Dictionary = Research.active()
	var line: String = _tr("RESEARCHED  %d / %d") % [Research.done_list().size(), Research.ids().size()]
	if not a.is_empty():
		line = _tr("%s  ·  %s left") % [_tr(str(Research.def(Research.active_id()).get("name", ""))), Research.time_text(Research.remaining())] + "     " + line
	return line
