class_name Tending
extends RefCounted
## Lumi's hand tending on a Garden (design spec section 5; numbers in the regrowth table's
## `tending` block, read into Garden.tending). Planting sets a patch of several plants for one
## seed cost, so a hex takes a few actions, not dozens. Watering soaks every plant on the hex in
## front of her for wet_s (3 minutes of full growth; thirsty plants grow at dry_rate) and gives the
## hex an immediate growth burst, at most once per rewater_s, so tending always moves a hex on.


## Plants a patch round the free slot in front of Lumi: up to patch_size plants on that slot's hex
## within patch_radius_m, for patch_seeds seeds. Returns how many went in (0: no room or no seeds).
static func plant_patch(g: Garden, pos: Vector3, fwd: Vector3) -> int:
	var first: int = g.free_slot_near(pos, fwd)
	var price := BigNum.from_float(float(g.tending.get("patch_seeds", 1.0)))
	if first < 0 or not GameState.can_afford("seeds", price):
		return 0
	var picks: Array[int] = patch_slots(g, first)
	GameState.spend("seeds", price)
	for s: int in picks:
		g.set_seed(s)
	return picks.size()


## The empty plantable slots a patch round `first` takes: `first` and its nearest neighbours on
## the same hex within patch_radius_m, at most `size` (patch_size when 0: Lumi's patch).
static func patch_slots(g: Garden, first: int, size: int = 0) -> Array[int]:
	var r: float = float(g.tending.get("patch_radius_m", 3.0))
	var cands: Array = []
	for s: int in g.hex_slots.get(g.slot_hex[first], PackedInt32Array()):
		var d: float = g.slot_pos[s].distance_to(g.slot_pos[first])
		if s != first and g.slot_species[s] < 0 and d <= r and g.plantable(s):
			cands.append([d, s])
	cands.sort_custom(_nearer)
	var out: Array[int] = [first]
	for c: Array in cands:
		if out.size() >= (size if size > 0 else maxi(1, int(g.tending.get("patch_size", 1)))):
			break
		out.append(int(c[1]))
	return out


## Lumi's pour on the hex in front of her: every plant on it is soaked for its wet cap, and the hex
## gets its burst (burst_stage of a stage at once) unless it had one within rewater_s.
## Returns the slots watered (empty: nothing planted there).
static func hand_water(g: Garden, pos: Vector3, fwd: Vector3) -> Array[int]:
	var out: Array[int] = []
	var hid: int = g.world.field.hex_at(pos + fwd * 1.3)
	g.ensure_hex(hid)
	if not g.hex_slots.has(hid):
		return out
	for s: int in g.hex_slots[hid]:
		if g.slot_species[s] >= 0:
			g.water(s, g.wet_cap(s))
			out.append(s)
	if not out.is_empty() and burst_ready(g, hid):
		g.burst_at[hid] = g.clock
		for s: int in out:
			g.push_growth(s, float(g.tending.get("burst_stage", 0.0)))
		g.grow_step(0.0)  # the burst shows at once
	return out


## True when a pour on hex `hid` would give its growth burst now.
static func burst_ready(g: Garden, hid: int) -> bool:
	return not g.burst_at.has(hid) or g.clock - float(g.burst_at[hid]) >= float(g.tending.get("rewater_s", 0.0))


static func _nearer(a: Array, b: Array) -> bool:
	return float(a[0]) < float(b[0])
