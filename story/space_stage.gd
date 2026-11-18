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
			env.background_energy_multiplier = 0.0
			env.ambient_light_color = Color(0.25, 0.35, 0.4)
			env.ambient_light_energy = 0.35
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


func _build_vault() -> void:
	var root := Node3D.new()
	root.position = VAULT_AT
	vp.add_child(root)
	_sets["vault"] = root
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.1)
	dark.metallic = 0.5
	dark.roughness = 0.3
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.88, 0.89, 0.88)
	white.roughness = 0.25
	white.clearcoat_enabled = true
	var glass := Mats.glass(Color(0.03, 0.05, 0.07, 1.0), 0.06)
	# Floor, ceiling and the round wall (seen from inside).
	var floor_mi := _mesh(root, ProcMesh.cyl(4.6, 4.6, 0.2, 48), dark, Vector3(0, -0.1, 0))
	floor_mi.name = "Floor"
	var ring := _mesh(root, ProcMesh.torus(2.0, 2.15, 48, 6), Mats.lamp(CradleShip.CYAN, 2.5), Vector3(0, 0.01, 0))
	ring.scale = Vector3(1, 0.2, 1)
	var wall := CylinderMesh.new()
	wall.top_radius = 4.6
	wall.bottom_radius = 4.6
	wall.height = 4.2
	wall.radial_segments = 48
	wall.cap_top = false
	wall.cap_bottom = false
	wall.flip_faces = true
	_mesh(root, wall, glass, Vector3(0, 2.1, 0))
	var ceil_ := CylinderMesh.new()
	ceil_.top_radius = 0.1
	ceil_.bottom_radius = 4.6
	ceil_.height = 1.4
	ceil_.radial_segments = 48
	ceil_.cap_bottom = false
	ceil_.flip_faces = true
	_mesh(root, ceil_, white, Vector3(0, 4.9, 0))
	var halo := _mesh(root, ProcMesh.torus(1.0, 1.12, 40, 6), Mats.lamp(Color(0.6, 1.0, 0.75), 3.0), Vector3(0, 4.25, 0))
	halo.scale = Vector3(1, 0.3, 1)
	# Seed drawers: rows of small glowing tiles around the wall (one MultiMesh per colour).
	var tile := BoxMesh.new()
	tile.size = Vector3(0.36, 0.2, 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for c: Color in [CradleShip.CYAN, Color(0.55, 1.0, 0.65), Color(1.0, 0.75, 0.35)]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tile
		var xs: Array[Transform3D] = []
		for row: int in 9:
			for col: int in 56:
				var a: float = TAU * (col + (row % 2) * 0.5) / 56.0
				if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.55:
					continue  # the pod bay
				var pick: float = rng.randf()
				var which: int = 0 if pick < 0.7 else (1 if pick < 0.92 else 2)
				if [CradleShip.CYAN, Color(0.55, 1.0, 0.65), Color(1.0, 0.75, 0.35)][which] != c:
					continue
				var p := Vector3(cos(a) * 4.5, 0.6 + row * 0.38, sin(a) * 4.5)
				xs.append(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p))
		mm.instance_count = xs.size()
		for i: int in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mats.lamp(c, 1.6)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	# Centre pedestal with the seedling tray.
	_mesh(root, ProcMesh.cyl(0.42, 0.55, 0.8, 32), white, Vector3(0, 0.4, 0))
	_mesh(root, ProcMesh.torus(0.42, 0.47, 32, 6), Mats.lamp(CradleShip.CYAN, 3.0), Vector3(0, 0.8, 0))
	tray = build_tray()
	tray.position = Vector3(0, 0.84, 0)
	root.add_child(tray)
	# The cargo pod in its bay, hatch open, facing the room.
	var bay := _mesh(root, ProcMesh.cyl(1.25, 1.25, 3.6, 32), dark, Vector3(0, 1.8, 4.65))
	bay.scale = Vector3(1, 1, 0.4)
	vault_pod = Intro.build_pod()
	var gv: GlimBot = vault_pod.get_node_or_null(GlimDirector.STUCK_NAME) as GlimBot
	if gv:  # [v4calm] in the ark he's awake, perched on Lumi's pod; dark only after the fall
		gv.broken = false
	(vault_pod.get_node("Scorch") as Node3D).visible = false
	vault_pod.position = Vector3(0, 0, 3.7)
	root.add_child(vault_pod)
	EscapePod.set_open(vault_pod, true)
	var bay_lamp := OmniLight3D.new()
	bay_lamp.light_color = Color(1.0, 0.7, 0.4)
	bay_lamp.light_energy = 1.2
	bay_lamp.omni_range = 3.0
	bay_lamp.position = Vector3(0, 2.6, 3.0)
	root.add_child(bay_lamp)
	# Lights: green from the tray, cool cyan bounce, a soft key.
	var green := OmniLight3D.new()
	green.light_color = Color(0.55, 1.0, 0.6)
	green.light_energy = 1.6
	green.omni_range = 3.5
	green.position = Vector3(0, 1.3, 0)
	root.add_child(green)
	_vault_lights.append(green)
	for k: int in 3:
		var o := OmniLight3D.new()
		var a: float = TAU * k / 3.0 + 0.4
		o.light_color = CradleShip.CYAN
		o.light_energy = 0.9
		o.omni_range = 6.0
		o.position = Vector3(cos(a) * 3.0, 3.2, sin(a) * 3.0)
		root.add_child(o)
		_vault_lights.append(o)
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 1.2
	key.omni_range = 6.0
	key.shadow_enabled = true
	key.position = Vector3(-1.5, 3.4, -2.2)
	root.add_child(key)
	alarm_light = SpotLight3D.new()
	alarm_light.light_color = CradleShip.ALARM
	alarm_light.light_energy = 0.0
	alarm_light.spot_range = 9.0
	alarm_light.spot_angle = 38.0
	alarm_light.position = Vector3(0, 4.2, 0)
	root.add_child(alarm_light)
	lumi = PatchModel.new()
	root.add_child(lumi)
	lumi.position = Vector3(0, 0.15, -1.1)
	lumi.rotation.y = 0.0  # faces -Z by default; turned toward the tray by the cinematic


## A small white tray of seedlings: dark soil and a dozen bright green sprouts.
static func build_tray() -> Node3D:
	var t := Node3D.new()
	t.name = "SeedTray"
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.88)
	white.roughness = 0.3
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.17, 0.11, 0.07)
	soil.roughness = 1.0
	var leaf := Mats.lamp(Color(0.45, 1.0, 0.4), 0.9)
	leaf.albedo_color = Color(0.3, 0.75, 0.25)
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
	for i: int in 4:
		for j: int in 3:
			var p := Vector3(-0.21 + i * 0.14, 0.11, -0.12 + j * 0.12)
			var stem := MeshInstance3D.new()
			stem.mesh = ProcMesh.cyl(0.006, 0.008, 0.08, 5)
			stem.material_override = leaf
			stem.position = p + Vector3(0, 0.04, 0)
			t.add_child(stem)
			for s: float in [-1.0, 1.0]:
				var lf := MeshInstance3D.new()
				lf.mesh = ProcMesh.sphere(0.028, 8, 4)
				lf.material_override = leaf
				lf.scale = Vector3(1.0, 0.35, 0.6)
				lf.position = p + Vector3(s * 0.025, 0.085, 0)
				lf.rotation.z = s * 0.4
				t.add_child(lf)
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
	_sets["space"].add_child(n)
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
	n.position = a
	n.look_at_from_position(a, b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	var tw := n.create_tween()
	tw.tween_property(n, "position", b, dur)
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


## Soft puffs (venting air, smoke, heat) drifting along vel. They swell from small, and fade.
func puff(pos: Vector3, vel: Vector3, col: Color = Color(0.9, 0.92, 0.95, 0.5), size_: float = 1.0) -> void:
	var holder: Node3D = _sets[_set] if _sets.has(_set) else _sets["space"]
	var p := MeshInstance3D.new()
	p.mesh = ProcMesh.sphere(0.5 * size_, 12, 8)
	var m: ShaderMaterial = puff_mat(Color(col.r, col.g, col.b, 0.0))
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	p.global_position = pos
	p.scale = Vector3.ONE * 0.45
	_fx.append({"node": p, "vel": vel, "spin": Vector3.ZERO, "life": 1.6, "life0": 1.6, "grow": 1.5 * size_, "fade": m, "col": col})


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
	# Vault alarm: a sweeping red beacon and the cyan lights breathing toward red.
	if alarm_light:
		alarm_light.light_energy = _alarm * 9.0
		alarm_light.rotation = Vector3(-0.9, _t * 3.4, 0)
		for i: int in _vault_lights.size():
			_vault_lights[i].light_color = (Color(0.55, 1.0, 0.6) if i == 0 else CradleShip.CYAN).lerp(CradleShip.ALARM, _alarm * (0.6 + 0.3 * sin(_t * 4.2)))
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
