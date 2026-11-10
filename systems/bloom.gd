class_name Bloom
extends Node
## Post-game (M11): planet-scale "Verdance Bloom" milestones (the planet's "postgame" table). Pure
## helpers are static (tests use them); the live node (added by the slice) keeps this district's
## summary fresh, checks milestones and plays the Cradle finale once.
## State: flags.bloom_done (Array of ids), flags.bloom_<id> (for achievements),
## flags.bloom_finale_seen, flags.biomes_visited, world.bloom_summary {thriving, land} per district.

const TABLE: String = "postgame"
const CHECK_S: float = 2.0

static var _cfg: Dictionary = {}

var world: Node
var _t: float = 0.0
var _finale_pending: bool = false


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.planet_table(TABLE)
		Economy.drop_on_planet_change(_drop_planet_cache)
	return _cfg


static func _drop_planet_cache() -> void:
	_cfg = {}


static func milestones() -> Array:
	return cfg().get("milestones", [])


static func done_list() -> Array:
	var v: Variant = GameState.flags.get("bloom_done")
	if not (v is Array):
		v = []
		GameState.flags["bloom_done"] = v
	return v


static func is_done(id: String) -> bool:
	return id in done_list()


# --- Measuring the planet (pure) ------------------------------------------------------

## Thriving and land hex counts for a saved district dict: its live summary if it has one,
## else the level bytes (land unknown, so the configured default).
static func district_summary(d: Dictionary) -> Vector2i:
	var s: Variant = d.get("bloom_summary")
	if s is Dictionary:
		return Vector2i(int((s as Dictionary).get("thriving", 0)), maxi(1, int((s as Dictionary).get("land", 1))))
	var hl: Variant = d.get("hex_levels")
	var thriving: int = 0
	if hl is Dictionary and (hl as Dictionary).has("levels"):
		for v: int in Marshalls.base64_to_raw(str((hl as Dictionary)["levels"])):
			if v >= HexLevels.MAX_LEVEL:
				thriving += 1
	return Vector2i(thriving, int(cfg().get("default_land_hexes", 230)))


static func is_thriving_district(sum: Vector2i, ratio: float = -1.0) -> bool:
	var r: float = float(cfg().get("thriving_district_ratio", 0.6)) if ratio < 0.0 else ratio
	return sum.y > 0 and sum.x >= int(ceil(r * sum.y))


## {thriving_hexes, thriving_districts, planet_pct} from per-district summaries and a planet fraction.
static func measure(summaries: Array[Vector2i], planet_fraction: float) -> Dictionary:
	var hexes: int = 0
	var districts: int = 0
	for s: Vector2i in summaries:
		hexes += s.x
		if is_thriving_district(s):
			districts += 1
	return {"thriving_hexes": hexes, "thriving_districts": districts, "planet_pct": planet_fraction * 100.0}


static func cond_met(c: Dictionary, m: Dictionary) -> bool:
	return float(m.get(str(c.get("type", "")), 0.0)) >= float(c.get("target", 1.0)) - 0.000001


static func milestone_met(ms: Dictionary, m: Dictionary) -> bool:
	for c: Dictionary in ms.get("any", []):
		if cond_met(c, m):
			return true
	return false


## Best progress 0..1 toward a milestone (its closest condition).
static func progress(ms: Dictionary, m: Dictionary) -> float:
	var best: float = 0.0
	for c: Dictionary in ms.get("any", []):
		best = maxf(best, clampf(float(m.get(str(c.get("type", "")), 0.0)) / maxf(float(c.get("target", 1.0)), 0.0001), 0.0, 1.0))
	return best


## Marks every newly met milestone done and pays it. Returns the new ids (in data order).
static func check(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for ms: Dictionary in milestones():
		var id: String = str(ms["id"])
		if is_done(id) or not milestone_met(ms, m):
			continue
		done_list().append(id)
		GameState.flags["bloom_" + id] = true
		_pay(ms.get("reward", {}), 1.0)
		out.append(id)
	return out


static func _pay(reward: Dictionary, mult: float) -> String:
	var bits: Array[String] = []
	for k: String in reward:
		var amt: float = round(float(reward[k]) * mult)
		GameState.add_currency(k, BigNum.from_float(amt))
		bits.append(L10nFmt.amount(k, amt, true))  # [i18n2]
	return "  ".join(bits)


## One short line for the hologram: the next milestone ("" before the first and after the last).
static func globe_line() -> String:
	var next: Dictionary = {}
	for ms: Dictionary in milestones():
		if not is_done(str(ms["id"])):
			next = ms
			break
	if done_list().is_empty() or next.is_empty():
		return ""
	return TranslationServer.translate("Verdance Bloom %d / %d  ·  next: %s") % [done_list().size(), milestones().size(), TranslationServer.translate(str(next.get("name", "")))]


# --- Live node -----------------------------------------------------------------------

func _ready() -> void:
	add_to_group("persist")
	# [beat] A method connection is dropped with this node (the slice's old one-shot lambda was not,
	# and fired into freed districts after rocket trips).
	EventBus.cradle_district_complete.connect(_on_cradle_complete)
	_visit_biome.call_deferred()
	# [beat] The Verdance Bloom is done but the finale never finished (quit mid-cinematic, or an
	# older save): play it again at the next quiet moment.
	if is_done("verdance_bloom") and not GameState.flags.get("bloom_finale_seen", false):
		_finale_pending = true
	if DevHooks.has("credits"):  # [beat] --credits[=S]: roll the end credits S seconds in
		get_tree().create_timer(DevHooks.get_f("credits", 3.0)).timeout.connect(func() -> void: CreditsRoll.play(world))
	if DevHooks.has("bloom-finale"):
		(func() -> void: play_finale(true)).call_deferred()


func persist_save() -> void:
	_store_summary()


func _visit_biome() -> void:
	if world == null or world.get("field") == null:
		return
	var b: String = str(world.field.biome)
	if b == "":
		return
	var seen: Array = GameState.flags.get("biomes_visited", [])
	if b in seen:
		return
	seen.append(b)
	GameState.flags["biomes_visited"] = seen
	var nm: String = tr(str(Economy.biome_set(b).get("name", b.capitalize())))
	EventBus.toast.emit(tr("Wilderness: %s. New ground, new junk, new colours under it.") % nm, "story")
	if world.get("wren") != null:
		get_tree().create_timer(4.0, false).timeout.connect(func() -> void: world.wren.say("biome_arrival", 1.0, true))


func _store_summary() -> void:
	if world == null or world.get("hex_levels") == null:
		return
	var hl: HexLevels = world.hex_levels
	GameState.world["bloom_summary"] = {"thriving": hl.count_at_least(HexLevels.MAX_LEVEL), "land": hl.levels.size()}


## Live measurement over every district (this one live, the others from their saves).
func measure_now() -> Dictionary:
	_store_summary()
	var sums: Array[Vector2i] = []
	var seen_current: bool = false
	for k: Variant in GameState.districts:
		var d: Variant = GameState.world if int(k) == GameState.current_hub else GameState.districts[k]
		if int(k) == GameState.current_hub:
			seen_current = true
		if d is Dictionary:
			sums.append(district_summary(d))
	if not seen_current:
		sums.append(district_summary(GameState.world))
	var frac: float = world.planet.restored_fraction() if world and world.get("planet") != null else 0.0
	var m: Dictionary = measure(sums, frac)
	# [beat] The true ending runs through the Cradle Returns frontier (data/bloom.json).
	m["cradle_returned"] = 1.0 if GameState.flags.get("cradle_returned", false) else 0.0
	if world and world.get("planet") != null:
		m["campaign"] = CoreCharge.campaign_progress((world.planet as PlanetData).frontier_hubs)
	return m


func _process(delta: float) -> void:
	_t += delta
	if _t < CHECK_S:
		return
	_t = 0.0
	if _finale_pending:
		play_finale()
	var got: Array[String] = check(measure_now())
	for id: String in got:
		_celebrate(id)


func _celebrate(id: String) -> void:
	var ms: Dictionary = {}
	for m: Dictionary in milestones():
		if str(m["id"]) == id:
			ms = m
	EventBus.toast.emit(tr("Verdance Bloom: %s. %s") % [tr(str(ms.get("name", id))), tr(str(ms.get("desc", "")))], "story")
	EventBus.toast.emit(_reward_text(ms.get("reward", {})), "hint")
	Audio.play("fanfare", 0.9, -4.0)
	if world and world.get("patch") != null:
		var bp: Vector3 = (world.patch as Node3D).global_position
		Vfx.burst("big_sparkle", bp + OrbitUp.up(bp) * 1.5, Color(0.8, 1.0, 0.6))  # [orbB] local up
	if world and world.get("wren") != null:
		world.wren.say("bloom_milestone", 1.0, true)
	if bool(ms.get("finale", false)):
		play_finale()


static func _reward_text(r: Dictionary) -> String:
	var bits: Array[String] = []
	for k: String in r:
		bits.append(L10nFmt.amount(k, float(r[k]), true))  # [i18n2]
	return "  ".join(bits)


func _on_cradle_complete(_hub: int) -> void:
	play_finale()


## The Cradle answers (once). Waits for a quiet moment if a menu or another scene is busy.
func play_finale(force: bool = false) -> void:
	if GameState.flags.get("bloom_finale_seen", false) and not force:
		_finale_pending = false
		return
	if BloomFinale.playing:
		_finale_pending = false
		return
	if world == null or (world.has_method("any_modal_open") and world.any_modal_open()) or bool(world.get("launching")) or _busy_story():
		_finale_pending = true
		return
	_finale_pending = false
	# [beat] bloom_finale_seen is set when the cinematic ends (BloomFinale), so quitting halfway
	# replays it on the next load instead of losing the ending.
	var f := BloomFinale.new()
	f.world = world
	world.add_child(f)
	f.play()


## [beat] Another cinematic owns the screen (intro, first seed, a Bloom Core beat).
func _busy_story() -> bool:
	var intro: Variant = world.get("intro")
	if intro is Intro and (intro as Intro).busy():
		return true
	var fs: Variant = world.get("first_seed")
	if fs is FirstSeed and bool((fs as FirstSeed).get("_active")):
		return true
	var cc: Variant = world.get("core_charge")
	return cc is CoreCharge and bool((cc as CoreCharge).get("_busy"))
