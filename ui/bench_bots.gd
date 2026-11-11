class_name BenchBots
extends RefCounted
## [ui7] Rows for the workbench Bots tab, in the same list + detail pattern as Upgrades / Build /
## Research (ui/list_detail.gd). Categories:
##   Build      - one row per robot type: build the next one (cubes + Parts); locked types are
##                "? ?" rows that name the research. The Multibot job board once there are any.
##   Tiers      - the next Mk step of each robot type you have.
##   Fleet      - the fleet upgrades (speed, hopper, ...): the cheapest few you can buy soon plus
##                at most two locked rows.

# l10n:begin
const CATS: Array = [["build", "Build"], ["tiers", "Tiers"], ["fleet", "Fleet"]]
# l10n:end
## The row that holds the Assembler's panel (ui/assembler_panel.gd).
const ASSEMBLER_ROW: String = "assembler_mix"
const ROLE_ICON: Dictionary = {"clean": "scoop", "haul": "cube", "plant": "plant", "water": "water", "skim": "water", "any": "star"}


static func _tr(s: String) -> String:
	return TranslationServer.translate(s)


static func rows(fleet: Fleet, build_at: Callable) -> Array:
	var out: Array = []
	if fleet == null:
		return out
	var world: Node = fleet.world
	var tiers_n: int = Economy.robot_tiers.size()
	for rid: String in Economy.robot_order:
		var def: Dictionary = Economy.robots[rid]
		var name_: String = _tr(str(def.get("name", rid)))
		var icon: String = str(ROLE_ICON.get(str(def.get("role", "clean")), "star"))
		var n: int = fleet.count(rid)
		var t: int = fleet.tier_of(rid)
		var cap: int = fleet.crew_cap()
		var in_crew: int = fleet.robot_total()  # one cap for the whole crew (the planet's robots table)
		# Build.
		if not Research.robot_unlocked(rid) and n == 0:
			out.append({"id": "build_" + rid, "cat": "build", "state": "locked", "name": name_,
				"requires": Research.robot_lock_text(rid)})  # [v4bots] research, or "comes later"
		else:
			var cost: Dictionary = {"cubes": fleet.build_cost(rid).to_float(), "parts": fleet.build_parts(rid).to_float()}
			var why: String = fleet.build_block_reason(rid)
			var short: bool = why == _tr("Not enough parts") or why == _tr("Not enough cubes")
			var table: Array = [[_tr("Built"), str(n)], [_tr("Crew"), "%d / %d" % [mini(in_crew, cap), cap]],
				[_tr("Tier"), Economy.tier_name(t)], [_tr("Cost"), Currencies.cost_text(cost)]]
			if str(def.get("role", "")) == "water" and fleet.water_net:
				table.insert(2, [_tr("Tanks"), "%d / %d" % [fleet.water_net.tanks.size(), int(WaterNet.cfg().get("max", 6))]])
			out.append({"id": "build_" + rid, "cat": "build", "icon": icon, "name": name_, "desc": _tr(str(def.get("desc", ""))),
				"lv": mini(in_crew, cap), "max": cap if cap <= 10 else 0, "price": cost,
				"state": "ready" if why == "" else ("short" if short or n > 0 else "locked"),  # owned types keep their name
				"table": table, "requires": "" if why == "" or short else why,
				"action": _tr("Build a %s") % name_ if n > 0 else _tr("Build your first %s") % name_,
				"act": func() -> bool: return fleet.build(rid, build_at.call() if build_at.is_valid() else Vector3.ZERO) != null})
		# Tiers (only for types you have).
		if n > 0:
			var req: Dictionary = fleet.tier_requirements(rid)
			if not req.get("maxed", false) and not req.get("locked", false):
				var nt: Dictionary = req["next"]
				var tc: Dictionary = {"cubes": (req["cost"] as BigNum).to_float(), "parts": (req["parts"] as BigNum).to_float()}
				out.append({"id": "tier_" + rid, "cat": "tiers", "icon": icon, "name": "%s  ·  %s" % [name_, _tr(str(nt["name"]))],
					"desc": _tr("Every %s gets the new look and works faster.") % name_, "lv": t + 1, "max": tiers_n, "price": tc,
					"state": "ready" if bool(req["ok"]) else "short",
					"table": [[_tr("Tier"), "%s → %s" % [Economy.tier_name(t), _tr(str(nt["name"]))]],
						[_tr("Work speed"), "x%s → x%s" % [str(snappedf(float(Economy.robot_tiers[t].get("mult", 1.0)), 0.1)), str(snappedf(float(nt["mult"]), 0.1))]],
						[_tr("Robots"), str(n)], [_tr("Cost"), Currencies.cost_text(tc)]],
					"requires": "", "action": _tr("Upgrade to %s") % _tr(str(nt["name"])),
					"act": func() -> bool: return fleet.upgrade_tier(rid)})
	# The Assembler: its build mix, once the building stands. First in the list: from here on it
	# is where the crew is steered from.
	var rc: RobotChain = RobotChain.of(world)
	if rc != null and rc.is_built():
		out.push_front({"id": ASSEMBLER_ROW, "cat": "build", "icon": "star", "name": _tr(rc.display_name()), "desc": "",
			"state": "done", "table": [], "action": "", "custom": func(_w: Node) -> Control:
				var ap := AssemblerPanel.new()
				ap.rc = rc
				return ap})
	# Multibot jobs: a custom detail (the allocation board) once there are multibots.
	if fleet.count("multibot") > 0:
		out.append({"id": "multibot_jobs", "cat": "build", "icon": "star", "name": _tr("Multibot jobs"), "desc": "",
			"state": "done", "table": [], "action": "", "custom": func(_w: Node) -> Control:
				var ab := AllocationBoard.new()
				ab.fleet = fleet
				ab.world = world
				return ab})
	# Fleet upgrades: per type, only types you have; the cheapest few + two locked.
	var fleet_rows: Array = []
	for id: String in Economy.upgrade_order:
		var rid2: String = str(Economy.upgrade_defs[id].get("robot", ""))
		if rid2 == "" or fleet.count(rid2) == 0:
			continue
		var it: Dictionary = BenchLists._upgrade_item(id, "fleet")
		it["icon"] = str(ROLE_ICON.get(str(Economy.robots[rid2].get("role", "clean")), "star"))
		it["icon_set"] = "hud"
		fleet_rows.append(it)
	out.append_array(BenchLists._trim(fleet_rows))
	return out


static func counter(fleet: Fleet) -> String:
	if fleet == null:
		return ""
	var total: int = fleet.robot_total()  # [orbC] globe crews
	return _tr("ROBOTS  %d   ·   CREW SPOTS %d") % [total, fleet.crew_cap()]
