class_name Composter
extends Node3D
## Compost press at the base: the seed economy.
## [money] It turns organic junk straight into Seeds: paper/cardboard junk (anyone who picks it up)
## and every flower that blooms go into the press's hopper (GameState.flags.press_hopper, a
## machine fill level, not a currency), and the press makes seed packets from it on a timer.
## E at the press upgrades it (faster cycles, better yield). Dormant until the first sprout.

const POS := Vector3(-5.8, 0.0, 6.4)
const RANGE: float = 2.6

var world: Node
var level: int = 1
var _cycle_t: float = 0.0
var _last_blooms: float = -1.0
var _drum: Node3D
var _lamp: StandardMaterial3D
var _label: Label3D
var _steam_t: float = 0.0
var _press_head: Node3D


const DORMANT_CAP: float = 8.0  # [first] hopper limit while the press is dormant
const HOPPER_CAP: float = 2000.0  # [money] the hopper only holds so much organic matter


## [money] Organic matter waiting in the press (global, like the old compost currency).
static func hopper() -> float:
	return float(GameState.flags.get("press_hopper", 0.0))


static func add_hopper(v: float) -> void:
	var h: float = hopper()
	# A migrated old compost heap may sit above the cap; it only stops new matter coming in.
	GameState.flags["press_hopper"] = maxf(0.0, minf(h + v, maxf(h, HOPPER_CAP)))

func _ready() -> void:
	add_to_group("persist")
	level = int(GameState.world.get("composter_level", 1))
	_build()
	position = POS
	(func() -> void: PropColliders.fit(PropColliders.body(self, "Props"), self)).call_deferred()  # [world2] solid bins


func active() -> bool:
	if not YardBuilds.built("composter") and not DevHooks.has("unlock-seeds"):
		return false  # [camp2] a Hub build now: it does nothing until it is built
	return bool(GameState.flags.get("first_sprout", false)) or DevHooks.has("unlock-seeds")


func cycle_seconds() -> float:
	return 24.0 / (1.0 + 0.45 * float(level - 1))


func compost_per_cycle() -> float:
	return 4.0


func seeds_per_cycle() -> float:
	return 1.0 + 0.5 * float(level - 1)


func upgrade_cost() -> BigNum:
	return BigNum.from_float(180.0 * pow(2.6, float(level - 1)))


func max_level() -> int:
	return 8


func near(p: Vector3) -> bool:
	return is_visible_in_tree() and p.distance_to(global_position) < RANGE  # [camp] hidden until it works


func prompt() -> String:
	if not active():
		return tr("E   compost press  ·  dormant until something grows")
	if level >= max_level():
		return tr("E   compost press  ·  Lv %d (max)") % level
	return tr("E   upgrade compost press to Lv %d  ·  %s cubes") % [level + 1, Settings.fmt(upgrade_cost())]


func interact() -> void:
	if not active():
		EventBus.toast.emit(tr("The press is cold. Grow something first: it runs on what plants leave behind."), "hint")
		Audio.play("buzz", 1.1, -10.0)
		return
	if level >= max_level():
		return
	if not GameState.spend("cubes", upgrade_cost()):
		EventBus.toast.emit(tr("Not enough cubes to upgrade the press."), "info")
		Audio.play("buzz", 1.2, -10.0)
		return
	level += 1
	GameState.world["composter_level"] = level
	GameState.inc_stat("upgrades_bought")
	Vfx.burst("big_sparkle", to_global(Vector3(0, 1.4, 0)), Color(0.7, 1.0, 0.55))  # [orbB] its own up
	Audio.play("hydraulic", 1.0, -6.0)
	Audio.music_sting("upgrade")
	EventBus.toast.emit(tr("Compost press Lv %d: %.0f s cycles, %.1f seeds each.") % [level, cycle_seconds(), seeds_per_cycle()], "story")
	_refresh_label()


## Paper and card rot down nicely. Called for every piece anyone salvages.
func on_salvage(type_id: String, vol: float) -> void:
	if type_id == "paper":
		# [first] Before the first sprout the press is dormant: only a small heap builds up, so its
		# first output is a couple of seeds rather than a flood from an hour of paper.
		if not active() and hopper() >= DORMANT_CAP:
			return
		add_hopper(vol * 0.6)


func _process(delta: float) -> void:
	# Blooms feed the press too.
	var blooms: float = float(GameState.stats.get("plants_bloomed", 0.0))
	if _last_blooms < 0.0:
		_last_blooms = blooms
	elif blooms > _last_blooms:
		add_hopper((blooms - _last_blooms) * 1.5)
		_last_blooms = blooms
	var on: bool = active()
	_lamp.emission = Color(0.5, 1.0, 0.4) if on else Color(0.0, 0.0, 0.0)  # [yard] a dead lens while dormant
	if not on:
		return
	var have: bool = hopper() >= compost_per_cycle()
	if have:
		_cycle_t += delta
		_drum.rotation.z += delta * 1.6
		_steam_t -= delta
		if _steam_t <= 0.0:
			_steam_t = 1.2
			Vfx.burst("steam", to_global(Vector3(-0.6, 1.5, 0)), Color(0.9, 0.95, 0.9, 0.5), 0.4)
	var k: float = clampf(_cycle_t / cycle_seconds(), 0.0, 1.0)
	_press_head.position.y = 1.15 - 0.25 * smoothstep(0.85, 1.0, k)
	if _cycle_t >= cycle_seconds():
		_cycle_t = 0.0
		add_hopper(-compost_per_cycle())
		var n: float = seeds_per_cycle()
		GameState.add_currency("seeds", BigNum.from_float(n))
		GameState.inc_stat("seeds_pressed", n)
		Vfx.burst("soil", to_global(Vector3(0.6, 0.6, -0.4)), Color(0.45, 0.33, 0.2), 0.5)
		Vfx.burst("sparkle", to_global(Vector3(0.6, 0.9, -0.4)), Color(0.7, 1.0, 0.5), 0.3)
		Audio.play("thud", 1.3, -12.0)
		Audio.play("pop", 1.2, -10.0)
	if Engine.get_process_frames() % 20 == 0:
		_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	if not active():
		_label.text = tr("COMPOST PRESS\ndormant")
		return
	_label.text = tr("COMPOST PRESS  Lv %d\nhopper %d%%  →  seeds") % [level, int(round(100.0 * hopper() / HOPPER_CAP))]


func _build() -> void:
	# [yard] Kit bins, press cabinet, drum and stamping head (systems/camp/yard_art.gd).
	var parts: Dictionary = YardArt.composter()
	add_child((parts["body"] as YardArt.Kit).mi(0.2, "Body"))
	_drum = Node3D.new()
	_drum.position = Vector3(1.0, 1.1, 0)
	add_child(_drum)
	_drum.add_child((parts["drum"] as YardArt.Kit).mi(0.2, "Drum"))
	_press_head = Node3D.new()
	_press_head.position = Vector3(1.0, 1.15, -0.55)
	add_child(_press_head)
	_press_head.add_child((parts["head"] as YardArt.Kit).mi(0.2, "Head"))
	var lamp := MeshInstance3D.new()
	lamp.mesh = YardArt.bbox(Vector3(0.1, 0.1, 0.04), 0.02)
	_lamp = Mats.lamp(Color(0.5, 1.0, 0.4), 2.5)
	lamp.material_override = _lamp
	lamp.position = Vector3(0.65, 0.85, -0.45)
	add_child(lamp)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.pixel_size = 0.004
	_label.outline_size = 6
	_label.modulate = Color(0.85, 1.0, 0.8)
	_label.position = Vector3(0.3, 1.9, 0)
	add_child(_label)
	_refresh_label()


func persist_save() -> void:
	GameState.world["composter_level"] = level
