class_name BotBay
extends Node3D
## [v10pace] The Bot Bay as its own machine (owner: "Make the bot bay another thing like the tool
## bench. seperate from other stuff"): a robot assembly bay in the yard. It is built once per base
## (the workbench's Build tab: data/builds.json "bot_bay"; price and conditions in
## data/workbench.json tiers[1]); walk up, press E, and its own screen opens: build and upgrade
## robots, nothing else (UpgradesScreen in solo mode, ui/upgrades_screen.gd). The workbench has no
## Bots tab any more. Robots built here roll out of this bay, so they start work at this base.
##
## One per base. `key` names the base: HOME ("0") is the start yard, whose state is the old
## "Workbench Mk II: Bot Bay" tier (BenchTiers.tier() >= 2), so a save that had the Bots tab has
## the bay standing. Any other key (a far base: its site index as text) is kept in
## GameState.orbit["bot_bays"][key] (BotBay.built(key) / BotBay.mark_built(key)). A far base:
##   var b := BotBay.new(); parent.add_child(b)      # any parent: the site's prefab, the world
##   b.setup(world, str(site))                         # world = the slice (fleet, hub, interactables)
##   b.transform = local_xf; b.reseat()                # or b.place(global_xf)
##   BotBay.mark_built(str(site))                      # when it is bought there: it shows itself
## Nothing in here reads the start site or GameState.world.
## The unbuilt spot is marked on the ground by BuildSpot (systems/camp/build_spot.gd).

const HOME: String = "0"
const REACH: float = 2.6
## Flat-yard fallback spot (the globe uses the site's "bot_bay" anchor).
const POS := Vector3(8.0, 0.0, 7.0)
## Footprint (m): the build spot's outline and the keep-clear.
const SIZE := Vector2(3.2, 2.6)

static var events: BayEvents = BayEvents.new()

var world: Node
var key: String = HOME
var screen: UpgradesScreen
var _anchor: Node3D
var _shell: MeshInstance3D
var _pad: MeshInstance3D
var _busy_t: float = 0.0
var _check_t: float = 0.0


class BayEvents:
	extends RefCounted
	@warning_ignore("unused_signal")
	signal built(key: String)


static func built(p_key: String = HOME) -> bool:
	if p_key == HOME:
		return BenchTiers.tier() >= 2
	return bool((GameState.orbit.get("bot_bays", {}) as Dictionary).get(p_key, false))


## A far base's bay is bought (the start yard's goes through BenchTiers.buy).
static func mark_built(p_key: String) -> void:
	if p_key == HOME:
		GameState.flags["bench_tier"] = maxi(BenchTiers.tier(), 2)
	else:
		if not (GameState.orbit.get("bot_bays") is Dictionary):
			GameState.orbit["bot_bays"] = {}
		(GameState.orbit["bot_bays"] as Dictionary)[p_key] = true
	events.built.emit(p_key)


## The bay of base `p_key` in this world (null when none was set up).
static func of(p_world: Node, p_key: String = HOME) -> BotBay:
	if p_world == null:
		return null
	for n: Node in p_world.get_tree().get_nodes_in_group("bot_bay") if p_world.is_inside_tree() else []:
		if n is BotBay and (n as BotBay).key == p_key:
			return n as BotBay
	return null


func setup(p_world: Node, p_key: String = HOME) -> void:
	world = p_world
	key = p_key
	name = "BotBay" if key == HOME else "BotBay_%s" % key
	add_to_group("bot_bay")
	_shell = YardArt.bot_bay().mi(0.12, "BayShell")
	add_child(_shell)
	YardArt.set_powered(_shell, true)
	_pad = YardArt.bot_bay_pad().mi(0.12, "BayPad")
	add_child(_pad)
	YardArt.set_powered(_pad, false)
	YardArt.solid(self, Vector3(SIZE.x - 0.2, 2.6, 0.5), Vector3(0, 1.3, -0.95), "BayBack")
	for s: float in [-1.0, 1.0]:
		YardArt.solid(self, Vector3(0.4, 2.6, 1.9), Vector3(s * 1.3, 1.3, -0.2), "BaySide")
	position = POS
	_anchor = Node3D.new()
	_anchor.name = "BotBayReach"
	world.add_child(_anchor)
	reseat()
	if world.get("interactables") != null:
		(world.interactables as Interactables).register(_anchor, REACH,
			func() -> String: return tr("E   open the Bot Bay"),
			func() -> void: open(),
			func() -> bool: return visible)
	_show(built(key))
	events.built.connect(_on_built)  # methods: the static signals drop them when we're freed
	YardBuilds.events.built.connect(_on_yard_built)
	EventBus.robot_built.connect(_on_robot_built)
	if DevHooks.has("open-botbay") and key == HOME:  # dev (shots): --open-botbay[=S] builds it and opens its screen S s in
		mark_built(HOME)
		Research.grant("salvage_logic")  # as BenchTiers.buy: the Scoopie can be built
		(func() -> void:
			await DevHooks.wait_wall(DevHooks.get_f("open-botbay", 100.0))
			if is_inside_tree():
				open()).call_deferred()


## Puts the bay (and its E spot) at a world transform: the site's anchor.
func place(xf: Transform3D) -> void:
	global_transform = xf
	reseat()


## Moves the E spot to the bay after its transform was set.
func reseat() -> void:
	if _anchor and is_inside_tree():
		_anchor.global_position = stand_point()


## Where a robot built here rolls out: the bay's round pad.
func build_point() -> Vector3:
	var at: Vector3 = global_transform * Vector3(0, 0, 0.5)
	return at + OrbitUp.up(at) * 0.25


## Where Lumi stands to use it (the E spot, the card's beam): in front of the bay mouth.
func stand_point() -> Vector3:
	return global_transform * Vector3(0, 0, 2.0)


func _show(on: bool) -> void:
	visible = on
	for c: Node in get_children():
		if c is StaticBody3D:
			for sh: Node in c.get_children():
				if sh is CollisionShape3D:
					(sh as CollisionShape3D).disabled = not on


func _on_built(p_key: String) -> void:
	if p_key == key:
		_show(true)


func _on_yard_built(id: String) -> void:
	if id == "bot_bay" and key == HOME:
		_show(built(key))


## A robot was built: if it was at this bay's screen, the pad lights up, and the very first one
## closes the screen so the player watches it roll out.
func _on_robot_built(_n: String) -> void:
	if not is_open():
		return
	flash_build()
	var v: Variant = GameState.stats.get("robots_built", 0.0)
	if (v is float or v is int) and float(v) <= 1.0:
		screen.close_screen.call_deferred()


## Opens the Bot Bay's own screen (Esc, Tab or Close shuts it).
func open() -> void:
	if not built(key):
		return
	if screen == null or not is_instance_valid(screen):
		screen = UpgradesScreen.new()
		screen.solo = "bots"
		screen.name = "BotBayScreen"
		screen.fleet = world.get("fleet")
		screen.hub = world.get("hub")
		screen.build_at = build_point
		world.add_child(screen)
		screen.closed.connect(_on_closed)
	if screen.is_open:
		return
	var so: Variant = world.get("orbit")
	if so != null and (so as Object).has_method("set_input"):
		so.call("set_input", false)
	screen.open_screen()


func is_open() -> bool:
	return screen != null and is_instance_valid(screen) and screen.is_open


func _on_closed() -> void:
	var so: Variant = world.get("orbit")
	if so != null and (so as Object).has_method("on_modal_closed"):
		so.call("on_modal_closed")


## A robot is being put together: the pad and its light glow for a few seconds.
func flash_build() -> void:
	_busy_t = 4.0
	YardArt.set_powered(_pad, true)


func _process(delta: float) -> void:
	_check_t += delta
	if _check_t >= 0.5:  # the state is the truth (a load, a dev jump): stand when built
		_check_t = 0.0
		if visible != built(key):
			_show(built(key))
	if _busy_t > 0.0:
		_busy_t -= delta
		if _busy_t <= 0.0:
			YardArt.set_powered(_pad, false)
