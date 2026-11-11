class_name PatchModel
extends Node3D
## The player's robot, Lumi (LM-1): the ark's seed-keeper bot, fallen back to Verdance.
## Matches the owner's Aurora portrait and turnaround (rebuilt Nov 2026, art/models/aurora/build_aurora.py):
## a wide rounded-rectangle head (about 56% of his height) with a thick off-white shell, one curved
## glossy black visor across nearly the whole front with two oversized cyan crescent eyes, round side
## modules with a thin cyan ring lens and a mechanical hub, a short swept-back fin with an amber edge,
## a compact torso tucked under the head with a raised recycling plate and orange latches, short
## chunky arms with curved claws (the right one projects the pickup lasers), and a compact rounded
## underside with one recessed hover ring. Worn, dusty paint. Colorways are unlockable designs ("aurora" is
## the default look). Faces -Z. Base (hover ring) near y=0.

# Unlockable designs (owner's concept sheet art/concept/lumi_concept.png; gameplay side in
# systems/designs.gd + data/designs.json).
# paint / trim / accent: hero_paint colours; glow: eyes, hover ring, chest light and pickup lasers;
# lamp: the small accent lights (cheeks, vent LEDs); latch: the glowing chest latches (else accent);
# ear_glow: the side modules' ring lenses (else glow); plate: the raised chest plate (else paint);
# arm: the arm armour (else paint); icon: chest icon (recycle / leaf / cross) with icon_col (else
# glow) and icon_lit (emission, 0 = painted on); chips: wear chip colour; dark / fin / claw / cable:
# COLOR_DEFAULTS overrides; coverage / grime / specks / dust: wear; moss and stripes: hero_paint
# extras; eyes: EYE_SHAPES (resting look) and happy: 1.0 rests on smiling arcs; smile: the small
# visor smile; acc: every add-on piece, each one a builder option in data/style_parts.json (pieces
# from designs.glb by mesh name, "antenna" from aurora.glb, and the animated ones: gear, bottle,
# holo, case, butterfly).
# l10n:begin
const VARIANTS: Dictionary = {
	"aurora": {"name": "Aurora", "paint": Color(0.78, 0.74, 0.725), "trim": Color(0.412, 0.435, 0.471), "glow": Color(0.25, 0.886, 0.94), "accent": Color(0.945, 0.42, 0.012), "lamp": Color(0.973, 0.686, 0.035), "paddle": Color(0.953, 0.753, 0.251), "icon": "recycle", "grime": 0.75, "eyes": "crescent", "acc": ["antenna"]},  # eyes: owner (Nov 9): the concept sheet's crescent eyes, never solid discs
	# Bolt: hazard yellow with black chips and dark panels; rests on smiling arcs with a small smile.
	"bolt": {"name": "Bolt", "paint": Color(0.95, 0.72, 0.06), "trim": Color(0.2, 0.19, 0.17), "glow": Color(1.0, 0.66, 0.14), "accent": Color(0.95, 0.7, 0.06), "lamp": Color(1.0, 0.62, 0.1), "paddle": Color(0.97, 0.7, 0.12), "plate": Color(0.96, 0.75, 0.1), "icon": "recycle", "icon_col": Color(0.05, 0.045, 0.04), "icon_lit": 0.0, "chips": Color(0.05, 0.045, 0.04), "claw": Color(0.84, 0.63, 0.1), "coverage": 0.8, "grime": 0.6, "specks": 1.0, "dust": 0.12, "stripes": 1.0, "eyes": "crescent", "happy": 1.0, "smile": 1.0, "acc": ["antenna", "acc_panels", "acc_ear_nut", "acc_pad_r", "acc_pad_l", "gear"]},
	# Sprout: olive green with moss on the crown and a seedling instead of the fin.
	"sprout": {"name": "Sprout", "paint": Color(0.42, 0.48, 0.16), "trim": Color(0.25, 0.29, 0.16), "glow": Color(0.42, 1.0, 0.15), "accent": Color(0.36, 0.42, 0.17), "lamp": Color(1.0, 0.6, 0.16), "latch": Color(0.42, 1.0, 0.15), "plate": Color(0.5, 0.52, 0.22), "icon": "leaf", "claw": Color(0.42, 0.47, 0.3), "grime": 0.6, "dust": 0.2, "moss": 0.6, "eyes": "crescent", "acc": ["acc_sprout", "acc_moss", "acc_ear_leaf", "bottle"]},
	# Pixel: red over a cream lower head, wing fins, heart lenses; rests on smiling arcs.
	"pixel": {"name": "Pixel", "paint": Color(0.74, 0.11, 0.1), "trim": Color(0.5, 0.1, 0.1), "glow": Color(1.0, 0.2, 0.42), "accent": Color(0.93, 0.9, 0.86), "lamp": Color(1.0, 0.2, 0.42), "latch": Color(1.0, 0.2, 0.42), "plate": Color(0.8, 0.14, 0.11), "icon": "recycle", "icon_col": Color(0.95, 0.94, 0.92), "icon_lit": 0.6, "claw": Color(0.62, 0.12, 0.11), "chips": Color(0.72, 0.66, 0.62), "dust": 0.15, "eyes": "crescent", "happy": 1.0, "smile": 1.0, "acc": ["acc_pixel", "acc_twotone", "acc_ear_heart", "butterfly"]},
	# Nova: dark gunmetal lit violet from its seams, cat-ear fins, a holo data panel.
	"nova": {"name": "Nova", "paint": Color(0.34, 0.33, 0.4), "trim": Color(0.15, 0.14, 0.2), "glow": Color(0.58, 0.22, 1.0), "accent": Color(0.26, 0.24, 0.31), "lamp": Color(0.6, 0.25, 1.0), "latch": Color(0.58, 0.22, 1.0), "plate": Color(0.3, 0.29, 0.34), "icon": "recycle", "claw": Color(0.3, 0.29, 0.36), "metal": 0.15, "dust": 0.15, "grime": 0.45, "eyes": "crescent", "acc": ["acc_catears", "acc_seams", "holo"]},
	# Patch: white with orange panels and arms, a medic cross, satchel, carry case and side radio.
	"patch": {"name": "Patch", "paint": Color(0.86, 0.84, 0.8), "trim": Color(0.35, 0.36, 0.38), "glow": Color(1.0, 0.68, 0.2), "accent": Color(0.94, 0.45, 0.07), "lamp": Color(1.0, 0.6, 0.15), "paddle": Color(0.98, 0.72, 0.22), "plate": Color(0.94, 0.44, 0.07), "arm": Color(0.93, 0.5, 0.09), "icon": "cross", "icon_col": Color(0.96, 0.95, 0.92), "icon_lit": 0.4, "ear_glow": Color(0.45, 0.95, 0.4), "eyes": "crescent", "acc": ["antenna", "acc_radio", "acc_toolbox", "case"]},
}
# l10n:end

var variant: String = "aurora"

# Interface used by Patch, the camera, the detector and baling.
var chest_point := Vector3(0, 0.4, -0.25)
var back_hatch_point := Vector3(0, 0.38, 0.23)
var vent_points: Array[Vector3] = [Vector3(-0.12, 0.93, 0.34), Vector3(0.12, 0.93, 0.34)]  # head's back vent band
var stack_point := Vector3(0, 1.3, 0.3)
var lens_point := Vector3(0, 0.86, -0.36)
## [hero] Attachment anchors for head pieces, chest icons, held items and back gear (character
## builder). Positions in the model's float space (head_top in the head's space); see get_anchor().
const ANCHORS := {"head_top": Vector3(0, 0.66, 0.0), "chest_plate": Vector3(0, 0.407, -0.236), "hand_r": Vector3(0, 0, -0.13), "hand_l": Vector3(0, 0, -0.13), "back": Vector3(0, 0.42, 0.225)}
## Eye shapes for bot_face.gdshader's eye_shape (VARIANTS may set "eyes"; set_eye_shape() at runtime).
const EYE_SHAPES := ["crescent", "round", "happy", "bar", "heart"]
var _anchors: Dictionary = {}
## [hero] Detector beacon: a small red lamp on the rear of the fin mount (head space), parented to
## the head so it follows hover bob, lean, head turn/tilt and every pose (owner: "the blinking red
## dot sometimes comes off the player's head" when it lived on Patch at a fixed height).
const BEACON_LOCAL := Vector3(0, 0.657, 0.21)  # on the fin mount, behind the stalk (build_aurora.py prints it)
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
var _happy_face: float = 0.0
## [hero v2] Idle arm pose: x = shoulder pitch (up/forward), z = outward (right arm; mirrored on
## the left), y = elbow bend.
## [hero v2] Character-builder slots: each swappable characteristic is its own part (or part pair)
## in aurora.glb. A variant / builder save overrides any slot by naming another part with the same
## pivot conventions; eyes ("eyes" -> EYE_SHAPES), colours (the colour keys below) and toppers
## ("acc", head_top / beacon anchors) are already independent of the shapes.
const SLOT_DEFAULTS := {"head": "head", "visor": "visor", "ears": "ears", "finger": "finger", "finger_tip": "finger_tip"}
## Per-part colours a variant may override (defaults are Aurora's, sampled from the concept).
const COLOR_DEFAULTS := {"dark": Color(0.114, 0.125, 0.141), "fin": Color(0.2, 0.225, 0.245), "claw": Color(0.6, 0.58, 0.555), "cable": Color(0.06, 0.062, 0.068)}
const ARM_REST := Vector3(0.12, 0.4, 0.5)
## [hero v2] The concept's arms and claws are chunkier than the modelled ones: scale the whole arm
## from the shoulder socket, and the claws again on top (fingers spread a little wider).
const ARM_SCALE := 1.2
const CLAW_SCALE := 1.3
const BLINK_CLOSE := 0.07
const BLINK_HOLD := 0.04
const BLINK_OPEN := 0.11
const BLINK_LEN := BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN
var _flash: float = 0.0
var _lean := Vector2.ZERO
var _dip: float = 0.0
## Holding up the survey hologram (right claw raised, palm up).
var holding: bool = false
var _hold: float = 0.0
var _pet_t: float = 0.0  # [fauna2] petting an animal: claw reach + head tilt
var _pet_dur: float = 0.0
## Bloom Core glow: multiplies the eyes, thruster ring and cyan trim (low battery < 1, charged > 1).
var core_glow: float = 1.0
const EYE_MIN_ENERGY: float = 2.8  # [v2feel]


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
func _part(parent: Node3D, part: String, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	_load_parts()
	var mi := MeshInstance3D.new()
	mi.mesh = _parts[part]["mesh"]
	mi.position = pos
	mi.layers = 1 | HERO_LAYER
	for i: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		var key: String = src.resource_name if src else ""
		if _mats.has(key):
			var mat: Material = _mats["arm"] if key == "paint" and part.begins_with("arm_") else _mats[key]
			# Add-ons (designs.glb, "acc_*") have their own UVs: no hero mask atlas on them.
			if part.begins_with("acc_") and mat is ShaderMaterial and (mat as ShaderMaterial).shader == HERO_PAINT and float((mat as ShaderMaterial).get_shader_parameter("use_mask")) > 0.5:
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
	_ring_mat = Mats.lamp(glow, 4.5)
	var screen := Mats.glass(Color(0.02, 0.03, 0.04, 1.0), 0.08)
	var cover: float = float(v.get("coverage", 0.9))
	var lamp_c: Color = v.get("lamp", accent_c)
	_mats = {
		"paint": _paint((v["paint"] as Color), 3.0, cover, float(v.get("metal", 0.0)), 0.3 - float(v.get("metal", 0.0)) * 0.15, 0.75),
		"trim": _paint((v["trim"] as Color).darkened(0.45), 7.0, cover, 0.35, 0.4),
		"accent": _paint(accent_c, 11.0, cover - 0.04),
		# [hero v2] Dark joint metal (sampled #1D2024): metallic with sharp highlights.
		"dark": _paint(_col(v, "dark"), 5.0, 0.8, 0.85, 0.26),
		"steel": Mats.metal("steel"),
		"glow": Mats.lamp(glow, 3.6),
		"lamp_accent": Mats.lamp(lamp_c, 1.3),  # [hero v2] saturated amber, not blown out
		# [hero] Rebuild: side-module ring lenses and the hatch frame (thinner, dimmer than the eyes),
		# the raised chest plate, the fin and the claws.
		"glow_soft": Mats.lamp(v.get("ear_glow", glow), 2.4),
		"plate": _paint(v.get("plate", (v["paint"] as Color).lightened(0.05)), 17.0, cover, 0.2, 0.3, 0.5),
		"fin": _paint(_col(v, "fin"), 19.0, 0.97, 0.9, 0.28),  # concept: dark teal-grey stalk
		"claw": _paint(_col(v, "claw"), 23.0, 0.85, 0.3, 0.34),  # [hero v2] light worn-grey finger armour (concept)
		"paddle": _paint(v.get("paddle", accent_c), 29.0, 0.97, 0.1, 0.3, 0.6),
		"paddle_edge": Mats.lamp((v.get("paddle", accent_c) as Color).lightened(0.12), 1.1),
		"latch": Mats.lamp(v.get("latch", accent_c), 1.4),  # [hero v2] saturated orange (sampled #F16B03)
		"cable": _paint(_col(v, "cable"), 31.0, 1.0, 0.0, 0.55),
		"arm": _paint(v.get("arm", v["paint"]), 43.0, cover, float(v.get("metal", 0.0)), 0.32, 0.6),
		# Design add-on materials (designs.glb).
		"rust": _paint(Color(0.5, 0.26, 0.11), 13.0, 0.9, 0.25, 0.75),
		"decal": _decal_mat(),
		"sign": _sign_mat(accent_c),
		"glow_dim": Mats.lamp(glow, 0.9),  # lit inner faces (cat ears): coloured, under the bloom threshold
		"case": _paint(Color(0.8, 0.4, 0.1), 41.0, 0.74, 0.15, 0.5),
		"bottle": _bottle_mat(),
		"bottle_cap": _cap_mat(),
		"leaf": _leaf_mat(Color(0.3, 0.6, 0.16)),
		"leaf_vein": _leaf_mat(Color(0.2, 0.42, 0.1)),
		"moss": _moss_mat(),
		"holo": _holo_mat_of(HOLO_COLOR, 1.25, 1.0),  # just under the bloom threshold: crisp lines, no white blur
		"holo_fill": _holo_mat_of(HOLO_COLOR, 0.6, 0.22),
		"wing": _wing_mat(glow),
		"screen": screen,
		"thruster": _ring_mat,
		"thruster_core": Mats.lamp(glow.lightened(0.3), 2.2),
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
		if v.has("chips"):
			m.set_shader_parameter("chip_color", v["chips"])
		if v.has("dust"):
			m.set_shader_parameter("dust", float(v["dust"]))
	if v.has("specks"):
		for k: String in ["paint", "plate", "arm", "accent"]:
			(_mats[k] as ShaderMaterial).set_shader_parameter("specks", float(v["specks"]))
	(_mats["case"] as ShaderMaterial).set_shader_parameter("grime", 0.75)
	(_mats["case"] as ShaderMaterial).set_shader_parameter("rust_amount", 0.6)
	(_mats["rust"] as ShaderMaterial).set_shader_parameter("rust_amount", 0.9)
	(_mats["rust"] as ShaderMaterial).set_shader_parameter("chip_color", Color(0.22, 0.12, 0.06))
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
	_face_mat.set_shader_parameter("half_width", 0.35)
	_face_mat.set_shader_parameter("half_height", 0.235)
	_face_mat.set_shader_parameter("eye_radius", 0.46)  # [hero v2] turnaround: eye radius ~0.45 visor half-heights
	_face_mat.set_shader_parameter("eye_spacing", 0.74)
	_face_mat.set_shader_parameter("eye_shape", maxi(EYE_SHAPES.find(str(v.get("eyes", "crescent"))), 0))
	_face_mat.set_shader_parameter("smile", float(v.get("smile", 0.0)))
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
	if (icon == "leaf" or icon == "cross") and _parts.has("acc_icon_" + icon):
		_icon_mesh = _part(_float, "acc_icon_" + icon, _pivot("acc_icon_" + icon))  # designs.glb, on the plate
	elif icon == "recycle" and _parts.has("icon_recycle"):
		_icon_mesh = _part(_float, "icon_recycle", _pivot("icon_recycle"))
	if _icon_mesh and v.has("icon_col"):
		# Printed (icon_lit 0) or lit in its own colour, instead of the design glow.
		var ic: Color = v["icon_col"]
		var ilit: float = float(v.get("icon_lit", 3.0))
		var im: StandardMaterial3D = Mats.lamp(ic, ilit) if ilit > 0.0 else StandardMaterial3D.new()
		if ilit <= 0.0:
			im.albedo_color = ic
			im.roughness = 0.6
		_icon_mesh.material_override = im
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
	_fill_bar = _mi(_float, ProcMesh.box(Vector3(0.14, 0.008, 0.005)), Mats.lamp(glow, 2.5), Vector3(0, 0.338, -0.238))
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
	_part(_head, _slot(v, "ears"), _pivot(_slot(v, "ears")) - _pivot("head"))
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
## Held items ride the left claw but keep their own facing (set every frame, see _update_held):
## the gear and the bottle stay; Nova's holo panel and Patch's carry case come and go when idle.
var _holo: Node3D
var _case: Node3D
var _gear: Node3D
var _bottle: Node3D
var _bfly: Node3D
var _bfly_wings: Array[Node3D] = []
var _idle_t: float = 0.0
var _prop_amt: float = 0.0
var _happy_bias: float = 0.0
## The holo panel is light-blue projector light on every design (sheet), not the design's glow.
const HOLO_COLOR := Color(0.25, 0.66, 1.0)
const BFLY_SCALE := 2.2
## The fin's mount on the crown (head space, build_aurora.py FIN_BASE), its sweep to the side and size.
const FIN_PIVOT := Vector3(0, 0.631, 0.16)
const FIN_YAW := 0.35
const FIN_SCALE := 1.25
## Shoulder pads hang a little outward-down from the shoulder (radians).
const PAD_DROOP := 0.22
## Fin-less heads carry the detector beacon on the crown itself (head space).
const BEACON_CROWN := Vector3(0, 0.648, 0.196)


func _build_accessories(v: Dictionary) -> void:
	_sprout = null
	_holo = null
	_case = null
	_gear = null
	_bottle = null
	_bfly = null
	_bfly_wings.clear()
	_happy_bias = clampf((float(v.get("happy", 0.5)) - 0.5) * 2.0, 0.0, 1.0)
	var head_p: Vector3 = _pivot("head")
	var acc: Array = v.get("acc", [])
	if not ("antenna" in acc) and _anchors.has("beacon"):
		# No fin mount to sit on: a small dark lamp base on the crown instead.
		var bn: Node3D = _anchors["beacon"]
		bn.position = BEACON_CROWN
		var base := CylinderMesh.new()
		base.top_radius = 0.011
		base.bottom_radius = 0.016
		base.height = 0.024
		base.radial_segments = 12
		_mi(bn, base, _mats["dark"], Vector3(0, -0.016, 0))
	for a: String in acc:
		match a:
			"acc_sprout":
				_sprout = Node3D.new()
				_sprout.position = _pivot(a) - head_p
				_head.add_child(_sprout)
				_part(_sprout, a)
			"acc_pad_r", "acc_pad_l":
				# Heavier stance: the padded shoulders sit a touch wider. The pad is bolted to the body
				# over the shoulder (the sheet's armour box) and the arm swings out from under it.
				var side_s: float = 1.0 if a.ends_with("_r") else -1.0
				var arm_n: Node3D = _arm_r if side_s > 0.0 else _arm_l
				arm_n.position.x += 0.012 * side_s
				var mount := Node3D.new()
				mount.position = arm_n.position
				mount.scale = Vector3.ONE * ARM_SCALE
				mount.rotation.z = -PAD_DROOP * side_s
				_float.add_child(mount)
				_part(mount, a)
			"acc_toolbox":
				_part(_float, a, _pivot(a))
			"gear":
				_gear = _held_item("acc_gear", true)
			"bottle":
				_bottle = _held_item("acc_bottle", true)
			"case":
				_case = _held_item("acc_case", false)
			"holo":
				_holo = _held_item("acc_holo", false)
				for mi: MeshInstance3D in _holo.find_children("*", "MeshInstance3D", true, false):
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"butterfly":
				_build_butterfly()
			_:
				# Head pieces (fin, ears, wings, panels, lens emblems, radio): fixed to the head.
				if a == "antenna":
					# The sheet's fin is a long blade swept back and to his right, so it reads from the
					# front: the modelled fin is turned and enlarged about its mount.
					var fin_mount := Node3D.new()
					fin_mount.position = FIN_PIVOT
					fin_mount.rotation.y = FIN_YAW
					fin_mount.scale = Vector3.ONE * FIN_SCALE
					_head.add_child(fin_mount)
					_part(fin_mount, a, _pivot(a) - head_p - FIN_PIVOT)
				elif _parts.has(a):
					_part(_head, a, _pivot(a) - head_p)


## A held item: its own top-level node (positioned from the left wrist each frame).
func _held_item(part: String, shown: bool) -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	n.visible = shown
	add_child(n)
	if _parts.has(part):
		_part(n, part)
	return n


func _build_butterfly() -> void:
	_bfly = Node3D.new()
	_bfly.top_level = true
	_bfly.scale = Vector3.ONE * BFLY_SCALE
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


func _holo_mat_of(c: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS  # depth of field then treats the panel as near, not as the far ground
	return m


func _bottle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.9, 0.92, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.metallic_specular = 0.8
	m.rim_enabled = true
	m.rim = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Painted-on signs (the satchel's cross, the case's recycling mark): clean cream, so they read.
func _decal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.88, 0.82)
	m.roughness = 0.55
	return m


## The satchel's cross: fresh paint in the design's accent colour.
func _sign_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.25
	return m


func _cap_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.62, 0.6)
	m.roughness = 0.35
	return m


func _leaf_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
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
	m.albedo_color = Color(0.2, 0.31, 0.09)
	m.roughness = 0.95
	m.vertex_color_use_as_albedo = false
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.8
	return m


func _wing_mat(glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.8, 0.55, 0.94).lerp(glow, 0.1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.45).lerp(glow, 0.25)
	m.emission_energy_multiplier = 0.45
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
	_update_held()
	if _case or _holo:
		# Carry pose: the left arm a little out and forward (case), or raised to point (holo).
		var e2: float = _prop_amt * _prop_amt * (3.0 - 2.0 * _prop_amt)
		if _case:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.12, e2)
			_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.18, e2)
		if _holo:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.75 + sin(_t * 1.1) * 0.03, e2)
			_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.2, e2)
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
		_bfly.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP).rotated(heading, sin(_t * 2.0) * 0.2).scaled(Vector3.ONE * BFLY_SCALE), pos)
		var flap: float = sin(_t * 17.0) * 0.85 + 0.35
		for h: Node3D in _bfly_wings:
			h.rotation.z = flap * float(h.get_meta("side", 1.0))


## Held items follow the left claw but keep facing the way the body faces, like the sheet: the gear
## stands face-on, the bottle and the case hang upright, the holo panel floats beside the fingertip.
func _update_held() -> void:
	var wrist: Node3D = _arm_l.get_meta("wrist")
	var body: Basis = _float.global_transform.basis.orthonormalized()
	var free_hand: bool = _beam_target == null
	if _gear:
		_gear.visible = free_hand
		# The mesh's grip point is on its rim, the wheel above it: turned so the wheel sits outside the claw.
		_gear.global_transform = Transform3D(body.rotated(body.y, -0.4) * Basis(Vector3.BACK, PI * 0.5), wrist.to_global(Vector3(0, 0.0, -0.15)))
	if _bottle:
		_bottle.visible = free_hand
		_bottle.global_transform = Transform3D(body.rotated(body.z, 0.3), wrist.to_global(Vector3(0, -0.01, -0.19)))
	if _case:
		_case.visible = _prop_amt > 0.5 and free_hand
		_case.global_transform = Transform3D(body.rotated(body.y, -0.3), wrist.to_global(Vector3(0, -0.01, -0.1)))
	if _holo:
		# Placed even while hidden, so it opens from the fingertip, never from the world origin.
		_holo.visible = _prop_amt > 0.01
		var e: float = maxf(_prop_amt * _prop_amt * (3.0 - 2.0 * _prop_amt), 0.01)
		var p: Vector3 = claw_point_l() - body.z * 0.06 - body.x * 0.27 + body.y * (0.17 + sin(_t * 1.4) * 0.008)
		_holo.global_transform = Transform3D(body.rotated(body.y, -0.35).scaled(Vector3(e * 1.15, e * 1.15, 1.0)), p)


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


func _process(delta: float) -> void:
	_t += delta
	# Hover bob and ring pulse.
	_float.position.y = 0.04 + sin(_t * 2.4) * 0.02 - _dip
	_dip = maxf(0.0, _dip - delta * 0.4)
	_ring_mat.emission_energy_multiplier = (3.5 + sin(_t * 9.0) * 0.4) * core_glow + _flash * 4.0
	if _mats.has("glow"):
		(_mats["glow"] as StandardMaterial3D).emission_energy_multiplier = 3.2 * core_glow
	if _mats.has("glow_soft"):
		(_mats["glow_soft"] as StandardMaterial3D).emission_energy_multiplier = 2.8 * core_glow
	_flash = maxf(0.0, _flash - delta * 2.0)
	# Arms: reach forward and pinch while scooping; the right claw projects a small tractor beam.
	_scoop_amt = move_toward(_scoop_amt, 1.0 if _scoop_t > 0.0 else 0.0, delta * 5.0)
	_scoop_t = maxf(0.0, _scoop_t - delta)
	var s: float = _t * 8.0
	# [hero v2] Idle: arms out and a little up and forward, elbows bent (the portrait's reaching pose).
	_arm_r.rotation.x = lerpf(ARM_REST.x + 0.08 * sin(_t * 1.3), -0.9 + sin(s) * 0.15, _scoop_amt)
	_arm_l.rotation.x = lerpf(ARM_REST.x + 0.08 * sin(_t * 1.3 + 1.0), -0.5 + sin(s + 1.5) * 0.12, _scoop_amt * 0.7)
	_arm_r.rotation.z = lerpf(ARM_REST.z + 0.04 * sin(_t * 0.9), -0.25, _scoop_amt)
	_arm_l.rotation.z = lerpf(-ARM_REST.z - 0.04 * sin(_t * 0.9 + 0.7), 0.0, _scoop_amt * 0.7)
	(_arm_r.get_meta("elbow") as Node3D).rotation.x = lerpf(ARM_REST.y, 0.0, _scoop_amt)
	(_arm_l.get_meta("elbow") as Node3D).rotation.x = lerpf(ARM_REST.y, 0.0, _scoop_amt * 0.7)
	_hold = move_toward(_hold, 1.0 if holding else 0.0, delta * 3.0)
	if _hold > 0.0:
		var e: float = _hold * _hold * (3.0 - 2.0 * _hold)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.25 + sin(_t * 1.6) * 0.03, e)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.35, e)
		var elbow_h: Node3D = _arm_r.get_meta("elbow")
		elbow_h.rotation.x = lerpf(ARM_REST.y, 0.9, e)
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
	_root.scale = Vector3(1.0 + _press * 0.04, 1.0 - _press * 0.06, 1.0 + _press * 0.04)
	if _shudder > 0.0:
		_shudder -= delta
		_root.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.01
	else:
		_root.position = Vector3.ZERO
	_float.rotation = Vector3(_lean.x, 0, _lean.y)
	# Head look and face.
	_head_yaw = lerp_angle(_head_yaw, _head_yaw_target, clampf(delta * 4.0, 0.0, 1.0))  # clamped: a weight past 2 runs away on long frames
	_head.rotation.y = _head_yaw
	_head.rotation.z = sin(_t * 0.7) * 0.03 + (0.08 if _happy > 0.8 else 0.0) + pet_e * 0.2  # [fauna2] head tilt while petting
	_look = _look.lerp(_look_target, clampf(delta * 6.0, 0.0, 1.0))
	_happy = lerpf(_happy, _happy_target, clampf(delta * 4.0, 0.0, 1.0))
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
	var sleep_e: float = _sleep_amt * _sleep_amt * (3.0 - 2.0 * _sleep_amt)
	# Happy face: snaps between C eyes and ^ ^ in ~0.17 s (the shader squashes the C shut before the
	# arc opens), never parked half way.
	var want_happy: bool = _happy_target > 0.8 or (_happy_bias > 0.5 and _eye_flash < 0.2)
	_happy_face = move_toward(_happy_face, 1.0 if want_happy else 0.0, delta * 6.0)
	_face_mat.set_shader_parameter("look", _look)
	_face_mat.set_shader_parameter("happy", _happy_face)
	# [v2feel] Asleep: cleanly shut (0.9 left a squashed sliver); eased by the hero's sleep curve.
	_face_mat.set_shader_parameter("blink", maxf(_blink, sleep_e))
	_eye_flash = maxf(0.0, _eye_flash - delta * 6.0)
	# [v2feel] Awake eyes stay fully lit on a low core; the core and ring still show the battery.
	_face_mat.set_shader_parameter("energy", lerpf(maxf(4.0 * core_glow, EYE_MIN_ENERGY) + _flash * 2.0 + _eye_flash * 3.0, 1.2 * minf(core_glow, 1.0), sleep_e))


func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	var target := Vector2(clampf(-local_accel.y * 0.015, -0.18, 0.18) - speed_ratio * 0.08, clampf(local_accel.x * 0.012, -0.15, 0.15))
	_lean = _lean.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	_ring_mat.emission_energy_multiplier += speed * 0.3


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
	return _float.to_global(Vector3(0, 0.407, -0.24))


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
	var b: Node3D = _anchors.get("beacon") as Node3D
	return b.global_position if b else _head.to_global(BEACON_LOCAL)


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
	return claw_point() + Vector3(0, 0.05, 0)


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
	_dip = clampf(_dip + absf(amount) * 0.04, 0.0, 0.05)


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
