extends Node3D
## [p_seas] Standalone preview of one Rime site prefab (rime_site.gd), for renders and checks
## without a district: a thin cold sky, weak suns, the site on its own ice patch, Lumi for scale.
## --time below 0.25 or above 0.75 is night: giantshine (cool fill) instead of the suns.
##   godot --path . res://planets/rime/site_preview.tscn -- --site=hub_camp
##     --site-stage=0..2 --site-restore=0..1 --site-cam=dist,pitch_deg,yaw_deg[,fov[,target_y]]
##     --site-lumi=x,z (Lumi hovering there) --time=0..1 (sun) --shot=... --shot-delay=S --quit-after=S

var site: RimeHubSite
var sun: DirectionalLight3D
var _lumi: Node3D
var _t: float = 0.0
var _night: bool = false


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_color = Color(0.12, 0.28, 0.75)
	sm.rayleigh_coefficient = 1.2
	sm.mie_color = Color(0.9, 0.95, 1.0)
	sm.turbidity = 1.4
	sm.mie_coefficient = 0.002
	sm.sun_disk_scale = 1.2
	sm.ground_color = Color(0.5, 0.6, 0.7)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.fog_enabled = true
	env.fog_density = 0.0006
	env.fog_light_color = Color(0.72, 0.82, 0.96)
	env.fog_aerial_perspective = 0.5
	env.volumetric_fog_density = 0.0006  # (the presets turn volumetric fog on; its default is a pea-souper)
	env.volumetric_fog_albedo = Color(0.85, 0.9, 0.96)
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_sky_affect = 0.1
	env.fog_sky_affect = 0.15
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
	if tod < 0.24 or tod > 0.76:
		# Night: giantshine, a cool broad light from the gas giant, and a bluish ambient.
		sun.rotation_degrees = Vector3(-38.0, 140.0, 0.0)
		sun.light_color = Color(0.62, 0.74, 1.0)
		sun.light_energy = 0.9
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.015, 0.025, 0.06)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.3, 0.4, 0.62)
		env.ambient_light_energy = 0.55
		env.tonemap_exposure = 1.5
		env.glow_intensity = 0.7
		env.fog_light_color = Color(0.1, 0.14, 0.24)
		_night = true
	var id: String = DevHooks.get_s("site", "hub_camp")
	site = RimeHubSite.place(id, self, int(DevHooks.get_f("site-stage", 0.0)), DevHooks.get_f("site-restore", 0.0))
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
	if _night:
		site.set_night(1.0)
	print("[site-preview] %s stage=%d restore=%.2f" % [id, site.stage, site.restore])


func _process(delta: float) -> void:
	_t += delta
	if _lumi:
		_lumi.position.y = 0.36 + sin(_t * 1.7) * 0.05
