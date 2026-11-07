class_name LateDirector
extends Node
## [late] Wires the post-game layer into a district (one call from scenes/slice.gd): Garden Mode
## (systems/decor.gd + ui/garden_placer.gd), the Ark Bridge (ui/ark_bridge.gd), a new world's
## arrival card, kit robots and look (systems/cradle_mode.gd), and the "Cradle Mode is open" beat
## after the finale. Dev hooks:
##   --post-finale        jump this save to just after the Cradle finale (Verdance won, credits seen,
##                        Seed Ark open, base 5) so Cradle Mode and Garden Mode are available
##   --open=ark           open the Ark Bridge;  --open=garden[=type] opens Garden Mode
##   --garden             Garden Mode unlocked here;  --decor-sample places a small garden near the base
##   --starseeds=N        add N Starseeds to the profile;  --heirlooms=id:lv+id:lv sets Heirloom levels (at boot)
##   --world=N            start on Cradle Mode world N (systems/cradle_mode.gd boot; new worlds land fresh)
##   --new-world          seed a new world right away (with --save-dir for staged runs)
##   --sample-worlds=N    shots: N visited worlds in the profile (no saves)
##   --garden-cam=x,z,yaw,dist,pitch  fixed camera for Garden shots

var world: Node
var decor: Decor
var placer: GardenPlacer
var bridge: ArkBridge
var _t: float = 0.0


static func attach(slice: Node) -> LateDirector:
	var d := LateDirector.new()
	d.name = "LateDirector"
	d.world = slice
	slice.add_child(d)
	d._setup()
	return d


static func of(slice: Node) -> LateDirector:
	return slice.get_node_or_null("LateDirector") as LateDirector if slice else null


func _setup() -> void:
	if DevHooks.has("post-finale") and not GameState.flags.get("late_post_finale_dev", false) and CradleMode.current_index() == 0:
		dev_post_finale()
	if DevHooks.has("starseeds"):
		CradleMode.profile["starseeds"] = CradleMode.starseeds() + DevHooks.get_f("starseeds", 100.0)
	if DevHooks.has("sample-worlds") and CradleMode.worlds().size() < 2:  # shots: a profile with some history
		for i: int in int(DevHooks.get_f("sample-worlds", 2.0)):
			var sw: Dictionary = CradleMode._add_world()
			sw["stats"] = {"time_played": 3600.0 * (5.5 - i * 2.0), "hexes_cleaned": 380 - i * 150, "ark_waves": 4 - i * 3, "eggs": 31 - i * 12}
			sw["finale"] = i == 0
		CradleMode.profile["current"] = 0
	CradleMode.mirror_stats()
	decor = Decor.new()
	world.add_child(decor)
	decor.setup(world)
	placer = GardenPlacer.new()
	placer.name = "GardenPlacer"
	placer.world = world
	placer.decor = decor
	world.add_child(placer)
	HomewardDirector.attach(world)  # [home] the system campaign (systems/homeward_director.gd)
	bridge = ArkBridge.new()
	bridge.name = "ArkBridge"
	bridge.world = world
	world.add_child(bridge)
	if GameState.flags.get("late_new_world", false):
		_arrive_new_world.call_deferred()
	_world_look.call_deferred()
	if DevHooks.has("decor-sample"):
		_decor_sample.call_deferred()
	if DevHooks.has("late-save-after"):  # dev: write the save S seconds in (prepared states for shots)
		get_tree().create_timer(DevHooks.get_f("late-save-after", 20.0)).timeout.connect(func() -> void:
			print("[late] saved: %s" % str(SaveManager.save_game())))
	var op: String = DevHooks.get_s("open", "")
	if op == "ark":
		(func() -> void: bridge.open_bridge()).call_deferred()
	elif op == "garden":
		(func() -> void:
			placer.open()
			if DevHooks.has("garden-type"):
				placer.select(DevHooks.get_s("garden-type", "bench"))
			if DevHooks.has("garden-cell"):
				var gc: PackedStringArray = DevHooks.get_s("garden-cell", "0,12").split(",")
				placer.move_to(Vector2i(int(gc[0]), int(gc[1])))
			_garden_cam()).call_deferred()
	elif DevHooks.has("garden-cam"):
		_garden_cam.call_deferred()
	if DevHooks.has("new-world") and not GameState.flags.get("late_new_world", false) and CradleMode.current_index() == 0:
		get_tree().create_timer(DevHooks.get_f("new-world", 2.0)).timeout.connect(func() -> void: CradleMode.launch_new_world(get_tree()))


## Opens the Ark Bridge (pause menu, autoplay). False while it is still locked.
func open_bridge() -> bool:
	if not (CradleMode.unlocked() or Homeward.answered()):  # [home] Heirloom picks open with the Cradle's answer
		EventBus.toast.emit(tr("The Ark Bridge opens once the Cradle has come home."), "info")
		return false
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	world.cam.input_enabled = false
	bridge.open_bridge()
	return true


func open_garden() -> bool:
	return placer.open()


## A cinematic or story beat owns the screen (don't leave the world now).
func story_busy() -> bool:
	if BloomFinale.playing:
		return true
	var cc: Variant = world.get("core_charge")
	if cc is CoreCharge and bool((cc as CoreCharge).get("_busy")):
		return true
	var intro: Variant = world.get("intro")
	return intro is Intro and (intro as Intro).busy()


func _process(delta: float) -> void:
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	# The finale has played: Cradle Mode opens (once per profile, a story beat).
	if GameState.flags.get("bloom_finale_seen", false) and not GameState.flags.get("late_bridge_hint", false):
		GameState.flags["late_bridge_hint"] = true
		CradleMode.bank()
		get_tree().create_timer(8.0, false).timeout.connect(func() -> void:
			EventBus.toast.emit(tr("Cradle Mode: the ark's seed vault holds seeds for other worlds. Pause > Ark Bridge to see them, spend Starseeds on Heirlooms, or seed a new world. Garden Mode (H) is open too."), "story")
			if world.get("wren") != null:
				world.wren.say("cradle_mode", 1.0, true))


## Verdance won: as if the campaign had just played through the Cradle finale and credits.
func dev_post_finale() -> void:
	GameState.flags["late_post_finale_dev"] = true
	for id: String in ["first_meadow", "thriving_district", "green_shoots", "verdance_bloom"]:
		if not Bloom.is_done(id):
			Bloom.done_list().append(id)
			GameState.flags["bloom_" + id] = true
	GameState.flags["cradle_returned"] = true
	GameState.flags["bloom_finale_seen"] = true
	GameState.flags["credits_seen"] = true
	GameState.flags["intro_done"] = true
	GameState.flags["seeds_unlocked"] = true
	GameState.flags["tutorial_step"] = 999  # the opening chores, the Ledger and WREN's memory: long done
	GameState.flags["ledger_act"] = 4
	GameState.flags["ledger_resolved"] = true
	GameState.flags["wren_awake"] = true
	GameState.flags["first_sprout"] = true
	if world.get("tutorial") != null:
		world.tutorial.set("step", 999)
	if world.get("ledger") != null:
		world.ledger.set("act", 4)
	if world.get("planet") != null:
		var pl: PlanetData = world.planet
		for c: int in pl.cells_within(pl.hubs[0], 4):
			pl.mark_clean(c)
	GameState.flags["core_charge"] = 1.0  # the Bloom Core beats played on the way (no replays now)
	GameState.flags["core_beats"] = [25, 50, 75, 100]
	Bloom.ark_state()
	GameState.stats["ark_waves"] = maxf(float(GameState.stats.get("ark_waves", 0.0)), DevHooks.get_f("ark-waves", 3.0))
	GameState.stats["time_played"] = maxf(float(GameState.stats.get("time_played", 0.0)), 8.0 * 3600.0)
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0.0)), 420.0)
	GameState.world["hub_level"] = 5
	GameState.add_currency("cubes", BigNum.from_float(DevHooks.get_f("post-cubes", 400000.0)))
	GameState.add_currency("trinkets", BigNum.from_float(12))
	GameState.add_currency("seeds", BigNum.from_float(300))
	if world.get("hub") != null and int(world.hub.level) < 5:  # the base as the campaign left it
		for l: int in range(int(world.hub.level) + 1, 6):
			world.hub.call("_build_level", l, false)
		world.hub.level = 5
		world.hub.level_changed.emit(5)
	for k: int in 3:  # districts done on the way (summaries count toward Starseeds)
		if not GameState.districts.has(k + 1):
			GameState.districts[k + 1] = {"hub_level": 5, "bloom_summary": {"thriving": 140, "land": 230}}
	dev_clean_near.call_deferred(int(DevHooks.get_f("post-clean", 12.0)))
	print("[late] post-finale state: Verdance won, %d Seed Ark waves" % int(GameState.stats["ark_waves"]))


func _arrive_new_world() -> void:
	GameState.flags.erase("late_new_world")
	var w: Dictionary = CradleMode.current_world()
	# Robots that waited at the landing site (Old Crew heirloom).
	var bots: Array = GameState.flags.get("late_start_robots", [])
	GameState.flags.erase("late_start_robots")
	var fl: Fleet = world.get("fleet")
	if fl:
		for i: int in bots.size():
			var rb: Robot = fl.spawn(str(bots[i]), 0, Vector3(-2.4 + i * 1.6, 0.2, 0.8), 0.0, "Heir-%d" % (i + 1))
			if rb:
				rb.rotation.y = PI
	if not DevHooks.has("no-banner"):  # dev: shots without the arrival card
		WorldBanner.show_world(world, w)
	print("[late] arrived on world %d %s: cubes=%s data=%s seeds_unlocked=%s robots=%d research=%d" % [int(w.get("index", 0)), str(w.get("name", "")),
		GameState.get_currency("cubes").format(), GameState.get_currency(Research.CURRENCY).format(), str(GameState.flags.get("seeds_unlocked", false)),
		fl.robots().size() if fl else 0, Research.done_list().size()])
	GameState.inc_stat("worlds_landed")
	if world.get("wren") != null:
		get_tree().create_timer(5.0, false).timeout.connect(func() -> void: world.wren.say("new_world", 1.0, true))


## A new world's look: its type (frost on an ice moon, sand on a desert world) and a wet sheen
## under Heavy Rain, as a coat over the junk.
func _world_look() -> void:
	if CradleMode.current_index() <= 0 or world.get("frontier") != null or world.get("view") == null:
		return
	var coat: Array = WorldGen.world_type(str(CradleMode.current_world().get("type", ""))).get("coat", [])
	for mid: Variant in CradleMode.modifiers():
		if coat.is_empty():
			coat = WorldGen.modifier(str(mid)).get("coat", [])
	if coat.size() < 6 or not world.view.has_method("set_junk_overlay"):
		return
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/junk_coat.gdshader")
	m.set_shader_parameter("coat", Color(float(coat[0]), float(coat[1]), float(coat[2])))
	m.set_shader_parameter("top_amt", float(coat[3]))
	m.set_shader_parameter("film", float(coat[4]))
	m.set_shader_parameter("roughness", float(coat[5]))
	world.view.set_junk_overlay(m)


## Dev: cleans the n land hexes nearest the base (a district the campaign already worked).
func dev_clean_near(n: int) -> void:
	var f: HexField = world.field
	var cleaned: int = 0
	var order: Array = range(f.hex_count()).filter(func(h: int) -> bool: return f.hex_hub[h] == 0 and not f.is_water(h))
	order.sort_custom(func(a: int, b: int) -> bool: return f.hex_center(a).length() < f.hex_center(b).length())
	for h: int in order:
		if cleaned >= n:
			break
		if not f.is_clean(h):
			for pid: int in f.hex_pieces[h]:
				if f.piece_alive[pid] == 1:
					world.collect_piece(pid)
		cleaned += 1


## Dev: a small finished garden near the base (shots and the autoplay check).
func _decor_sample() -> void:
	dev_clean_near(int(DevHooks.get_f("decor-hexes", 8.0)))
	var plan: Array = sample_plan()
	var placed: int = 0
	for p: Array in plan:
		if decor.place(str(p[0]), Vector2i(int(p[1]), int(p[2])), int(p[3]), false, false):
			placed += 1
	print("[late] decor sample: %d / %d placed, charm %.1f" % [placed, plan.size(), decor.charm()])


## A little plaza south of the base: a fountain with benches, lamps, beds and a path.
static func sample_plan() -> Array:
	var out: Array = [["fountain", -1, 13, 0], ["lumi_sculpture", -1, 18, 0], ["bench", -4, 13, 1], ["bench", 3, 13, 1],
		["lamp", -4, 11, 0], ["lamp", 3, 11, 0], ["lamp", -4, 16, 0], ["lamp", 3, 16, 0],
		["flower_bed", -3, 10, 0], ["flower_bed", 1, 10, 0], ["planter", -2, 16, 0], ["planter", 1, 16, 0],
		["bird_bath", 5, 14, 0], ["statue", 6, 17, 0], ["wren_kite", -6, 14, 0]]
	for z: int in range(9, 21):
		out.append(["path", 0 if z < 12 or z > 15 else -2, z, 0])
	return out


func _garden_cam() -> void:
	if not DevHooks.has("garden-cam"):
		return
	var v: PackedStringArray = DevHooks.get_s("garden-cam", "0,14,3.14,9,-0.5").split(",")
	var anchor := Node3D.new()
	world.add_child(anchor)
	anchor.global_position = Vector3(float(v[0]), 0.8, float(v[1]))
	world.cam.target = anchor
	world.cam.yaw = float(v[2]) if v.size() > 2 else 0.0
	world.cam.distance = float(v[3]) if v.size() > 3 else 9.0
	world.cam.pitch = float(v[4]) if v.size() > 4 else -0.5
	world.cam.snap()
