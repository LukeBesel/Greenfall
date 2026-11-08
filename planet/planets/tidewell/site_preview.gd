extends Node3D
## [planet-tidewell] Standalone preview of one Tidewell site prefab (sites.gd), for renders and
## checks without a district: sky, the binary suns, the site on its own sea patch, Lumi for scale.
##   godot --path . res://planet/planets/tidewell/site_preview.tscn -- --site=hub_raft
##     --site-stage=0..2 --site-restore=0..1 --site-cam=dist,pitch_deg,yaw_deg[,fov[,target_y]]
##     --site-lumi=x,z (Lumi hovering there) --time=0..1 (sun) --shot=... --shot-delay=S --quit-after=S

var site: TideSite
var sun: DirectionalLight3D
var binary: BinarySun
var _lumi: Node3D
var _t: float = 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_color = Color(0.2, 0.46, 1.0)
	sm.mie_color = Color(1.0, 0.95, 0.88)
	sm.turbidity = 2.6
	sm.mie_coefficient = 0.002
	sm.sun_disk_scale = 1.2
	sm.ground_color = Color(0.2, 0.32, 0.38)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.fog_enabled = true
	env.fog_density = 0.0006
	env.fog_light_color = Color(0.7, 0.84, 0.98)
	env.fog_aerial_perspective = 0.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	var tod: float = DevHooks.get_f("time", 0.4)
	var day_t: float = (tod - 0.25) / 0.5
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI) * 70.0
	sun.rotation_degrees = Vector3(-maxf(elev, 4.0), -30.0 + day_t * 60.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 2.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	Settings.apply_render_quality(env, get_viewport())
	Settings.apply_sun_quality(sun)
	binary = BinarySun.new()
	add_child(binary)
	binary.setup("tidewell", sm)
	var id: String = DevHooks.get_s("site", "hub_raft")
	site = TideSite.place(id, self, int(DevHooks.get_f("site-stage", 0.0)), DevHooks.get_f("site-restore", 0.0), {"water_radius": 420.0})
	if DevHooks.has("site-lumi"):
		var lp: PackedStringArray = DevHooks.get_s("site-lumi", "0,0").split(",")
		_lumi = PatchModel.new()
		add_child(_lumi)
		_lumi.position = Vector3(float(lp[0]), float(lp[2]) if lp.size() > 2 else 0.36, float(lp[1]))
		_lumi.rotation.y = float(lp[3]) if lp.size() > 3 else 0.0
	var cam := Camera3D.new()
	var c: PackedStringArray = DevHooks.get_s("site-cam", "70,25,30,55,2").split(",")
	var dist: float = float(c[0])
	var pitch: float = deg_to_rad(float(c[1]) if c.size() > 1 else 25.0)
	var yaw: float = deg_to_rad(float(c[2]) if c.size() > 2 else 30.0)
	cam.fov = float(c[3]) if c.size() > 3 else 55.0
	var target := Vector3(float(c[5]) if c.size() > 5 else 0.0, float(c[4]) if c.size() > 4 else 2.0, float(c[6]) if c.size() > 6 else 0.0)
	cam.far = 3000.0
	add_child(cam)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(target, Vector3.UP)
	cam.current = true
	print("[site-preview] %s stage=%d restore=%.2f" % [id, site.stage, site.restore])


func _process(delta: float) -> void:
	_t += delta
	if binary:
		sun.light_energy = 2.8
		binary.update(sun, 1.0)
	if _lumi:
		_lumi.position.y = 0.36 + sin(_t * 1.7) * 0.05
