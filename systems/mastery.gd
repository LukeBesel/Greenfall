class_name Mastery
extends Node
## Lumi's mastery of each pollution kind on the planet being played (design spec section 3), and
## what it means for her apprentices, the robots. Only Lumi's own work fills it: this listens for
## EventBus.pollution_cleared with by_player. The rules and their numbers are MasteryRules and the
## planet's tables; this node holds the state (units of hand work per kind) and saves it with the
## planet.
##
##   level(kind)             0..max_level
##   hand_bonus(kind)        Lumi's rate on the kind (1 + 0.08 x level on the first planet)
##   robots_can_work(kind)   false under level 1: a robot may not touch the kind
##   robot_factor(kind)      a robot's rate on the kind (0.4 + 0.12 x level), 0 while it may not
##   near_factor(metres)     the bonus for a robot working alongside Lumi
##
## Emits EventBus.mastery_gained(kind, level) once per level reached, and its own `changed`
## whenever a level moves (the pollution system re-reads which hexes robots must leave alone).
## A planet with no `mastery` block in its kinds table has no mastery: every robot may work
## everything at its own rate, and nothing is emitted.
##
## Dev flag: --mastery=N (every kind at level N) or --mastery=litter:3,wrecks:1. With --robots and
## no --mastery every kind starts at the robots table's dev_level, so robot reports keep their rates.
##
## Use: var m := Mastery.new(); world.add_child(m); m.setup(def, saved)

signal changed

const NODE_NAME: String = "Mastery"
const FLAG: String = "mastery"
const FLAG_ROBOTS: String = "robots"
const UNLOCK_START: String = "start"

var _cfg: Dictionary = {}
var _units: Dictionary[String, float] = {}
var _levels: Dictionary[String, int] = {}
var _met: Dictionary[String, bool] = {}
var _district_kinds: Dictionary[String, Array] = {}
## Set while a save from before mastery is being read: level-ups then make no sound.
var _quiet: bool = false


func _init() -> void:
	name = NODE_NAME


func _exit_tree() -> void:
	if EventBus.pollution_cleared.is_connected(_on_pollution_cleared):
		EventBus.pollution_cleared.disconnect(_on_pollution_cleared)
	if EventBus.district_entered.is_connected(_on_district_entered):
		EventBus.district_entered.disconnect(_on_district_entered)


## The Mastery of a world (null when it has none).
static func of(world: Node) -> Mastery:
	return world.get_node_or_null(NODE_NAME) as Mastery if world != null else null


# --- Setup and state --------------------------------------------------------------------------

## Reads the planet's rules and restores a save_state() dictionary ({} = nothing learnt yet).
func setup(def: PlanetDefinition, saved: Dictionary = {}) -> void:
	_cfg = MasteryRules.config(def.table(Pollution.TABLE) if def else {}, def.table("robots") if def else {})
	_units.clear()
	_levels.clear()
	_met.clear()
	_district_kinds.clear()
	for id: String in (_cfg["kinds"] as Dictionary):
		_units[id] = 0.0
		_levels[id] = 0
	for spec: Dictionary in Districts.specs_for(def):
		_district_kinds[str(spec["id"])] = spec.get("pollution", [])
		if str((spec.get("unlock", {}) as Dictionary).get("type", "")) == UNLOCK_START:
			_meet(spec.get("pollution", []))
	load_state(saved)
	_apply_dev_flags()
	if not EventBus.pollution_cleared.is_connected(_on_pollution_cleared):
		EventBus.pollution_cleared.connect(_on_pollution_cleared)
	if not EventBus.district_entered.is_connected(_on_district_entered):
		EventBus.district_entered.connect(_on_district_entered)


func save_state() -> Dictionary:
	var units: Dictionary = {}
	for id: String in _units:
		if _units[id] > 0.0:
			units[id] = _units[id]
	return {"units": units}


func load_state(saved: Dictionary) -> void:
	var units: Dictionary = saved.get("units", {})
	for id: Variant in units:
		if _units.has(str(id)):
			_units[str(id)] = maxf(0.0, float(units[id]))
			_levels[str(id)] = MasteryRules.level_for(_cfg, str(id), _units[str(id)])
			if _units[str(id)] > 0.0:
				_met[str(id)] = true
	changed.emit()


## A save from before mastery: `cleaned` is the waste of its clean hexes by kind (Pollution.
## cleaned_units); the planet's legacy_credit of it counts as Lumi's hand work. `roles` are the
## roles of the robots the save already has: the kinds they work are never under the level
## robots need, so a crew that was working keeps working.
func seed_legacy(cleaned: Dictionary, roles: Array) -> void:
	if not enabled():
		return
	_quiet = true
	for id: Variant in cleaned:
		if _units.has(str(id)):
			_set_units(str(id), maxf(_units[str(id)], float(cleaned[id]) * float(_cfg["legacy_credit"])))
	for role: Variant in roles:
		for id: String in MasteryRules.kinds_of_role(_cfg, str(role)):
			grant(id, int(_cfg["robot_min"]))
	_quiet = false
	changed.emit()


## Marks the kinds of every city Lumi has stood in as met (the readouts list only met kinds).
func sync_districts(districts: Districts) -> void:
	if districts == null:
		return
	for id: String in districts.ids():
		if districts.is_visited(id):
			_meet(_district_kinds.get(id, []))


func _apply_dev_flags() -> void:
	if not enabled():
		return
	var spec: String = DevHooks.get_s(FLAG, "") if DevHooks.has(FLAG) else ""
	if spec == "" and DevHooks.has(FLAG_ROBOTS):
		spec = str(int(_cfg["dev_level"]))
	if spec == "":
		return
	_quiet = true
	for part: String in spec.split(",", false):
		if ":" in part:
			grant(part.get_slice(":", 0), int(part.get_slice(":", 1)))
		else:
			for id: String in _units:
				grant(id, int(part))
	_quiet = false


# --- Queries ----------------------------------------------------------------------------------

func enabled() -> bool:
	return MasteryRules.enabled(_cfg)


func config() -> Dictionary:
	return _cfg


func max_level() -> int:
	return int(_cfg.get("max_level", 0))


## Kind ids that have mastery, in table order.
func kinds() -> Array[String]:
	var out: Array[String] = []
	for id: String in _units:
		if MasteryRules.tracks(_cfg, id):
			out.append(id)
	return out


## The kinds Lumi has met: those of every city she has stood in, and any she has worked.
func met_kinds() -> Array[String]:
	var out: Array[String] = []
	for id: String in kinds():
		if _met.has(id):
			out.append(id)
	return out


func level(kind: String) -> int:
	return int(_levels.get(kind, 0))


func units(kind: String) -> float:
	return float(_units.get(kind, 0.0))


## Share (0..1) of the way from this level to the next (1 at the top level).
func progress(kind: String) -> float:
	var lv: int = level(kind)
	if lv >= max_level() or not MasteryRules.tracks(_cfg, kind):
		return 1.0
	var from: float = MasteryRules.units_for(_cfg, kind, lv)
	var to: float = MasteryRules.units_for(_cfg, kind, lv + 1)
	return clampf((units(kind) - from) / maxf(to - from, 0.001), 0.0, 1.0)


## The kind's shown name (translated).
func kind_name(kind: String) -> String:
	return tr(str((_cfg.get("kinds", {}) as Dictionary).get(kind, {}).get("name", kind)))


func hand_bonus(kind: String) -> float:
	return MasteryRules.hand_bonus(_cfg, level(kind)) if MasteryRules.tracks(_cfg, kind) else 1.0


func robots_can_work(kind: String) -> bool:
	return MasteryRules.robots_allowed(_cfg, kind, level(kind))


func robot_factor(kind: String) -> float:
	return MasteryRules.robot_factor(_cfg, kind, level(kind))


func near_factor(dist_m: float) -> float:
	return MasteryRules.near_factor(_cfg, dist_m)


## The kinds a robot role works that Lumi has met, in table order.
func role_kinds(role: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in MasteryRules.kinds_of_role(_cfg, role):
		if _met.has(id) and MasteryRules.tracks(_cfg, id):
			out.append(id)
	return out


## Why a robot of `role` cannot work a kind Lumi has met: "Lumi must learn wrecks first". "" when
## it may work them all.
func block_text(role: String) -> String:
	for id: String in role_kinds(role):
		if not robots_can_work(id):
			return learn_text(id)
	return ""


func learn_text(kind: String) -> String:
	return tr("Lumi must learn %s first") % kind_name(kind).to_lower()


## One line for a robot's card: "Litter 3  ·  Wrecks 0" over the kinds its role works.
func role_line(role: String) -> String:
	var parts: PackedStringArray = []
	for id: String in role_kinds(role):
		parts.append("%s %d" % [kind_name(id), level(id)])
	return "  ·  ".join(parts)


# --- Changes ----------------------------------------------------------------------------------

## Lumi cleared `amount` units of a kind with her own hands.
func add_work(kind: String, amount: float) -> void:
	if amount <= 0.0 or not MasteryRules.tracks(_cfg, kind):
		return
	_set_units(kind, _units[kind] + MasteryRules.gain(_cfg, kind, amount))


## Raises a kind to at least `level` (dev flags, saves from before mastery).
func grant(kind: String, to_level: int) -> void:
	if not MasteryRules.tracks(_cfg, kind):
		return
	var want: float = MasteryRules.units_for(_cfg, kind, mini(to_level, max_level()))
	if want > _units[kind]:
		_set_units(kind, want)


func _set_units(kind: String, value: float) -> void:
	_units[kind] = value
	_met[kind] = true
	var now: int = MasteryRules.level_for(_cfg, kind, value)
	var before: int = _levels[kind]
	if now == before:
		return
	_levels[kind] = now
	if not _quiet:
		for lv: int in range(before + 1, now + 1):
			EventBus.mastery_gained.emit(kind, lv)
	changed.emit()


func _meet(list: Array) -> void:
	for id: Variant in list:
		if _units.has(str(id)):
			_met[str(id)] = true


func _on_pollution_cleared(kind: String, amount: float, by_player: bool) -> void:
	if by_player:
		add_work(kind, amount)


func _on_district_entered(district_id: String) -> void:
	_meet(_district_kinds.get(district_id, []))
