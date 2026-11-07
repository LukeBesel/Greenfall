class_name AutoplayHome
extends RefCounted
## [home] Homeward layer of the autoplay bot (tools/autoplay.gd -> _campaign): after the Cradle
## answers at Cradle Returns it builds the rocket drive, flies the planets in order, comes back to
## Verdance's Cradle Returns, builds the Mk VII Homeward rocket, plants the last seed and launches
## home (story/homecoming.gd), marking home_* milestones on the way. Without fast-forward it lets
## the ordinary bot restore each planet. Flags:
##   --home-ff[=S]   fast-forward: a planet counts as restored S game seconds after landing
##                   (default 20) and drive costs are granted when short
## A step returns "" to let the ordinary campaign go on, or what it did (the caller then waits).

static var _landed_t: float = -1.0
static var _landed_planet: int = -99


static func _t() -> float:
	return AutoplayLate.total_time()


static func step(world: Node) -> String:
	if not Homeward.answered():
		return ""
	AutoplayLate.mark("home_answered_s")
	if Homeward.done():
		AutoplayLate.mark("homecoming_s")
		return "" if not (BloomFinale.playing or Homecoming.playing) else "ending"
	if bool(world.get("launching")) or Homecoming.playing or CradleAnswers.playing or BloomFinale.playing:
		return "wait"
	var d: HomewardDirector = HomewardDirector.of(world)
	if d == null or (d.map and d.map.is_open):
		return "wait"
	var ld: LateDirector = LateDirector.of(world)
	if ld and ld.story_busy():
		return "wait"
	var k: int = Homeward.current_planet()
	if k < 0:
		return ""
	var pid: String = str(Homeward.planet_def(k).get("id", ""))
	if _landed_planet != k:
		_landed_planet = k
		_landed_t = _t()
	AutoplayLate.mark("home_on_%s_s" % pid)
	var ff: bool = DevHooks.has("home-ff")
	if ff and not Homeward.restored(k) and _t() - _landed_t > DevHooks.get_f("home-ff", 20.0):
		(Homeward.state()["pct"] as Dictionary)[pid] = 0.999
		d._on_restored(Homeward.store_current(1.0))
	if Homeward.restored(k):
		AutoplayLate.mark("home_restored_%s_s" % pid)
	elif not ff:
		return ""
	else:
		return "wait"
	# Next planet still to restore, in order.
	var target: int = -1
	for i: int in Homeward.planets().size():
		if not Homeward.restored(i):
			target = i
			break
	if target > 0:
		var nav: int = int(Homeward.planet_def(target).get("nav", 5))
		while Homeward.drive() < nav:
			if not _build_drive(world, ff):
				return ""
		if ff:
			_ff_rocket()
		if SystemMap.launch_blocker(world, target) != "":
			return ""
		AutoplayLate.mark("home_launch_%s_s" % str(Homeward.planet_def(target)["id"]))
		HomewardDirector.launch_planet(world, target)
		return "fly to %s" % Homeward.planet_name(target)
	# Every planet restored: home to Verdance's Cradle Returns, then the Homeward rocket.
	if k != 0:
		if ff:
			_ff_rocket()
		if SystemMap.launch_blocker(world, 0) != "":
			return ""
		HomewardDirector._launch(world, Homeward.PLANET_BASE)
		return "fly home to Verdance"
	if not Homeward.at_home_site(world):
		var pl: PlanetData = world.get("planet")
		if pl == null or not pl.frontier_hubs.has("cradle_returns"):
			return ""
		if ff:
			_ff_rocket()
		if world.rocket_status() != "":
			return "wait"
		world._launch(int(pl.frontier_hubs["cradle_returns"]))
		return "hop to Cradle Returns"
	AutoplayLate.mark("home_site_s")
	if Homeward.drive() < 7:
		if not _build_drive(world, ff):
			return ""
		AutoplayLate.mark("home_rocket_built_s")
		return "built the Homeward rocket"
	if not GameState.flags.get("home_last_seed", false):
		d._build_home_site()
		d._use_bed()
		AutoplayLate.mark("home_last_seed_s")
		return "planted the last seed"
	if ff:
		_ff_rocket()
	AutoplayLate.mark("home_launch_home_s")
	if HomewardDirector.launch_home(world):
		return "launch home"
	return "wait"


static func _build_drive(world: Node, ff: bool) -> bool:
	var nd: Dictionary = Homeward.next_drive()
	if nd.is_empty():
		return false
	if ff:
		for c: String in nd.get("cost", {}):
			var cur: String = Homeward._cur(c)
			var need: float = float(nd["cost"][c]) - GameState.get_currency(cur).to_float()
			if need > 0.0:
				GameState.add_currency(cur, BigNum.from_float(need + 1.0))
	if not Homeward.buy_drive(Homeward.at_home_site(world)):
		return false
	HomewardDirector.on_drive_built(world)
	AutoplayLate.mark("home_drive_%d_s" % Homeward.drive())
	print("[Autoplay] home: built %s" % str(nd["name"]))
	return true


## Fast-forward: the cells are full and a rocket stands ready (a dev-hook start has no pad yet).
static func _ff_rocket() -> void:
	GameState.flags.erase("rocket_ready_unix")
	GameState.world["rocket_parked"] = true
