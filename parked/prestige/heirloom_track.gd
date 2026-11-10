class_name HeirloomTrack
extends RefCounted
## [money] Heirlooms are milestone unlocks now, not purchases: Starseeds are no longer a currency.
## A world's restoration score (CradleMode.prestige_earned, banked into profile.starseeds_total as
## before) unlocks Heirloom levels along a fixed track: cheapest first, round-robin by level, at
## cumulative thresholds equal to the old Starseed prices, so the pace matches buying them in that
## order. Levels a profile bought before are kept (a profile never loses one).
## The "home" helper is replacing Cradle Mode's main flow; this file is the whole rule so it can
## be moved or dropped in one piece.


## The track: [{id, level (the level reached), at (score needed)}], in unlock order.
static func steps(defs: Array) -> Array[Dictionary]:
	var sorted: Array = defs.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("cost", 10)) < float(b.get("cost", 10)) or (float(a.get("cost", 10)) == float(b.get("cost", 10)) and str(a["id"]) < str(b["id"])))
	var top: int = 0
	for h: Dictionary in sorted:
		top = maxi(top, int(h.get("max", 5)))
	var out: Array[Dictionary] = []
	var at: int = 0
	for lv: int in top:
		for h: Dictionary in sorted:
			if lv >= int(h.get("max", 5)):
				continue
			at += CradleMode.heirloom_cost(h, lv)
			out.append({"id": str(h["id"]), "level": lv + 1, "at": at})
	return out


## Heirloom levels a score has unlocked: {id: level}.
static func levels_for(score: float, defs: Array) -> Dictionary:
	var out: Dictionary = {}
	for s: Dictionary in steps(defs):
		if float(s["at"]) > score + 0.0001:
			break
		out[s["id"]] = int(s["level"])
	return out


## Raises the profile's Heirloom levels to what its score has unlocked. Returns the ids raised.
static func apply(profile: Dictionary, defs: Array) -> Array[String]:
	var got: Dictionary = levels_for(float(profile.get("starseeds_total", 0.0)), defs)
	var hl: Dictionary = profile.get("heirlooms", {})
	var raised: Array[String] = []
	for id: Variant in got:
		if int(got[id]) > int(hl.get(id, 0)):
			hl[id] = int(got[id])
			raised.append(str(id))
	profile["heirlooms"] = hl
	profile["starseeds"] = 0.0  # nothing to spend: the score only unlocks
	return raised


## The next step not reached yet ({} once the track is done).
static func next_step(score: float, defs: Array) -> Dictionary:
	for s: Dictionary in steps(defs):
		if float(s["at"]) > score + 0.0001:
			return s
	return {}
