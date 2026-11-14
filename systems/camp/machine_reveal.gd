class_name MachineReveal
extends Node3D
## [camp] "It's here": shown whenever something is built into the world (stations, yard builds,
## the compost press waking up). A thin light pillar on the spot, a sparkle burst and a chime,
## the thing's name floating over it, and a dotted trail of light along the ground from Lumi to it
## that runs for a few seconds, so a purchase never goes unseen. Cheap: one pillar, one label,
## ~30 small unshaded dots, freed after LIFE seconds. Works in Compatibility.

const LIFE: float = 7.0
const COL := Color(0.55, 0.92, 1.0)

static var events: RevealEvents = RevealEvents.new()

var label_text: String = ""
var target := Vector3.ZERO
var from := Vector3.ZERO
var _t: float = 0.0
var _pillar: MeshInstance3D
var _pillar_mat: StandardMaterial3D
var _label: Label3D
var _dots: Array[MeshInstance3D] = []
var _dot_mat: StandardMaterial3D


class RevealEvents:
	extends RefCounted
	@warning_ignore("unused_signal")
	signal revealed(name_: String, at: Vector3)


## Shows the reveal in `world` (the slice; any Node3D parent works). Safe with world == null
## (tests): it only emits the signal then.
static func reveal(world: Node, name_: String, at: Vector3, toast: bool = true) -> void:
	events.revealed.emit(name_, at)
	if world == null or not world.is_inside_tree():
		return
	var r := MachineReveal.new()
	r.name = "MachineReveal"
	r.label_text = name_
	r.target = at
	var patch: Node3D = world.get("patch") as Node3D
	r.from = patch.global_position if patch else at
	world.add_child(r)
	if not toast:
		return
	EventBus.toast.emit(TranslationServer.translate("%s built.") % name_, "info")  # [v9c] no "follow the light": the light may be gone by the time a modal closes


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # also while the workbench (a pausing modal) is open
	_pillar_mat = StandardMaterial3D.new()
	_pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pillar_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pillar_mat.albedo_color = Color(COL.r, COL.g, COL.b, 0.0)
	_pillar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pillar = MeshInstance3D.new()
	_pillar.mesh = ProcMesh.cyl(0.07, 0.16, 9.0, 12)
	_pillar.material_override = _pillar_mat
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)
	_pillar.global_position = target + Vector3(0, 4.5, 0)
	_label = Label3D.new()
	_label.text = label_text
	_label.font_size = 54
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 10
	_label.modulate = Color(0.92, 0.98, 1.0, 0.0)
	_label.outline_modulate = Color(0.02, 0.08, 0.12, 0.0)
	add_child(_label)
	_label.global_position = target + Vector3(0, 3.0, 0)
	# Trail: dots every ~1.2 m along the ground from Lumi to the machine, lit one after another.
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = COL
	var a := Vector3(from.x, 0.0, from.z)
	var b := Vector3(target.x, 0.0, target.z)
	var n: int = clampi(int(a.distance_to(b) / 1.2), 0, 40)
	var dot_mesh: Mesh = ProcMesh.cyl(0.09, 0.09, 0.02, 10)
	for i: int in n:
		var d := MeshInstance3D.new()
		d.mesh = dot_mesh
		d.material_override = _dot_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		d.global_position = a.lerp(b, (float(i) + 0.5) / float(n)) + Vector3(0, 0.05, 0)
		d.scale = Vector3.ZERO
		_dots.append(d)
	Vfx.burst("sparkle", target + Vector3(0, 1.0, 0), COL, 1.2)
	Audio.play("confirm", 1.0, -3.0)
	Audio.play("whoosh", 0.8, -8.0)


func _process(delta: float) -> void:
	_t += delta
	if DevHooks.has("reveal-hold"):  # screenshots on slow software renders: keep it lit
		_t = minf(_t, LIFE * 0.5)
	var fade_in: float = clampf(_t / 0.4, 0.0, 1.0)
	var fade_out: float = clampf((LIFE - _t) / 1.2, 0.0, 1.0)
	var a: float = fade_in * fade_out
	_pillar_mat.albedo_color.a = 0.55 * a * (0.85 + 0.15 * sin(_t * 5.0))
	_pillar.scale = Vector3(1.0, fade_in, 1.0)
	_label.modulate.a = a
	_label.outline_modulate.a = a
	_label.global_position.y = target.y + 3.0 + 0.15 * sin(_t * 2.0)
	# The trail lights up from Lumi outwards, then a pulse keeps running along it toward the machine.
	var n: int = _dots.size()
	for i: int in n:
		var k: float = float(i) / maxf(1.0, float(n))
		var on: float = clampf((_t * 2.2 - k * 1.6), 0.0, 1.0)
		var pulse: float = 0.6 + 0.4 * maxf(0.0, cos((k * 6.0 - _t * 4.0)))
		_dots[i].scale = Vector3.ONE * on * pulse * fade_out
	if _t >= LIFE:
		queue_free()
