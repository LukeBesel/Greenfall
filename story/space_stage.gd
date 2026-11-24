class_name SpaceStage
extends SubViewportContainer
## A self-contained little film set for the story cinematics that happen off Verdance: its own
## 3D world in a SubViewport (so the game's sky, fog and lights stay untouched), shown full screen
## under the cinematic letterbox. Holds three sets, one visible at a time:
##   "space"  : starfield, Verdance below, the ark Cradle, meteors, the cargo pod.
##   "vault"  : the Cradle's seed vault, a small round room of glowing seed drawers (Lumi + tray).
##   "garden" : the ark's garden deck under the glass dome (a warm memory).
## Free it to drop everything; nothing outside it is touched.

const PLANET_R := 420.0
## [v9intro] The glow shell's radius over the planet's (the shader needs the same number).
const ATMO_K := 1.07
const VAULT_AT := Vector3(0, 0, 4000)
const GARDEN_AT := Vector3(0, 0, -4000)

var vp: SubViewport
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var planet: MeshInstance3D
var atmo: MeshInstance3D
var ark: CradleShip
var pod: Node3D
var lumi: PatchModel
var tray: Node3D
var vault_pod: Node3D
var alarm_light: SpotLight3D
## Camera shake amount (decays).
var shake: float = 0.0

var _sets: Dictionary = {}
var _set: String = ""
var _from := Transform3D()
var _to := Transform3D()
var _dur: float = 1.0
var _ct: float = 0.0
var _fov_from: float = 50.0
var _fov_to: float = 50.0
var _fx: Array[Dictionary] = []
var _planet_mat: ShaderMaterial
var _alarm: float = 0.0
var _t: float = 0.0
var _vault_lights: Array[OmniLight3D] = []
var _leaf_mat: StandardMaterial3D
## [v9intro] Warm bounce light off the planet (fills the ark's belly, which was black on black).
var fill: DirectionalLight3D
## [v9intro] Drifting specks around the camera in the space set: they give speed and depth to a
## shot (stars are too far to move). motes_on shows them; they hang still in space (a moving
## camera streams past them) unless motes_vel gives them a speed of their own, in m/s.
var motes_vel := Vector3.ZERO
var motes_on: bool = false
var _motes: MultiMeshInstance3D
var _mote_pos: PackedVector3Array = PackedVector3Array()
const MOTES: int = 110
const MOTE_BOX: float = 46.0
const GLOW_SHADER := preload("res://art/shaders/cine_glow.gdshader")
const PUFF_SHADER := preload("res://art/shaders/cine_puff.gdshader")
const TRAIL_SHADER := preload("res://art/shaders/cine_trail.gdshader")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.world_3d = World3D.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if RenderingServer.get_current_rendering_method() != "gl_compatibility" else Viewport.SCREEN_SPACE_AA_DISABLED  # [qafix] QA #35
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	add_child(vp)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = _stars()
	pano.energy_multiplier = 2.3  # [v9intro] was 1.4: the stars barely showed
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.45)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 6000.0
	vp.add_child(cam)
	cam.current = true
	_build_space()
	_build_vault()
	_build_garden()
	show_set("space")


# --- Sets ------------------------------------------------------------------------------

## [v11film] Drawing on or off: the opening film builds the stage behind the loading screen and
## only starts drawing it when the film starts.
func set_live(on: bool) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## [v11film] One frame of the vault in its worst state (broken glass, wind, alarm), seen wide:
## drawn under the film's first black frames so its shaders are ready before the first cut to it.
func warm_view(step: int) -> void:
	show_set("vault")
	vault_wind = 1.0
	vault_breach = 1.0 if step > 0 else 0.0
	set_alarm(1.0 if step > 0 else 0.0)
	lumi.visible = true
	set_cam(Transform3D(Basis(), VAULT_AT + Vector3(-3.6, 2.2, -3.2)).looking_at(VAULT_AT + Vector3(0.6, 0.9, 1.6), Vector3.UP), 70.0)


func show_set(id: String) -> void:
	_set = id
	for k: String in _sets:
		(_sets[k] as Node3D).visible = k == id
	sun.visible = id != "vault"
	if fill:
		fill.visible = id == "space"
	match id:
		"space":
			env.background_energy_multiplier = 1.0
			env.ambient_light_energy = 0.35
			env.adjustment_saturation = 1.1
			sun.light_energy = 2.2
			sun.light_color = Color(1.0, 0.95, 0.88)
		"vault":
			env.background_energy_multiplier = 1.0  # [v11film] the stars and the planet through the glass
			env.ambient_light_color = Color(0.3, 0.36, 0.42)
			env.ambient_light_energy = 0.4
		"garden":
			env.background_energy_multiplier = 0.6
			env.ambient_light_color = Color(0.6, 0.55, 0.45)
			env.ambient_light_energy = 0.8
			sun.light_energy = 2.0
			sun.light_color = Color(1.0, 0.86, 0.66)
			sun.rotation_degrees = Vector3(-38, 30, 0)


func _build_space() -> void:
	var root := Node3D.new()
	vp.add_child(root)
	_sets["space"] = root
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 52, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	vp.add_child(sun)
	fill = DirectionalLight3D.new()  # [v9intro] planet bounce, from below
	fill.rotation_degrees = Vector3(62, -150, 0)
	fill.light_color = Color(0.85, 0.66, 0.5)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	vp.add_child(fill)
	_build_motes(root)
	planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PLANET_R
	sm.height = PLANET_R * 2.0
	sm.radial_segments = 128
	sm.rings = 64
	planet.mesh = sm
	_planet_mat = ShaderMaterial.new()
	_planet_mat.shader = preload("res://art/shaders/space_planet.gdshader")
	planet.material_override = _planet_mat
	planet.position = Vector3(0, -PLANET_R - 60.0, -120.0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(planet)
	atmo = MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = PLANET_R * ATMO_K
	am.height = PLANET_R * ATMO_K * 2.0
	am.radial_segments = 128
	am.rings = 64
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = preload("res://art/shaders/space_atmosphere.gdshader")
	amat.set_shader_parameter("shell", ATMO_K)
	amat.set_shader_parameter("sun_dir", sun.global_basis.z)
	atmo.material_override = amat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(atmo)
	ark = CradleShip.new()
	root.add_child(ark)
	pod = Intro.build_pod()
	(pod.get_node("Scorch") as Node3D).visible = false
	pod.visible = false
	root.add_child(pod)


## The root node of a set ("space", "vault", "garden").
func root_of(id: String) -> Node3D:
	return _sets.get(id) as Node3D


func set_planet_green(g: float) -> void:
	_planet_mat.set_shader_parameter("green", g)


## [v11film] The seed vault is the inside of the ark's garden dome (the one on its back in the
## space set): a round glass room under white ribs, with the dead planet filling the glass on one
## side. It was a black void with tiles floating in it. In it: planting beds of real plants (ferns,
## shrubs, saplings, flowers), two warm garden lamps, a low wall of softly lit seed drawers, a
## planter table in the middle with the tray of seedlings under a grow lamp, a watering can, and
## the drop pod standing in its bay. `vault_breach` breaks the glass, `vault_wind` drags
## everything loose toward the hole and bends the plants, `vault_power` dims the lamps.
const VAULT_R: float = 5.2
const VAULT_SY: float = 0.86
## Where the storm breaks the glass, from the room's middle.
const VAULT_HOLE := Vector3(0.62, 0.55, -0.56)
var vault_breach: float = 0.0
var vault_wind: float = 0.0
var vault_power: float = 1.0
var vault_planet: MeshInstance3D
var _vault_dome: ShaderMaterial
var _vault_plants: Array[Node3D] = []
var _vault_lamps: Array[OmniLight3D] = []
var _vault_lamp_mats: Array[StandardMaterial3D] = []
var _vault_leaves: CPUParticles3D
var _vault_mist: CPUParticles3D
var _vault_drawers: Array[StandardMaterial3D] = []
var _grow_light: OmniLight3D
var _grow_pendant: Node3D


func _build_vault() -> void:
	var root := Node3D.new()
	root.position = VAULT_AT
	vp.add_child(root)
	_sets["vault"] = root
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.15)
	dark.metallic = 0.4
	dark.roughness = 0.45
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.86, 0.87, 0.86)
	white.roughness = 0.35
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.16, 0.11, 0.075)
	soil.roughness = 1.0
	var orange := StandardMaterial3D.new()
	orange.albedo_color = CradleShip.TANGERINE
	orange.roughness = 0.4
	# Floor: a deck of plates, a lit ring round the middle, a walkway to the pod bay and the glass.
	var floor_mi := _mesh(root, ProcMesh.cyl(VAULT_R + 0.3, VAULT_R + 0.3, 0.2, 48), dark, Vector3(0, -0.1, 0))
	floor_mi.name = "Floor"
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.3, 0.32, 0.35)
	deck.roughness = 0.6
	deck.metallic = 0.3
	_mesh(root, ProcMesh.cyl(1.9, 1.9, 0.03, 40), deck, Vector3(0, 0.012, 0))
	for z: float in [2.6, -2.6]:
		var path := _mesh(root, ProcMesh.box(Vector3(1.5, 0.03, 3.4)), deck, Vector3(0, 0.012, z))
		path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := _mesh(root, ProcMesh.torus(1.86, 1.94, 48, 6), Mats.lamp(CradleShip.CYAN, 1.2), Vector3(0, 0.03, 0))
	ring.scale = Vector3(1, 0.3, 1)
	# The low wall the glass stands on, with a tangerine cap and rows of seed drawers.
	var wall := CylinderMesh.new()
	wall.top_radius = VAULT_R + 0.05
	wall.bottom_radius = VAULT_R + 0.05
	wall.height = 1.0
	wall.radial_segments = 48
	wall.cap_top = false
	wall.cap_bottom = false
	wall.flip_faces = true
	_mesh(root, wall, white, Vector3(0, 0.5, 0))
	var cap := _mesh(root, ProcMesh.torus(VAULT_R - 0.08, VAULT_R + 0.12, 64, 6), orange, Vector3(0, 1.0, 0))
	cap.scale = Vector3(1, 0.6, 1)
	var tile := BoxMesh.new()
	tile.size = Vector3(0.24, 0.045, 0.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var drawer_cols: Array[Color] = [CradleShip.CYAN, Color(0.55, 1.0, 0.65), Color(1.0, 0.75, 0.35)]
	var drawer_xf: Array = [[], [], []]
	for row: int in 3:
		for col: int in 72:
			var a: float = TAU * (col + (row % 2) * 0.5) / 72.0
			var pick: float = rng.randf()
			if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.5 or pick > 0.5:
				continue  # the pod bay; an unlit drawer
			var which: int = 0 if pick < 0.34 else (1 if pick < 0.44 else 2)
			(drawer_xf[which] as Array).append(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * (VAULT_R - 0.02), 0.26 + row * 0.24, sin(a) * (VAULT_R - 0.02))))
	for ci: int in drawer_cols.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tile
		var xs: Array = drawer_xf[ci]
		mm.instance_count = xs.size()
		for i: int in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var dm: StandardMaterial3D = Mats.lamp(drawer_cols[ci].lerp(Color.WHITE, 0.35), 0.7)
		_vault_drawers.append(dm)
		mmi.material_override = dm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	# The glass dome (the ark's own dome shader, seen from inside) and the world outside it.
	_vault_dome = CradleShip.dome_material()
	_vault_dome.set_shader_parameter("ribs_round", 16.0)
	_vault_dome.set_shader_parameter("ribs_up", 4.0)
	_vault_dome.set_shader_parameter("rib_w", 0.008)
	_vault_dome.set_shader_parameter("hole_dir", VAULT_HOLE)
	_vault_dome.set_shader_parameter("hole_size", 0.42)
	var glass := _mesh(root, CradleShip.dome_mesh(VAULT_R, VAULT_SY, 64, 16), _vault_dome, Vector3(0, 1.0, 0))
	glass.name = "Glass"
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vault_planet = MeshInstance3D.new()
	var psm := SphereMesh.new()
	psm.radius = PLANET_R
	psm.height = PLANET_R * 2.0
	psm.radial_segments = 96
	psm.rings = 48
	vault_planet.mesh = psm
	vault_planet.material_override = _planet_mat
	vault_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vault_planet.layers = 2
	vault_planet.position = Vector3(40, -250, -540)
	root.add_child(vault_planet)
	var vsun := DirectionalLight3D.new()  # lights the planet outside the glass, and nothing else
	vsun.rotation_degrees = Vector3(-38, -28, 0)
	vsun.light_energy = 2.0
	vsun.light_color = Color(1.0, 0.95, 0.88)
	vsun.light_cull_mask = 2
	root.add_child(vsun)
	# Planting beds: two crescents left and right of the walkway, edged in white, full of plants.
	_build_beds(root, soil, white)
	# The planter table in the middle, the tray on it, the grow lamp over it.
	_mesh(root, ProcMesh.cyl(0.36, 0.5, 0.74, 24), white, Vector3(0, 0.37, 0))
	_mesh(root, ProcMesh.cyl(0.52, 0.52, 0.07, 24), white, Vector3(0, 0.775, 0))
	var lip := _mesh(root, ProcMesh.torus(0.5, 0.535, 32, 6), orange, Vector3(0, 0.79, 0))
	lip.scale = Vector3(1, 0.5, 1)
	tray = build_tray()
	tray.position = Vector3(0, 0.84, 0)
	root.add_child(tray)
	var arm := StandardMaterial3D.new()
	arm.albedo_color = Color(0.75, 0.76, 0.77)
	arm.roughness = 0.4
	arm.metallic = 0.5
	# The grow lamp hangs on a cable from the dome's crown (it stood on a pole that crossed Lumi's
	# face in the close shots at the table); in the storm the wind swings it toward the hole.
	_grow_pendant = Node3D.new()
	_grow_pendant.name = "GrowLamp"
	_grow_pendant.position = Vector3(0.04, 5.3, -0.02)
	root.add_child(_grow_pendant)
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.1, 0.11, 0.12)
	cable.roughness = 0.6
	_mesh(_grow_pendant, ProcMesh.cyl(0.006, 0.006, 3.36, 5), cable, Vector3(0, -1.68, 0))
	_mesh(_grow_pendant, ProcMesh.cyl(0.07, 0.2, 0.12, 16), white, Vector3(0, -3.43, 0))
	var bulb_m: StandardMaterial3D = Mats.lamp(Color(0.75, 1.0, 0.7), 1.3)
	_vault_lamp_mats.append(bulb_m)
	_mesh(_grow_pendant, ProcMesh.cyl(0.16, 0.16, 0.02, 16), bulb_m, Vector3(0, -3.5, 0))
	if AssetLib.has_model("watering_can_metal_01"):
		var can := MeshInstance3D.new()
		can.mesh = AssetLib.model_mesh_lite("watering_can_metal_01", 2500)
		can.position = Vector3(-2.15, 0.0, 1.35)  # by the bed, clear of the close shots at the table
		can.rotation.y = 2.2
		can.scale = Vector3.ONE * (0.4 / maxf(0.1, AssetLib.model_aabb("watering_can_metal_01").size.y))
		root.add_child(can)
	# The drop pod in its bay, hatch open, facing the room: a hooded alcove in the wall.
	var hood := CylinderMesh.new()
	hood.top_radius = 1.5
	hood.bottom_radius = 1.5
	hood.height = 2.9
	hood.radial_segments = 28
	hood.cap_bottom = false
	hood.flip_faces = true
	var bay := _mesh(root, hood, dark, Vector3(0, 1.45, 4.25))
	bay.scale = Vector3(1, 1, 0.82)
	var bay_rim := _mesh(root, ProcMesh.torus(1.42, 1.56, 40, 6), Mats.lamp(Color(1.0, 0.6, 0.25), 0.9), Vector3(0, 0.03, 3.95))
	bay_rim.scale = Vector3(1, 0.3, 0.86)
	vault_pod = Intro.build_pod()
	var gv: GlimBot = vault_pod.get_node_or_null(GlimDirector.STUCK_NAME) as GlimBot
	if gv:  # [v4calm] in the ark he's awake, perched on Lumi's pod; dark only after the fall
		gv.broken = false
	(vault_pod.get_node("Scorch") as Node3D).visible = false
	vault_pod.position = Vector3(0, 0, 3.95)
	root.add_child(vault_pod)
	EscapePod.set_open(vault_pod, true)
	var bay_lamp := OmniLight3D.new()
	bay_lamp.light_color = Color(1.0, 0.7, 0.4)
	bay_lamp.light_energy = 0.9
	bay_lamp.omni_range = 3.0
	bay_lamp.position = Vector3(0, 2.5, 3.2)
	root.add_child(bay_lamp)
	_vault_lamps.append(bay_lamp)
	# Lights: the grow lamp's green over the tray, two warm garden lamps, a warm fill from the
	# planet's side, and a soft cool key with shadows.
	_grow_light = OmniLight3D.new()
	_grow_light.light_color = Color(0.6, 1.0, 0.62)
	_grow_light.light_energy = 1.9
	_grow_light.omni_range = 3.6
	_grow_light.position = Vector3(0, 1.55, 0)
	root.add_child(_grow_light)
	_vault_lights.append(_grow_light)
	for at: Vector3 in [Vector3(-2.9, 0, -1.6), Vector3(2.7, 0, 1.7)]:
		_mesh(root, ProcMesh.cyl(0.03, 0.045, 1.5, 8), arm, at + Vector3(0, 0.75, 0))
		var lm: StandardMaterial3D = Mats.lamp(Color(1.0, 0.82, 0.55), 1.3)
		_vault_lamp_mats.append(lm)
		_mesh(root, ProcMesh.sphere(0.13, 12, 8), lm, at + Vector3(0, 1.58, 0))
		_mesh(root, ProcMesh.cyl(0.2, 0.16, 0.04, 12), white, at + Vector3(0, 1.72, 0))
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.8, 0.52)
		o.light_energy = 1.5
		o.omni_range = 4.6
		o.position = at + Vector3(0, 1.6, 0)
		root.add_child(o)
		_vault_lamps.append(o)
		_vault_lights.append(o)
	var planet_fill := OmniLight3D.new()
	planet_fill.light_color = Color(0.95, 0.72, 0.5)
	planet_fill.light_energy = 0.9
	planet_fill.omni_range = 9.0
	planet_fill.position = Vector3(0.5, 2.2, -4.4)
	root.add_child(planet_fill)
	var key := OmniLight3D.new()
	key.light_color = Color(0.82, 0.9, 1.0)
	key.light_energy = 0.9
	key.omni_range = 8.0
	key.shadow_enabled = true
	key.position = Vector3(-1.8, 3.4, 1.6)
	root.add_child(key)
	_vault_lamps.append(key)
	alarm_light = SpotLight3D.new()
	alarm_light.light_color = CradleShip.ALARM
	alarm_light.light_energy = 0.0
	alarm_light.spot_range = 9.0
	alarm_light.spot_angle = 38.0
	alarm_light.position = Vector3(0, 4.2, 0)
	root.add_child(alarm_light)
	_build_vault_wind(root)
	lumi = PatchModel.new()
	root.add_child(lumi)
	lumi.position = Vector3(0, 0.15, -1.1)
	lumi.rotation.y = 0.0  # faces -Z by default; turned toward the tray by the cinematic


## The planting beds and what grows in them (each plant its own node, so the wind can bend it).
func _build_beds(root: Node3D, soil: StandardMaterial3D, white: StandardMaterial3D) -> void:
	var kinds: Array = [["fern_02", 1.5, 2500], ["shrub_01", 1.0, 2500], ["shrub_02", 1.0, 2500], ["pine_sapling_small", 1.3, 2500],
		["periwinkle_plant", 1.6, 2000], ["flower_gazania", 1.5, 1500], ["grass_medium_01", 1.2, 1500], ["grass_medium_02", 1.2, 1500]]
	var meshes: Array = []
	for k: Array in kinds:
		if AssetLib.has_model(str(k[0])):
			meshes.append([AssetLib.model_mesh_lite(str(k[0]), int(k[2])), float(k[1]), AssetLib.model_aabb(str(k[0]))])
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var edge := TorusMesh.new()
	edge.inner_radius = 2.05
	edge.outer_radius = 2.17
	edge.rings = 48
	edge.ring_segments = 6
	var em := _mesh(root, edge, white, Vector3(0, 0.05, 0))
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side: float in [-1.0, 1.0]:
		# The bed: a crescent of soil between the middle ring and the wall.
		for i: int in 9:
			var a: float = lerpf(-1.05, 1.05, i / 8.0)
			var c := Vector3(side * cos(a) * 3.45, 0.0, sin(a) * 3.45)
			var mound := _mesh(root, ProcMesh.sphere(1.0, 12, 6), soil, c + Vector3(0, 0.02, 0))
			mound.scale = Vector3(1.25, 0.16, 1.0)
			mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if meshes.is_empty():
			continue
		for i: int in 17:
			var a: float = lerpf(-1.08, 1.08, (i + rng.randf_range(-0.3, 0.3)) / 16.0)
			var r: float = rng.randf_range(2.55, 4.5)
			var m: Array = meshes[rng.randi() % meshes.size()]
			var aabb: AABB = m[2]
			var want: float = rng.randf_range(0.5, 1.0) * float(m[1]) * (0.75 + 0.5 * (r - 2.5) / 2.0)
			# Sized by its height, but never wider than a bed plant should be (a flat grass patch
			# scaled by its height alone grew four metres across, into the close shots at the table).
			var sc: float = minf(want / maxf(0.2, aabb.size.y), 1.3 / maxf(0.2, maxf(aabb.size.x, aabb.size.z)))
			var plant := MeshInstance3D.new()
			plant.mesh = m[0]
			plant.position = Vector3(side * cos(a) * r, 0.1, sin(a) * r)
			plant.rotation.y = rng.randf() * TAU
			plant.scale = Vector3.ONE * sc
			plant.set_meta("rest", plant.basis)
			plant.set_meta("sway", rng.randf() * TAU)
			root.add_child(plant)
			_vault_plants.append(plant)


## What the breach drags toward the hole: torn leaves and a white mist of escaping air.
func _build_vault_wind(root: Node3D) -> void:
	var hole: Vector3 = vault_hole() - VAULT_AT
	var leaf_m := StandardMaterial3D.new()
	leaf_m.albedo_color = Color(0.3, 0.55, 0.22)
	leaf_m.emission_enabled = true
	leaf_m.emission = Color(0.3, 0.7, 0.3)
	leaf_m.emission_energy_multiplier = 0.12
	leaf_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_m.vertex_color_use_as_albedo = true
	var lq := QuadMesh.new()
	lq.size = Vector2(0.07, 0.03)
	lq.material = leaf_m
	_vault_leaves = CPUParticles3D.new()
	_vault_leaves.mesh = lq
	_vault_leaves.amount = 150
	_vault_leaves.lifetime = 1.5
	_vault_leaves.local_coords = false
	_vault_leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_vault_leaves.emission_box_extents = Vector3(4.0, 0.4, 3.5)
	_vault_leaves.position = Vector3(0, 0.7, 0)
	_vault_leaves.direction = (hole - Vector3(0, 0.7, 0)).normalized()
	_vault_leaves.spread = 24.0
	_vault_leaves.initial_velocity_min = 3.0
	_vault_leaves.initial_velocity_max = 6.5
	_vault_leaves.gravity = (hole - Vector3(0, 0.7, 0)).normalized() * 5.0
	_vault_leaves.angular_velocity_min = -400.0
	_vault_leaves.angular_velocity_max = 400.0
	_vault_leaves.angle_max = 360.0
	_vault_leaves.scale_amount_min = 0.6
	_vault_leaves.scale_amount_max = 1.6
	var lg := Gradient.new()
	lg.set_color(0, Color(1, 1, 1, 0))
	lg.set_color(1, Color(1, 1, 1, 0))
	lg.add_point(0.15, Color(1, 1, 1, 1))
	lg.add_point(0.8, Color(1, 1, 1, 1))
	_vault_leaves.color_ramp = lg
	_vault_leaves.emitting = false
	_vault_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_vault_leaves)
	var mist_m := StandardMaterial3D.new()
	mist_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist_m.billboard_keep_scale = true
	mist_m.vertex_color_use_as_albedo = true
	mist_m.albedo_texture = EscapePod._soft_tex()
	mist_m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mq := QuadMesh.new()
	mq.size = Vector2.ONE
	mq.material = mist_m
	_vault_mist = CPUParticles3D.new()
	_vault_mist.mesh = mq
	_vault_mist.amount = 40
	_vault_mist.lifetime = 1.1
	_vault_mist.local_coords = false
	_vault_mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_vault_mist.emission_sphere_radius = 2.6
	_vault_mist.position = Vector3(0.8, 1.6, -0.8)
	_vault_mist.direction = (hole - _vault_mist.position).normalized()
	_vault_mist.spread = 14.0
	_vault_mist.initial_velocity_min = 4.0
	_vault_mist.initial_velocity_max = 8.0
	_vault_mist.gravity = (hole - _vault_mist.position).normalized() * 9.0
	_vault_mist.scale_amount_min = 0.5
	_vault_mist.scale_amount_max = 1.3
	var mg := Gradient.new()
	mg.set_color(0, Color(0.9, 0.95, 1.0, 0.0))
	mg.set_color(1, Color(0.9, 0.95, 1.0, 0.0))
	mg.add_point(0.25, Color(0.9, 0.95, 1.0, 0.16))
	_vault_mist.color_ramp = mg
	_vault_mist.emitting = false
	_vault_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_vault_mist)


## Drop every leaf and wisp in the air (a shot that starts in still air starts clean).
func vault_clear_fx() -> void:
	for p: CPUParticles3D in [_vault_leaves, _vault_mist]:
		p.emitting = false
		p.restart()
		p.emitting = false


## The hole in the vault's glass, in the stage's world space.
static func vault_hole() -> Vector3:
	return VAULT_AT + Vector3(0, 1.0, 0) + Vector3(VAULT_HOLE.x * VAULT_R, VAULT_HOLE.y * VAULT_R * VAULT_SY, VAULT_HOLE.z * VAULT_R)


func _update_vault(_delta: float) -> void:
	if _set != "vault":
		return
	_vault_dome.set_shader_parameter("breach", clampf(vault_breach, 0.0, 1.0))
	var w: float = clampf(vault_wind, 0.0, 1.0)
	_vault_leaves.emitting = w > 0.05
	_vault_mist.emitting = w > 0.05
	_vault_leaves.speed_scale = lerpf(0.6, 1.3, w)
	# Plants sway a little in still air and lean hard toward the hole in the wind.
	var pull := Vector3(VAULT_HOLE.x, 0.0, VAULT_HOLE.z).normalized()
	var axis: Vector3 = pull.cross(Vector3.UP).normalized()
	for p: Node3D in _vault_plants:
		var rest: Basis = p.get_meta("rest")
		var ph: float = float(p.get_meta("sway"))
		var lean: float = 0.03 * sin(_t * 0.9 + ph) + w * (0.42 + 0.14 * sin(_t * 13.0 + ph * 3.0))
		p.basis = Basis(axis, -lean) * rest
	var pw: float = clampf(vault_power, 0.0, 1.0)
	var fl: float = pw
	if _alarm > 0.05:
		fl = pw * (0.55 + (0.45 if fmod(_t * 7.0 + sin(_t * 31.0), 1.0) > 0.35 else 0.0))
	for i: int in _vault_lamps.size():
		_vault_lamps[i].light_energy = [0.9, 1.5, 1.5, 0.9][mini(i, 3)] * fl
	for m: StandardMaterial3D in _vault_lamp_mats:
		m.emission_energy_multiplier = 1.3 * fl
	for m: StandardMaterial3D in _vault_drawers:
		m.emission_energy_multiplier = 0.7 * fl
	_grow_light.light_energy = 1.9 * lerpf(0.5, 1.0, pw)
	var swing: float = 0.02 * sin(_t * 0.8) + w * (0.32 + 0.1 * sin(_t * 6.0))
	_grow_pendant.basis = Basis(axis, swing)  # its foot goes the way the air goes


## A small white tray of seedlings: dark soil and a dozen young plants, each a thin stem with two
## round seed leaves; a few are a little further on and have a second pair.
## One seed leaf, 1 long along +X from its stalk: an oval a little wider past the middle, its edges
## curled up and its tip drooping (scaled down to a few centimetres by the tray).
static func seed_leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 9
	var rows: Array = []
	for i: int in n + 1:
		var u: float = float(i) / n
		var hw: float = 0.34 * sin(PI * pow(u, 0.8))
		var y: float = 0.06 * sin(PI * u) - 0.16 * u * u
		rows.append([Vector3(u, y + 0.35 * hw * hw, -hw), Vector3(u, y, 0.0), Vector3(u, y + 0.35 * hw * hw, hw)])
	for i: int in n:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for side: int in 2:
			var p0: Vector3 = a[side]
			var p1: Vector3 = a[side + 1]
			var q0: Vector3 = b[side]
			var q1: Vector3 = b[side + 1]
			for v: Vector3 in [p0, q0, q1, p0, q1, p1]:
				st.set_uv(Vector2(v.x, v.z + 0.5))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func build_tray() -> Node3D:
	var t := Node3D.new()
	t.name = "SeedTray"
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.88)
	white.roughness = 0.3
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.17, 0.11, 0.07)
	soil.roughness = 1.0
	# Leaves: a living green that glows a little (brighter when Lumi hums to them); stems pale.
	var leaf := Mats.lamp(Color(0.32, 0.8, 0.3), 0.75)
	leaf.albedo_color = Color(0.3, 0.62, 0.2)
	leaf.roughness = 0.55
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	t.set_meta("leaf", leaf)
	var stem_m := StandardMaterial3D.new()
	stem_m.albedo_color = Color(0.66, 0.78, 0.48)
	stem_m.roughness = 0.6
	stem_m.emission_enabled = true
	stem_m.emission = Color(0.3, 0.55, 0.25)
	stem_m.emission_energy_multiplier = 0.25
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.rounded_box(Vector3(0.62, 0.1, 0.42), 0.03, 2)
	body.material_override = white
	body.position = Vector3(0, 0.05, 0)
	t.add_child(body)
	var dirt := MeshInstance3D.new()
	dirt.mesh = ProcMesh.box(Vector3(0.56, 0.02, 0.36))
	dirt.material_override = soil
	dirt.position = Vector3(0, 0.1, 0)
	t.add_child(dirt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var stem_mesh: CylinderMesh = ProcMesh.cyl(0.0045, 0.0065, 1.0, 6)
	var leaf_mesh: ArrayMesh = seed_leaf_mesh()
	for i: int in 4:
		for j: int in 3:
			var p := Vector3(-0.21 + i * 0.14, 0.11, -0.12 + j * 0.12) + Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012))
			var big: bool = (i + j * 2) % 5 == 1
			var h: float = rng.randf_range(0.07, 0.1) * (1.55 if big else 1.0)
			var plant := Node3D.new()
			plant.position = p
			plant.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
			t.add_child(plant)
			var stem := MeshInstance3D.new()
			stem.mesh = stem_mesh
			stem.material_override = stem_m
			stem.scale = Vector3(1, h, 1)
			stem.position = Vector3(0, h * 0.5, 0)
			plant.add_child(stem)
			# Two round seed leaves at the top, lifted like open hands; the bigger ones have their
			# first pair of true leaves above them, smaller and turned a quarter round.
			for pair: int in (2 if big else 1):
				var y: float = h * (1.0 if pair == 0 else 0.7)
				var sz: float = rng.randf_range(0.034, 0.042) * (1.2 if big else 1.0) * (1.0 if pair == 0 else 1.15)
				if big and pair == 0:
					sz *= 0.62  # the new pair on top is the small one
				for s: float in [0.0, PI]:
					var lf := MeshInstance3D.new()
					lf.mesh = leaf_mesh
					lf.material_override = leaf
					var lift: float = rng.randf_range(0.3, 0.55) if pair == 0 else rng.randf_range(0.1, 0.3)
					lf.basis = Basis(Vector3.UP, s + PI * 0.5 * pair) * Basis(Vector3(0, 0, 1), lift) * Basis().scaled(Vector3.ONE * sz)
					lf.position = Vector3(0, y, 0)
					plant.add_child(lf)
	return t


func _build_garden() -> void:
	var root := Node3D.new()
	root.position = GARDEN_AT
	vp.add_child(root)
	_sets["garden"] = root
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.32, 0.55, 0.22)
	grass.roughness = 0.95
	_mesh(root, ProcMesh.cyl(30.0, 30.0, 0.4, 64), grass, Vector3(0, -0.2, 0))
	var path := StandardMaterial3D.new()
	path.albedo_color = Color(0.78, 0.72, 0.6)
	path.roughness = 0.9
	var pm := _mesh(root, ProcMesh.box(Vector3(1.6, 0.02, 40.0)), path, Vector3(1.4, 0.01, 0))
	pm.rotation.y = 0.25
	var pond_m := Mats.glass(Color(0.2, 0.45, 0.55, 1.0), 0.02)
	var pond := _mesh(root, ProcMesh.cyl(3.2, 3.2, 0.03, 40), pond_m, Vector3(-4.5, 0.02, -6.0))
	pond.scale = Vector3(1.4, 1, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.26, 0.18)
	var leaves: Array[StandardMaterial3D] = []
	for c: Color in [Color(0.25, 0.5, 0.18), Color(0.35, 0.6, 0.2), Color(0.2, 0.42, 0.2), Color(0.5, 0.65, 0.25)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		leaves.append(m)
	for i: int in 46:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(5.0, 26.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x - 1.4 - p.z * 0.25) < 2.0:
			continue
		var h: float = rng.randf_range(2.5, 6.0)
		_mesh(root, ProcMesh.cyl(0.12, 0.22, h, 8), bark, p + Vector3(0, h * 0.5, 0))
		var crown := _mesh(root, ProcMesh.sphere(rng.randf_range(1.2, 2.4), 14, 8), leaves[rng.randi() % leaves.size()], p + Vector3(0, h + 0.6, 0))
		crown.scale = Vector3(1.0, rng.randf_range(0.8, 1.2), 1.0)
	# Flower beds.
	var petals: Array[Color] = [Color(1.0, 0.8, 0.2), Color(1.0, 0.45, 0.55), Color(0.6, 0.6, 1.0), Color(1, 1, 1)]
	for i: int in 160:
		var p := Vector3(rng.randf_range(-12, 12), 0.15, rng.randf_range(-12, 8))
		var m := StandardMaterial3D.new()
		m.albedo_color = petals[rng.randi() % petals.size()]
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.15
		_mesh(root, ProcMesh.sphere(0.09, 6, 3), m, p)
	# The great glass dome overhead with white ribs.
	var dome := SphereMesh.new()
	dome.radius = 30.0
	dome.height = 30.0
	dome.is_hemisphere = true
	dome.radial_segments = 64
	dome.rings = 16
	dome.flip_faces = true
	var dm := Mats.glass(Color(0.6, 0.85, 0.95, 0.12), 0.02)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dmi := _mesh(root, dome, dm, Vector3.ZERO)
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rib_m := StandardMaterial3D.new()
	rib_m.albedo_color = Color(0.9, 0.9, 0.88)
	for k: int in 12:
		var rib := _mesh(root, ProcMesh.torus(29.7, 30.1, 64, 4), rib_m, Vector3.ZERO)
		rib.rotation = Vector3(PI * 0.5, TAU * k / 24.0, 0)
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.85, 0.6)
	warm.light_energy = 1.0
	warm.omni_range = 14.0
	warm.position = Vector3(2, 5, 4)
	root.add_child(warm)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _stars() -> ImageTexture:
	var w: int = 4096
	var h: int = 2048
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.003, 0.004, 0.01))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# A faint milky band.
	for i: int in 30000:
		var x: int = rng.randi() % w
		var y: int = clampi(int(h * 0.42 + sin(float(x) / w * TAU) * h * 0.12 + rng.randfn(0.0, h * 0.05)), 0, h - 1)
		img.set_pixel(x, y, img.get_pixel(x, y) + Color(0.012, 0.012, 0.02))
	for i: int in 9000:
		var b: float = pow(rng.randf(), 6.0)
		var tint: float = rng.randf()
		var c := Color(0.75 + tint * 0.25, 0.8 + b * 0.2, 1.0 - tint * 0.2) * (0.12 + b * 1.6)
		img.set_pixel(rng.randi() % w, rng.randi() % h, c)
	return ImageTexture.create_from_image(img)


# --- Camera -----------------------------------------------------------------------------

## Move the camera from one framing to another over dur seconds (smoothstep).
func shot(from: Vector3, from_look: Vector3, to: Vector3, to_look: Vector3, dur: float, fov_from: float = 50.0, fov_to: float = -1.0) -> void:
	_from = Transform3D(Basis(), from).looking_at(from_look, Vector3.UP)
	_to = Transform3D(Basis(), to).looking_at(to_look, Vector3.UP)
	_dur = maxf(dur, 0.01)
	_ct = 0.0
	_fov_from = fov_from
	_fov_to = fov_from if fov_to < 0.0 else fov_to
	cam.global_transform = _from
	cam.fov = fov_from


## Hold the camera in place but keep it pointed at a moving target.
func aim(pos: Vector3, look: Vector3, fov: float = 50.0) -> void:
	_dur = -1.0
	cam.global_transform = Transform3D(Basis(), pos).looking_at(look, Vector3.UP)
	cam.fov = fov


## [v9intro] Put the camera exactly here (the caller animates it every frame).
func set_cam(xf: Transform3D, fov: float) -> void:
	_dur = -1.0
	cam.global_transform = xf
	cam.fov = fov


func set_alarm(a: float) -> void:
	_alarm = a
	ark.alarm = a


# --- Effects ----------------------------------------------------------------------------
# [v9intro] Every effect here is soft: it is born small and faint, and dies by fading, never by
# being cut off, and none of them shows a hard disc or a stick (the old blast was a solid white
# ball, the puffs flat circles, the meteors a ball on an orange rod).

static func glow_mat(col: Color, power: float = 2.2, strength: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("strength", strength)
	return m


static func puff_mat(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PUFF_SHADER
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("seed", randf() * 40.0)
	return m


## A streaming fire / light trail material for an open CylinderMesh (its side UVs run 0..0.5).
static func trail_mat(hot: Color, cool: Color, strength: float = 1.0, head_at_top: bool = false, speed: float = 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	m.set_shader_parameter("hot", hot)
	m.set_shader_parameter("cool", cool)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("head_at_top", 1.0 if head_at_top else 0.0)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("v_scale", 2.0)
	return m


## A meteor streaking from a to b over dur seconds: a dark rock in a soft white-hot glow, with a
## long tapering tail of fire behind it.
func meteor(a: Vector3, b: Vector3, dur: float, size_: float = 1.0) -> void:
	var n := Node3D.new()
	(_sets[_set] if _sets.has(_set) else _sets["space"]).add_child(n)  # [v11film] also past the vault's glass
	var rock := MeshInstance3D.new()
	rock.mesh = ProcMesh.sphere(0.5 * size_, 7, 4)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.16, 0.13, 0.12)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.45, 0.15)
	rm.emission_energy_multiplier = 0.6
	rock.material_override = rm
	rock.scale = Vector3(1.0, 0.8, 1.25)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(rock)
	var head := MeshInstance3D.new()
	head.mesh = ProcMesh.sphere(1.0, 16, 10)
	head.material_override = glow_mat(Color(1.0, 0.8, 0.55), 2.6, 1.5)
	head.scale = Vector3.ONE * 1.7 * size_
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(head)
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.03
	tm.bottom_radius = 0.6 * size_
	tm.height = 30.0 * size_
	tm.radial_segments = 12
	tm.rings = 6
	tm.cap_top = false
	tm.cap_bottom = false
	tail.mesh = tm
	tail.material_override = trail_mat(Color(1.0, 0.9, 0.7), Color(1.0, 0.38, 0.1), 1.25, false, 5.0)
	tail.rotation.x = PI * 0.5  # the thin end trails behind (+Z), the wide end sits on the head
	tail.position = Vector3(0, 0, 15.0 * size_)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(tail)
	n.look_at_from_position(a, b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	var tw := n.create_tween()
	tw.tween_property(n, "global_position", b, dur)
	tw.tween_callback(n.queue_free)


## A flash with a shock shell, a light pulse and flying debris: a white-hot core that swells and
## fades, a slower orange bloom behind it and a thin ring racing outward.
func blast(pos: Vector3, scale_k: float = 1.0, col: Color = Color(1.0, 0.7, 0.35)) -> void:
	var holder: Node3D = _sets[_set] if _sets.has(_set) else _sets["space"]
	var n := Node3D.new()
	holder.add_child(n)
	n.global_position = pos
	var tw := n.create_tween().set_parallel(true)
	for k: int in 2:
		var ball := MeshInstance3D.new()
		ball.mesh = ProcMesh.sphere(1.0, 20, 12)
		var c: Color = Color(1.0, 0.96, 0.88) if k == 0 else col
		var m: ShaderMaterial = glow_mat(c, 1.5 if k == 0 else 2.4, 2.6 if k == 0 else 1.5)
		ball.material_override = m
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.scale = Vector3.ONE * 0.3 * scale_k
		n.add_child(ball)
		var grow: float = (3.2 if k == 0 else 5.5) * scale_k
		var life: float = 0.55 if k == 0 else 1.3
		tw.tween_property(ball, "scale", Vector3.ONE * grow, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(m, "shader_parameter/strength", 0.0, life).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	var ring := MeshInstance3D.new()
	ring.mesh = ProcMesh.torus(0.975, 1.0, 48, 6)
	var rmat: ShaderMaterial = glow_mat(Color(1.0, 0.85, 0.65), 0.6, 0.55)
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 0.5 * scale_k
	n.add_child(ring)
	ring.look_at(cam.global_position, Vector3.UP)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)  # the torus lies in XZ: face it to the camera
	tw.tween_property(ring, "scale", Vector3.ONE * 9.0 * scale_k, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rmat, "shader_parameter/strength", 0.0, 0.9)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 12.0
	light.omni_range = 30.0 * scale_k
	n.add_child(light)
	tw.tween_property(light, "light_energy", 0.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(n.queue_free)
	debris(pos, 14, 8.0 * scale_k, 0.6 * scale_k)
	shake = maxf(shake, 0.6 * scale_k)


## Chunks of hull flying outward and tumbling (they shrink away at the end, they don't pop).
func debris(pos: Vector3, count: int, speed: float, size_: float = 1.0, dir := Vector3.ZERO) -> void:
	var holder: Node3D = _sets[_set] if _sets.has(_set) else _sets["space"]
	var hull_m := StandardMaterial3D.new()
	hull_m.albedo_color = Color(0.85, 0.85, 0.83)
	var hot := Mats.lamp(Color(1.0, 0.55, 0.2), 3.0)
	for i: int in count:
		var d := MeshInstance3D.new()
		d.mesh = ProcMesh.box(Vector3(randf_range(0.1, 0.5), randf_range(0.05, 0.2), randf_range(0.1, 0.6)) * size_)
		d.material_override = hot if i % 3 == 0 else hull_m
		holder.add_child(d)
		d.global_position = pos
		var v: Vector3 = (Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() + dir).normalized() * speed * randf_range(0.4, 1.2)
		var life: float = randf_range(2.0, 4.0)
		_fx.append({"node": d, "vel": v, "spin": Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), "life": life, "life0": life})


## [v11film] A torn leaf tumbling away (the garden pouring out of the broken dome).
func leaf(pos: Vector3, vel: Vector3) -> void:
	var holder: Node3D = _sets[_set] if _sets.has(_set) else _sets["space"]
	if _leaf_mat == null:
		_leaf_mat = Mats.lamp(Color(0.4, 1.0, 0.45), 1.3)
		_leaf_mat.albedo_color = Color(0.3, 0.75, 0.3)
		_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var d := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(randf_range(0.14, 0.3), randf_range(0.08, 0.16))
	d.mesh = q
	d.material_override = _leaf_mat
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(d)
	d.global_position = pos
	var life: float = randf_range(2.2, 3.6)
	_fx.append({"node": d, "vel": vel, "spin": Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7)), "life": life, "life0": life})


## Soft puffs (venting air, smoke, heat) drifting along vel. They swell from small, and fade.
func puff(pos: Vector3, vel: Vector3, col: Color = Color(0.9, 0.92, 0.95, 0.5), size_: float = 1.0, life_: float = 1.6) -> void:
	var holder: Node3D = _sets[_set] if _sets.has(_set) else _sets["space"]
	var p := MeshInstance3D.new()
	p.mesh = ProcMesh.sphere(0.5 * size_, 12, 8)
	var m: ShaderMaterial = puff_mat(Color(col.r, col.g, col.b, 0.0))
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	p.global_position = pos
	p.scale = Vector3.ONE * 0.45
	_fx.append({"node": p, "vel": vel, "spin": Vector3.ZERO, "life": life_, "life0": life_, "grow": 1.5 * size_ * 1.6 / life_, "fade": m, "col": col})


## Musical notes drifting up from Lumi while it hums.
func note(pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = ["♪", "♫", "♩"][randi() % 3]
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = Color(0.6, 1.0, 0.75, 0.0)
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	_sets["vault"].add_child(l)
	l.global_position = pos
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position", l.position + Vector3(randf_range(-0.25, 0.25), 0.9, randf_range(-0.1, 0.1)), 2.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "modulate:a", 0.9, 0.5)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)


# --- [v9intro] Drifting specks ------------------------------------------------------------

func _build_motes(root: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = MOTES
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i: int in MOTES:
		_mote_pos.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * MOTE_BOX)
	_motes = MultiMeshInstance3D.new()
	_motes.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.5, 0.52, 0.56)
	_motes.material_override = m
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visible = false
	_motes.top_level = true
	root.add_child(_motes)


func _update_motes(delta: float) -> void:
	var on: bool = _set == "space" and motes_on
	_motes.visible = on
	if not on:
		return
	var mm: MultiMesh = _motes.multimesh
	var c: Vector3 = cam.global_position
	var stretch: float = clampf(motes_vel.length() * 0.008, 0.0, 1.0)
	var along: Vector3 = motes_vel.normalized()
	var b := Basis()
	if stretch > 0.05:  # fast: each speck smears into a short streak along its path
		var side: Vector3 = along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
		b = Basis(side, along.cross(side), along)
	for i: int in MOTES:
		var p: Vector3 = _mote_pos[i] + motes_vel * delta
		# Keep every speck in a box round the camera: one that leaves comes back on the far side.
		p.x = c.x + wrapf(p.x - c.x, -MOTE_BOX, MOTE_BOX)
		p.y = c.y + wrapf(p.y - c.y, -MOTE_BOX, MOTE_BOX)
		p.z = c.z + wrapf(p.z - c.z, -MOTE_BOX, MOTE_BOX)
		_mote_pos[i] = p
		var sz: float = 0.05 + 0.07 * float(i % 5) / 4.0
		if p.distance_squared_to(c) < 64.0:
			sz = 0.0  # never a big blob right in front of the lens
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(sz, sz, sz * (1.0 + stretch * 9.0))), p))


## Smooth camera shake: a few slow sines, so it rumbles instead of buzzing.
static func shake_offset(t: float, amount: float) -> Vector3:
	return Vector3(sin(t * 23.0) + sin(t * 37.3 + 1.3) * 0.6, sin(t * 29.1 + 0.7) + sin(t * 41.7) * 0.6, sin(t * 19.7 + 2.1)) * amount


func _process(delta: float) -> void:
	_t += delta
	if _dur > 0.0:
		_ct += delta
		var k: float = clampf(_ct / _dur, 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		cam.global_transform = _from.interpolate_with(_to, e)
		cam.fov = lerpf(_fov_from, _fov_to, e)
	if shake > 0.0:
		var o: Vector3 = shake_offset(_t, shake)
		cam.global_position += o * 0.12
		cam.rotate_object_local(Vector3(0, 0, 1), o.z * 0.006)
		shake = maxf(0.0, shake - delta * 0.8)
	_update_motes(delta)
	_update_vault(delta)
	# Vault alarm: a sweeping red beacon and the cyan lights breathing toward red.
	if alarm_light:
		alarm_light.light_energy = _alarm * 9.0
		alarm_light.rotation = Vector3(-0.9, _t * 3.4, 0)
		for i: int in _vault_lights.size():
			_vault_lights[i].light_color = (Color(0.6, 1.0, 0.62) if i == 0 else Color(1.0, 0.8, 0.52)).lerp(CradleShip.ALARM, _alarm * (0.6 + 0.3 * sin(_t * 4.2)))
	var i: int = _fx.size() - 1
	while i >= 0:
		var f: Dictionary = _fx[i]
		var n: Node3D = f["node"]
		f["life"] = float(f["life"]) - delta
		if not is_instance_valid(n) or float(f["life"]) <= 0.0:
			if is_instance_valid(n):
				n.queue_free()
			_fx.remove_at(i)
			i -= 1
			continue
		n.position += (f["vel"] as Vector3) * delta
		n.rotation += (f["spin"] as Vector3) * delta
		var life: float = float(f["life"])
		var age: float = float(f.get("life0", life)) - life
		if f.has("grow"):
			n.scale += Vector3.ONE * float(f["grow"]) * delta
			var fm: ShaderMaterial = f["fade"]
			var col: Color = f["col"]
			col.a *= clampf(age / 0.18, 0.0, 1.0) * clampf(life / (float(f["life0"]) * 0.7), 0.0, 1.0)
			fm.set_shader_parameter("tint", col)
		elif life < 0.4:
			n.scale = Vector3.ONE * (life / 0.4)
		i -= 1
