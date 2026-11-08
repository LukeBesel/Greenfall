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
	if world and world.get("layout") != null:
		var lay: CityLayout = world.layout
		position.y = clampf(lay.height_at(position.x, position.z), 0.0, 0.3)
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
	var it: Variant = world.get("interactables") if world else null
	if it is Interactables:
		(it as Interactables).register(self, 2.2, _prompt, _use, func() -> bool: return tier() < max_tier())


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
	Audio.play("chime", 0.9, -4.0)
	Audio.play("servo", 0.8, -8.0)
	Vfx.burst("sparkle", global_position + Vector3(0, 2.0 + tier() * 1.1, 0), GLOW)
	EventBus.toast.emit(tr("Relay signal %d%%. WREN can reach you.") % signal_pct() if tier() == 1 else tr("Relay signal %d%%. WREN comes through clearer.") % signal_pct(), "story")
	var w: Variant = world.get("wren") if world else null
	if w is Wren:
		(w as Wren).on_signal_raised(tier())


# --- Look -----------------------------------------------------------------------------------

## A slim white-and-steel mast that grows with each tier: a broken, leaning stub at tier 0; then
## a dish, more sections, a second dish, a halo ring and a lit tip. A thin cyan seam runs up it.
func _build() -> void:
	if _model:
		_model.queue_free()
	_model = Node3D.new()
	add_child(_model)
	var t: int = tier()
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.86, 0.87, 0.86) if t > 0 else Color(0.45, 0.4, 0.36)
	white.roughness = 0.35 if t > 0 else 0.8
	var seam: StandardMaterial3D = Mats.lamp(GLOW, 1.6 if t > 0 else 0.0)
	_lamp_mat = Mats.lamp(Color(1.0, 0.25, 0.2) if t == 0 else GLOW, 2.5)
	_cyl(steel, 0.62, 0.7, 0.28, 0.14)  # plinth
	var h: float = [1.3, 2.6, 3.8, 5.0, 6.2][clampi(t, 0, 4)]
	var mast := Node3D.new()
	_model.add_child(mast)
	if t == 0:
		mast.rotation = Vector3(0.0, 0.0, deg_to_rad(14.0))  # bent and leaning
	_cyl(white, 0.16, 0.11, h, 0.28 + h * 0.5, mast)
	if t > 0:
		_cyl(seam, 0.03, 0.03, h - 0.3, 0.28 + h * 0.5, mast, Vector3(0.12, 0, 0.06))
	for k: int in int(h / 1.2):  # collars
		_cyl(steel, 0.2, 0.2, 0.06, 0.6 + k * 1.2, mast)
	if t >= 1:
		_dish(mast, Vector3(0.0, h * 0.62, 0.0), 0.0, 0.55)
	if t >= 2:
		_dish(mast, Vector3(0.0, h * 0.82, 0.0), PI * 0.8, 0.45)
	if t >= 3:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.5
		tm.outer_radius = 0.54
		ring.mesh = tm
		ring.material_override = seam
		ring.position = Vector3(0, h - 0.4, 0)
		mast.add_child(ring)
	var tip := MeshInstance3D.new()
	tip.mesh = ProcMesh.sphere(0.07 if t < 4 else 0.11, 10, 6)
	tip.material_override = _lamp_mat
	tip.position = Vector3(0, 0.28 + h + 0.05, 0)
	mast.add_child(tip)


func _cyl(m: Material, top: float, bottom: float, h: float, y: float, parent: Node3D = null, off: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3(0, y, 0) + off
	(parent if parent else _model).add_child(mi)


func _dish(parent: Node3D, at: Vector3, yaw: float, r: float) -> void:
	var piv := Node3D.new()
	piv.position = at
	piv.rotation = Vector3(0, yaw, 0)
	parent.add_child(piv)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 0.5
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.88)
	m.roughness = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.rotation = Vector3(deg_to_rad(-70.0), 0, 0)
	mi.position = Vector3(0, 0, r * 0.45)
	piv.add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if _lamp_mat:  # slow blink: red while broken, a calm cyan pulse once it carries a signal
		var on: float = 0.5 + 0.5 * sin(_t * (5.0 if tier() == 0 else 2.0))
		_lamp_mat.emission_energy_multiplier = lerpf(0.4, 3.0, on)
