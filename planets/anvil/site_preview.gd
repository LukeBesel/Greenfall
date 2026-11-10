class_name AnvilSitePreview
extends Node3D
## [planet-anvil] Light preview of one Anvil site prefab: environment, Anvil sky grade and both suns
## (shared SkyDirector + BinarySun), a dust backdrop and the site, without loading the game world.
##   godot --path . res://planets/anvil/site_preview.tscn -- --anvil-site=id,stage,restoration
##     --planet-view=x,y,z,lx,ly,lz[,fov] --time=0.4 [--quality=1 --shot=... --shot-delay=S --quit-after=S]
## Properties named like the slice's (_env, _sun, sky_director) so AnvilEnv's sky code works here.

var _env: Environment
var _sun: DirectionalLight3D
var sky_director: SkyDirector
var _kit: AnvilEnv
var _r: float = 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_coefficient = 2.4
	sm.mie_eccentricity = 0.82
	sm.turbidity = 6.0
	sm.sun_disk_scale = 1.2
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.015
	env.glow_hdr_threshold = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 140.0
	_sun.light_angular_distance = 0.6
	add_child(_sun)
	Settings.apply_render_quality(env, get_viewport())
	Settings.apply_sun_quality(_sun)
	sky_director = SkyDirector.new()
	add_child(sky_director)
	sky_director.setup(env, _sun)
	sky_director.time_of_day = DevHooks.get_f("time", 0.4)
	sky_director.frozen = true
	var a: PackedStringArray = DevHooks.get_s("anvil-site", "foundry_yard,1,0").split(",")
	var stage: int = int(a[1]) if a.size() > 1 else 1
	_r = clampf(float(a[2]) if a.size() > 2 else 0.0, 0.0, 1.0)
	_r = maxf(_r, AnvilSites.eff(stage, _r))
	# Anvil's sky, suns and night floor through a world-less kit.
	_kit = AnvilEnv.kit()
	_kit.world = self
	add_child(_kit)
	_kit._sky()
	var back := MeshInstance3D.new()
	back.name = "Backdrop"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	back.mesh = pm
	back.position.y = -0.22
	back.material_override = _kit.terrain_mat
	add_child(back)
	var site_root := Node3D.new()
	site_root.name = "Site"
	add_child(site_root)
	AnvilSites.build(site_root, a[0], stage, _r if a.size() > 2 else 0.0)
	var v: PackedStringArray = DevHooks.get_s("planet-view", "0,26,48,0,4,-18,60").split(",")
	var cam := Camera3D.new()
	cam.far = 2600.0
	cam.fov = float(v[6]) if v.size() > 6 else 60.0
	add_child(cam)
	cam.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
	cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
	cam.current = true
	print("[planet-anvil] site preview %s stage %d restoration %.2f" % [a[0], stage, _r])


func _process(_delta: float) -> void:
	# After SkyDirector (tree order): Anvil's grade for this restoration, its suns and night floor.
	sky_director.grade = _kit.sky_grade(_r)
	sky_director.grade_amt = 1.0
	sky_director.clear_bonus = 0.85 * _r
	_kit._update_suns()
	var sk: Dictionary = _kit.entry.get("sky", {})
	(_env.sky.sky_material as PhysicalSkyMaterial).rayleigh_coefficient = lerpf(float(sk.get("rayleigh_coef", 1.4)), float((_kit.entry.get("restored", {}) as Dictionary).get("rayleigh_coef", 2.6)), smoothstep(0.1, 0.95, _r))
