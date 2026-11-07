class_name AutoplayLate
extends RefCounted
## [late] Post-game layer of the autoplay bot (tools/autoplay.gd -> _campaign): after the Cradle
## finale on Verdance it decorates a little (Garden Mode), banks Starseeds, buys Heirlooms
## (cheapest first) and seeds a new world; on the new world it marks how fast the opening goes
## with the Heirlooms (w2_* milestones, game time counted on from Verdance's).
## Flags: --late-waves=N waits for N Seed Ark waves before leaving (default 0: leave once
## decorated); --late-decor=N decorations first (default 6); --stop-at=seed_world_s etc.

const DECOR_ORDER: Array[String] = ["bench", "lamp", "planter", "flower_bed", "bird_bath", "fountain", "path", "statue"]

static var _last_decor_t: float = -999.0


## Total game time across worlds (Verdance's archived time + this world's).
static func total_time() -> float:
	var t: float = float(GameState.stats.get("time_played", 0.0))
	if CradleMode.current_index() > 0:
		for i: int in CradleMode.current_index():
			t += float((CradleMode.worlds()[i].get("stats", {}) as Dictionary).get("time_played", 0.0))
	return t


static func mark(key: String) -> void:
	AutoplayCampaign.mark(key, total_time())
	if DevHooks.get_s("stop-at", "") == key:
		print("[Autoplay] stopping: stop-at %s" % key)
		SaveManager.save_game()
		Engine.get_main_loop().quit()


## One step (about once a second). Returns an event line or "".
static func step(world: Node) -> String:
	if bool(world.get("launching")):
		return ""
	var d: LateDirector = LateDirector.of(world)
	if d == null:
		return ""
	if CradleMode.current_index() > 0:
		return _new_world(world)
	if not GameState.flags.get("bloom_finale_seen", false):
		return ""
	mark("cradle_mode_open_s")
	var t: float = float(GameState.stats.get("time_played", 0.0))
	var want: int = int(DevHooks.get_f("late-decor", 6.0))
	if int(GameState.stats.get("decor_placed", 0)) < want and t - _last_decor_t > 5.0:
		_last_decor_t = t
		var got: String = decorate(world, d.decor)
		if got != "":
			mark("first_decor_s")
			return "decor " + got
	if int(GameState.stats.get("ark_waves", 0)) < int(DevHooks.get_f("late-waves", 0.0)):
		return ""
	if int(GameState.stats.get("decor_placed", 0)) < want and t - float(AutoplayCampaign.marks.get("cradle_mode_open_s", t)) < 600.0:
		return ""
	if d.story_busy():
		return ""
	var gain: int = CradleMode.bank()
	var bought: Array[String] = buy_heirlooms()
	mark("heirlooms_s")
	print("[Autoplay] late: banked %d Starseeds, bought %s, %d left" % [gain, str(bought), int(CradleMode.starseeds())])
	mark("seed_world_s")
	CradleMode.launch_new_world(world.get_tree())
	return "seed new world"


## Buys Heirlooms cheapest-first until nothing is affordable.
static func buy_heirlooms() -> Array[String]:
	var out: Array[String] = []
	for n: int in 40:
		var best: String = ""
		var best_c: int = 1 << 30
		for h: Dictionary in CradleMode.heirloom_defs():
			var id: String = str(h["id"])
			if CradleMode.buy_block_reason(id) == "":
				var c: int = CradleMode.heirloom_cost(h, CradleMode.heirloom_level(id))
				if c < best_c:
					best_c = c
					best = id
		if best == "" or not CradleMode.buy(best):
			break
		out.append(best)
	return out


## Places the next affordable decoration on the nearest clean cell that takes it.
static func decorate(world: Node, decor: Decor) -> String:
	var f: HexField = world.field
	var t: String = DECOR_ORDER[int(GameState.stats.get("decor_placed", 0)) % DECOR_ORDER.size()]
	if Decor.buy_block_reason(t) != "":
		return ""
	var hexes: Array = range(f.hex_count()).filter(func(h: int) -> bool: return f.is_clean(h) and not f.is_water(h))
	hexes.sort_custom(func(a: int, b: int) -> bool: return f.hex_center(a).length() < f.hex_center(b).length())
	for h: int in hexes:
		var c: Vector2i = Decor.cell_at(f.hex_center(h))
		for k: int in 9:
			var cc: Vector2i = c + Vector2i((k % 3 - 1) * 2, (k / 3 - 1) * 2)
			if decor.place(t, cc, k % 4):
				return "%s at %s" % [t, str(cc)]
	return ""


static func _new_world(world: Node) -> String:
	var w: String = "w%d" % (CradleMode.current_index() + 1)
	mark("%s_arrive_s" % w)
	if int(GameState.stats.get("hexes_cleaned", 0)) >= 1:
		mark("%s_first_hex_s" % w)
	if world.get("fleet") != null and (world.fleet as Fleet).robots().size() >= 3:
		mark("%s_three_robots_s" % w)
	var hl: int = int(world.hub.level) if world.get("hub") != null else 1
	for l: int in range(2, hl + 1):
		mark("%s_base_%d_s" % [w, l])
	if GameState.flags.get("seeds_unlocked", false):
		mark("%s_seeds_s" % w)
	if Research.has("pollinator_survey"):
		mark("%s_garden_takes_off_s" % w)
	return ""
