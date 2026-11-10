class_name Districts
extends Node
## The districts (cities) of the planet being played: the chapters of its story (design spec
## section 1). Each district is the hexes within `rings` of one hub site. This node keeps, per
## district, how many of its land hexes stand at each regrowth stage, the district's own stage,
## whether it is unlocked and whether the player has been there.
##
## A hex's stage is its regrowth level (SphereCells.level, written from HexLevels), and at least 1
## once its pollution is gone. Land = not water and not hub ground (the yard, under buildings).
## A district's stage is the highest stage that at least `stage_share` of its land hexes have
## reached. It never drops: a hex dirtied again lowers the share, not the stage.
##
## Counts are kept up to date from SphereCells.cell_changed, one dictionary lookup per changed
## cell; nothing scans the globe after setup.
##
## A planet with no "districts" table plays as ONE district: its start site (site 0), named after
## the planet, FALLBACK_RINGS in size, unlocked from the start. Every other site is open ground.
## So every planet has a district readout and an ending without any data.
##
## Emits on EventBus: district_unlocked(id), district_stage_changed(id, stage), and
## district_entered(id) the first time the player stands in an unlocked district (districts open
## from the start are not arrivals and never emit it).
##
## Use: var d := Districts.new(); add_child(d); d.setup(def, grid, cells, site_cells);
## d.load_state(saved); d.player_cell_fn = func() -> int: ...

const TABLE: String = "districts"
const MAX_STAGE: int = 5
## A planet without a districts table: the size of its one district and of every open-ground
## region (the size every hub region had before districts existed), and the stage share.
const FALLBACK_RINGS: int = 18
const FALLBACK_STAGE_SHARE: float = 0.8
const UNLOCK_START: String = "start"
const UNLOCK_DISTRICT_STAGE: String = "district_stage"
const TRAVEL_ALL_UNLOCKED: String = "all_unlocked"
const TRAVEL_ALWAYS: String = "always"
const POLL_S: float = 0.5
const NOT_LAND: int = -1

## Returns the hex the player stands on (-1 when unknown). Polled a few times a second.
var player_cell_fn: Callable
var stage_share: float = FALLBACK_STAGE_SHARE

var _specs: Array[Dictionary] = []
var _index: Dictionary[String, int] = {}
var _site_district: Dictionary[int, int] = {}
var _open_travel: String = TRAVEL_ALL_UNLOCKED
var _cells: SphereCells
var _district_cells: Array[PackedInt32Array] = []
var _cell_district: Dictionary[int, int] = {}
var _cell_stage: Dictionary[int, int] = {}
## Per district: how many land hexes stand at exactly each stage (index 0..MAX_STAGE).
var _counts: Array[PackedInt32Array] = []
var _stage := PackedInt32Array()
var _unlocked := PackedByteArray()
var _visited := PackedByteArray()
var _current: int = -1
var _focus: int = 0
var _poll: float = 0.0
var _quiet: bool = false


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or not player_cell_fn.is_valid():
		return
	_poll = POLL_S
	set_player_cell(int(player_cell_fn.call()))


func _exit_tree() -> void:
	if _cells and _cells.cell_changed.is_connected(_on_cell_changed):
		_cells.cell_changed.disconnect(_on_cell_changed)


# --- Data (static: SiteManager and tests read the same rules) -------------------------------

## The planet's districts in play order, every field filled in: {id, name, site, rings,
## pollution, unlock}. A planet without the table gets its one implicit district.
static func specs_for(def: PlanetDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	if not def.has_table(TABLE):
		out.append({"id": String(def.id), "name": def.display_name, "site": 0, "rings": FALLBACK_RINGS,
			"pollution": [], "unlock": {"type": UNLOCK_START}})
		return out
	for raw: Variant in def.table(TABLE).get("districts", []):
		if not raw is Dictionary:
			continue
		var d: Dictionary = raw
		var id: String = str(d.get("id", ""))
		if id == "":
			continue
		var unlock: Dictionary = d.get("unlock", {"type": UNLOCK_START})
		out.append({"id": id, "name": str(d.get("name", id.capitalize())), "site": int(d.get("site", 0)),
			"rings": maxi(0, int(d.get("rings", FALLBACK_RINGS))), "pollution": d.get("pollution", []), "unlock": unlock})
	return out


## Region size, in rings, of hub site `site`: its district's, or the open-ground size.
static func rings_for_site(def: PlanetDefinition, site: int) -> int:
	for spec: Dictionary in specs_for(def):
		if int(spec["site"]) == site:
			return int(spec["rings"])
	if def == null or not def.has_table(TABLE):
		return FALLBACK_RINGS
	return maxi(0, int(def.table(TABLE).get("open_ground_rings", FALLBACK_RINGS)))


## Hexes within `rings` of a hex on a grid of six-sided cells.
static func hexes_for_rings(rings: int) -> int:
	return 1 + 3 * rings * (rings + 1)


## The hexes of a region: `cell` and everything within `rings` rings of it, nearest first.
static func region_cells(grid: SphereGrid, cell: int, rings: int) -> PackedInt32Array:
	return grid.cells_around(cell, rings) if grid else PackedInt32Array()


## The English name of a regrowth stage from the planet's "regrowth" table ("" when it has none);
## whoever shows it passes it through tr().
static func stage_name(def: PlanetDefinition, stage: int) -> String:
	var levels: Array = def.table("regrowth").get("levels", []) if def else []
	if stage < 0 or stage >= levels.size() or not levels[stage] is Dictionary:
		return ""
	return str((levels[stage] as Dictionary).get("name", ""))


## The stage a district is at for these counts (land hexes at exactly each stage): the highest
## stage reached by at least `share` of them. 0 when there is no land.
static func stage_from_counts(counts: PackedInt32Array, share: float) -> int:
	var need: int = hexes_needed(counts, share)
	if need <= 0:
		return 0
	var at_least: int = 0
	for s: int in range(mini(MAX_STAGE, counts.size() - 1), 0, -1):
		at_least += counts[s]
		if at_least >= need:
			return s
	return 0


## How many land hexes must reach a stage for the district to be at it (0 when there is no land).
static func hexes_needed(counts: PackedInt32Array, share: float) -> int:
	var land: int = 0
	for n: int in counts:
		land += n
	if land <= 0:
		return 0
	return clampi(ceili(share * float(land) - 0.000001), 1, land)


## Share of the way from `stage` to the next one, 0..1 (1 at the last stage).
static func share_from_counts(counts: PackedInt32Array, share: float, stage: int) -> float:
	if stage >= MAX_STAGE:
		return 1.0
	var need: int = hexes_needed(counts, share)
	if need <= 0:
		return 0.0
	var at_least: int = 0
	for s: int in range(stage + 1, counts.size()):
		at_least += counts[s]
	return clampf(float(at_least) / float(need), 0.0, 1.0)


## The stage of one hex from the globe's cell state (NOT_LAND for water and hub ground).
static func cell_stage(cells: SphereCells, c: int) -> int:
	if cells.state[c] == PlanetData.State.WATER or (cells.flags[c] & SphereCells.F_HUB) != 0:
		return NOT_LAND
	if cells.is_dirty(c):
		return 0
	return clampi(int(cells.level[c]), 1, MAX_STAGE)


# --- Setup and state --------------------------------------------------------------------------

## Builds every district's hex set and counts from the globe as it is now. site_cells[i] is the
## hex hub site i stands on. A district whose site the globe does not have is reported and left
## out. Where two districts overlap, a hex belongs to the earlier one.
func setup(def: PlanetDefinition, grid: SphereGrid, cells: SphereCells, site_cells: PackedInt32Array) -> void:
	_cells = cells
	var table: Dictionary = def.table(TABLE) if def else {}
	stage_share = clampf(float(table.get("stage_share", FALLBACK_STAGE_SHARE)), 0.01, 1.0)
	_open_travel = str(table.get("open_ground_travel", TRAVEL_ALL_UNLOCKED))
	for spec: Dictionary in specs_for(def):
		var site: int = int(spec["site"])
		if site < 0 or site >= site_cells.size():
			push_error("Districts: district '%s' names site %d, but the globe has %d sites" % [spec["id"], site, site_cells.size()])
			continue
		var i: int = _specs.size()
		_specs.append(spec)
		_index[str(spec["id"])] = i
		_site_district[site] = i
		var own := PackedInt32Array()
		var counts := PackedInt32Array()
		counts.resize(MAX_STAGE + 1)
		for c: int in region_cells(grid, site_cells[site], int(spec["rings"])):
			if _cell_district.has(c):
				continue
			_cell_district[c] = i
			own.append(c)
			var st: int = cell_stage(cells, c)
			_cell_stage[c] = st
			if st >= 0:
				counts[st] += 1
		_district_cells.append(own)
		_counts.append(counts)
	var n: int = _specs.size()
	_stage.resize(n)
	_unlocked.resize(n)
	_visited.resize(n)
	_derive()
	if cells and not cells.cell_changed.is_connected(_on_cell_changed):
		cells.cell_changed.connect(_on_cell_changed)


## What a save keeps: the stage each district reached, and which are unlocked and visited.
func save_state() -> Dictionary:
	var stages: Dictionary = {}
	var unlocked: Array[String] = []
	var visited: Array[String] = []
	for i: int in _specs.size():
		var id: String = str(_specs[i]["id"])
		stages[id] = _stage[i]
		if _unlocked[i] == 1:
			unlocked.append(id)
		if _visited[i] == 1:
			visited.append(id)
	return {"stages": stages, "unlocked": unlocked, "visited": visited, "focus": focus_id()}


## Restores a save_state() dictionary. An empty one (a save from before districts existed) leaves
## everything as derived from the globe's hexes: stages from the hex stages, unlocks from the
## rules, and a district counts as visited when the player has cleaned anything in it. Silent: no
## events.
func load_state(d: Dictionary) -> void:
	_derive()
	if d.is_empty():
		return
	var stages: Dictionary = d.get("stages", {})
	for i: int in _specs.size():
		var id: String = str(_specs[i]["id"])
		_stage[i] = clampi(maxi(_stage[i], int(stages.get(id, 0))), 0, MAX_STAGE)
		_visited[i] = 1 if (id in d.get("visited", []) or _starts_open(i)) else 0
		if id in d.get("unlocked", []):
			_unlocked[i] = 1
	_quiet = true
	_apply_unlocks()
	_quiet = false
	_publish_open()
	var focus: int = _index.get(str(d.get("focus", "")), -1)
	if focus >= 0 and _unlocked[focus] == 1:
		_focus = focus


# --- Queries ----------------------------------------------------------------------------------

func count() -> int:
	return _specs.size()


## District ids in play order.
func ids() -> Array[String]:
	var out: Array[String] = []
	for spec: Dictionary in _specs:
		out.append(str(spec["id"]))
	return out


func has(id: String) -> bool:
	return _index.has(id)


## The district's data: {id, name, site, rings, pollution, unlock}. Empty for an unknown id.
func spec_of(id: String) -> Dictionary:
	return _specs[_index[id]] if _index.has(id) else {}


## The English name from the data; whoever shows it passes it through tr().
func name_of(id: String) -> String:
	return str(spec_of(id).get("name", ""))


func site_of(id: String) -> int:
	return int(spec_of(id).get("site", -1))


func stage_of(id: String) -> int:
	return _stage[_index[id]] if _index.has(id) else 0


## Share of the way to the district's next stage, 0..1.
func share_of(id: String) -> float:
	if not _index.has(id):
		return 0.0
	var i: int = _index[id]
	return share_from_counts(_counts[i], stage_share, _stage[i])


## Land hexes of the district (water and hub ground are not land).
func land_of(id: String) -> int:
	if not _index.has(id):
		return 0
	var land: int = 0
	for n: int in _counts[_index[id]]:
		land += n
	return land


## Land hexes of the district at `stage` or above.
func count_at_least(id: String, stage: int) -> int:
	if not _index.has(id):
		return 0
	var counts: PackedInt32Array = _counts[_index[id]]
	var total: int = 0
	for s: int in range(maxi(stage, 0), counts.size()):
		total += counts[s]
	return total


## Every hex of the district, nearest its site first (water and hub ground included).
func cells_of(id: String) -> PackedInt32Array:
	return _district_cells[_index[id]] if _index.has(id) else PackedInt32Array()


func is_unlocked(id: String) -> bool:
	return _index.has(id) and _unlocked[_index[id]] == 1


func is_visited(id: String) -> bool:
	return _index.has(id) and _visited[_index[id]] == 1


func unlocked_count() -> int:
	return _unlocked.count(1)


func all_unlocked() -> bool:
	return unlocked_count() == _specs.size()


## How many districts have reached `stage`.
func count_at_stage(stage: int) -> int:
	var n: int = 0
	for s: int in _stage:
		if s >= stage:
			n += 1
	return n


## The district a hex belongs to, or "".
func district_of_cell(cell: int) -> String:
	var i: int = _cell_district.get(cell, -1)
	return str(_specs[i]["id"]) if i >= 0 else ""


## The district that stands on hub site `site`, or "" for open ground.
func district_of_site(site: int) -> String:
	var i: int = _site_district.get(site, -1)
	return str(_specs[i]["id"]) if i >= 0 else ""


## The district the player stands in right now, or "" between districts.
func current_id() -> String:
	return str(_specs[_current]["id"]) if _current >= 0 else ""


## The district the readouts show: the unlocked district the player is in, else the last one, else
## the first. "" only when the planet has no district at all.
func focus_id() -> String:
	return str(_specs[_focus]["id"]) if _focus >= 0 and _focus < _specs.size() else ""


## Travel rule: whether the rocket may fly to hub site `site`. A district's site is offered once
## the district is unlocked. Open ground follows the table's `open_ground_travel`: by default it
## opens when every district is unlocked, so the chapters are played in order first.
func site_offered(site: int) -> bool:
	var i: int = _site_district.get(site, -1)
	if i >= 0:
		return _unlocked[i] == 1
	match _open_travel:
		TRAVEL_ALWAYS:
			return true
		TRAVEL_ALL_UNLOCKED:
			return all_unlocked()
	return false


# --- Updates ----------------------------------------------------------------------------------

## Tells the districts which hex the player stands on (the node polls player_cell_fn itself).
func set_player_cell(cell: int) -> void:
	var i: int = _cell_district.get(cell, -1)
	if i == _current:
		return
	_current = i
	if i >= 0 and _unlocked[i] == 1:
		_enter(i)


## Recounts one hex after the globe changed it.
func _on_cell_changed(c: int) -> void:
	var i: int = _cell_district.get(c, -1)
	if i < 0:
		return
	var now: int = cell_stage(_cells, c)
	var was: int = _cell_stage[c]
	if now == was:
		return
	_cell_stage[c] = now
	if was >= 0:
		_counts[i][was] -= 1
	if now >= 0:
		_counts[i][now] += 1
	_raise_stage(i)


func _raise_stage(i: int) -> void:
	var reached: int = stage_from_counts(_counts[i], stage_share)
	if reached <= _stage[i]:
		return
	_stage[i] = reached
	EventBus.district_stage_changed.emit(str(_specs[i]["id"]), reached)
	_apply_unlocks()


## Opens every district whose rule is met, in play order, until nothing more opens (a rule may
## name a district listed after it).
func _apply_unlocks() -> void:
	var opened: bool = true
	while opened:
		opened = false
		for i: int in _specs.size():
			if _unlocked[i] == 1 or not _rule_met(_specs[i]["unlock"]):
				continue
			_unlocked[i] = 1
			opened = true
			if _quiet:
				continue
			EventBus.district_unlocked.emit(str(_specs[i]["id"]))
			if i == _current:
				_enter(i)
	_publish_open()


## Writes how many districts are open where the economy reads it: each open district opens the
## next price tier of the upgrade tracks (Economy.tiers_open).
func _publish_open() -> void:
	GameState.flags[Economy.FLAG_TIERS_OPEN] = maxi(1, unlocked_count())


func _rule_met(rule: Dictionary) -> bool:
	match str(rule.get("type", UNLOCK_START)):
		UNLOCK_START:
			return true
		UNLOCK_DISTRICT_STAGE:
			# The named district must be open itself: chapters open in order even when the player
			# has worked ahead in a locked one.
			var other: int = _index.get(str(rule.get("district", "")), -1)
			return other >= 0 and _unlocked[other] == 1 and _stage[other] >= int(rule.get("stage", MAX_STAGE))
	return false


func _starts_open(i: int) -> bool:
	return str((_specs[i]["unlock"] as Dictionary).get("type", UNLOCK_START)) == UNLOCK_START


func _enter(i: int) -> void:
	_focus = i
	if _visited[i] == 1:
		return
	_visited[i] = 1
	EventBus.district_entered.emit(str(_specs[i]["id"]))


## State from the globe alone: stages from the counts, unlocks from the rules, visited where the
## district is open from the start or has any cleaned hex. No events.
func _derive() -> void:
	_focus = 0
	for i: int in _specs.size():
		_stage[i] = stage_from_counts(_counts[i], stage_share)
		_unlocked[i] = 0
	_quiet = true
	_apply_unlocks()
	_quiet = false
	for i: int in _specs.size():
		var cleaned: int = 0
		for s: int in range(1, _counts[i].size()):
			cleaned += _counts[i][s]
		_visited[i] = 1 if _starts_open(i) or (_unlocked[i] == 1 and cleaned > 0) else 0
