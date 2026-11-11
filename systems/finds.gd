class_name Finds
extends Node
## Where the planet being played hides the pieces of Lumi's looks (design spec section 13). Reads
## the planet's `finds` table and hands pieces to Looks.grant() when the player earns them:
##   buried  a paint tin or lens chip under an ordinary hex of a city (or of open ground): each
##           hex cleaned there may turn it up, and a set count of hexes turns it up for certain;
##   wreck   an old robot under the trash, off the main path: its pieces come when its hex is
##           cleared, or when Lumi uses the wreck once the world has put one there (register_site);
##   source  given when a city's pollution source is shut down;
##   secret  given when a curiosity is found.
## A planet without the table hides nothing. Which pieces a planet offers is its data alone.
##
## Everything is decided from the planet's seed and the find's id, never from a live random
## number, so a find turns up at the same cleaned hex in every run, the simulator and the tests
## can replay it, and a reload cannot re-roll it.
##
## State (the planet's save section): the ids already taken, how many hexes have been cleaned in
## each city, and the hex each wreck stands on.
##
## Use: var f := Finds.new(); add_child(f); f.setup(def, districts, cells, interactables);
## f.load_state(saved).

const TABLE: String = "finds"
const BURIED: String = "buried"
const WRECK: String = "wreck"
const SOURCE: String = "source"
const SECRET: String = "secret"
## The key of the hex counter for hexes outside every city.
const OPEN_GROUND: String = ""
const NO_CELL: int = -1
const SITE_REACH_M: float = 2.6
const DEFAULT_RING_SHARE: Array = [0.5, 0.9]

var _def: PlanetDefinition
var _districts: Districts
var _cells: SphereCells
var _interactables: Interactables
var _entries: Array[Dictionary] = []
var _shut_stage: int = 0
var _taken: Dictionary[String, bool] = {}
var _hexes: Dictionary[String, int] = {}
var _wreck_cells: Dictionary[String, int] = {}
var _sites: Dictionary[String, Node3D] = {}
var _caught_up: bool = false


# --- Rules (static: the game, the tests and the simulator share them) ---------------------------

## The planet's finds with every field filled in: {id, pieces, where, district, chance_per_hex,
## from_hex, by_hex, ring_share, egg, hint}. Entries that name no known piece are left out.
static func entries_for(def: PlanetDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Dictionary = def.table(TABLE) if def else {}
	for raw: Variant in table.get("finds", []):
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var pieces: Array[String] = []
		var listed: Array = e.get("pieces", [e.get("piece", "")])
		for p: Variant in listed:
			if Looks.exists(str(p)):
				pieces.append(str(p))
		if pieces.is_empty() or str(e.get("id", "")) == "":
			push_error("Finds: entry '%s' names no known piece" % str(e.get("id", "")))
			continue
		var from_hex: int = maxi(1, int(e.get("from_hex", 1)))
		out.append({
			"id": str(e["id"]), "pieces": pieces, "where": str(e.get("where", BURIED)),
			"district": str(e.get("district", OPEN_GROUND)),
			"chance_per_hex": clampf(float(e.get("chance_per_hex", 0.0)), 0.0, 1.0),
			"from_hex": from_hex, "by_hex": maxi(from_hex, int(e.get("by_hex", from_hex))),
			"ring_share": e.get("ring_share", DEFAULT_RING_SHARE), "egg": str(e.get("egg", "")),
			"hint": str(e.get("hint", "")),
		})
	return out


## Every piece this planet hides.
static func pieces_for(def: PlanetDefinition) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in entries_for(def):
		out.append_array(e["pieces"])
	return out


## The one hint line for an unfound piece on this planet, in English: where its find lies, else
## the piece's general hint (Looks.hint).
static func hint_for(def: PlanetDefinition, piece: String) -> String:
	for e: Dictionary in entries_for(def):
		if piece in (e["pieces"] as Array) and e["hint"] != "":
			return str(e["hint"])
	return Looks.hint(piece)


## The design this planet's wrecks and sources hold ("" when it offers none).
static func set_for(def: PlanetDefinition) -> String:
	return str((def.table(TABLE) if def else {}).get("set", ""))


## Seconds a found piece is shown on Lumi (the planet's data; 0 when it has no finds).
static func reveal_s(def: PlanetDefinition) -> float:
	return float((def.table(TABLE) if def else {}).get("reveal_s", 0.0))


## A fixed number in 0..1 for (planet seed, find, n): the same in every run.
static func roll(world_seed: int, find_id: String, n: int) -> float:
	return float(hash("%d/%s/%d" % [world_seed, find_id, n]) % 1000003) / 1000003.0


## The cleaned hex (counted from 1 within its city) at which a buried find turns up: the first
## one from `from_hex` whose roll falls under the chance, and `by_hex` at the latest.
static func buried_hex(world_seed: int, e: Dictionary) -> int:
	var last: int = int(e["by_hex"])
	for n: int in range(int(e["from_hex"]), last):
		if roll(world_seed, str(e["id"]), n) < float(e["chance_per_hex"]):
			return n
	return last


# --- Setup and state --------------------------------------------------------------------------

func setup(def: PlanetDefinition, districts: Districts, cells: SphereCells, interactables: Interactables = null) -> void:
	_def = def
	_districts = districts
	_cells = cells
	_interactables = interactables
	_entries = entries_for(def)
	_shut_stage = int((def.table(TABLE) if def else {}).get("source_shut_at_stage", 0))
	EventBus.hex_cleaned.connect(_on_hex_cleaned)
	EventBus.district_stage_changed.connect(_on_district_stage_changed)
	EventBus.source_shut_down.connect(shut_source)
	EventBus.easter_egg_found.connect(_on_egg_found)


## The registry wrecks are used through, when it is built after this node.
func set_interactables(interactables: Interactables) -> void:
	_interactables = interactables


func _exit_tree() -> void:
	for pair: Array in [[EventBus.hex_cleaned, _on_hex_cleaned], [EventBus.district_stage_changed, _on_district_stage_changed],
			[EventBus.source_shut_down, shut_source], [EventBus.easter_egg_found, _on_egg_found]]:
		if (pair[0] as Signal).is_connected(pair[1] as Callable):
			(pair[0] as Signal).disconnect(pair[1] as Callable)


func save_state() -> Dictionary:
	return {"taken": _taken.keys(), "hexes": _hexes.duplicate(), "wreck_cells": _wreck_cells.duplicate()}


## Restores a save_state() dictionary. An empty one (a save from before finds) starts every
## counter at zero: what was cleaned before does not count.
func load_state(d: Dictionary) -> void:
	_taken.clear()
	_hexes.clear()
	_wreck_cells.clear()
	for id: Variant in d.get("taken", []):
		_taken[str(id)] = true
	var hexes: Dictionary = d.get("hexes", {}) if d.get("hexes") is Dictionary else {}
	for k: Variant in hexes:
		_hexes[str(k)] = int(hexes[k])
	var wrecks: Dictionary = d.get("wreck_cells", {}) if d.get("wreck_cells") is Dictionary else {}
	for k: Variant in wrecks:
		_wreck_cells[str(k)] = int(wrecks[k])
	_caught_up = false


func _process(_delta: float) -> void:
	if not _caught_up:
		catch_up()


## Gives what the world's state already owes: a source find of a city whose source is shut, a
## wreck whose ground is already clear. Runs once after setup or a load, when listeners are up.
func catch_up() -> void:
	_caught_up = true
	if _districts == null:
		return
	for e: Dictionary in _entries:
		if is_taken(str(e["id"])):
			continue
		if e["where"] == SOURCE and _shut_stage > 0 and _districts.stage_of(str(e["district"])) >= _shut_stage:
			_release(e)
		elif e["where"] == WRECK and site_cell(str(e["id"])) == NO_CELL:
			_release(e)
		elif e["where"] == SECRET and bool(GameState.flags.get("egg_" + str(e["egg"]), false)):
			_release(e)


# --- Queries ----------------------------------------------------------------------------------

func entries() -> Array[Dictionary]:
	return _entries


func entry(find_id: String) -> Dictionary:
	for e: Dictionary in _entries:
		if e["id"] == find_id:
			return e
	return {}


func is_taken(find_id: String) -> bool:
	return _taken.has(find_id)


## Hexes cleaned so far in a city (OPEN_GROUND for outside every city).
func hexes_cleaned(district: String) -> int:
	return _hexes.get(district, 0)


## The hex a wreck stands on: a dirty land hex in the find's ring band, fixed by the planet's
## seed and kept in the save. NO_CELL when the find is not a wreck, its city is not on this
## globe, or no dirty hex is left in the band.
func site_cell(find_id: String) -> int:
	if _wreck_cells.has(find_id):
		return _wreck_cells[find_id]
	var e: Dictionary = entry(find_id)
	if e.is_empty() or e["where"] != WRECK or _districts == null or _cells == null:
		return NO_CELL
	var cell: int = _pick_wreck_cell(e)
	_wreck_cells[find_id] = cell
	return cell


func _pick_wreck_cell(e: Dictionary) -> int:
	var cells: PackedInt32Array = _districts.cells_of(str(e["district"]))
	if cells.is_empty():
		return NO_CELL
	var rings: int = int(_districts.spec_of(str(e["district"])).get("rings", 0))
	var share: Array = e["ring_share"]
	var lo: int = clampi(Districts.hexes_for_rings(int(float(share[0]) * rings)), 0, cells.size() - 1)
	var hi: int = clampi(Districts.hexes_for_rings(int(float(share[1]) * rings)), lo + 1, cells.size())
	var span: int = hi - lo
	var start: int = int(roll(_def.world_seed, str(e["id"]), 0) * span)
	for k: int in span:
		var c: int = cells[lo + (start + k) % span]
		if Districts.cell_stage(_cells, c) == 0:
			return c
	return NO_CELL


# --- The world's side ---------------------------------------------------------------------------

## The world has put a wreck (or any other thing to use) where a find is: Lumi takes the find by
## using it, and clearing its hex no longer gives it. Returns false for an unknown or taken find.
func register_site(find_id: String, anchor: Node3D, prompt: Variant, reach_m: float = SITE_REACH_M) -> bool:
	var e: Dictionary = entry(find_id)
	if e.is_empty() or is_taken(find_id) or anchor == null or _interactables == null:
		return false
	_sites[find_id] = anchor
	_interactables.register(anchor, reach_m, prompt, take.bind(find_id), _site_usable.bind(find_id))
	return true


func _site_usable(find_id: String) -> bool:
	return not is_taken(find_id)


## Give a find now (a used wreck, a dev hook). False when it is unknown or already taken.
func take(find_id: String) -> bool:
	var e: Dictionary = entry(find_id)
	if e.is_empty() or is_taken(find_id):
		return false
	_release(e)
	return true


## A city's pollution source was stopped: its source finds are given.
func shut_source(district: String) -> void:
	for e: Dictionary in _entries:
		if e["where"] == SOURCE and e["district"] == district and not is_taken(str(e["id"])):
			_release(e)


# --- Events -----------------------------------------------------------------------------------

func _on_hex_cleaned(cell: int, _pos: Vector3, _bonus: BigNum) -> void:
	var district: String = _districts.district_of_cell(cell) if _districts else OPEN_GROUND
	var n: int = hexes_cleaned(district) + 1
	_hexes[district] = n
	for e: Dictionary in _entries:
		if e["where"] == WRECK and not is_taken(str(e["id"])) and not _sites.has(str(e["id"])) and site_cell(str(e["id"])) == cell:
			_release(e)
	for e: Dictionary in _entries:
		if e["where"] != BURIED or e["district"] != district or is_taken(str(e["id"])):
			continue
		if n >= buried_hex(_def.world_seed, e):
			_release(e)
			break  # one buried find per hex


func _on_district_stage_changed(district: String, stage: int) -> void:
	if _shut_stage > 0 and stage >= _shut_stage:
		shut_source(district)


func _on_egg_found(egg_id: String) -> void:
	for e: Dictionary in _entries:
		if e["where"] == SECRET and e["egg"] == egg_id and not is_taken(str(e["id"])):
			_release(e)


func _release(e: Dictionary) -> void:
	_taken[str(e["id"])] = true
	if DevHooks.has("autoplay"):  # pacing log
		print("[looks] find %s (%s) at %.1f min, %d hexes cleaned" % [e["id"], ", ".join(e["pieces"]), float(GameState.stats.get("time_played", 0.0)) / 60.0,
			int(GameState.stats.get("hexes_cleaned", 0))])
	for piece: String in e["pieces"]:
		Looks.grant(piece, str(e["where"]))
