class_name PollutionCrew
extends RefCounted
## The apprentice rule on the ground (design spec section 3): which hexes robots must leave alone
## because they hold a pollution kind Lumi has not learnt, and how fast robots work the kinds she
## has. Pollution owns one of these; the crew asks Pollution.
##
## Scooped kinds (pieces, heavy pieces, floating waste) share a hex's pieces, so the gate is the
## whole hex: while a hex still holds a scooped kind under the level robots need, it is shut to
## them (SphereCells.shut, which every robot path reads: near robots, far records, the offline
## jump). Lumi can clear the kind off the hex herself, or learn it: both open the hex. Kinds worked
## with a tool (held) are gated one by one in Pollution's own robot calls.
##
## Use: var g := PollutionCrew.new(); g.setup(pollution, cells, mastery); g.refresh()

var _pollution: Pollution
var _cells: SphereCells
var _mastery: Mastery
var _ids: Array[String] = []
var _scooped := PackedByteArray()
var _gated := PackedByteArray()
var _factor := PackedFloat32Array()
var _role_gated: Dictionary[String, bool] = {}
var _any_scoop_gated: bool = false
var _recheck: Dictionary[int, bool] = {}


func setup(pollution: Pollution, cells: SphereCells, mastery: Mastery) -> void:
	_pollution = pollution
	_cells = cells
	_mastery = mastery
	_ids = pollution.ids()
	_scooped.resize(_ids.size())
	for k: int in _ids.size():
		_scooped[k] = 0 if str(pollution.kind(_ids[k])["work"]) == Pollution.WORK_HELD else 1
	refresh()


## Re-reads every kind's gate and rate from mastery and rewrites the shut hexes.
func refresh() -> void:
	var before: PackedByteArray = _gated.duplicate()
	_gated.resize(_ids.size())
	_factor.resize(_ids.size())
	_role_gated.clear()
	_any_scoop_gated = false
	for k: int in _ids.size():
		var learnt: bool = _mastery == null or _mastery.robots_can_work(_ids[k])
		_gated[k] = 0 if learnt else 1
		_factor[k] = _mastery.robot_factor(_ids[k]) if _mastery != null else 1.0
		if learnt:
			continue
		_any_scoop_gated = _any_scoop_gated or _scooped[k] == 1
		for role: Variant in (_pollution.kind(_ids[k]).get("robot_roles", []) as Array):
			_role_gated[str(role)] = true
	if before == _gated:
		return  # a level past the first: the rates moved, the shut hexes did not
	_recheck.clear()
	_write_shut()


func _write_shut() -> void:
	if _cells == null:
		return
	if not _any_scoop_gated:
		_cells.shut = PackedByteArray()
		return
	_cells.shut.resize(_cells.n)
	# Outside the cities a hex holds the default kinds: all shut while the base kind is unlearnt.
	# Only a default kind beside the base kind needs every hex looked at.
	var base_gated: bool = _gated[0] == 1
	_cells.shut.fill(1 if base_gated else 0)
	var lists: Array[PackedInt32Array] = _pollution.zone_lists()
	if not base_gated and _default_gated():
		lists = [PackedInt32Array(range(_cells.n))]
	for list: PackedInt32Array in lists:
		for c: int in list:
			_cells.shut[c] = 1 if _hex_shut(c) else 0


func _default_gated() -> bool:
	for k: int in _pollution.default_kinds():
		if k != 0 and _gated[k] == 1 and _scooped[k] == 1:
			return true
	return false


## Whether a hex still holds a scooped kind robots may not work.
func _hex_shut(cell: int) -> bool:
	for id: String in _pollution.kinds_left(cell):
		var k: int = _ids.find(id)
		if _gated[k] == 1 and _scooped[k] == 1:
			return true
	return false


## Lumi took waste off a hex: look at it again on the next flush (she may have cleared the kind).
func touched(cell: int) -> void:
	if _cells != null and _cells.is_shut(cell):
		_recheck[cell] = true


func flush() -> void:
	if _recheck.is_empty():
		return
	for c: int in _recheck:
		if c < _cells.shut.size():
			_cells.shut[c] = 1 if _hex_shut(c) else 0
	_recheck.clear()


## Whether robots may work kind index `k`.
func open(k: int) -> bool:
	return k >= _gated.size() or _gated[k] == 0


## A robot's rate multiplier on kind index `k`.
func factor(k: int) -> float:
	return _factor[k] if k < _factor.size() else 1.0


## A scooping robot's rate multiplier on a hex: the mean over its scooped kinds by their share.
func scoop_speed(cell: int) -> float:
	if _mastery == null:
		return 1.0
	var sum: float = 0.0
	var weight: float = 0.0
	for k: int in _pollution.kinds_at(cell):
		if _scooped[k] == 0:
			continue
		var share: float = _pollution.share_of(cell, _ids[k])
		sum += share * _factor[k]
		weight += share
	return sum / weight if weight > 0.0 else _factor[0]


## Whether any kind a role works is closed to robots (so an idle robot may have a reason to give).
func role_gated(role: String) -> bool:
	return _role_gated.has(role)


## The kind still on a hex that a robot of `role` would work had Lumi learnt it ("" = none).
func gate_kind(role: String, cell: int) -> String:
	if not _role_gated.has(role):
		return ""
	for id: String in _pollution.kinds_left(cell):
		if _gated[_ids.find(id)] == 1 and role in (_pollution.kind(id).get("robot_roles", []) as Array):
			return id
	return ""
