class_name Compartment
extends RefCounted
## Patch's chest compartment: what junk is inside and how full it is. Pure data (tested).

var contents: Dictionary = {}  # type_id -> volume
var fill: float = 0.0
## What the load pays tipped loose: the sum of its shares of the hexes it came from (HexWorth).
## Below zero when unknown (a chest saved before hexes had a value): priced by the unit instead.
var worth: float = 0.0
## Volume of pieces already flying in (counted so scooping never overshoots by more than one piece).
var pending: float = 0.0


func ratio(capacity: float) -> float:
	return fill / maxf(capacity, 0.001)


## True when another piece may be taken (the last piece is allowed to overflow, making a Lumpy cube).
func can_accept(capacity: float) -> bool:
	return fill + pending < capacity


func reserve(volume: float) -> void:
	pending += volume


func add(type_id: String, volume: float, cubes: float = 0.0) -> void:
	if worth >= 0.0:
		worth += cubes
	pending = maxf(0.0, pending - volume)
	if pending < 0.0001:  # [orbB] float residue (e.g. 1e-15) must not count as "still flying in" and block a dump
		pending = 0.0
	contents[type_id] = float(contents.get(type_id, 0.0)) + volume
	fill += volume


func in_perfect_band(capacity: float, band: Array) -> bool:
	var r: float = ratio(capacity)
	return r >= float(band[0]) and r <= float(band[1]) + 0.0001


func is_empty() -> bool:
	return fill <= 0.0001


## Empties the compartment and returns what was inside.
func take_all() -> Dictionary:
	var out: Dictionary = contents.duplicate()
	contents.clear()
	fill = 0.0
	worth = 0.0
	return out


func to_dict() -> Dictionary:
	return {"contents": contents.duplicate(), "fill": fill, "worth": worth}


func from_dict(d: Dictionary) -> void:
	contents = (d.get("contents", {}) as Dictionary).duplicate()
	fill = float(d.get("fill", 0.0))
	worth = float(d.get("worth", -1.0 if fill > 0.0 else 0.0))
	pending = 0.0
