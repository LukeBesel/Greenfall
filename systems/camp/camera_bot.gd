class_name CameraBot
extends Node3D
## [camp3] Blink, the camera bot (owner: "The camera guy is an unlock build after a while of
## playing"). A one-time, game-wide Hub build (data/camp.json builds.camera_bot, kind one_time in
## data/builds.json). Photo mode only exists once he is built (ui/photo_mode.gd checks
## CameraBot.available()). He is a small floating drone in the helper-bot palette (pearl shell,
## coral and amber trim): a big dark lens for a face with an iris ring that focuses, a little
## shutter-button antenna and a soft hover glow. At the base he hovers by his spot and turns to
## watch Lumi; while photo mode is open he floats beside Lumi as the photographer and his lens
## flashes on each capture.

const ID: String = "camera_bot"
const PEARL := Color(0.93, 0.91, 0.86)
const CORAL := Color(0.95, 0.45, 0.36)
const AMBER := Color(1.0, 0.68, 0.22)

var world: Node
var _model: Node3D
var _iris: MeshInstance3D
var _iris_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _t: float = 0.0
var _flash: float = 0.0
var _home := Vector3.ZERO
var _was_open: bool = false


## Whether photo mode is unlocked (the camera bot is built).
static func available() -> bool:
	return YardBuilds.built(ID) or DevHooks.has("photo")


## Old saves where photo mode was already used get him built (once per profile save).
static func migrate(loaded_district: bool) -> void:
	if GameState.flags.has("camera_bot_migrated"):
		return
	GameState.flags["camera_bot_migrated"] = true
	if not loaded_district:
		return  # a new game starts without him
	var used: bool = int(GameState.stats.get("photo_mode_opens", 0)) > 0 \
		or not (GameState.flags.get("fauna_photos", []) as Array).is_empty() \
		or int(GameState.stats.get("photos_taken", 0)) > 0
	if not used:
		var d := DirAccess.open(PhotoMode.SHOT_DIR)
		if d:
			for f: String in d.get_files():
				if f.ends_with(".png"):
					used = true
					break
	if used:
		YardBuilds.mark_built(ID)


func setup(p_world: Node) -> void:
	world = p_world
	name = "CameraBot"
	process_mode = Node.PROCESS_MODE_ALWAYS  # photo mode pauses the tree; he still poses
	_home = YardBuilds.pos(ID, Vector3(-6.2, 0, 4.4))
	_build()
	position = _home + Vector3(0, 1.5, 0)
	visible = YardBuilds.built(ID)
	var ph: Node = world.get("photo")
	if ph and ph.has_signal("captured"):
		ph.connect("captured", func(_p: String) -> void: _flash = 1.0)


## Shows him (live: he pops in with the reveal).
func set_built(animate: bool) -> void:
	visible = true
	if animate:
		scale = Vector3.ONE * 0.05
		create_tween().tween_property(self, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Audio.play("blip", 1.3, -6.0)


static func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


## Faces -Z like the robots: the lens is on the -Z side.
func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	var shell: StandardMaterial3D = _mat(PEARL, 0.28)
	shell.clearcoat_enabled = true
	shell.clearcoat = 0.6
	var coral: StandardMaterial3D = _mat(CORAL, 0.4)
	var dark: StandardMaterial3D = _mat(Color(0.07, 0.08, 0.1), 0.15, 0.4)
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	# Body: a rounded box, a coral band around it, a chrome lens barrel on the front.
	_mi(_model, ProcMesh.rounded_box(Vector3(0.42, 0.34, 0.34), 0.11, 4), shell, Vector3.ZERO)
	_mi(_model, ProcMesh.rounded_box(Vector3(0.44, 0.07, 0.36), 0.03, 2), coral, Vector3(0, -0.09, 0))
	_mi(_model, ProcMesh.cyl(0.13, 0.14, 0.1, 28), chrome, Vector3(0, 0.02, -0.2), Vector3(PI * 0.5, 0, 0))
	_mi(_model, ProcMesh.cyl(0.11, 0.11, 0.012, 28), dark, Vector3(0, 0.02, -0.252), Vector3(PI * 0.5, 0, 0))
	# The iris: an amber ring that tightens as he focuses and flashes on a capture.
	_iris_mat = StandardMaterial3D.new()
	_iris_mat.albedo_color = AMBER
	_iris_mat.emission_enabled = true
	_iris_mat.emission = AMBER
	_iris_mat.emission_energy_multiplier = 1.2
	_iris = _mi(_model, ProcMesh.torus(0.045, 0.06, 24, 4), _iris_mat, Vector3(0, 0.02, -0.258), Vector3(PI * 0.5, 0, 0))
	var glint := _mat(Color(1, 1, 1), 0.05)
	glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mi(_model, ProcMesh.sphere(0.018, 8, 4), glint, Vector3(0.05, 0.07, -0.26))
	# Shutter button and a tiny antenna with a coral tip; two little side fins.
	_mi(_model, ProcMesh.cyl(0.035, 0.035, 0.03, 14), coral, Vector3(0.11, 0.185, 0.02))
	_mi(_model, ProcMesh.cyl(0.006, 0.006, 0.14, 6), chrome, Vector3(-0.1, 0.24, 0.06))
	_mi(_model, ProcMesh.sphere(0.024, 10, 5), coral, Vector3(-0.1, 0.32, 0.06))
	for sx: float in [-1.0, 1.0]:
		_mi(_model, ProcMesh.rounded_box(Vector3(0.05, 0.16, 0.2), 0.02, 2), shell, Vector3(sx * 0.24, 0.0, 0.04), Vector3(0, 0, sx * 0.25))
	# Hover glow under him.
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.6)
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mi(_model, ProcMesh.torus(0.06, 0.1, 20, 4), _glow_mat, Vector3(0, -0.2, 0))


func _process(delta: float) -> void:
	if not visible or world == null:
		return
	_t += delta
	var patch: Node3D = world.get("patch") as Node3D
	var ph: Variant = world.get("photo")
	var shooting: bool = ph is PhotoMode and (ph as PhotoMode).is_open
	if shooting and not _was_open:
		GameState.inc_stat("blink_shoots")
	_was_open = shooting
	# Where he wants to be: his spot in the yard, or (photo mode) a little in front of Lumi.
	var goal: Vector3 = _home + Vector3(0, 1.5, 0)
	var look: Vector3 = patch.global_position + Vector3(0, 0.9, 0) if patch else goal + Vector3(0, 0, 1)
	if shooting and patch:
		var fwd: Vector3 = -patch.global_transform.basis.z
		goal = patch.global_position + fwd * 1.6 + patch.global_transform.basis.x * 0.8 + Vector3(0, 1.3, 0)
	elif patch and patch.global_position.distance_to(_home) > 14.0:
		goal = _home + Vector3(0, 1.5, 0)  # Lumi is out in the field: he stays home
	global_position = global_position.lerp(goal + Vector3(0, sin(_t * 2.1) * 0.06, 0), clampf(delta * (3.0 if shooting else 1.5), 0.0, 1.0))
	var to: Vector3 = look - global_position
	to.y = 0.0
	if to.length() > 0.05:
		var want: float = atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(delta * 4.0, 0.0, 1.0))
	_model.rotation.z = sin(_t * 1.3) * 0.06
	# Iris: breathes at rest, tightens while shooting, flashes white on a capture.
	_flash = maxf(0.0, _flash - delta * 3.0)
	var s: float = (0.75 if shooting else 1.0) + 0.06 * sin(_t * (5.0 if shooting else 1.6))
	_iris.scale = Vector3(s, 1.0, s)
	_iris_mat.emission = AMBER.lerp(Color.WHITE, _flash)
	_iris_mat.emission_energy_multiplier = 1.2 + 6.0 * _flash
	_glow_mat.albedo_color.a = 0.45 + 0.15 * sin(_t * 4.0)
