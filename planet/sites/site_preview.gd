extends Node3D
## [orbD] Site prefab preview and report (no globe, no district): builds PlanetEnvs.build_site
## prefabs on a plain ground disc, under a sun and sky, and prints a [site] line per prefab.
##   godot --headless --path . res://planet/sites/site_preview.tscn -- --sites=all --quit-after=1
##   xvfb-run ... godot --path . --rendering-driver opengl3 --resolution 960x540 \
##     res://planet/sites/site_preview.tscn -- --site=verdance/ruin_block --stage=1 \
##     --site-cam=dist,pitch,yaw --shot=screenshots/orbD/x.png --shot-delay=20 --quit-after=24
## --site=planet/id (default verdance/start_yard), --sites=all (every planet's hub sites side by
## side, report only), --stage=1..5, --restore=0..1, --hub=N (hub index: seeds the ruin blocks),
## --tilt (build the site on a tilted frame, like a site far round the globe: checks site_inv).

var prefabs: Array[SitePrefab] = []
var _cam: Camera3D
var _t: float = 0.0
var _orbit: bool = false


func _ready() -> void:
	_env()
	var stage: int = int(DevHooks.get_f("stage", 1.0))
	var rest: float = DevHooks.get_f("restore", 0.0)
	var list: Array = []
	if DevHooks.get_s("sites", "") == "all":
		for pid: String in ["verdance", "rime", "anvil", "tidewell", "ochre"]:
			for d: Dictionary in SiteBuilders.sites_of(pid):
				list.append([pid, str(d["id"])])
	else:
		var s: PackedStringArray = DevHooks.get_s("site", "verdance/start_yard").split("/")
		list.append([s[0], s[1] if s.size() > 1 else SiteBuilders.site_for_hub(s[0], 0)])
	var x: float = 0.0
	var tilt: bool = DevHooks.has("tilt")
	for e: Array in list:
		var sr := Node3D.new()
		add_child(sr)
		var xf := Transform3D(Basis(), Vector3(x, 0, 0))
		if tilt:
			xf = Transform3D(Basis(Vector3(1, 0, 1).normalized(), 0.9), Vector3(x, 0, 0))
		var t0: int = Time.get_ticks_msec()
		var p: SitePrefab = PlanetEnvs.build_site(sr, {"planet": e[0], "prefab": e[1], "transform": xf,
			"hub_index": int(DevHooks.get_f("hub", 0.0 if e[1] == "start_yard" else 1.0)), "seed": 4471}, stage, rest)
		if not p.is_built:
			await p.rebuilt
		prefabs.append(p)
		var tris: int = 0
		for mi: Node in p.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m is ArrayMesh:
				for si: int in m.get_surface_count():
					tris += (m as ArrayMesh).surface_get_array_len(si) / 3
		print("[site] %s/%s built in %d ms: %d nodes, ~%dk tris, %d collision shapes, anchors %s" % [e[0], e[1],
			Time.get_ticks_msec() - t0, p.find_children("*", "", true, false).size(), tris / 1000,
			p.find_children("*", "CollisionShape3D", true, false).size(), ",".join(p.anchor_names())])
		x += 220.0
	if prefabs.size() == 1:
		SiteManager.point_shaders_at(prefabs[0])
		_place_cam(prefabs[0])


func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sm.ground_bottom_color = Color(0.25, 0.22, 0.2)
	sm.ground_horizon_color = Color(0.6, 0.6, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 600)
	g.mesh = pm
	g.position = Vector3(500, -0.02, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.33, 0.27)
	gm.roughness = 0.95
	g.material_override = gm
	if not DevHooks.has("tilt"):
		add_child(g)
	else:
		g.free()


func _place_cam(p: SitePrefab) -> void:
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	var c: PackedFloat64Array = DevHooks.get_s("site-cam", "70,28,35").split_floats(",")
	var dist: float = c[0]
	var pitch: float = deg_to_rad(c[1] if c.size() > 1 else 28.0)
	var yaw: float = deg_to_rad(c[2] if c.size() > 2 else 35.0)
	var target: Vector3 = p.global_transform * Vector3(0, 3, 0)
	var up: Vector3 = p.global_transform.basis.y
	var off: Vector3 = p.global_transform.basis * (Vector3(sin(yaw), 0, cos(yaw)) * cos(pitch) * dist + Vector3(0, sin(pitch) * dist, 0))
	_cam.look_at_from_position(target + off, target, up)
	_cam.current = true
