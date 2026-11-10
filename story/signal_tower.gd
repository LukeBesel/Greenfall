class_name SignalTower
extends Node3D
## [onboard] The Signal Tower: the only way WREN can reach Lumi (owner, playtest 2: "We should
## build a signal before it can talk to us again"). After her one last message in the crash she is
## silent until the broken mast in the yard is rebuilt (E). Each tier raises the relay signal
## (25/50/75/100%), which makes WREN clearer (Wren.stage) and releases the lines she couldn't send
## (Wren backlog). Tier lives in GameState.flags["signal_tower"] (global: one relay network).
## Old saves get the tier matching the signal they had (restoration stages).

const PATH: String = "res://data/signal_tower.json"
const GLOW := Color(0.55, 0.9, 1.0)

static var _cfg: Dictionary = {}

var world: Node
var _model: Node3D
var _lamp_mat: StandardMaterial3D
var _t: float = 0.0
var _col: CollisionShape3D  # [camp2]


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func tier() -> int:
	return int(GameState.flags.get("signal_tower", 0))


static func max_tier() -> int:
	return (cfg().get("tiers", []) as Array).size()


## Relay signal 0..100 for a tier.
static func signal_pct(t: int = -1) -> int:
	var arr: Array = cfg().get("signal_pct", [0, 25, 50, 75, 100])
	return int(arr[clampi(tier() if t < 0 else t, 0, arr.size() - 1)])


## Cost of the next tier ({} at the top).
static func next_cost() -> Dictionary:
	var tiers: Array = cfg().get("tiers", [])
	return (tiers[tier()] as Dictionary).get("cost", {}) if tier() < tiers.size() else {}


static func pos() -> Vector3:
	var p: Array = cfg().get("pos", [3.4, 0.0, -6.6])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Pure: the tier an old save gets, from the WREN signal stage it had (restored hexes 0-5 / 6-19 / 20+).
static func migrated_tier(restored: int) -> int:
	return 1 if restored < 6 else (2 if restored < 20 else 3)


## Called once per load: fresh games start at 0 (and say so, so a later load never migrates);
## a save from before the tower gets the tier matching its old signal.
static func migrate(world_: Node) -> void:
	if GameState.flags.has("signal_tower"):
		return
	var veteran: bool = GameState.flags.get("wren_awake", false) or int(GameState.stats.get("cubes_cashed", 0)) >= 3 \
		or int(GameState.flags.get("tutorial_step", 0)) >= Tutorial.STEPS.size()
	var restored: int = 0
	var pl: Variant = world_.get("planet") if world_ else null
	if pl is PlanetData:
		restored = (pl as PlanetData).restored_count()
	GameState.flags["signal_tower"] = migrated_tier(restored) if veteran else 0


func _ready() -> void:
	position = pos()
	var dev: float = DevHooks.get_f("signal-tower", -1.0)
	if dev >= 0.0:
		GameState.flags["signal_tower"] = clampi(int(dev), 0, max_tier())
	_build()
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 2.4
	cs.shape = cyl
	cs.position = Vector3(0, 1.2, 0)
	body.add_child(cs)
	add_child(body)
	_col = cs
	_show_built()  # [camp2] nothing stands here until the first tier is built in the Hub tab
	var it: Variant = world.get("interactables") if world else null
	if it is Interactables:
		(it as Interactables).register(self, 2.2, _prompt, _use, func() -> bool: return tier() >= 1 and tier() < max_tier())  # [camp2] E boosts a standing tower


## [camp2] The tower is a Hub build (systems/camp/hub_builds.gd): hidden, with no collision,
## until tier 1 is bought.
func _show_built() -> void:
	visible = tier() >= 1
	if _col:
		_col.disabled = tier() < 1


func _prompt() -> String:
	var g: String = Settings.glyph("interact")
	var c: String = Currencies.cost_text(next_cost())
	# TRANSLATORS: %s = interact key, then the cost ("50 cubes").
	if tier() == 0:
		return tr("%s   rebuild the signal tower  ·  %s") % [g, c]
	return tr("%s   boost the signal tower  ·  %s") % [g, c]


func _use() -> void:
	var cost: Dictionary = next_cost()
	if cost.is_empty():
		return
	if not GameState.can_afford_all(cost):
		EventBus.toast.emit(tr("The tower needs %s.") % Currencies.cost_text(cost), "info")
		Audio.play("buzz", 1.2, -10.0)
		return
	GameState.spend_all(cost)
	raise()


## One tier up: rebuild the model, then WREN gets through (Wren.on_signal_raised).
func raise() -> void:
	GameState.flags["signal_tower"] = mini(tier() + 1, max_tier())
	GameState.inc_stat("signal_tower_tiers")
	_build()
	_show_built()  # [camp2]
	Audio.play("chime", 0.9, -4.0)
	Audio.play("servo", 0.8, -8.0)
	Vfx.burst("sparkle", global_position + global_basis.y.normalized() * (2.0 + tier() * 1.1), GLOW)  # [orbB] local up
	EventBus.toast.emit(tr("Relay signal %d%%. WREN can reach you.") % signal_pct() if tier() == 1 else tr("Relay signal %d%%. WREN comes through clearer.") % signal_pct(), "reward")  # [v4calm] cut: WREN's own line says it
	var w: Variant = world.get("wren") if world else null
	if w is Wren:
		(w as Wren).on_signal_raised(tier())


# --- Look -----------------------------------------------------------------------------------

## [yard] A kit lattice mast that grows per tier (systems/camp/yard_art.gd YardArt.signal_tower):
## dish, platform and second dish, halo ring and whips, beacon dome and solar panels. The tip lamp
## pulses (red while broken, cyan once it carries a signal).
func _build() -> void:
	if _model:
		_model.queue_free()
	_model = Node3D.new()
	add_child(_model)
	var t: int = tier()
	var d: Dictionary = YardArt.signal_tower(t)
	var mi: MeshInstance3D = (d["kit"] as YardArt.Kit).mi(0.15 if t > 0 else 0.7, "Mast")
	_model.add_child(mi)
	YardArt.set_powered(mi, t > 0)
	_lamp_mat = Mats.lamp(Color(1.0, 0.25, 0.2) if t == 0 else GLOW, 2.5)
	var tip := MeshInstance3D.new()
	tip.mesh = YardArt.bbox(Vector3.ONE * (0.14 if t < 4 else 0.2), 0.06 if t < 4 else 0.09)
	tip.material_override = _lamp_mat
	tip.position = d["tip"]
	_model.add_child(tip)


func _process(delta: float) -> void:
	_t += delta
	if _lamp_mat:  # slow blink: red while broken, a calm cyan pulse once it carries a signal
		var on: float = 0.5 + 0.5 * sin(_t * (5.0 if tier() == 0 else 2.0))
		_lamp_mat.emission_energy_multiplier = lerpf(0.4, 3.0, on)
