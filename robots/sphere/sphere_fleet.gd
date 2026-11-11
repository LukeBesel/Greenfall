class_name SphereFleet
extends Fleet
## [orbC] The game's Fleet on a round planet: the workbench Bots tab, robot cards, the Builder and
## everything else that talks to `world.fleet` keep working, but the robots are the SphereCrew's
## (near SphereBots and far records) instead of flat Robot nodes. Counts, crew sizes and build
## prices read the crew; build() spawns into it at the bench; Mk upgrades re-dress its robots.
## Saving is the crew's (GameState.orbit["robots"]), so Fleet's flat save is off here.

var crew: SphereCrew


func _ready() -> void:
	pass  # no flat WaterNet, no "persist" group (the crew saves itself)


func _process(_delta: float) -> void:
	if not GameState.parts.is_empty():
		RobotParts.fold_items()  # as the flat Fleet; the [bots] table is the crew's


func count(type_id: String) -> int:
	return crew.count(type_id) if crew else 0


func robot_total() -> int:
	return crew.robots().size() if crew else 0


func crew_size(role_id: String) -> int:
	var n: int = 0
	if crew == null:
		return 0
	for u: Dictionary in crew.robots():
		if str(u["role"]) == role_id:
			n += 1
	return n


## Builds a robot at the bench into the crew (same checks and prices as the flat Fleet). The flat
## API returns a Robot; here it is a stand-in carrying the name and type (never in the tree).
func build(type_id: String, at: Vector3) -> Robot:
	if crew == null or not can_build(type_id):
		return null
	GameState.spend("parts", build_parts(type_id))
	GameState.spend("cubes", build_cost(type_id))
	var cell: int = crew.grid.cell_at(at) if at != Vector3.ZERO else crew.depot_of(crew.hub_cell)
	var rname: String = NAMES[randi() % NAMES.size()] + "-%02d" % (randi() % 100)
	# [v6crew] It belongs to the hub it is built at, rolls out and starts by itself.
	var u: Dictionary = crew.spawn(type_id, tier_of(type_id), cell, crew.nearest_hub(crew.grid.centers[cell]), rname)
	crew.greet(u)
	if str(Economy.robots[type_id].get("role", "")) == "any":
		u["role"] = join_crew(type_id) if join_crew(type_id) != "" else "clean"
	if Once.take("first_robot_rollout") and world != null and world.get("upgrades") != null and world.get("upgrades").has_method("close_screen"):
		(world.get("upgrades") as Node).call_deferred("close_screen")  # [v6crew] the first one: watch it roll out
	GameState.inc_stat("robots_built")
	EventBus.robot_built.emit(rname)
	EventBus.toast.emit(tr("%s %s assembled. It looks around, then gets to work.") % [tr(str(Economy.robots[type_id]["name"])), rname], "story" if Once.take("toast_first_robot") else "reward")  # [v4calm] only the first
	var stand_in := Robot.new()
	stand_in.type_id = type_id
	stand_in.robot_name = rname
	stand_in.tier = tier_of(type_id)
	stand_in.queue_free()
	return stand_in


func upgrade_tier(type_id: String) -> bool:
	if not super(type_id):
		return false
	var t: int = tier_of(type_id)
	for u: Dictionary in crew.robots():
		if u["type"] == type_id:
			u["tier"] = t
			var b: SphereBot = u["bot"]
			if b != null:
				SphereRobotKinds.apply(b, type_id, t)
				var rv: RobotVisual = b.visual as RobotVisual
				if rv:
					rv.build(type_id, str(Economy.robot_tiers[clampi(t, 0, Economy.robot_tiers.size() - 1)].get("look", "salvage")))
				SphereCrew.dress(b, type_id, t)
				var bd: BotBadge = b.get_node_or_null("Badge") as BotBadge  # [v6crew] the new model's height, and a flash
				if bd != null:
					bd.position.y = BotBadge.top_of(b.visual) + 0.22
				Vfx.ring(b.global_position + b.dir * 0.15, 2.2, UITheme.GOLD, 1.0)
	return true


func persist_save() -> void:
	pass


func restore() -> void:
	pass
