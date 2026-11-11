class_name RobotChain
extends Node
## The robot chain in a world (design spec section 14): parts finders dig buried parts out of
## cleaned ground and carry them to the base, and the Assembler, a factory building, turns Parts
## into robots, more parts finders included, in the build mix the player sets. The rules and the
## state are CrewChain's (core/crew_chain.gd, plain data); this node feeds it from the world and
## shows what it does.
##
## What it does:
## - seeds a hex's buried parts the first time the hex is clean land (SphereCells.cell_changed,
##   settled on the next tick);
## - pays the Parts a parts finder brings in (SphereCrew.parts_delivered);
## - pays a city's arrival salvage and puts the Assembler on offer (EventBus.district_entered);
## - runs the Assembler's line on the fixed tick and sets each finished robot down at its door;
## - sends new robots to the base of the city Lumi is in (SphereCrew.new_robot_hub_fn), and
##   ships robots that have run out of work in another city after them (redeploy).
## It never calls UI: it emits parts_scrounged, salvage_found, assembler_offered, assembler_built
## and robot_assembled on EventBus (and robot_built, as the bench does).
##
## Data: the planet's "robots" table, key "chain". A planet without it has no chain: nothing is
## seeded and the Assembler is never offered.
## Save: save_state() / load_state() (the planet's save section, key "chain").
##
## Dev flags (listed in autoload/DevHooks.gd): --assembler, --chain-ground=RINGS[:PARTS],
## --zone=ROLE:RINGS[,ROLE:RINGS], --chain-report.
##
## Use: var rc := RobotChain.new(); world.add_child(rc); rc.setup(world, crew, fleet, districts,
##      cells, site_cells); rc.load_state(saved, save_is_older)

const NODE_NAME: String = "RobotChain"
const BUILD_ID: String = "assembler"
## The line is stepped this often (it counts seconds; nothing in it needs a finer step).
const LINE_STEP_S: float = 0.25
## How often idle robots in other cities are looked at (see _redeploy).
const REDEPLOY_CHECK_S: float = 5.0
const FLAG_BUILD: String = "assembler"
const FLAG_GROUND: String = "chain-ground"
const FLAG_ZONE: String = "zone"
const FLAG_REPORT: String = "chain-report"
const DEFAULT_DEV_GROUND: float = 1.0

var chain := CrewChain.new()
var model: AssemblerModel
## The base site whose anchors place the building (set before load_state; null: no building is
## shown, the line still runs).
var base_site: SitePrefab

var _world: Node
var _crew: SphereCrew
var _fleet: Fleet
var _districts: Districts
var _cells: SphereCells
var _site_cells := PackedInt32Array()
var _line_acc: float = 0.0
## Hexes that changed since the ground was last settled.
var _changed: Dictionary[int, bool] = {}
var _redeploy_acc: float = 0.0
var _report_done: bool = false


func _init() -> void:
	name = NODE_NAME


func _exit_tree() -> void:
	if _cells != null and _cells.cell_changed.is_connected(_on_cell_changed):
		_cells.cell_changed.disconnect(_on_cell_changed)
	if EventBus.district_entered.is_connected(_on_district_entered):
		EventBus.district_entered.disconnect(_on_district_entered)
	if _crew != null and is_instance_valid(_crew):
		if _crew.parts_delivered.is_connected(_on_parts_delivered):
			_crew.parts_delivered.disconnect(_on_parts_delivered)
		if _crew.chain == chain:
			_crew.chain = null


## The chain of a world (null when it has none).
static func of(world: Node) -> RobotChain:
	return world.get_node_or_null(NODE_NAME) as RobotChain if world != null else null


# --- Setup and state ------------------------------------------------------------------------------

## site_cells[i] = the hex hub site i stands on (new robots are sent to the site of the city in play).
func setup(world: Node, crew: SphereCrew, fleet: Fleet, districts: Districts, cells: SphereCells, site_cells: PackedInt32Array) -> void:
	_world = world
	_crew = crew
	_fleet = fleet
	_districts = districts
	_cells = cells
	_site_cells = site_cells
	chain.configure(Economy.robot_cfg.get("chain", {}))
	crew.chain = chain
	crew.new_robot_hub_fn = work_hub
	if not crew.parts_delivered.is_connected(_on_parts_delivered):
		crew.parts_delivered.connect(_on_parts_delivered)
	if not cells.cell_changed.is_connected(_on_cell_changed):
		cells.cell_changed.connect(_on_cell_changed)
	if not EventBus.district_entered.is_connected(_on_district_entered):
		EventBus.district_entered.connect(_on_district_entered)


func save_state() -> Dictionary:
	settle_ground()
	return chain.to_dict()


## Restores save_state(). `older_save` = a save from before the chain existed: the ground it has
## cleaned already is marked spent (nothing is handed out for the past), and a city Lumi has
## already stood in still gives its salvage and its offer.
func load_state(d: Dictionary, older_save: bool = false) -> void:
	chain.from_dict(d)
	if d.is_empty() and older_save:
		_mark_past_ground()
	for id: String in _districts.ids():
		if _districts.is_visited(id):
			_arrive(id, true)
	if not has_chain():
		return
	if not _unlock_district_exists():
		chain.offered = true  # no city gates it on this planet
	_apply_dev_flags()
	if chain.built:
		_place_model()


## Whether this planet has an Assembler at all.
func has_chain() -> bool:
	return not chain.assembler_cfg().is_empty()


# --- The Assembler as a base build (systems/camp/hub_builds.gd) --------------------------------------

func is_built() -> bool:
	return chain.built


## On the Build list: on offer and not standing yet.
func listed() -> bool:
	return has_chain() and chain.offered and not chain.built


func cost() -> Dictionary:
	return (chain.assembler_cfg().get("cost", {}) as Dictionary).duplicate()


func display_name() -> String:
	return str(chain.assembler_cfg().get("name", "Assembler"))


func description() -> String:
	return str(chain.assembler_cfg().get("desc", ""))


## "" when it can be built now, else why not.
func block_reason() -> String:
	if chain.built:
		return TranslationServer.translate("Built.")
	if not chain.offered:
		return TranslationServer.translate("Not yet.")
	if not Hub.can_pay(cost()):
		return TranslationServer.translate("Not enough materials.")
	return ""


## Pays for the Assembler and stands it up. False when it cannot be built now.
func build() -> bool:
	if block_reason() != "" or not Hub.pay(cost()):
		return false
	_stand_up()
	if model != null:
		MachineReveal.reveal(_world, TranslationServer.translate(display_name()), model.global_position)
	return true


# --- The line (read by ui/assembler_panel.gd) ---------------------------------------------------------

## Robot types the line may build: unlocked, and built once by hand already. In the game's order.
func allowed_types() -> Array[String]:
	var out: Array[String] = []
	for id: String in Economy.robot_order:
		if Research.robot_unlocked(id) and _fleet.count(id) > 0:
			out.append(id)
	return out


## Robot types the mix can name: every unlocked type (one not built by hand yet waits its turn).
func mix_types() -> Array[String]:
	var out: Array[String] = []
	for id: String in Economy.robot_order:
		if Research.robot_unlocked(id):
			out.append(id)
	return out


func price_of(type_id: String) -> float:
	return _fleet.build_parts(type_id).to_float()


func set_weight(type_id: String, w: int) -> void:
	chain.set_weight(type_id, w)


func set_paused(on: bool) -> void:
	chain.paused = on


## The hub a robot built now works for: the base of the city Lumi is in (-1 = the crew's own).
func work_hub() -> int:
	if _districts == null:
		return -1
	var site: int = _districts.site_of(_districts.focus_id())
	return _site_cells[site] if site >= 0 and site < _site_cells.size() else -1


func _physics_process(delta: float) -> void:
	settle_ground()
	_maybe_report()
	_redeploy_acc += delta
	if _redeploy_acc >= REDEPLOY_CHECK_S:
		_redeploy_acc = 0.0
		redeploy()
	if not chain.built:
		return
	_line_acc += delta
	if _line_acc < LINE_STEP_S:
		return
	var dt: float = _line_acc
	_line_acc = 0.0
	var out: Dictionary = chain.tick_line(dt, GameState.get_currency("parts").to_float(), _fleet.has_room(), allowed_types(), price_of)
	if float(out["spend"]) > 0.0:
		GameState.spend("parts", BigNum.from_float(float(out["spend"])))
	if str(out["built"]) != "":
		_roll_out(str(out["built"]))
	if model != null and is_instance_valid(model):
		model.set_building(chain.status == CrewChain.BUILDING)


## Robots with nothing left to do in another city follow Lumi: one that has been idle there for
## the table's redeploy_idle_s is shipped to the base of the city she is in. Returns how many moved.
func redeploy() -> int:
	var hub: int = work_hub()
	var wait_s: float = float(chain.cfg.get("redeploy_idle_s", 0.0))
	if hub < 0 or wait_s <= 0.0 or _crew == null:
		return 0
	var moved: int = 0
	for u: Dictionary in _crew.robots():
		if int(u["hub"]) != hub and _crew.idle_for(u) >= wait_s:
			_crew.reassign(u, hub)
			moved += 1
	return moved


func _roll_out(type_id: String) -> void:
	var hub: int = _crew.hub_for_new_robot()
	var cell: int = _crew.delivery_cell(hub)
	if model != null and is_instance_valid(model) and hub == _crew.hub_cell:
		cell = _crew.grid.cell_at(_crew.surface.up_at(model.door_position()))
	var u: Dictionary = _crew.spawn(type_id, _fleet.tier_of(type_id), cell, hub)
	GameState.inc_stat("robots_built")
	GameState.inc_stat("robots_assembled")
	EventBus.robot_built.emit(str(u["name"]))
	EventBus.robot_assembled.emit(type_id, str(u["name"]))
	if Once.take("toast_first_assembled"):
		EventBus.toast.emit(tr("The Assembler built its first robot. Set the build mix at the workbench."), "story")


# --- World events ----------------------------------------------------------------------------------

## A hex changed. Whether it is clean land is judged on the next tick (settle_ground), not here:
## the ground under a new building is cleaned first and marked as hub ground a moment later, and
## that ground must give nothing.
func _on_cell_changed(c: int) -> void:
	if not chain.seeded.has(c):
		_changed[c] = true


## Seeds the hexes that have become clean land since the last call. Runs on the fixed tick and
## before a save.
func settle_ground() -> void:
	if _changed.is_empty():
		return
	for c: int in _changed:
		if not chain.seeded.has(c) and Districts.cell_stage(_cells, c) >= 1:
			chain.seed_cell(c, _districts.district_of_cell(c))
	_changed.clear()


func _on_parts_delivered(parts: float, _hub: int) -> void:
	var whole: float = chain.deliver(parts)
	if whole <= 0.0:
		return
	GameState.add_currency("parts", BigNum.from_float(whole))
	GameState.inc_stat("parts_scrounged", whole)
	EventBus.parts_scrounged.emit(whole)
	if Once.take("toast_first_scrounge"):
		EventBus.toast.emit(tr("Your Scrounger brought parts home. Newly cleaned ground holds more."), "story")


func _on_district_entered(district_id: String) -> void:
	_arrive(district_id, false)


## Lumi stands in a city for the first time (or a save is loaded in which she has).
func _arrive(district_id: String, quiet: bool) -> void:
	var parts: float = chain.claim_arrival(district_id)
	if parts > 0.0:
		GameState.add_currency("parts", BigNum.from_float(parts))
		EventBus.salvage_found.emit(district_id, parts)
		if not quiet:
			EventBus.toast.emit(tr("Salvage: %s in an old factory shell.") % L10nFmt.amount("parts", parts), "reward")
	if has_chain() and not chain.offered and district_id == _unlock_district():
		chain.offered = true
		EventBus.assembler_offered.emit()
		if not quiet:
			EventBus.toast.emit(tr("The old factory line can run again. Build the Assembler at the workbench."), "story")


func _unlock_district() -> String:
	return str((chain.assembler_cfg().get("unlock", {}) as Dictionary).get("district", ""))


func _unlock_district_exists() -> bool:
	return _unlock_district() != "" and _districts.has(_unlock_district())


func _stand_up() -> void:
	chain.built = true
	chain.offered = true
	_place_model()
	EventBus.assembler_built.emit()


## Hexes already clean in a save from before the chain: they give nothing.
func _mark_past_ground() -> void:
	for c: int in _cells.state.size():
		if Districts.cell_stage(_cells, c) >= 1:
			chain.mark_spent(c)


## The building, at the table's spot on the base site ("pos" and "yaw_deg" in site metres, or a
## named "anchor"), in the same frame as the Depot (no site: no model, the line still runs).
func _place_model() -> void:
	if model != null and is_instance_valid(model):
		return
	var depot: Node3D = _world.get("depot") as Node3D if _world != null and "depot" in _world else null
	if depot == null or depot.get_parent() == null or base_site == null:
		return
	var cfg: Dictionary = chain.assembler_cfg()
	var at: Array = cfg.get("pos", [])
	var anchor: String = str(cfg.get("anchor", ""))
	if at.size() < 2 and base_site.anchor(anchor) == null:
		return
	model = AssemblerModel.new()
	model.name = "AssemblerModel"
	depot.get_parent().add_child(model)
	if at.size() >= 2:
		model.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(cfg.get("yaw_deg", 0.0)))), Vector3(float(at[0]), 0.0, float(at[1])))
	else:
		model.transform = base_site.anchor_local(anchor)
	_crew.set_obstacles(BUILD_ID, [[_crew.surface.up_at(model.global_position), AssemblerModel.FOOTPRINT_R]])


# --- Dev ---------------------------------------------------------------------------------------------

func _apply_dev_flags() -> void:
	if DevHooks.has(FLAG_BUILD) and not chain.built:
		_stand_up()
	if DevHooks.has(FLAG_GROUND):
		var spec: String = DevHooks.get_s(FLAG_GROUND, "3")
		var rings: int = maxi(int(spec.get_slice(":", 0)), 1)
		var parts: float = float(spec.get_slice(":", 1)) if ":" in spec else DEFAULT_DEV_GROUND
		var n: int = 0
		for c: int in _crew.grid.cells_around(_crew.hub_cell, rings):
			if Districts.cell_stage(_cells, c) == Districts.NOT_LAND or chain.seeded.has(c):
				continue
			chain.seeded[c] = true
			chain.stock[c] = parts
			chain.seeded_parts += parts
			n += 1
		print("[chain] dev: %d hexes within %d rings hold %.1f buried parts each" % [n, rings, parts])
	if DevHooks.has(FLAG_ZONE):
		for pair: String in DevHooks.get_s(FLAG_ZONE, "").split(",", false):
			var role: String = pair.get_slice(":", 0)
			var rings: int = maxi(int(pair.get_slice(":", 1)), 0)
			for c: int in _crew.grid.cells_around(_crew.hub_cell, rings):
				_crew.set_zone_cell(role, c, true)
			print("[chain] dev: %s zone = %d hexes round the base" % [role, (_crew.zones.get(role, {}) as Dictionary).size()])


func _maybe_report() -> void:
	if _report_done or not DevHooks.has(FLAG_REPORT) or not DevHooks.has("quit-after"):
		return
	if DevHooks._elapsed < DevHooks.get_f("quit-after", 5.0) - 1.0:
		return
	_report_done = true
	print(report_line())


## One line of numbers for dev runs and the bot's log.
func report_line() -> String:
	var by_type: PackedStringArray = []
	for id: String in Economy.robot_order:
		if _fleet.count(id) > 0:
			by_type.append("%s=%d" % [id, _fleet.count(id)])
	return "[chain] crew %d/%d (%s) | ground %.0f seeded, %.0f left | scrounged %.0f | assembler %s, line '%s' %s %d%%, built %d" % [
		_fleet.robot_total(), _fleet.crew_cap(), ", ".join(by_type), chain.seeded_parts, chain.stock_total(), chain.delivered_parts,
		"built" if chain.built else ("offered" if chain.offered else "locked"), chain.status, chain.current,
		int(chain.progress() * 100.0), int(GameState.stats.get("robots_assembled", 0.0))]
