class_name GardenCrew
extends RefCounted
## The crew's planting and watering on a Garden (B44): a planting robot sets a patch of real slots
## on its hex, a watering robot soaks every plant there, so the hex's stages (plants/hex_levels.gd,
## which reads the slots) move by crew work. Numbers in the regrowth table's `tending` block:
## crew_patch_size plants per planting action for crew_patch_seeds seeds from the shared store,
## and a hex is due water again once a plant has crew_rewater_frac of wet_s left
## (Garden.thirst_at). A robot's watering gives no growth burst: that is Lumi's pour.
## Planting and watering far from Lumi are quiet (no dust, sound or splash).


## True when hex `hid` is planting work: clean land with room for a seed (or slots not made yet).
static func wants_plant(g: Garden, hid: int) -> bool:
	return g.world.field.is_clean(hid) and g.open_slots(hid) != 0


## True when hex `hid` is watering work: clean, with a plant due water.
static func wants_water(g: Garden, hid: int) -> bool:
	return g.needs_water(hid) and g.world.field.is_clean(hid)


## Plants a patch on hex `hid` round its first open slot. Returns the plants set (0: no room, no
## seeds, or the hex is not clean). pay: false spends no seeds (tests, dev). fx: dust and sound.
static func plant(g: Garden, hid: int, pay: bool = true, fx: bool = false) -> int:
	if not g.world.field.is_clean(hid):
		return 0
	g.ensure_hex(hid)
	var first: int = -1
	for s: int in g.hex_slots.get(hid, PackedInt32Array()):
		if g.slot_species[s] < 0 and g.plantable(s):
			first = s
			break
	if first < 0:
		return 0
	var price := BigNum.from_float(float(g.tending.get("crew_patch_seeds", 1.0)))
	if pay and not GameState.can_afford("seeds", price):
		return 0
	if pay:
		GameState.spend("seeds", price)
	var picks: Array[int] = Tending.patch_slots(g, first, maxi(1, int(g.tending.get("crew_patch_size", 1))))
	for k: int in picks.size():
		g.set_seed(picks[k], not (fx and k == 0))
	return picks.size()


## Soaks every plant on hex `hid` for its wet cap. Returns the plants watered. fx: one splash.
static func water(g: Garden, hid: int, fx: bool = false) -> int:
	var n: int = 0
	for s: int in g.hex_slots.get(hid, PackedInt32Array()):
		if g.slot_species[s] < 0:
			continue
		if fx and n == 0:
			g.water(s, g.wet_cap(s))
		else:
			g.soak_quietly(s)
		n += 1
	if n > 0:
		g.mark_watered(hid)
	return n
