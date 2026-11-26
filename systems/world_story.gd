class_name WorldStory
extends Node
## [worlds2] A small story thread for each Cradle Mode world type, told by WREN
## (data/wren_lines.json "world_<type>_<beat>"): arrival, a first memory note (why the ark seeded
## worlds like this one), halfway, a second memory note, restored. Beats follow the district's
## progress (WorldLook.progress: base level or share of the field cleaned) and are remembered in the
## world's own save (GameState.flags["world_story"]), so each world tells its thread once.
## WREN speaks over the ark's relay here, so her lines arrive clear from the start.

const BEATS: Array[String] = ["arrival", "memory_1", "halfway", "memory_2", "restored"]
## Progress each beat waits for (restored also comes with base level 5 or the world's finale).
const AT: Dictionary = {"arrival": 0.0, "memory_1": 0.2, "halfway": 0.5, "memory_2": 0.7, "restored": 0.95}
const FIRST_DELAY_S: float = 16.0  # after the pod lands and WREN's own "new world" line
const GAP_S: float = 50.0          # never two beats close together

var world: Node
var type_id: String = ""
## Line keys to try, most specific first: a planet's own lines ("world_<planet>_<beat>"), then its look type's.
var keys: Array = []
var _t: float = 0.0
var _gap: float = 0.0


static func attach(slice: Node) -> WorldStory:
	if CradleMode.profile.is_empty() or CradleMode.current_index() <= 0:
		return null
	var s := WorldStory.new()
	s.name = "WorldStory"
	s.world = slice
	var w: Dictionary = CradleMode.current_world()
	s.type_id = str(w.get("type", ""))
	s.keys = [str(w.get("look", "")), str(WorldLook.current().get("type", "")), s.type_id]  # planet id, its look, the world type
	s._gap = FIRST_DELAY_S
	slice.add_child(s)
	return s


## The next beat due (pure): the first unseen beat whose progress has been reached, "" if none.
static func next_beat(prog: float, hub_level: int, finale: bool, seen: Array) -> String:
	for b: String in BEATS:
		if b in seen:
			continue
		var ok: bool = prog >= float(AT[b]) - 0.0001
		if b == "restored":
			ok = ok or hub_level >= 5 or finale
		return b if ok else ""
	return ""


## The wren_lines.json trigger for a type and beat.
static func trigger(wtype: String, beat: String) -> String:
	return "world_%s_%s" % [wtype, beat]


## The first trigger in data/wren_lines.json for these ids and this beat (pure; the last id as fallback).
static func pick_trigger(ids: Array, beat: String, lines: Dictionary) -> String:
	for id: Variant in ids:
		if str(id) != "" and lines.has(trigger(str(id), beat)):
			return trigger(str(id), beat)
	return trigger(str(ids.back()) if not ids.is_empty() else "", beat)


static func seen() -> Array:
	if not (GameState.flags.get("world_story") is Array):
		GameState.flags["world_story"] = []
	return GameState.flags["world_story"]


func _process(delta: float) -> void:
	_gap -= delta
	_t += delta
	if _t < 2.0 or _gap > 0.0:
		return
	_t = 0.0
	var w: Wren = world.get("wren")
	if w == null:
		return
	var f: HexField = world.get("field")
	var frac: float = float(f.cleaned_count) / float(maxi(f.junk_hex_count, 1)) if f else 0.0
	var lv: int = int(GameState.world.get("hub_level", 1))
	var h: Variant = world.get("hub")
	if h is Hub:
		lv = int((h as Hub).level)
	var b: String = next_beat(WorldLook.progress(lv, frac), lv, bool(GameState.flags.get("bloom_finale_seen", false)), seen())
	if b == "":
		return
	seen().append(b)
	GameState.flags["wren_awake"] = true  # she is on the ark's relay now
	w.say(pick_trigger(keys, b, w.lines), 1.0, true, {}, 2)
	print("[worlds2] WREN %s beat on %s" % [b, type_id])
	_gap = GAP_S
