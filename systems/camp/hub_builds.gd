class_name HubBuilds
extends RefCounted
## [camp2] Every structure in the yard is a Hub-tab build (owner: "Only the workbench, which you
## have to repair to start, and the garbage bin. Everything else is a build in the Hub."). This is
## the one list the Hub tab shows (ui/yard_builds_panel.gd). Each entry routes to the system that
## owns the thing:
##   once-builds (drop off the list when built): lean-to, generator, yard lamps, compost press,
##     CD player, robot nursery (systems/camp/yard_builds.gd), the bale stations
##     (automation/stations.gd), the telescope (automation/telescope.gd), the museum
##     (systems/museum.gd, only at its site);
##   tiered (only the next tier is shown): the trash bin (automation/trash_bin.gd) and the signal
##     tower (story/signal_tower.gd, only at the start base).
## An entry is only listed once its unlock condition holds (no spoilers). Building one shows it in
## the world at once with MachineReveal.
##
## Entry: {id, kind ("one_time" | "tiered"), name, desc, cost, reason ("" = can build now),
##   tier ("" for a building, else "Trash bin, level 3 of 5" style)}.
## The list, its order and each id's kind come from data/builds.json (the single source the
## workbench tabs read): one_time -> the Build tab, tiered -> the Upgrades tab. A tiered id with
## first_build_one_time (the signal tower) shows its first tier in the Build tab.

const PATH: String = "res://data/builds.json"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func ids() -> Array[String]:
	var out: Array[String] = []
	for b: Dictionary in cfg().get("builds", []):
		out.append(str(b["id"]))
	return out


static func def(id: String) -> Dictionary:
	for b: Dictionary in cfg().get("builds", []):
		if str(b["id"]) == id:
			return b
	return {}


## Which workbench tab the next purchase of `id` belongs to right now: "one_time" (Build tab) or
## "tiered" (Upgrades tab).
static func kind_now(id: String) -> String:
	var d: Dictionary = def(id)
	if str(d.get("kind", "one_time")) == "tiered" and bool(d.get("first_build_one_time", false)) and _count(id) == 0:
		return "one_time"
	return str(d.get("kind", "one_time"))


## How many of a counted/tiered thing stand here (tower tier, jammers, scrubbers).
static func _count(id: String) -> int:
	match id:
		"signal_tower":
			return SignalTower.tier()
		"signal_jammer":
			return LedgerArc.jammer_count()
		"air_scrubber":
			return int(GameState.world.get("hub_scrubbers", 0))
	return 0


static func _ledger(world: Node) -> Node:
	return world.get_tree().get_first_node_in_group("ledger") if world and world.is_inside_tree() else null


static func _hub_level(world: Node) -> int:
	var hub: Hub = world.get("hub") as Hub if world else null
	return hub.level if hub else int(GameState.world.get("hub_level", 1))


## Whether a block reason only means "can't afford it yet" (the button shows the cost then).
static func not_enough(reason: String) -> bool:
	return reason in [TranslationServer.translate("Not enough materials."), TranslationServer.translate("Not enough cubes or parts."),
		TranslationServer.translate("Not enough cubes, parts or seeds")]


## True once a one-time build stands (tiered builds never count as done while a tier is left).
static func is_built(world: Node, id: String) -> bool:
	match id:
		"trash_bin":
			return TrashBin.next_def().is_empty()
		"signal_tower":
			return SignalTower.tier() >= SignalTower.max_tier()
		"air_scrubber":
			var hub: Hub = world.get("hub") as Hub if world else null
			return hub != null and hub.scrubbers >= int(hub.scrubber_def().get("max", 6))
		"signal_jammer":
			var lg: Node = _ledger(world)
			return lg != null and (LedgerArc.jammer_count() >= int(lg.call("jammer_def").get("max", 3)) or bool(lg.call("resolved")))
		"conveyor", "auto_baler", "recycler":
			return Stations.built_in_state(id)
		"telescope":
			var t: Telescope = Telescope.of(world) if world else null
			return t != null and t.built()
		"museum":
			return Museum.built()
		"bot_fabricator":  # [orbC] per planet (robots/fabricator/bot_fabricator.gd)
			return BotFabricator.built(world)
	return YardBuilds.built(id)


## Whether `id` is offered at this base right now (its unlock condition holds and it isn't done).
static func listed(world: Node, id: String) -> bool:
	if is_built(world, id):
		return false
	match id:
		"trash_bin":
			return true
		"signal_tower":
			return world != null and world.get_node_or_null("SignalTower") != null
		"air_scrubber":
			var hub: Hub = world.get("hub") as Hub if world else null
			return hub != null and hub.level >= int(hub.scrubber_def().get("requires_level", 2))
		"signal_jammer":
			var lg: Node = _ledger(world)
			return lg != null and bool(lg.call("jammer_visible"))
		"conveyor", "auto_baler", "recycler":
			return Stations.of(world) != null and Research.exists(id) and Research.has(id) if world else false
		"telescope":
			var t: Telescope = Telescope.of(world) if world else null
			if t == null:
				return false
			var rid: String = str(t.data.get("requires_research", "observatory"))
			return _hub_level(world) >= int(t.data.get("requires_level", 4)) or (Research.exists(rid) and Research.has(rid))
		"museum":
			return world != null and Museum.site_here(world) and Museum.unlocked()
		"bot_fabricator":  # [orbC] from the 3rd planet (Tidewell) on
			return BotFabricator.unlocked(world)
	return YardBuilds.listed(id, _hub_level(world))


static func entry(world: Node, id: String) -> Dictionary:
	var e: Dictionary = {"id": id, "kind": kind_now(id), "name": id, "desc": "", "cost": {}, "reason": "", "tier": ""}
	var hl: int = _hub_level(world)
	match id:
		"trash_bin":
			var nd: Dictionary = TrashBin.next_def()
			e["name"] = str(nd.get("name", "Trash Bin"))
			e["desc"] = str(nd.get("desc", ""))
			e["cost"] = TrashBin.next_cost()
			e["reason"] = TrashBin.block_reason(hl)
			e["tier"] = TranslationServer.translate("Trash bin, level %d of %d") % [TrashBin.level() + 1, TrashBin.max_level()]
		"signal_tower":
			var tiers: Array = SignalTower.cfg().get("tiers", [])
			var td: Dictionary = tiers[SignalTower.tier()] if SignalTower.tier() < tiers.size() else {}
			e["name"] = str(td.get("name", "Signal Tower"))
			e["desc"] = TranslationServer.translate("WREN can only reach you through the relay. Each tier makes her clearer.")
			e["cost"] = SignalTower.next_cost()
			e["reason"] = "" if Hub.can_pay(e["cost"]) else TranslationServer.translate("Not enough materials.")
			if SignalTower.tier() > 0:
				e["tier"] = TranslationServer.translate("Tier %d of %d") % [SignalTower.tier() + 1, SignalTower.max_tier()]
		"air_scrubber":
			var hub: Hub = world.get("hub") as Hub if world else null
			if hub:
				var sd: Dictionary = hub.scrubber_def()
				e["name"] = str(sd.get("name", "Air Scrubber"))
				e["desc"] = str(sd.get("desc", ""))
				e["cost"] = _scaled(sd.get("cost", {}), hub.scrubber_cost_mult())
				e["reason"] = "" if Hub.can_pay(sd.get("cost", {}), hub.scrubber_cost_mult()) else TranslationServer.translate("Not enough materials.")
				e["tier"] = TranslationServer.translate("%d of %d built") % [hub.scrubbers, int(sd.get("max", 6))]
		"signal_jammer":
			var lg: Node = _ledger(world)
			if lg:
				var jd: Dictionary = lg.call("jammer_def")
				var mult: float = float(lg.call("jammer_cost_mult"))
				e["name"] = str(jd.get("name", "Signal Jammer"))
				e["desc"] = str(jd.get("desc", ""))
				e["cost"] = _scaled(jd.get("cost", {}), mult)
				e["reason"] = "" if bool(lg.call("can_build_jammer")) else TranslationServer.translate("Not enough materials.")
				if LedgerArc.jammer_count() > 0:
					e["tier"] = TranslationServer.translate("%d of %d built") % [LedgerArc.jammer_count(), int(jd.get("max", 3))]
		"conveyor", "auto_baler", "recycler":
			var st: Stations = Stations.of(world) if world else null
			if st:
				e["name"] = str(st.def(id).get("name", id))
				e["desc"] = str(st.def(id).get("desc", ""))
				e["cost"] = st.def(id).get("cost", {})
				e["reason"] = st.block_reason(id)
		"telescope":
			var t: Telescope = Telescope.of(world) if world else null
			if t:
				e["name"] = str(t.data.get("name", "Telescope"))
				e["desc"] = str(t.data.get("desc", ""))
				e["cost"] = Telescope.cost()
				e["reason"] = t.block_reason()
		"museum":
			e["name"] = TranslationServer.translate("Museum")
			e["desc"] = TranslationServer.translate("A hall with a plinth for everything Lumi found, for whoever comes next.")
			e["cost"] = Museum.cost()
			e["reason"] = Museum.blocker()
		"bot_fabricator":  # [orbC]
			e["name"] = str(BotFabricator.cfg().get("name", "Bot Fabricator"))
			e["desc"] = str(BotFabricator.cfg().get("desc", ""))
			e["cost"] = BotFabricator.cost()
			e["reason"] = BotFabricator.block_reason(world)
		_:
			var d: Dictionary = YardBuilds.def(id)
			e["name"] = str(d.get("name", id))
			e["desc"] = str(d.get("desc", ""))
			e["cost"] = d.get("cost", {})
			e["reason"] = YardBuilds.block_reason(id, hl)
	return e


static func _scaled(cost: Dictionary, mult: float) -> Dictionary:
	var out: Dictionary = {}
	for k: String in cost:
		out[k] = float(cost[k]) * mult
	return out


## What can be bought now, in order. kind "one_time" = the Build tab, "tiered" = the Upgrades tab,
## "" = both.
static func available(world: Node, kind: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids():
		if listed(world, id) and (kind == "" or kind_now(id) == kind):
			out.append(entry(world, id))
	return out


## Names of the one-time builds already standing here (the collapsed "Built" line).
static func built_names(world: Node) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids():
		if str(def(id).get("kind", "one_time")) != "one_time":
			continue
		if id == "museum" and not (world != null and Museum.site_here(world)):
			continue
		if is_built(world, id):
			out.append(str(entry(world, id)["name"]))
	return out


## Builds (or raises a tier of) `id`. Pays, puts it in the world and reveals it.
static func build(world: Node, id: String) -> bool:
	if not listed(world, id):
		return false
	var e: Dictionary = entry(world, id)
	if str(e["reason"]) != "":
		return false
	var nm: String = TranslationServer.translate(str(e["name"]))
	match id:
		"trash_bin":
			if not TrashBin.upgrade(_hub_level(world)):
				return false
			var dp: Node3D = world.get("depot") as Node3D if world else null
			MachineReveal.reveal(world, nm, dp.global_position + Vector3(0, 0, -2.7) if dp else Vector3.ZERO)
		"signal_tower":
			var tw: Node3D = world.get_node_or_null("SignalTower") as Node3D
			if tw == null or not Hub.pay(e["cost"]):
				return false
			tw.call("raise")
			MachineReveal.reveal(world, nm, tw.global_position, false)
		"air_scrubber":
			var hub: Hub = world.get("hub") as Hub
			if hub == null or not hub.build_scrubber():
				return false
			MachineReveal.reveal(world, nm, _newest_child(hub, hub.global_position), false)
		"signal_jammer":
			var lg: Node = _ledger(world)
			if lg == null or not bool(lg.call("build_jammer")):
				return false
			var js: Array = lg.get("_jammers")
			MachineReveal.reveal(world, nm, (js.back() as Node3D).global_position if not js.is_empty() and js.back() is Node3D else world.BOARD_POS, false)
		"conveyor", "auto_baler", "recycler":
			var st: Stations = Stations.of(world)
			if st == null or not st.build(id):
				return false
		"telescope":
			var t: Telescope = Telescope.of(world)
			if t == null or not t.build():
				return false
			MachineReveal.reveal(world, nm, t.door_point(), false)
		"museum":
			var m: Node = world.get_node_or_null("Museum")
			if m == null or not bool(m.call("build_from_hub")):
				return false
			MachineReveal.reveal(world, nm, (m as Node3D).global_position, false)
		"bot_fabricator":  # [orbC]
			if not BotFabricator.build(world):
				return false
			var fdp: Node3D = world.get("depot") as Node3D if world else null
			if fdp:
				MachineReveal.reveal(world, nm, fdp.global_position, false)
		_:
			if not YardBuilds.build(id, _hub_level(world)):
				return false  # Camp shows it and reveals it (YardBuilds.events.built)
	GameState.inc_stat("hub_builds")
	return true


static func _newest_child(n: Node, fallback: Vector3) -> Vector3:
	for i: int in range(n.get_child_count() - 1, -1, -1):
		var c: Node3D = n.get_child(i) as Node3D
		if c:
			return c.global_position
	return fallback
