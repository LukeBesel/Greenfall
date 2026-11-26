class_name PatchModel
extends Node3D
## The player's robot, Lumi (LM-1): the ark's seed-keeper bot, fallen back to Verdance.
## Matches the owner's Aurora portrait and turnaround (rebuilt Nov 2026, art/models/aurora/build_aurora.py):
## a wide rounded-rectangle head (about 56% of his height) with a thick off-white shell, one curved
## glossy black visor across nearly the whole front with two oversized cyan C-ring eyes (a ring with a
## gap to the upper right and one dot in the gap), round side
## modules with a thin cyan ring lens and a mechanical hub, a short swept-back fin with an amber edge,
## a compact torso tucked under the head with a raised recycling plate and orange latches, short
## chunky arms with curved claws (the right one projects the pickup lasers), and a compact rounded
## underside with one recessed hover ring. Worn, dusty paint. Colorways are unlockable designs ("aurora" is
## the default look). Faces -Z. Base (hover ring) near y=0.

# Unlockable designs (owner's concept sheet; gameplay side in systems/designs.gd + data/designs.json).
# paint / trim / accent: hero_paint colours; glow: eyes, ear rings, hover ring, chest light and
# pickup lasers; lamp: the small accent lights (cheeks, chest tabs); coverage/grime: wear; moss and
# stripes: hero_paint extras; acc: add-ons from designs.glb (+ "antenna" from aurora.glb) and
# procedural extras (holo, butterfly, case); icon: chest screen icon; happy: resting smile (0..1).
# l10n:begin
const VARIANTS: Dictionary = {
	"aurora": {"name": "Aurora", "paint": Color(0.8, 0.735, 0.685), "trim": Color(0.412, 0.435, 0.471), "glow": Color(0.25, 0.886, 0.94), "accent": Color(0.945, 0.42, 0.012), "lamp": Color(0.973, 0.686, 0.035), "paddle": Color(0.953, 0.753, 0.251), "icon": "recycle", "grime": 0.75, "acc": ["antenna"]},
	"bolt": {"name": "Bolt", "paint": Color(0.95, 0.7, 0.1), "trim": Color(0.32, 0.29, 0.24), "glow": Color(1.0, 0.68, 0.18), "accent": Color(0.95, 0.72, 0.12), "lamp": Color(1.0, 0.6, 0.12), "icon": "recycle", "coverage": 0.8, "grime": 0.85, "stripes": 1.0, "acc": ["antenna", "acc_pad_r", "acc_pad_l", "gear"]},
	"sprout": {"name": "Sprout", "paint": Color(0.47, 0.53, 0.23), "trim": Color(0.33, 0.35, 0.22), "glow": Color(0.52, 1.0, 0.36), "accent": Color(0.86, 0.62, 0.22), "lamp": Color(0.6, 1.0, 0.35), "icon": "leaf", "grime": 0.7, "moss": 0.6, "acc": ["acc_sprout"]},
	"pixel": {"name": "Pixel", "paint": Color(0.8, 0.15, 0.14), "trim": Color(0.6, 0.12, 0.12), "glow": Color(1.0, 0.33, 0.5), "accent": Color(0.93, 0.91, 0.88), "lamp": Color(1.0, 0.4, 0.55), "icon": "recycle", "happy": 1.0, "acc": ["acc_pixel", "butterfly"]},
	"nova": {"name": "Nova", "paint": Color(0.25, 0.245, 0.28), "trim": Color(0.16, 0.15, 0.19), "glow": Color(0.7, 0.4, 1.0), "accent": Color(0.4, 0.38, 0.45), "lamp": Color(0.72, 0.42, 1.0), "icon": "recycle", "metal": 0.35, "acc": ["acc_catears", "holo"]},
	"patch": {"name": "Patch", "paint": Color(0.92, 0.9, 0.86), "trim": Color(0.35, 0.36, 0.38), "glow": Color(1.0, 0.7, 0.26), "accent": Color(1.0, 0.48, 0.12), "lamp": Color(1.0, 0.55, 0.15), "icon": "cross", "acc": ["antenna", "acc_toolbox", "case"]},
}
# l10n:end

var variant: String = "aurora"

# Interface used by Patch, the camera, the detector and baling.
var chest_point := Vector3(0, 0.43, -0.22)
var back_hatch_point := Vector3(0, 0.42, 0.2)
var vent_points: Array[Vector3] = [Vector3(-0.11, 0.935, 0.33), Vector3(0.11, 0.935, 0.33)]  # head's back vent band
var stack_point := Vector3(0, 1.3, 0.3)
var lens_point := Vector3(0, 0.9, -0.36)
## [hero] Attachment anchors for head pieces, chest icons, held items and back gear (character
## builder). Positions in the model's float space (head_top in the head's space); see get_anchor().
const ANCHORS := {"head_top": Vector3(0, 0.66, 0.0), "chest_plate": Vector3(0, 0.435, -0.216), "hand_r": Vector3(0, 0, -0.13), "hand_l": Vector3(0, 0, -0.13), "back": Vector3(0, 0.435, 0.19)}
## Eye shapes for bot_face.gdshader's eye_shape (VARIANTS may set "eyes"; set_eye_shape() at runtime).
const EYE_SHAPES := ["crescent", "round", "happy", "bar", "heart"]
var _anchors: Dictionary = {}
## [hero] Detector beacon: a small red lamp on the rear of the fin mount (head space), parented to
## the head so it follows hover bob, lean, head turn/tilt and every pose (owner: "the blinking red
## dot sometimes comes off the player's head" when it lived on Patch at a fixed height).
const BEACON_LOCAL := Vector3(0, 0.673, 0.155)  # on the fin mount, behind the stalk (build_aurora.py prints it)
var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D
var _beacon_light: OmniLight3D
var _beacon_amt: float = 0.0
var sleeping: bool = false
var _iris_now: float = 0.5

var _root: Node3D
var _float: Node3D
var _head: Node3D
var _face_mat: ShaderMaterial
var _ring_mat: StandardMaterial3D
var _arm_l: Node3D
var _arm_r: Node3D
var _claws: Array[Node3D] = []
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _beam_big: bool = false
## World position the tractor beam locks onto (null = no beam).
var _beam_target: Variant = null
var _beam_amt: float = 0.0
var _spark_t: float = 0.0
var _fill_bar: MeshInstance3D
var _icon: Label3D
var _icon_color := Color.WHITE
## Pickup feedback: hopper pop (fill bar + chest icon) and a quick eye flash.
var _hopper_pulse: float = 0.0
var _eye_flash: float = 0.0
var _hatch: Node3D

var _t: float = 0.0
var _scoop_t: float = 0.0
var _scoop_amt: float = 0.0
var _shudder: float = 0.0
var _press: float = 0.0
var _happy: float = 0.5
var _happy_target: float = 0.5
## [v10ui] set_happy() at or above this shows the ^ ^ arcs; below it the round eyes.
const HAPPY_ARCS_FROM: float = 0.75
var _face_happy: float = 0.0
var _look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _head_yaw: float = 0.0
var _head_yaw_target: float = 0.0
var _blink_timer: float = 2.5
var _blink: float = 0.0
## Blink phase time (s): < 0 idle (or the gap before a double blink), 0..BLINK_LEN blinking.
var _blink_t: float = -1.0
var _blink_double: bool = false
var _sleep_amt: float = 0.0
var _sleep_seen: bool = false
## [hero v2] Idle arm pose: x = shoulder pitch (up/forward), z = outward (right arm; mirrored on
## the left), y = elbow bend.
## [hero v2] Character-builder slots: each swappable characteristic is its own part (or part pair)
## in aurora.glb. A variant / builder save overrides any slot by naming another part with the same
## pivot conventions; eyes ("eyes" -> EYE_SHAPES), colours (the colour keys below) and toppers
## ("acc", head_top / beacon anchors) are already independent of the shapes.
## [art2] On the ears part (the side modules) the dark housings and rings take the Locker's "side"
## colour (_mats["side"]); their lens, ring light and steel fins stay as modelled.
const SIDE_REMAP := {"dark": "side", "trim": "side"}
## Add-ons in designs.glb were modelled for an earlier, lower and wider head and a wider torso (not
## rebuilt, see docs/HANDOVER_AURORA.md): offsets and scales that seat them on the current shapes.
## [art2] Re-fitted to the concept-proportioned head (narrower, ears higher) and the slimmer torso.
const ACC_FIT := {
	"acc_catears": {"pos": Vector3(0, 0.155, 0), "scale": Vector3(0.85, 1, 1)},
	"acc_sprout": {"pos": Vector3(0, 0.17, 0)},
	"acc_pixel": {"pos": Vector3(0, 0.145, 0), "scale": Vector3(0.85, 1, 1)},
	"acc_pixel_hearts": {"pos": Vector3(0, 0.105, -0.025), "scale": Vector3(0.84, 1, 1)},
	"acc_toolbox": {"pos": Vector3(-0.015, 0, 0)},
}
const SLOT_DEFAULTS := {"head": "head", "visor": "visor", "ears": "ears", "finger": "finger", "finger_tip": "finger_tip"}
## Per-part colours a variant may override (defaults are Aurora's, sampled from the concept).
const COLOR_DEFAULTS := {"dark": Color(0.114, 0.125, 0.141), "fin": Color(0.2, 0.225, 0.245), "claw": Color(0.6, 0.58, 0.555), "cable": Color(0.06, 0.062, 0.068)}
const ARM_REST := Vector3(-0.2, -0.75, 0.55)
## [hero v2] The concept's arms and claws are chunkier than the modelled ones: scale the whole arm
## from the shoulder socket, and the claws again on top (fingers spread a little wider).
const ARM_SCALE := 0.85
const CLAW_SCALE := 1.15
const BLINK_CLOSE := 0.07
const BLINK_HOLD := 0.04
const BLINK_OPEN := 0.11
const BLINK_LEN := BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN
var _flash: float = 0.0
var _lean := Vector2.ZERO
var _dip: float = 0.0
## [v6feel] Carrying bales: both arms up under the load (set by Patch).
var carrying: bool = false
var _carry: float = 0.0
## Holding up the survey hologram (right claw raised, palm up).
var holding: bool = false
var _hold: float = 0.0
var _pet_t: float = 0.0  # [fauna2] petting an animal: claw reach + head tilt
var _pet_dur: float = 0.0
## Bloom Core glow: multiplies the eyes, thruster ring and cyan trim (low battery < 1, charged > 1).
var core_glow: float = 1.0
const EYE_MIN_ENERGY: float = 2.8  # [v2feel]
## [art2] Light strips, ear rings and the hover unit glow in saturated colour: an emission much
## above 1 clips to white on screen (the concept's cyan is (64,226,240) to (155,235,246)).
const GLOW_E: float = 1.35
const GLOW_SOFT_E: float = 1.25
const RING_E: float = 1.45


## Set before adding to the tree to build a given design (previews) instead of the worn one.
var preview_variant: String = ""


static func glow_of(id: String) -> Color:
	return (VARIANTS.get(id, VARIANTS["aurora"]) as Dictionary)["glow"]


func _ready() -> void:
	variant = preview_variant if preview_variant != "" else str(GameState.flags.get("patch_skin", "aurora"))
	if not VARIANTS.has(variant):
		variant = "aurora"
	_build()
	if DevHooks.has("beam-demo"):
		beam_at(Vector3(0.45, 0.25, -0.9))


## Switch colorway (cosmetic unlocks).
func set_variant(v: String) -> void:
	if not VARIANTS.has(v):
		return
	variant = v
	for c: Node in get_children():
		c.free()
	_claws.clear()
	_idle_t = 0.0
	_prop_amt = 0.0
	_build()


const MODEL_PATH := "res://art/models/aurora/aurora.glb"
## Design add-ons (same build script): shoulder pads, sprout, cat ears, toolbox, case, gear, ...
const DESIGNS_PATH := "res://art/models/aurora/designs.glb"
const HERO_PAINT := preload("res://art/shaders/hero_paint.gdshader")
## [hero v2] Baked per-pixel AO / edge / cavity atlas for aurora.glb (tools/hero/bake_masks.py).
const MASK_PATH := "res://art/models/aurora/aurora_masks.png"
var _acc_mats: Dictionary = {}
## Visual layer bit the hero's meshes also sit on, so his own key light only lights him.
const HERO_LAYER := 2
## Meshes and pivots baked from art/models/aurora (built by build_aurora.py in Blender).
static var _parts: Dictionary = {}
var _mats: Dictionary = {}
var _paint_mats: Array[ShaderMaterial] = []


static func _load_parts() -> void:
	if not _parts.is_empty():
		return
	for path: String in [MODEL_PATH, DESIGNS_PATH]:
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var inst: Node = scene.instantiate()
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			_parts[str(mi.name)] = {"mesh": mi.mesh, "pos": mi.position}
		inst.free()
	# Pixel's add-on is one mesh (crown fins + heart lenses over the ear hubs). The v2 head moved the
	# crown and the ear hubs by different amounts, so the hearts become their own part (ACC_FIT).
	if _parts.has("acc_pixel") and not _parts.has("acc_pixel_hearts"):
		var whole: Mesh = _parts["acc_pixel"]["mesh"]
		_parts["acc_pixel_hearts"] = {"mesh": _surfaces_of(whole, ["glow"], true), "pos": _parts["acc_pixel"]["pos"]}
		_parts["acc_pixel"] = {"mesh": _surfaces_of(whole, ["glow"], false), "pos": _parts["acc_pixel"]["pos"]}


## A copy of `mesh` with only the surfaces whose material name is (keep) / is not in `names`.
static func _surfaces_of(mesh: Mesh, names: Array, keep: bool) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i: int in mesh.get_surface_count():
		var src: Material = mesh.surface_get_material(i)
		if names.has(src.resource_name if src else "") != keep:
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		out.surface_set_material(out.get_surface_count() - 1, src)
	return out


static func _pivot(part: String) -> Vector3:
	_load_parts()
	return _parts[part]["pos"]


## [hero v2] The part filling a character-builder slot (variant override, else Aurora's).
static func _slot(v: Dictionary, slot: String) -> String:
	var p: String = str(v.get(slot, SLOT_DEFAULTS[slot]))
	return p if _parts.is_empty() or _parts.has(p) else str(SLOT_DEFAULTS[slot])


static func _col(v: Dictionary, key: String) -> Color:
	return v.get(key, COLOR_DEFAULTS[key])


func _paint(c: Color, seed_: float, coverage: float = 0.88, metal: float = 0.0, rough: float = 0.42, coat: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(c, coverage, 0.25, seed_, 0.5)
	m.set_shader_parameter("clearcoat", coat)
	m.shader = HERO_PAINT
	m.set_shader_parameter("paint_roughness", rough)
	m.set_shader_parameter("paint_metallic", metal)
	m.set_shader_parameter("dust", 0.45)
	m.set_shader_parameter("metallic_bare", 0.25)  # [hero v2] chips read matte brown, not mirror-dark
	m.set_shader_parameter("rim_strength", 0.11)  # [hero v2] the concept's warm/cyan edge glints
	m.set_shader_parameter("grime", 0.6)
	m.set_shader_parameter("fade", 0.15 if c.s < 0.5 else 0.0)
	_paint_mats.append(m)
	return m


## Instance a baked part (mesh vertices are relative to its pivot) with per-surface materials.
## `remap` swaps material keys for this instance (the ears' housings use the Locker's "side").
func _part(parent: Node3D, part: String, pos: Vector3 = Vector3.ZERO, remap: Dictionary = {}) -> MeshInstance3D:
	_load_parts()
	var mi := MeshInstance3D.new()
	mi.mesh = _parts[part]["mesh"]
	mi.position = pos
	mi.layers = 1 | HERO_LAYER
	for i: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		var key: String = src.resource_name if src else ""
		key = str(remap.get(key, key))
		if _mats.has(key):
			var mat: Material = _mats[key]
			# Add-ons (designs.glb, "acc_*") have their own UVs: no hero mask atlas on them.
			if part.begins_with("acc_") and mat is ShaderMaterial and float((mat as ShaderMaterial).get_shader_parameter("use_mask")) > 0.5:
				if not _acc_mats.has(key):
					var c: ShaderMaterial = (mat as ShaderMaterial).duplicate()
					c.set_shader_parameter("use_mask", 0.0)
					_acc_mats[key] = c
				mat = _acc_mats[key]
			mi.set_surface_override_material(i, mat)
	parent.add_child(mi)
	return mi


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	m.layers = 1 | HERO_LAYER
	parent.add_child(m)
	return m


## Point the paint rim light away from the scene's sun (once the scene is up).
func _find_sun() -> void:
	if not is_inside_tree():
		return
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = n
		if sun.visible:
			var to_sun: Vector3 = sun.global_transform.basis.z.normalized()
			for m: ShaderMaterial in _paint_mats:
				m.set_shader_parameter("sun_dir", to_sun)
			return


func _build() -> void:
	var v: Dictionary = LumiStyle.variant_for(self, VARIANTS[variant])  # [style] Character Builder look (systems/lumi_style.gd)
	var glow: Color = v["glow"]
	var accent_c: Color = v["accent"]
	_paint_mats.clear()
	_ring_mat = Mats.lamp(glow, RING_E)
	var screen := Mats.glass(Color(0.02, 0.03, 0.04, 1.0), 0.08)
	var cover: float = float(v.get("coverage", 0.9))
	var lamp_c: Color = v.get("lamp", accent_c)
	_mats = {
		"paint": _paint((v["paint"] as Color), 3.0, cover, float(v.get("metal", 0.0)), 0.3 - float(v.get("metal", 0.0)) * 0.15, 0.75),
		"trim": _paint((v["trim"] as Color).darkened(0.45), 7.0, cover, 0.35, 0.4),
		"accent": _paint(accent_c, 11.0, cover - 0.04),
		# [hero v2] Dark joint metal (sampled #1D2024): metallic with sharp highlights.
		"dark": _paint(_col(v, "dark"), 5.0, 0.8, 0.85, 0.26),
		# [art2] The side modules (ear ring housings) have their own slot: the Locker's "side" colour
		# (LumiStyle._recolor); the trim colour until it is set. Same dark metal finish as "dark".
		"side": _paint((v["trim"] as Color).darkened(0.45), 9.0, 0.8, 0.85, 0.26),
		"steel": Mats.metal("steel"),
		"glow": Mats.lamp(glow, GLOW_E),
		"lamp_accent": Mats.lamp(lamp_c, 1.3),  # [hero v2] saturated amber, not blown out
		# [hero] Rebuild: side-module ring lenses and the hatch frame (thinner, dimmer than the eyes),
		# the raised chest plate, the fin and the claws.
		"glow_soft": Mats.lamp(glow, GLOW_SOFT_E),
		"plate": _paint((v["paint"] as Color).lightened(0.05), 17.0, cover, 0.2, 0.3, 0.5),
		"fin": _paint(_col(v, "fin"), 19.0, 0.97, 0.9, 0.28),  # concept: dark teal-grey stalk
		"claw": _paint(_col(v, "claw"), 23.0, 0.85, 0.3, 0.34),  # [hero v2] light worn-grey finger armour (concept)
		"paddle": _paint(v.get("paddle", accent_c), 29.0, 0.97, 0.1, 0.3, 0.6),
		"paddle_edge": Mats.lamp((v.get("paddle", accent_c) as Color).lightened(0.12), 1.1),
		"latch": Mats.lamp(accent_c, 1.4),  # [hero v2] saturated orange (sampled #F16B03)
		"cable": _paint(_col(v, "cable"), 31.0, 1.0, 0.0, 0.55),
		# Design add-on materials (designs.glb).
		"rust": _paint(Color(0.42, 0.36, 0.3), 13.0, 0.45, 0.5, 0.5),
		"leaf": _leaf_mat(),
		"moss": _moss_mat(),
		"wing": _wing_mat(glow),
		"screen": screen,
		"thruster": _ring_mat,
		"thruster_core": Mats.lamp(glow.lightened(0.25), 1.5),
	}
	# [hero] The chest plate stays readable: lighter edge wear than the shell.
	(_mats["plate"] as ShaderMaterial).set_shader_parameter("edge_wear", 0.25)
	# [hero v2] The concept's paddle is clean, saturated amber: a few chips, no grime wash.
	(_mats["paddle"] as ShaderMaterial).set_shader_parameter("specks", 0.35)
	(_mats["paddle"] as ShaderMaterial).set_shader_parameter("dust", 0.0)
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = preload("res://art/shaders/bot_face.gdshader")
	_face_mat.set_shader_parameter("eye_color", glow)
	for m: ShaderMaterial in _paint_mats:
		m.set_shader_parameter("grime", float(v.get("grime", 0.6)))
		m.set_shader_parameter("moss", float(v.get("moss", 0.0)))
	(_mats["paddle"] as ShaderMaterial).set_shader_parameter("grime", 0.2)
	(_mats["claw"] as ShaderMaterial).set_shader_parameter("specks", 0.5)
	_acc_mats.clear()
	if ResourceLoader.exists(MASK_PATH):
		var mask: Texture2D = load(MASK_PATH)
		for m: ShaderMaterial in _paint_mats:
			m.set_shader_parameter("mask_tex", mask)
			m.set_shader_parameter("use_mask", 1.0)
	if float(v.get("stripes", 0.0)) > 0.0:
		(_mats["accent"] as ShaderMaterial).set_shader_parameter("stripes", float(v["stripes"]))
	# [art2] Measured on the turnaround (tools/hero/overlay.py): ring diameter 0.55 of the visor's height,
	# a thin stroke, the two centres 0.36 of the head's width apart.
	_face_mat.set_shader_parameter("half_width", 0.3)
	_face_mat.set_shader_parameter("half_height", 0.178)
	_face_mat.set_shader_parameter("eye_radius", 0.55)
	_face_mat.set_shader_parameter("ring_inner", 0.7)
	_face_mat.set_shader_parameter("eye_spacing", 0.8)
	_face_mat.set_shader_parameter("eye_shape", maxi(EYE_SHAPES.find(str(v.get("eyes", "crescent"))), 0))
	_mats["face"] = _face_mat
	_root = Node3D.new()
	add_child(_root)
	_float = Node3D.new()
	_root.add_child(_float)

	# --- Body: rounded torso (white upper shell, dark lower section, orange side panels, chest
	# screen with orange lights, cyan collar strip) on a dark hover bowl with a thruster ring.
	_part(_float, "body")
	_part(_float, "thruster")
	var hover_light := OmniLight3D.new()
	hover_light.light_color = glow
	hover_light.light_energy = 0.7  # [hero] tight glow: light the ground, not the whole bot
	hover_light.omni_range = 0.9
	hover_light.position = Vector3(0, 0.06, 0)
	hover_light.shadow_enabled = false
	hover_light.light_cull_mask = 0xFFFFF & ~(1 << 18)  # [fauna2] not on animals (FaunaRig.LAYER): no cyan cats
	_float.add_child(hover_light)
	# His own soft key light (only lights his meshes) so he reads against the busy world.
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.84)
	key.light_energy = 0.8
	key.omni_range = 2.2
	key.omni_attenuation = 1.2
	key.light_cull_mask = HERO_LAYER
	key.shadow_enabled = false
	key.light_specular = 0.4
	key.position = Vector3(0.4, 1.5, 0.9)  # above/behind: the side the game camera usually sees
	_float.add_child(key)
	var fill := key.duplicate() as OmniLight3D
	fill.light_energy = 0.45
	fill.position = Vector3(-0.5, 1.1, -1.0)  # soft front fill for the face and chest
	_float.add_child(fill)
	var icon: String = str(v.get("icon", "recycle"))
	_icon = null
	_icon_mesh = null
	if icon == "leaf" or icon == "cross":
		# designs.glb icons (modelled for the old chest screen): placed on the new plate.
		_icon_mesh = _part(_float, "acc_icon_" + icon, ANCHORS["chest_plate"] + Vector3(0, 0, -0.004))
	elif icon == "recycle" and _parts.has("icon_recycle"):
		_icon_mesh = _part(_float, "icon_recycle", _pivot("icon_recycle"))
	var icon_l := Label3D.new()
	icon_l.visible = _icon_mesh == null
	icon_l.text = "♻"
	icon_l.font_size = 64
	icon_l.pixel_size = 0.0013
	icon_l.modulate = glow.lightened(0.3)
	icon_l.outline_size = 0
	icon_l.shaded = false
	icon_l.position = ANCHORS["chest_plate"] + Vector3(0, 0, -0.004)
	_float.add_child(icon_l)
	_icon = icon_l
	_icon_color = icon_l.modulate
	_fill_bar = _mi(_float, ProcMesh.box(Vector3(0.14, 0.006, 0.004)), Mats.lamp(glow, 2.5), Vector3(0, 0.365, -0.2165))
	_fill_bar.scale.x = 0.01
	# Back hatch where bales come out (hinged at its top edge).
	_hatch = Node3D.new()
	_hatch.position = _pivot("hatch")
	_float.add_child(_hatch)
	_part(_hatch, "hatch")

	# --- Arms with three-finger claws.
	_arm_l = _build_arm(-1.0)
	_arm_r = _build_arm(1.0)

	# --- Head: big rounded shell, glossy convex visor, ear discs with glow rings, crown vent,
	# curved antenna with an orange fin.
	_head = Node3D.new()
	_head.position = _pivot("head")
	_float.add_child(_head)
	_part(_head, _slot(v, "head"))
	_part(_head, _slot(v, "ears"), _pivot(_slot(v, "ears")) - _pivot("head"), SIDE_REMAP)
	_part(_head, _slot(v, "visor"), _pivot(_slot(v, "visor")) - _pivot("head"))
	_make_anchors()
	call_deferred("_find_sun")
	_build_accessories(v)
	# Tractor beam from the right claw: a cone of scrolling energy rings (tractor_beam shader)
	# that stretches to whatever is being picked up. The twin lasers and arcs are PickupFx.
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.12
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 6
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://art/shaders/tractor_beam.gdshader")
	_beam_mat.set_shader_parameter("beam_color", glow)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)
	LumiStyle.after_build(self)  # [style] eyes, side modules, hover ring, extra add-ons, laser colour


# --- Design add-ons -----------------------------------------------------------------------------

var _icon_mesh: MeshInstance3D
var _sprout: Node3D
## Props that come and go: Nova's holo screen (right claw), Patch's carry case (left claw).
var _holo: MeshInstance3D
var _holo_mat: ShaderMaterial
var _case: Node3D
var _gear: Node3D
var _bfly: Node3D
var _bfly_wings: Array[Node3D] = []
var _idle_t: float = 0.0
var _prop_amt: float = 0.0
var _happy_bias: float = 0.0


func _build_accessories(v: Dictionary) -> void:
	_sprout = null
	_holo = null
	_case = null
	_gear = null
	_bfly = null
	_bfly_wings.clear()
	_happy_bias = clampf((float(v.get("happy", 0.5)) - 0.5) * 2.0, 0.0, 1.0)
	var head_p: Vector3 = _pivot("head")
	for a: String in v.get("acc", []):
		match a:
			"antenna", "acc_catears", "acc_pixel":
				var hp: MeshInstance3D = _part(_head, a, _pivot(a) - head_p + acc_fit(a))
				hp.scale = (ACC_FIT.get(a, {}) as Dictionary).get("scale", Vector3.ONE)
				if a == "acc_pixel":
					var hearts: MeshInstance3D = _part(_head, "acc_pixel_hearts", _pivot(a) - head_p + acc_fit("acc_pixel_hearts"))
					hearts.scale = ACC_FIT["acc_pixel_hearts"]["scale"]
			"acc_sprout":
				_sprout = Node3D.new()
				_sprout.position = _pivot(a) - head_p + acc_fit(a)
				_head.add_child(_sprout)
				_part(_sprout, a)
			"acc_pad_r", "acc_pad_l":
				_part(_arm_r if a.ends_with("_r") else _arm_l, a)
				# Heavier stance: the padded shoulders sit a touch wider.
				(_arm_r if a.ends_with("_r") else _arm_l).position.x += 0.012 * (1.0 if a.ends_with("_r") else -1.0)
			"acc_toolbox":
				_part(_float, a, _pivot(a) + acc_fit(a))
			"gear":
				# A spare gear gripped in the left claw by its rim, standing on edge.
				var wrist: Node3D = _arm_l.get_meta("wrist")
				_gear = Node3D.new()
				_gear.position = Vector3(0.0, -0.055, -0.115)
				_gear.rotation = Vector3(0.25, PI * 0.5, 0.0)
				wrist.add_child(_gear)
				_part(_gear, "acc_gear")
			"case":
				_case = Node3D.new()
				_case.top_level = true
				_case.visible = false
				add_child(_case)
				_part(_case, "acc_case")
			"holo":
				_holo = MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.42, 0.3)
				_holo.mesh = q
				_holo_mat = ShaderMaterial.new()
				_holo_mat.shader = preload("res://art/shaders/holo_panel.gdshader")
				_holo_mat.set_shader_parameter("col", v["glow"])
				_holo.material_override = _holo_mat
				_holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_holo.top_level = true
				_holo.visible = false
				_holo.layers = 1 | HERO_LAYER
				add_child(_holo)
			"butterfly":
				_bfly = Node3D.new()
				_bfly.top_level = true
				_bfly.scale = Vector3.ONE * 2.2
				add_child(_bfly)
				_part(_bfly, "acc_bfly_body")
				for side: float in [-1.0, 1.0]:
					var hinge := Node3D.new()
					hinge.scale = Vector3(side, 1.0, 1.0)
					hinge.set_meta("side", side)
					_bfly.add_child(hinge)
					var w: MeshInstance3D = _part(hinge, "acc_wing")
					w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					w.scale.z = -1.0  # the big forewing toward the head (-Z)
					_bfly_wings.append(hinge)


## Where a designs.glb add-on moves to sit on the v2 head / torso (ACC_FIT; zero for the rest).
static func acc_fit(part: String) -> Vector3:
	return (ACC_FIT.get(part, {}) as Dictionary).get("pos", Vector3.ZERO)


func _leaf_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.6, 0.18)
	m.roughness = 0.38
	m.metallic_specular = 0.6
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.55, 0.1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.25
	return m


func _moss_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.36, 0.11)
	m.roughness = 0.95
	m.vertex_color_use_as_albedo = false
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.6
	return m


func _wing_mat(glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.62, 0.25, 0.92).lerp(glow, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.35).lerp(glow, 0.4)
	m.emission_energy_multiplier = 0.6
	m.roughness = 0.5
	return m


## Idle-only props and the companion: Nova's holo screen, Patch's case, Pixel's butterfly.
func _update_accessories(delta: float) -> void:
	var busy: bool = _scoop_amt > 0.05 or _beam_target != null or holding or sleeping
	_idle_t = 0.0 if busy else _idle_t + delta
	if _sprout:
		_sprout.rotation = Vector3(sin(_t * 1.3) * 0.05 - _lean.x * 0.6, 0.0, sin(_t * 1.7 + 0.5) * 0.07 - _lean.y * 0.6)
	# Props show after a few idle seconds and stay a while (then a short break: "occasionally").
	var want: bool = _idle_t > 2.5 and fmod(_idle_t - 2.5, 26.0) < 18.0
	_prop_amt = move_toward(_prop_amt, 1.0 if want else 0.0, delta * (2.5 if want else 6.0))
	if _holo:
		_holo.visible = _prop_amt > 0.01
		if _holo.visible:
			var e: float = _prop_amt * _prop_amt * (3.0 - 2.0 * _prop_amt)
			var b: Basis = _float.global_transform.basis
			var fwd: Vector3 = -b.z
			var side: Vector3 = b.x
			var mu: Vector3 = global_basis.y.normalized()  # [v6feel] his own up (world +Y only on a flat world)
			var p: Vector3 = claw_point() + fwd * 0.14 + side * 0.12 + mu * (0.16 + sin(_t * 1.4) * 0.008)
			var face_dir: Vector3 = (fwd * 0.55 + side * 0.85).normalized()
			_holo.global_transform = Transform3D(Basis.looking_at(-face_dir, mu).scaled(Vector3(e, e, 1.0)), p)
			_holo_mat.set_shader_parameter("amt", e)
			_holo_mat.set_shader_parameter("t_now", _t)
	if _case:
		_case.visible = _prop_amt > 0.5 and _beam_target == null
		if _case.visible:
			var wrist: Node3D = _arm_l.get_meta("wrist")
			_case.global_transform = Transform3D(_float.global_transform.basis.rotated(Vector3.UP, 0.0), wrist.to_global(Vector3(0, -0.01, -0.07)))
	if _case or _holo:
		# Carry pose: left arm (case) or right arm (holo) a little out and forward.
		var e2: float = _prop_amt * _prop_amt * (3.0 - 2.0 * _prop_amt)
		if _case:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.12, e2)
			_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.18, e2)
		if _holo:
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.75 + sin(_t * 1.1) * 0.03, e2)
			_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.2, e2)
	if _bfly:
		var c: Vector3 = _head.global_position
		var a: float = _t * 0.55
		var r: float = 0.58 + sin(_t * 0.37) * 0.08
		# Orbits above and beside the head, never in front of the visor.
		var off := Vector3(cos(a) * r, 0.42 + sin(_t * 1.9) * 0.06 + sin(_t * 0.6) * 0.05, sin(a) * r * 0.75 + 0.12)
		var basis_m: Basis = global_transform.basis
		var pos: Vector3 = c + basis_m * off
		var vel := Vector3(-sin(a), 0.0, cos(a) * 0.75)
		var heading: Vector3 = (basis_m * vel).normalized()
		_bfly.global_transform = Transform3D(Basis.looking_at(heading, global_basis.y.normalized()).rotated(heading, sin(_t * 2.0) * 0.2).scaled(Vector3.ONE * 2.2), pos)  # [v6feel] his own up
		var flap: float = sin(_t * 17.0) * 0.85 + 0.35
		for h: Node3D in _bfly_wings:
			h.rotation.z = flap * float(h.get_meta("side", 1.0))


func _build_arm(side: float) -> Node3D:
	var sfx: String = "_r" if side > 0.0 else "_l"
	var sp: Vector3 = _pivot("arm_shoulder" + sfx)
	var ep: Vector3 = _pivot("arm_elbow" + sfx)
	var wp: Vector3 = _pivot("arm_wrist" + sfx)
	var shoulder := Node3D.new()
	shoulder.position = sp
	shoulder.scale = Vector3.ONE * ARM_SCALE
	_float.add_child(shoulder)
	_part(shoulder, "arm_shoulder" + sfx)
	var elbow := Node3D.new()
	elbow.position = ep - sp
	shoulder.add_child(elbow)
	_part(elbow, "arm_elbow" + sfx)
	var wrist := Node3D.new()
	wrist.position = wp - ep
	elbow.add_child(wrist)
	_part(wrist, "arm_wrist" + sfx)
	for k: int in 3:
		var a: float = TAU * k / 3.0 + PI * 0.5
		var f := Node3D.new()
		f.position = Vector3(cos(a) * 0.036, sin(a) * 0.036, -0.058)
		f.scale = Vector3.ONE * CLAW_SCALE
		wrist.add_child(f)
		# The finger meshes point down -Z with their outer face on +Y; turn them to face outward.
		var orient := Node3D.new()
		orient.rotation.z = a - PI * 0.5
		f.add_child(orient)
		_part(orient, _slot(VARIANTS.get(variant, VARIANTS["aurora"]), "finger"))
		var tip := Node3D.new()
		tip.position = Vector3(0, 0.0, -0.05)
		tip.rotation.x = -0.35  # [hero v2] with the tip's own angled blocks the claw reads as an open C (concept)
		orient.add_child(tip)
		_part(tip, _slot(VARIANTS.get(variant, VARIANTS["aurora"]), "finger_tip"))
		f.set_meta("dir", Vector2(cos(a), sin(a)))
		_claws.append(f)
	shoulder.set_meta("elbow", elbow)
	shoulder.set_meta("wrist", wrist)
	return shoulder


# [art2] Motion with weight. The body rides springs instead of easing straight to its pose: it dips
# and settles on a landing or a stop, leans with a little overshoot, banks into turns; the head
# leads a turn and lags a lurch; the arms trail and swing through when he stops; standing still he
# glances about now and then. All of it is in the model: Patch calls the same hooks as before.
var _lean_v := Vector2.ZERO
var _sq: float = 0.0      # body height on its spring (m, down is negative)
var _sq_v: float = 0.0
var _nod: float = 0.0     # head pitch following the body late
var _nod_v: float = 0.0
var _arm_lag: float = 0.0
var _arm_v: float = 0.0
var _turn: float = 0.0    # smoothed turn rate (rad/s, left is positive)
var _fwd_prev := Vector3.ZERO
var _speed_ratio: float = 0.0
var _glance: float = 0.0
var _glance_t: float = 3.0


func _weight(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_sq_v += (-190.0 * _sq - 11.0 * _sq_v) * dt
	_sq = clampf(_sq + _sq_v * dt, -0.07, 0.05)
	_nod_v += ((-_lean.x * 0.8 - _sq * 2.5 - _nod) * 70.0 - _nod_v * 8.0) * dt
	_nod = clampf(_nod + _nod_v * dt, -0.3, 0.3)
	_arm_v += ((minf(_speed_ratio, 1.6) * 0.32 - _arm_lag) * 55.0 - _arm_v * 5.5) * dt
	_arm_lag = clampf(_arm_lag + _arm_v * dt, -0.5, 0.8)
	if is_inside_tree():
		var f: Vector3 = -global_basis.z
		var up: Vector3 = global_basis.y.normalized()
		var rate: float = 0.0
		if _fwd_prev != Vector3.ZERO and delta > 0.0001:
			rate = clampf(_fwd_prev.signed_angle_to(f, up) / delta, -6.0, 6.0)
		_fwd_prev = f
		_turn = lerpf(_turn, rate, clampf(delta * 7.0, 0.0, 1.0))
	# Idle: a look to one side every few seconds (never while he looks at something).
	_glance_t -= delta
	if _glance_t <= 0.0:
		var idle: bool = _speed_ratio < 0.05 and absf(_head_yaw_target) < 0.01 and not sleeping
		_glance = 0.0 if _glance != 0.0 or not idle else (0.34 if randf() < 0.5 else -0.34)
		_glance_t = randf_range(0.9, 1.6) if _glance != 0.0 else randf_range(3.5, 7.0)
	if _speed_ratio > 0.05 or sleeping:
		_glance = 0.0


func _process(delta: float) -> void:
	_t += delta
	_weight(delta)
	# Hover bob (smaller under way) on the body spring, and ring pulse.
	_float.position.y = 0.04 + sin(_t * 2.4) * lerpf(0.022, 0.01, clampf(_speed_ratio, 0.0, 1.0)) + _sq - _dip
	_dip = maxf(0.0, _dip - delta * 0.4)
	_ring_mat.emission_energy_multiplier = (RING_E + sin(_t * 9.0) * 0.12) * core_glow + _flash * 2.0
	if _mats.has("glow"):
		(_mats["glow"] as StandardMaterial3D).emission_energy_multiplier = GLOW_E * core_glow
	if _mats.has("glow_soft"):
		(_mats["glow_soft"] as StandardMaterial3D).emission_energy_multiplier = GLOW_SOFT_E * core_glow
	_flash = maxf(0.0, _flash - delta * 2.0)
	# Arms: reach forward and pinch while scooping; the right claw projects a small tractor beam.
	_scoop_amt = move_toward(_scoop_amt, 1.0 if _scoop_t > 0.0 else 0.0, delta * 5.0)
	_scoop_t = maxf(0.0, _scoop_t - delta)
	var s: float = _t * 8.0
	# [hero v2] Idle: arms out and a little up and forward, elbows bent (the portrait's reaching pose).
	# [art2] The arms trail behind under way and swing through when he stops (_arm_lag).
	_arm_r.rotation.x = lerpf(ARM_REST.x + 0.08 * sin(_t * 1.3) + _arm_lag, -0.9 + sin(s) * 0.15, _scoop_amt)
	_arm_l.rotation.x = lerpf(ARM_REST.x + 0.08 * sin(_t * 1.3 + 1.0) + _arm_lag * 0.9, -0.5 + sin(s + 1.5) * 0.12, _scoop_amt * 0.7)
	_arm_r.rotation.z = lerpf(ARM_REST.z + 0.04 * sin(_t * 0.9), -0.25, _scoop_amt)
	_arm_l.rotation.z = lerpf(-ARM_REST.z - 0.04 * sin(_t * 0.9 + 0.7), 0.0, _scoop_amt * 0.7)
	var elbow_r: Node3D = _arm_r.get_meta("elbow")
	var elbow_l: Node3D = _arm_l.get_meta("elbow")
	elbow_r.rotation.x = lerpf(ARM_REST.y, 0.0, _scoop_amt)
	elbow_l.rotation.x = lerpf(ARM_REST.y, 0.0, _scoop_amt * 0.7)
	_carry = move_toward(_carry, 1.0 if carrying else 0.0, delta * 5.0)
	if _carry > 0.0:
		# [v6feel] Arms up and a little out, steadying the stack; the scooping arm still does its job.
		var ce: float = _carry * _carry * (3.0 - 2.0 * _carry)
		var up_r: float = ce * (1.0 - _scoop_amt)
		var up_l: float = ce * (1.0 - _scoop_amt * 0.7)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -2.7 + sin(_t * 2.4) * 0.03, up_r)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -2.7 + sin(_t * 2.4 + 0.6) * 0.03, up_l)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.22, up_r)
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.22, up_l)
		elbow_r.rotation.x = lerpf(elbow_r.rotation.x, 0.0, up_r)  # straight arms under the load
		elbow_l.rotation.x = lerpf(elbow_l.rotation.x, 0.0, up_l)
	_hold = move_toward(_hold, 1.0 if holding else 0.0, delta * 3.0)
	if _hold > 0.0:
		var e: float = _hold * _hold * (3.0 - 2.0 * _hold)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.25 + sin(_t * 1.6) * 0.03, e)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.35, e)
		var elbow_h: Node3D = _arm_r.get_meta("elbow")
		elbow_h.rotation.x = lerpf(elbow_h.rotation.x, 0.9, e)
	var pet_e: float = _pet_env(delta)
	if pet_e > 0.0:
		# [fauna2] Petting: the right claw reaches down and forward and strokes; the left arm lifts a
		# little in sympathy, the elbow softens.
		var stroke: float = sin(_t * 5.5)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.78 + stroke * 0.12, pet_e)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, -0.12 + stroke * 0.05, pet_e)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.25, pet_e * 0.6)
		var elbow_p: Node3D = _arm_r.get_meta("elbow")
		elbow_p.rotation.x = lerpf(elbow_p.rotation.x, 0.35 + stroke * 0.08, pet_e)
	for f: Node3D in _claws:
		var dir: Vector2 = f.get_meta("dir")
		var open: float = (0.5 + 0.5 * sin(s * 1.5)) if _scoop_amt > 0.1 else lerpf(0.2, 0.9, _hold)
		open = lerpf(open, 0.55 + 0.15 * sin(_t * 5.5), pet_e)
		f.rotation = Vector3(-dir.y, dir.x, 0) * open * 0.6
	_update_beam(delta)
	_update_hopper(delta)
	_update_accessories(delta)
	# Press: the body compresses slightly while baling.
	var sq_s: float = clampf(_sq * 1.5, -0.09, 0.07)  # [art2] squash on the way down, stretch on the rebound
	_root.scale = Vector3(1.0 + _press * 0.04 - sq_s * 0.5, 1.0 - _press * 0.06 + sq_s, 1.0 + _press * 0.04 - sq_s * 0.5)
	if _shudder > 0.0:
		_shudder -= delta
		_root.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.01
	else:
		_root.position = Vector3.ZERO
	_float.rotation = Vector3(_lean.x, 0, _lean.y + clampf(_turn * 0.035 * minf(0.4 + _speed_ratio, 1.4), -0.16, 0.16))  # [art2] banks into a turn
	# Head look and face.
	_head_yaw = lerp_angle(_head_yaw, _head_yaw_target + _glance, delta * 4.0)
	_head.rotation.y = _head_yaw + clampf(_turn * 0.085, -0.32, 0.32)  # [art2] the head leads the turn
	_head.rotation.x = _nod
	_head.rotation.z = sin(_t * 0.7) * 0.03 + (0.08 if _happy > 0.8 else 0.0) + pet_e * 0.2  # [fauna2] head tilt while petting
	_look = _look.lerp(_look_target, minf(1.0, delta * 6.0))  # [v7play] clamped: long frames overshot
	_happy = lerpf(_happy, _happy_target, minf(1.0, delta * 4.0))  # [v7play]
	_iris_now = _happy
	# [hero] Crisp blinks (owner: "closing slowly"): ~70 ms close, a short hold, ~110 ms open, and
	# now and then a double blink. Sleep closes/opens eased over about a second / half a second.
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_blink_double = randf() < 0.22
		_blink_timer = randf_range(2.2, 5.5)
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t > BLINK_LEN:
			if _blink_double:
				_blink_double = false
				_blink_t = -0.12  # a short gap, then the second blink
			else:
				_blink_t = -1.0
	elif _blink_t > -0.5:
		_blink_t = minf(_blink_t + delta, 0.0)  # counting the double-blink gap up to 0
	_blink = blink_curve(_blink_t)
	_sleep_amt = move_toward(_sleep_amt, 1.0 if sleeping else 0.0, delta * (0.9 if sleeping else 2.2))
	if not _sleep_seen:
		_sleep_seen = true
		_sleep_amt = 1.0 if sleeping else 0.0  # a model that starts asleep starts with its eyes shut
	var sleep_e: float = _sleep_amt * _sleep_amt * (3.0 - 2.0 * _sleep_amt)
	_face_mat.set_shader_parameter("look", _look)
	# [v10ui] The eyes rest on ONE shape: the C ring (0) or the ^ ^ arcs (1), never a blend. A mood of
	# 0.9 (the title) used to rest at 0.75 here, which drew the arc over the disc: "eyes messed up".
	# The shader shuts the C before the arc opens, so the ~0.17 s move between them is clean too.
	_face_happy = move_toward(_face_happy, 1.0 if _happy_target >= HAPPY_ARCS_FROM else 0.0, delta * 6.0)
	_face_mat.set_shader_parameter("happy", maxf(_face_happy, _happy_bias * (1.0 - minf(_eye_flash * 2.0, 1.0))))
	# [v2feel] Asleep: cleanly shut (0.9 left a squashed sliver); [hero] eased shut / open (sleep_e).
	_face_mat.set_shader_parameter("blink", maxf(_blink, sleep_e))
	_eye_flash = maxf(0.0, _eye_flash - delta * 6.0)
	# [v2feel] Awake eyes stay fully lit on a low core (the intro's wake read as half-closed at 0.9);
	# the core and ring still show the battery.
	_face_mat.set_shader_parameter("energy", lerpf(maxf(4.0 * core_glow, EYE_MIN_ENERGY) + _flash * 2.0 + _eye_flash * 3.0, 1.2 * minf(core_glow, 1.0), sleep_e))


func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	# [v6feel] The run lean stops growing past twice walking speed: a boost leaned him 30 degrees.
	var target := Vector2(clampf(-local_accel.y * 0.015, -0.18, 0.18) - minf(speed_ratio, 2.0) * 0.08, clampf(local_accel.x * 0.012, -0.15, 0.15))
	# [art2] On a spring: a little overshoot when he sets off, a rock back when he stops.
	var dt: float = minf(delta, 0.05)
	_lean_v += ((target - _lean) * 110.0 - _lean_v * 12.0) * dt
	_lean += _lean_v * dt
	_lean = Vector2(clampf(_lean.x, -0.32, 0.32), clampf(_lean.y, -0.25, 0.25))
	_speed_ratio = speed_ratio
	_ring_mat.emission_energy_multiplier += speed * 0.1


## Lock the claw's tractor beam onto a world position (null releases it). `big` widens it.
func beam_at(world_pos: Variant, big: bool = false) -> void:
	_beam_target = world_pos
	_beam_big = big
	if world_pos != null:
		_scoop_t = maxf(_scoop_t, 0.2)


func claw_point() -> Vector3:
	var wrist: Node3D = _arm_r.get_meta("wrist")
	return wrist.to_global(Vector3(0, 0, -0.13))


## Left claw tip (the second laser emitter).
func claw_point_l() -> Vector3:
	var wrist: Node3D = _arm_l.get_meta("wrist")
	return wrist.to_global(Vector3(0, 0, -0.13))


## World position of the chest hopper screen (where pickups stream in).
func chest_world() -> Vector3:
	return _float.to_global(Vector3(0, 0.435, -0.219))


## [hero] Anchor nodes for add-ons: "head_top" (on the head, turns with it), "chest_plate",
## "back" (float space) and "hand_r" / "hand_l" (claw tips, on the wrists).
func _make_anchors() -> void:
	_anchors.clear()
	_make_beacon()
	for n: String in ANCHORS:
		var a := Node3D.new()
		a.name = n
		a.position = ANCHORS[n]
		var parent: Node3D = _float
		if n == "head_top":
			parent = _head
		elif n == "hand_r":
			parent = _arm_r.get_meta("wrist")
		elif n == "hand_l":
			parent = _arm_l.get_meta("wrist")
		parent.add_child(a)
		_anchors[n] = a


func _make_beacon() -> void:
	var b := Node3D.new()
	b.name = "beacon"
	b.position = BEACON_LOCAL
	_head.add_child(b)
	_anchors["beacon"] = b
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.25, 0.02, 0.02)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.08, 0.05)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = ProcMesh.sphere(0.014, 10, 5)
	_beacon.material_override = _beacon_mat
	_beacon.layers = 1 | HERO_LAYER
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(_beacon)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = Color(1.0, 0.1, 0.05)
	_beacon_light.omni_range = 2.5
	_beacon_light.shadow_enabled = false
	b.add_child(_beacon_light)
	set_beacon(_beacon_amt)


## Detector beacon brightness (0 idle glow .. 1 flash); PartDetector drives it.
func set_beacon(amount: float) -> void:
	_beacon_amt = amount
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 0.15 + amount * 6.0
		_beacon_light.light_energy = amount * 1.6


func beacon_world() -> Vector3:
	return _head.to_global(BEACON_LOCAL)


func get_anchor(anchor: String) -> Node3D:
	return _anchors.get(anchor) as Node3D


## Eye shape by name (EYE_SHAPES) for the face shader.
func set_eye_shape(shape: String) -> void:
	var i: int = EYE_SHAPES.find(shape)
	if i >= 0 and _face_mat:
		_face_mat.set_shader_parameter("eye_shape", i)


## Quick brightening of the visor eyes (target lock).
func eye_flash(amount: float = 0.4) -> void:
	_eye_flash = maxf(_eye_flash, amount)


## Soft pop on the chest panel: the fill bar and icon flare as a pickup lands in the hopper.
func hopper_pulse(amount: float = 0.6) -> void:
	_hopper_pulse = clampf(maxf(_hopper_pulse, amount), 0.0, 1.0)


func _update_hopper(delta: float) -> void:
	if _fill_bar == null:
		return
	_hopper_pulse = maxf(0.0, _hopper_pulse - delta * 5.0)
	var p: float = _hopper_pulse
	_fill_bar.scale.y = 1.0 + p * 2.5
	_fill_bar.scale.z = 1.0 + p * 1.5
	(_fill_bar.material_override as StandardMaterial3D).emission_energy_multiplier = 2.5 + p * 7.0
	if _icon:
		_icon.modulate = _icon_color.lerp(Color(1.6, 1.8, 1.9), p * 0.8)
		_icon.scale = Vector3.ONE * (1.0 + p * 0.18)
	if _icon_mesh:
		_icon_mesh.scale = Vector3.ONE * (1.0 + p * 0.18)


func _update_beam(delta: float) -> void:
	_beam_amt = move_toward(_beam_amt, 1.0 if _beam_target != null else 0.0, delta * 8.0)
	var on: bool = _beam_amt > 0.02 and _beam_target != null
	_beam.visible = false  # no cone: the pickup is a few thin lasers (player/pickup_fx.gd)
	if not on:
		return
	var a: Vector3 = claw_point()
	var b: Vector3 = _beam_target
	var d: Vector3 = b - a
	var len_: float = maxf(d.length(), 0.05)
	var y: Vector3 = d / len_
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	# Cylinder top (narrow) at the claw, wide end at the target.
	var w: float = 1.35 if _beam_big else 1.0
	var basis_ := Basis(x * w, -y * len_, z * w)
	_beam.global_transform = Transform3D(basis_, a + d * 0.5)
	_beam_mat.set_shader_parameter("beam_length", len_)
	_beam_mat.set_shader_parameter("intensity", _beam_amt * (1.25 if _beam_big else 1.0))
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = 0.16
		Vfx.burst("sparkle", b, VARIANTS[variant]["glow"], 0.1)
	# Aim the right arm toward the target.
	var local: Vector3 = _float.global_transform.affine_inverse() * b
	var reach: float = clampf(-atan2(local.y - 0.4, -local.z) , -1.4, 0.3)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, reach - 0.3, _beam_amt)


## World position just above the raised right claw (where the hologram sits).
func hand_point() -> Vector3:
	return claw_point() + global_basis.y.normalized() * 0.05  # [v6feel]


func set_scooping(active: bool) -> void:
	if active:
		_scoop_t = 0.15


func set_fill(ratio: float, band: Array) -> void:
	if _fill_bar == null:
		return
	_fill_bar.scale.x = clampf(ratio, 0.01, 1.1)
	var m: StandardMaterial3D = _fill_bar.material_override
	hopper_pulse(0.3)
	if ratio > float(band[1]) + 0.0001:
		m.emission = Color(1.0, 0.3, 0.25)
	elif ratio >= float(band[0]):
		m.emission = Color(1.0, 0.8, 0.3)
	else:
		m.emission = VARIANTS[variant]["glow"]


func shudder(duration: float = 0.3) -> void:
	_shudder = duration


func squash(amount: float) -> void:
	_sq_v -= clampf(absf(amount), 0.0, 0.6) * 1.1  # [art2] a push down into the body spring (was a linear dip)


func look_toward(world_pos: Variant) -> void:
	if world_pos == null:
		_head_yaw_target = 0.0
		_look_target = Vector2.ZERO
		return
	var local: Vector3 = global_transform.affine_inverse() * (world_pos as Vector3)
	var yaw: float = atan2(-local.x, -local.z)
	_head_yaw_target = clampf(yaw * 0.5, -0.45, 0.45)
	# Eyes stay facing forward; only the head turns (a hint of eye shift for life).
	_look_target = Vector2(clampf(-yaw * 0.3, -0.2, 0.2), 0.0)


## [fauna2] Pet an animal for `duration` seconds: claw reach and stroke, head tilt.
func pet_reach(duration: float = 2.4) -> void:
	_pet_dur = maxf(duration, 0.5)
	_pet_t = _pet_dur


func is_petting() -> bool:
	return _pet_t > 0.0


## 0..1 envelope of the petting pose (eases in over 0.3 s, out over the last 0.45 s).
func _pet_env(delta: float) -> float:
	if _pet_t <= 0.0:
		return 0.0
	_pet_t = maxf(0.0, _pet_t - delta)
	var into: float = clampf((_pet_dur - _pet_t) / 0.3, 0.0, 1.0)
	var out: float = clampf(_pet_t / 0.45, 0.0, 1.0)
	var e: float = minf(into, out)
	return e * e * (3.0 - 2.0 * e)


## Eyelid closure (0 open .. 1 shut) at blink phase time t: fast ease-in close, hold, ease-out open.
static func blink_curve(t: float) -> float:
	if t < 0.0 or t > BLINK_LEN:
		return 0.0
	if t < BLINK_CLOSE:
		var a: float = t / BLINK_CLOSE
		return a * a
	if t < BLINK_CLOSE + BLINK_HOLD:
		return 1.0
	var b: float = 1.0 - (t - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN
	return b * b * (3.0 - 2.0 * b)


func set_happy(amount: float) -> void:
	_happy_target = clampf(amount, 0.0, 1.0)


func flash() -> void:
	_flash = 1.0


func set_rust(_amount: float) -> void:
	pass  # Wear comes from the worn-paint shader; colorways are swapped with set_variant().


func press(t: float) -> void:
	_press = clampf(t, 0.0, 1.0)


func open_hatch(t: float) -> void:
	if _hatch:
		_hatch.rotation.x = -clampf(t, 0.0, 1.0) * 1.3
