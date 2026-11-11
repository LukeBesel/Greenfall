class_name Rigs
extends Node
## Lumi's rig (design spec section 7): modules fitted to her body at the workbench, one per slot.
## Everything about them is the planet's "rigs" table: the slots, each module's slot, what it
## changes, what it costs, the city whose opening brings its plan, and the pollution kind it is the
## tool for. A kind whose gate names a module (pollution kinds table, gate.module) can be worked by
## Lumi only while that module is fitted: each city's kind needs its tool, and the tool takes a slot.
##
## Rigs are function. Looks (systems/looks.gd, the Locker) are cosmetic and live in their own
## slots; nothing here reads or writes a look.
##
##   state(id)        LOCKED (no plan yet), PLAN (can be built), OWNED, FITTED
##   build(id)        pays the module's cost once; a module with no cost is owned with its plan
##   fit(id)          puts an owned module in its slot (free, any number of times)
##   is_fitted(id)    what the pollution gates ask
##
## While fitted, a module's mods reach the game through two static calls, so no caller needs the
## node: Rigs.stat_mod(stat, value) from Economy.stat for Lumi's own stats, and Rigs.factor(key)
## for the rest (kind_<kind id>, parts_yield, crew_near, crew_radius).
##
## Saved with the planet (the save's orbit section): the modules, their prices and the kinds they
## clear are all this planet's. A planet with no rigs table has no rig and gates nothing by module.
##
## Emits EventBus.rig_module_unlocked(id) when a plan arrives, rig_module_built(id) and
## rig_fitted(slot, id) ("" = the slot was emptied), and its own `changed` after any of them.
##
## Dev flags: --rig=plate_cutter,deep_hold owns and fits the named modules; --rig-plans=<district
## id>,... brings the plans of those cities without opening them.
##
## Use: var r := Rigs.new(); world.add_child(r); r.setup(def, saved)

signal changed

const TABLE: String = "rigs"
const NODE_NAME: String = "Rigs"
const FLAG: String = "rig"
const FLAG_PLANS: String = "rig-plans"
## Set once any plan has arrived: the workbench shows its Rig tab from then on (data/workbench.json).
const FLAG_OPEN: String = "rigs_open"
const UNLOCK_START: String = "start"
const KIND_PREFIX: String = "kind_"

const LOCKED: String = "locked"
const PLAN: String = "plan"
const OWNED: String = "owned"
const FITTED: String = "fitted"

# l10n:begin
## What a stat is called on a module's effect line.
const STAT_LABELS: Dictionary = {
	"capacity": "chest size",
	"scoop_width": "sweep width",
	"scoop_reach": "reach",
	"scoop_rate": "scoop speed",
	"move_speed": "speed",
	"carry_stack": "bales carried",
	"cube_value_mult": "bale value",
	"detector_range": "detector range",
	"parts_yield": "parts found",
	"crew_near": "robots' bonus near Lumi",
	"crew_radius": "range of that bonus",
}
# l10n:end

## The fitted modules' effects, for the static calls. One rig is live at a time (the planet being
## played); the node that owns it clears these when it leaves the tree.
static var _mul: Dictionary[String, float] = {}
static var _add: Dictionary[String, float] = {}
static var _floor: Dictionary[String, float] = {}
static var _sources: Dictionary[String, Array] = {}
## Instance id of the node whose rig is live (a reload may build the new world before the old one
## has left the tree: the old one must not wipe the new one's effects).
static var _live_owner: int = 0

var _slots: Array[String] = []
var _slot_names: Dictionary[String, String] = {}
var _modules: Dictionary[String, Dictionary] = {}
var _kind_names: Dictionary[String, String] = {}
var _district_names: Dictionary[String, String] = {}
var _known: Dictionary[String, bool] = {}
var _owned: Dictionary[String, bool] = {}
var _fit: Dictionary[String, String] = {}
## Set while a save is being read or an old save is being credited: no toasts, no sounds.
var _quiet: bool = false


func _init() -> void:
	name = NODE_NAME


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _live_owner == get_instance_id():
		_clear_live()  # freed without ever leaving a tree (tests, tools): its effects go with it


func _exit_tree() -> void:
	if EventBus.district_unlocked.is_connected(_on_district_unlocked):
		EventBus.district_unlocked.disconnect(_on_district_unlocked)
	if _live_owner == get_instance_id():
		_clear_live()


## The Rigs of a world (null when it has none).
static func of(world: Node) -> Rigs:
	return world.get_node_or_null(NODE_NAME) as Rigs if world != null else null


# --- Live effects (static) ----------------------------------------------------------------------

## A stat of Lumi's with the fitted modules applied: adds, then multipliers, then floors.
static func stat_mod(stat_id: String, value: float) -> float:
	if not _sources.has(stat_id):
		return value
	return maxf((value + _add.get(stat_id, 0.0)) * _mul.get(stat_id, 1.0), _floor.get(stat_id, -INF))


## The fitted modules' multiplier for a key that is not a stat of Lumi's (1.0 when none touches it).
static func factor(key: String) -> float:
	return _mul.get(key, 1.0)


## Breakdown rows for the stat tooltip: [{source, text}].
static func breakdown(stat_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in _sources.get(stat_id, []):
		out.append({"source": TranslationServer.translate("Rig: %s") % TranslationServer.translate(str(row["name"])), "text": str(row["text"])})
	return out


static func _clear_live() -> void:
	_mul.clear()
	_add.clear()
	_floor.clear()
	_sources.clear()


# --- Setup and state ----------------------------------------------------------------------------

## Reads the planet's rig table and restores a save_state() dictionary ({} = nothing owned).
func setup(def: PlanetDefinition, saved: Dictionary = {}) -> void:
	_read(def.table(TABLE) if def else {}, def.table(Pollution.TABLE) if def else {})
	_known.clear()
	_owned.clear()
	_fit.clear()
	_quiet = true
	for id: String in _modules:
		if str(_modules[id].get("district", "")) == "":
			_reveal(id)
	_district_names.clear()
	for spec: Dictionary in Districts.specs_for(def):
		_district_names[str(spec["id"])] = str(spec.get("name", spec["id"]))
		if str((spec.get("unlock", {}) as Dictionary).get("type", "")) == UNLOCK_START:
			_open_district(str(spec["id"]))
	load_state(saved)
	_apply_dev_flag()
	_quiet = false
	_rebuild()
	if not EventBus.district_unlocked.is_connected(_on_district_unlocked):
		EventBus.district_unlocked.connect(_on_district_unlocked)


func _read(table: Dictionary, kinds_table: Dictionary) -> void:
	_slots.clear()
	_slot_names.clear()
	_modules.clear()
	_kind_names.clear()
	for row: Variant in table.get("slots", []):
		var slot: String = str((row as Dictionary).get("id", ""))
		_slots.append(slot)
		_slot_names[slot] = str((row as Dictionary).get("name", slot))
	var rows: Dictionary = table.get("modules", {})
	for id: String in rows:
		if str(rows[id].get("slot", "")) in _slots:
			_modules[id] = rows[id]
	var kinds: Dictionary = kinds_table.get("kinds", {})
	for id: String in kinds:
		_kind_names[id] = str(kinds[id].get("name", id))


func save_state() -> Dictionary:
	var in_slots: Dictionary = {}
	for slot: String in _fit:
		in_slots[slot] = _fit[slot]
	return {"known": _known.keys(), "owned": _owned.keys(), "fit": in_slots}


func load_state(saved: Dictionary) -> void:
	for id: Variant in saved.get("known", []):
		if _modules.has(str(id)):
			_known[str(id)] = true
	for id: Variant in saved.get("owned", []):
		if _modules.has(str(id)):
			_known[str(id)] = true
			_owned[str(id)] = true
	var in_slots: Dictionary = saved.get("fit", {})
	for slot: Variant in in_slots:
		var id: String = str(in_slots[slot])
		if _owned.has(id) and slot_of(id) == str(slot):
			_fit[str(slot)] = id
	_note_open()
	_rebuild()


## Brings the plans of every city already open. `legacy` = the save is from before rigs: its
## cities' tools are fitted wherever their slot is free, so ground it was working stays workable.
func sync_districts(districts: Districts, legacy: bool = false) -> void:
	if districts == null:
		return
	_quiet = true
	for id: String in districts.ids():
		if not districts.is_unlocked(id):
			continue
		_open_district(id)
		if not legacy:
			continue
		for mid: String in _modules:
			if str(_modules[mid].get("district", "")) == id and is_tool(mid) and not _fit.has(slot_of(mid)):
				_fit[slot_of(mid)] = mid
	_quiet = false
	_rebuild()


func _apply_dev_flag() -> void:
	for district: String in DevHooks.get_s(FLAG_PLANS, "").split(",", false):
		_open_district(district)
	for id: String in DevHooks.get_s(FLAG, "").split(",", false):
		grant(id)


func _on_district_unlocked(district_id: String) -> void:
	_open_district(district_id)
	_rebuild()


func _open_district(district_id: String) -> void:
	for id: String in _modules:
		if str(_modules[id].get("district", "")) == district_id:
			_reveal(id)


## A module's plan arrives at the bench. One with no cost is owned at once.
func _reveal(id: String) -> void:
	if _known.has(id):
		return
	_known[id] = true
	if cost_of(id).is_empty():
		_owned[id] = true
	_note_open()
	if _quiet:
		return
	EventBus.rig_module_unlocked.emit(id)
	if is_tool(id):
		EventBus.toast.emit(tr("New tool: %s. Fit it at the workbench.") % tr(name_of(id)), "good")


func _note_open() -> void:
	if not _known.is_empty():
		GameState.flags[FLAG_OPEN] = true


# --- Reading ------------------------------------------------------------------------------------

func enabled() -> bool:
	return not _slots.is_empty()


func slots() -> Array[String]:
	return _slots


func slot_name(slot: String) -> String:
	return _slot_names.get(slot, slot)


func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_modules.keys())
	return out


## The modules of a slot, in table order.
func modules_of(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in _modules:
		if slot_of(id) == slot:
			out.append(id)
	return out


func module(id: String) -> Dictionary:
	return _modules.get(id, {})


func slot_of(id: String) -> String:
	return str(module(id).get("slot", ""))


func name_of(id: String) -> String:
	return str(module(id).get("name", id))


func cost_of(id: String) -> Dictionary:
	return module(id).get("cost", {})


func district_of(id: String) -> String:
	return str(module(id).get("district", ""))


## Where a module with no plan yet comes from ("Its plan arrives when Ironside opens.").
func lock_hint(id: String) -> String:
	var district: String = district_of(id)
	return tr("Its plan arrives when %s opens.") % tr(_district_names.get(district, district))


## Whether a module is a pollution kind's tool.
func is_tool(id: String) -> bool:
	return str(module(id).get("tool_for", "")) != ""


## The module that is the tool for a kind ("" when no module is).
func tool_for(kind: String) -> String:
	for id: String in _modules:
		if str(_modules[id].get("tool_for", "")) == kind:
			return id
	return ""


func state(id: String) -> String:
	if is_fitted(id):
		return FITTED
	if _owned.has(id):
		return OWNED
	return PLAN if _known.has(id) else LOCKED


func is_owned(id: String) -> bool:
	return _owned.has(id)


func is_fitted(id: String) -> bool:
	return id != "" and _fit.get(slot_of(id), "") == id


## The module in a slot ("" = empty).
func fitted(slot: String) -> String:
	return _fit.get(slot, "")


## How each fitted module shows on Lumi: [{id, slot, shape, color}] in slot order.
func parts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: String in _slots:
		if fitted(slot) != "":
			out.append(part_of(fitted(slot), module(fitted(slot))))
	return out


## How one module of a rig table shows on the model: {id, slot, shape, color}.
static func part_of(id: String, row: Dictionary) -> Dictionary:
	var part: Dictionary = row.get("part", {})
	return {"id": id, "slot": str(row.get("slot", "")), "shape": str(part.get("shape", "")), "color": Color(str(part.get("color", "#b0b0b0")))}


## What a module changes, one short line each ("+40% chest size"): the kind it clears, then what
## it gives, then what it takes.
func effect_lines(id: String) -> Array[String]:
	var out: Array[String] = []
	var m: Dictionary = module(id)
	if is_tool(id):
		out.append(tr("Clears %s") % tr(_kind_names.get(str(m["tool_for"]), str(m["tool_for"]))))
	var mods: Dictionary = m.get("mods", {})
	var adds: Dictionary = m.get("adds", {})
	var losses: Array[String] = []
	for key: String in mods:
		var line: String = "%+d%% %s" % [roundi((float(mods[key]) - 1.0) * 100.0), _label(key)]
		if float(mods[key]) >= 1.0:
			out.append(line)
		else:
			losses.append(line)
	for key: String in adds:
		var line: String = "%+d %s" % [roundi(float(adds[key])), _label(key)]
		if float(adds[key]) >= 0.0:
			out.append(line)
		else:
			losses.append(line)
	out.append_array(losses)
	return out


func _label(key: String) -> String:
	if key.begins_with(KIND_PREFIX):
		var kind: String = key.trim_prefix(KIND_PREFIX)
		return tr("%s work") % tr(_kind_names.get(kind, kind)).to_lower()
	return tr(str(STAT_LABELS.get(key, key.replace("_", " "))))


# --- Building and fitting -----------------------------------------------------------------------

func can_build(id: String) -> bool:
	return state(id) == PLAN and GameState.can_afford_all(cost_of(id))


## Builds a module from its plan for its cost. False when it has no plan, is owned or is not paid for.
func build(id: String) -> bool:
	if not can_build(id) or not GameState.spend_all(cost_of(id)):
		return false
	_owned[id] = true
	EventBus.rig_module_built.emit(id)
	_rebuild()
	return true


## Fits an owned module in its slot, in place of whatever was there. False when it is not owned.
func fit(id: String) -> bool:
	if not _owned.has(id):
		return false
	if is_fitted(id):
		return true
	_fit[slot_of(id)] = id
	EventBus.rig_fitted.emit(slot_of(id), id)
	_rebuild()
	return true


## Hands a module over without its plan or its price, fitted unless `fit_it` is false (dev flags,
## tests and tools; the game itself only builds and fits).
func grant(id: String, fit_it: bool = true) -> void:
	if not _modules.has(id):
		return
	_known[id] = true
	_owned[id] = true
	if fit_it:
		_fit[slot_of(id)] = id
	_note_open()
	_rebuild()


## Empties a slot.
func unfit(slot: String) -> void:
	if not _fit.has(slot):
		return
	_fit.erase(slot)
	EventBus.rig_fitted.emit(slot, "")
	_rebuild()


## The owned tools Lumi would need for `kinds` and has not fitted, at most one per slot (the first
## kind in the list wins a slot two tools share). The bot fits these; the panel marks them.
func tools_wanted(kinds: Array) -> Array[String]:
	var out: Array[String] = []
	var taken: Dictionary[String, bool] = {}
	for kind: Variant in kinds:
		var id: String = tool_for(str(kind))
		if id == "" or not _owned.has(id) or taken.has(slot_of(id)):
			continue
		taken[slot_of(id)] = true
		if not is_fitted(id):
			out.append(id)
	return out


## Works the fitted modules' effects out again and tells everyone the rig changed.
func _rebuild() -> void:
	_clear_live()
	_live_owner = get_instance_id()
	for slot: String in _slots:
		var id: String = fitted(slot)
		if id == "":
			continue
		var m: Dictionary = module(id)
		var mods: Dictionary = m.get("mods", {})
		for key: String in mods:
			_mul[key] = _mul.get(key, 1.0) * float(mods[key])
			_note_source(key, id, "x%.2f" % float(mods[key]))
		var adds: Dictionary = m.get("adds", {})
		for key: String in adds:
			_add[key] = _add.get(key, 0.0) + float(adds[key])
			_note_source(key, id, "%+d" % roundi(float(adds[key])))
		var floors: Dictionary = m.get("floors", {})
		for key: String in floors:
			_floor[key] = maxf(_floor.get(key, -INF), float(floors[key]))
			_note_source(key, id, tr("at least %d") % roundi(float(floors[key])))
	changed.emit()


func _note_source(key: String, id: String, text: String) -> void:
	if not _sources.has(key):
		_sources[key] = []
	_sources[key].append({"name": name_of(id), "text": text})
