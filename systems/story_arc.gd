class_name StoryArc
extends RefCounted
## [v7arc] The whole-game story spine (docs/STORY_ARC.md): home needs FUEL (to fly the Cradle home)
## and POWER (to wake the Settlers). Every planet in data/homeward.json's order has a story block in
## data/story_arc.json: what it gives toward home, its one-line reason to go, its open question,
## and WREN's lines on arrival and on leaving. Read generically: no planet-specific code.
##
## A planet's gift is earned once, at its exit beat (the moment its way onward opens: the
## planet's leave gate in homeward.json, else its restoration reaching chart_at), stored as the
## Homeward beat "<id>_exit" (Verdance's is the older "verdance_exit", so old saves keep it).
## Pure helpers for tests: meter_of, format_meter, gives_of.

const PATH: String = "res://data/story_arc.json"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func home() -> Dictionary:
	return cfg().get("home", {})


## The story block of planet k (by its homeward.json id), {} if none.
static func block(k: int) -> Dictionary:
	var id: String = str(Homeward.planet_def(k).get("id", ""))
	var v: Variant = (cfg().get("planets", {}) as Dictionary).get(id, {})
	return v if v is Dictionary else {}


## What home needs: x = fuel, y = power.
static func need() -> Vector2i:
	return Vector2i(int(home().get("fuel", 0)), int(home().get("power", 0)))


## What planet k gives toward home: x = fuel, y = power.
static func gives(k: int) -> Vector2i:
	return gives_of(block(k))


static func gives_of(b: Dictionary) -> Vector2i:
	var g: Variant = b.get("gives", {})
	if not (g is Dictionary):
		return Vector2i.ZERO
	return Vector2i(int((g as Dictionary).get("fuel", 0)), int((g as Dictionary).get("power", 0)))


static func exit_beat(k: int) -> String:
	return "%s_exit" % str(Homeward.planet_def(k).get("id", ""))


## True once planet k's exit beat has played (its fuel and power are in the meters), or the
## planet is fully restored (older saves from before the meters: 100% is past its way onward).
static func given(k: int) -> bool:
	return Homeward.beat_done(exit_beat(k)) or Homeward.restored(k)


## Fuel and power gathered from the planets whose exit beat is done (pure on `done_ids`).
static func meter_of(done_ids: Array) -> Vector2i:
	var out := Vector2i.ZERO
	var ps: Dictionary = cfg().get("planets", {})
	for id: Variant in done_ids:
		var b: Variant = ps.get(str(id), {})
		if b is Dictionary:
			out += gives_of(b)
	return out


## Campaign planets only (data/homeward.json; dev planets from PlanetCfg never are there).
static func given_ids() -> Array:
	var ids: Array = []
	for k: int in Homeward.planets().size():
		if given(k):
			ids.append(str(Homeward.planet_def(k).get("id", "")))
	return ids


## The home meters now: x = fuel, y = power.
static func meter() -> Vector2i:
	return meter_of(given_ids())


static func full() -> bool:
	var m: Vector2i = meter()
	var n: Vector2i = need()
	return m.x >= n.x and m.y >= n.y


static func _vars(m: Vector2i) -> Dictionary:
	var n: Vector2i = need()
	return {"fuel": m.x, "power": m.y, "fuel_need": n.x, "power_need": n.y}


## "Home: fuel 2/10, power 2/10" (translated).
static func format_meter(m: Vector2i) -> String:
	return TranslationServer.translate(str(home().get("meter", ""))).format(_vars(m))


static func meter_text() -> String:
	return format_meter(meter())


## WREN's home line: "To go home we need 10 fuel and 10 power. We have 2 fuel and 2 power."
static func home_line(m: Vector2i) -> String:
	if m.x >= need().x and m.y >= need().y:
		return TranslationServer.translate(str(home().get("full", "")))
	return TranslationServer.translate(str(home().get("home_line", ""))).format(_vars(m))


## "Gives fuel 1 and power 3" (or "Gave ..." once earned) for the map card.
static func gives_text(k: int) -> String:
	var g: Vector2i = gives(k)
	var key: String = "gave_text" if given(k) else "gives_text"
	return TranslationServer.translate(str(home().get(key, ""))).format({"fuel": g.x, "power": g.y})


static func reason(k: int) -> String:
	return TranslationServer.translate(str(block(k).get("reason", "")))


## The reason to fly on from planet k, said once at its exit beat: the next planet's reason
## ("Ochre is next. Its sun and wind can fill up our power."), or the Cradle's after the last.
static func next_line(k: int) -> String:
	if k + 1 < Homeward.planets().size():
		var r: String = reason(k + 1)
		if r == "":
			return ""
		return TranslationServer.translate(str(home().get("next", ""))).format({"planet": Homeward.planet_name(k + 1), "reason": r})
	return TranslationServer.translate(str((cfg().get("cradle", {}) as Dictionary).get("reason", "")))


static func _lines(k: int, key: String) -> Array[String]:
	var out: Array[String] = []
	for l: Variant in block(k).get(key, []):
		if str(l) != "":
			out.append(TranslationServer.translate(str(l)))
	return out


static func arrive_lines(k: int) -> Array[String]:
	return _lines(k, "arrive")


## Everything WREN says at planet k's exit beat after the planet's leave toast, in order:
## the home line (with the meters after this planet's gift), the planet's leave lines, and the
## reason to fly on. `m` = the meters to report.
static func exit_lines(k: int, m: Vector2i) -> Array[String]:
	var out: Array[String] = [home_line(m)]
	out.append_array(_lines(k, "leave"))
	var nl: String = next_line(k)
	if nl != "":
		out.append(nl)
	return out


## The planet's way onward is open (generic): its leave gate in homeward.json (hubs at a level,
## or a base level, while Lumi is there), or its stored restoration at chart_at.
static func leave_open(k: int) -> bool:
	if k < 0:
		return false
	if k == Homeward.current_planet():
		var lh: Vector2i = Homeward.leave_hubs(k)
		if lh.x > 0 and Homeward.hubs_at_level(lh.y) >= lh.x:
			return true
		var ob: int = Homeward.leave_base_level(k)
		if ob > 0 and (int(GameState.world.get("hub_level", 1)) >= ob or Frontiers.bases_at_level(ob) > 0):
			return true
	return Homeward.stored_pct(k) >= float(Homeward.cfg().get("chart_at", 0.5)) - 0.0001


## Queues lines for WREN (forced past the signal gate: these are story beats), or toasts them
## when she is not there. Returns how many were queued.
static func speak(w: Node, lines: Array[String]) -> int:
	var wv: Variant = w.get("wren") if w else null
	var wr: Wren = wv as Wren if wv is Wren else null
	for l: String in lines:
		if wr != null:
			wr.speak(l, wr.stage(), true)
		else:
			EventBus.toast.emit(l, "story")
	return lines.size()
