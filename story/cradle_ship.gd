class_name CradleShip
extends Node3D
## The ark *Cradle*: a long glossy-white seed ship with dark glass window bands, cyan seams, a
## spinning habitat ring and the glowing seed-vault dome (mesh: art/models/cradle, built in
## Blender by build_cradle.py). Used by the intro, the core-charge memories and the Bloom finale.
## ~40 m long at scale 1, flying toward -Z.

const MODEL_PATH := "res://art/models/cradle/cradle.glb"
const CYAN := Color(0.3, 0.9, 1.0)
const ALARM := Color(1.0, 0.16, 0.1)

static var _meshes: Dictionary = {}

## 0..1: seams pulse red (meteor storm).
var alarm: float = 0.0
## Engine glow multiplier.
var thrust: float = 1.0
var ring_speed: float = 0.12

var _ring: Node3D
var _glow: StandardMaterial3D
var _engine: StandardMaterial3D
var _vault: StandardMaterial3D
var _t: float = 0.0
var _vault_light: OmniLight3D


static func _load() -> void:
	if not _meshes.is_empty():
		return
	var scene: PackedScene = load(MODEL_PATH)
	var inst: Node = scene.instantiate()
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		_meshes[str(mi.name)] = {"mesh": mi.mesh, "pos": mi.position}
	inst.free()


func _ready() -> void:
	_load()
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.9, 0.91, 0.9)
	hull.roughness = 0.22
	hull.metallic = 0.05
	hull.clearcoat_enabled = true
	hull.clearcoat = 0.8
	hull.clearcoat_roughness = 0.1
	hull.rim_enabled = true
	hull.rim = 0.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.02, 0.03, 0.045)
	glass.metallic = 0.7
	glass.roughness = 0.06
	glass.emission_enabled = true
	glass.emission = Color(0.55, 0.8, 0.85)
	glass.emission_energy_multiplier = 0.25
	_glow = Mats.lamp(CYAN, 4.0)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(1.0, 0.48, 0.12)
	accent.roughness = 0.3
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.45, 0.1)
	accent.emission_energy_multiplier = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.16, 0.17, 0.19)
	trim.metallic = 0.6
	trim.roughness = 0.35
	var dome := StandardMaterial3D.new()
	dome.albedo_color = Color(0.55, 0.9, 0.95, 0.22)
	dome.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome.roughness = 0.04
	dome.metallic = 0.3
	dome.rim_enabled = true
	dome.rim = 0.8
	dome.emission_enabled = true
	dome.emission = Color(0.35, 0.9, 0.85)
	dome.emission_energy_multiplier = 0.25
	var garden := Mats.lamp(Color(0.35, 0.85, 0.35), 0.9)
	garden.albedo_color = Color(0.25, 0.6, 0.25)
	_vault = Mats.lamp(Color(0.55, 1.0, 0.7), 5.0)
	_engine = Mats.lamp(Color(0.6, 0.95, 1.0), 6.0)
	var mats: Dictionary = {"hull": hull, "glass": glass, "glow": _glow, "accent": accent, "trim": trim,
		"dome": dome, "garden": garden, "vault": _vault, "engine": _engine}
	for part: String in ["hull", "dome", "ring"]:
		if not _meshes.has(part):
			continue
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = _meshes[part]["mesh"]
		mi.position = _meshes[part]["pos"]
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var key: String = src.resource_name if src else ""
			if mats.has(key):
				mi.set_surface_override_material(i, mats[key])
		if part == "dome":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if part == "ring":
			_ring = mi
	_vault_light = OmniLight3D.new()
	_vault_light.light_color = Color(0.55, 1.0, 0.7)
	_vault_light.light_energy = 2.0
	_vault_light.omni_range = 7.0
	_vault_light.position = Vector3(0, 4.2, -2.0)
	add_child(_vault_light)


## The seed-vault dome's centre in world space.
func dome_world() -> Vector3:
	return global_transform * Vector3(0, 4.0, -2.0)


## Where the cargo pods hang (k = 0..5) in world space.
func pod_world(k: int = 2) -> Vector3:
	return global_transform * Vector3(0, -3.35, -9.0 + k * 2.6)


func _process(delta: float) -> void:
	_t += delta
	if _ring:
		_ring.rotate_object_local(Vector3(0, 0, 1), delta * ring_speed)
	var pulse: float = 0.5 + 0.5 * sin(_t * 9.0)
	var a: float = clampf(alarm, 0.0, 1.0)
	_glow.emission = CYAN.lerp(ALARM, a * (0.55 + 0.45 * pulse))
	_glow.emission_energy_multiplier = 4.0 + a * pulse * 3.0
	_engine.emission_energy_multiplier = 6.0 * thrust + sin(_t * 23.0) * 0.3
	_vault.emission_energy_multiplier = 5.0 + sin(_t * 1.3) * 0.6
	_vault_light.light_color = Color(0.55, 1.0, 0.7).lerp(ALARM, a * pulse)
