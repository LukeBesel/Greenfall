extends Node3D
## [yard] Close-up lineup of the yard and Hub-build art (systems/camp/yard_art.gd) without loading
## a district:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 960x540 \
##     res://tools/yard_lineup.tscn -- --out=screenshots/yard/b1 [--shots=yard,bins] [--night]
## Writes <out>_<shot>.png per shot. Shots:
##   yard   the lean-to with the fixed bench, a broken bench beside it, generator, lamp, trash bin L1
##   bins   trash bin levels 1-5 on their plates

const SHOTS: Dictionary = {
	"yard": [Vector3(7.5, 7.5, 11.0), Vector3(-1.5, 0.3, -0.5)],
	"shack": [Vector3(1.2, 2.6, 4.2), Vector3(-4.6, 1.0, 1.4)],
	"bench": [Vector3(23.2, 2.2, 2.6), Vector3(20.0, 0.8, 0.0)],
	"locker": [Vector3(-4.0, 1.9, 7.4), Vector3(-6.4, 1.1, 4.6)],
	"builds": [Vector3(40.5, 3.6, 6.8), Vector3(40.5, 0.6, 0.0)],
	"stations": [Vector3(66.0, 6.0, 13.0), Vector3(66.0, 0.8, 0.0)],
	"tower": [Vector3(90.0, 4.5, 15.0), Vector3(90.0, 3.0, 0.0)],
	"fabricator": [Vector3(115.5, 3.6, 6.5), Vector3(114.0, 1.1, -0.3)],
	"bins": [Vector3(0.0, 4.4, -18.0), Vector3(0.0, 0.8, -26.5)],
	# [v6yard] the rebuilt machines, the picture signs, the pod and the six hub landmarks
	"baler": [Vector3(70.4, 3.4, 6.2), Vector3(66.2, 1.9, -0.8)],
	"baler_back": [Vector3(62.0, 3.6, -7.0), Vector3(66.0, 1.8, -1.0)],
	"belt": [Vector3(61.0, 3.6, 5.6), Vector3(56.2, 0.9, -0.6)],
	"signs": [Vector3(130.0, 2.6, 7.5), Vector3(130.0, 1.6, 0.0)],
	"pod": [Vector3(152.5, 2.4, 5.5), Vector3(150.0, 1.3, 0.0)],
	"lm_water_tower": [Vector3(16.0, 9.0, 232.0), Vector3(0.0, 9.0, 200.0)],
	"lm_windpump": [Vector3(74.0, 7.0, 226.0), Vector3(60.0, 7.0, 200.0)],
	"lm_crane": [Vector3(136.0, 9.0, 230.0), Vector3(120.0, 7.5, 200.0)],
	"lm_radio_mast": [Vector3(200.0, 12.0, 244.0), Vector3(180.0, 14.0, 200.0)],
	"lm_ferris_wheel": [Vector3(255.0, 8.0, 234.0), Vector3(240.0, 10.5, 200.0)],
	"lm_smokestack": [Vector3(320.0, 10.0, 243.0), Vector3(300.0, 13.0, 200.0)],
	"lm_kiosk": [Vector3(6.5, 2.2, 211.0), Vector3(4.4, 1.2, 204.0)],
}
const BOARD_POS := Vector3(-3.6, 0, 2.2)  # scenes/slice.gd

var _shots: PackedStringArray
var _i: int = -1
var _wait: int = 0
var _out: String
var _cam: Camera3D


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/yard/lineup")
	_shots = DevHooks.get_s("shots", "yard,shack,bench,locker,builds,stations,tower,fabricator,bins").split(",")
	if _shots.size() == 1 and _shots[0] == "v6":  # [v6yard] everything this wave rebuilt
		_shots = PackedStringArray(["baler", "baler_back", "belt", "signs", "pod", "lm_water_tower", "lm_windpump", "lm_crane", "lm_radio_mast", "lm_ferris_wheel", "lm_smokestack", "lm_kiosk"])
	var night: bool = DevHooks.has("night")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.05, 0.07, 0.14) if night else Color(0.42, 0.58, 0.82)
	sm.sky_horizon_color = Color(0.15, 0.16, 0.22) if night else Color(0.85, 0.8, 0.72)
	sm.ground_horizon_color = Color(0.6, 0.55, 0.48)
	sm.ground_bottom_color = Color(0.4, 0.35, 0.3)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35 if night else 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.15 if night else 2.4
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	ground.mesh = pm
	ground.material_override = AssetLib.pbr_material("dirty_concrete", 0.25, Color(0.7, 0.62, 0.52), true)
	add_child(ground)
	var slab := MeshInstance3D.new()  # stands in for StreetDressing's painted yard slab
	var sp := PlaneMesh.new()
	sp.size = Vector2(17, 17)
	slab.mesh = sp
	slab.position.y = 0.012
	slab.material_override = AssetLib.pbr_material("concrete_floor_worn_001", 0.3, Color(0.85, 0.83, 0.8), true)
	slab.name = "YardSlab"
	dressing = Node3D.new()
	dressing.name = "Dressing"
	add_child(dressing)
	dressing.add_child(slab)  # YardArt hides it under the kit ground patch
	_build_yard()
	_build_builds()
	_build_stations()
	_build_towers()
	_build_bins()
	_build_v6()
	if DevHooks.has("hub-level"):
		YardArt.ground_for_level(self, int(DevHooks.get_f("hub-level", 1.0)))
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true


## The same node layout scenes/slice.gd _build_board makes (the parts YardArt.dress_board restyles).
## The same node layout scenes/slice.gd _build_board makes (the parts YardArt.dress_board restyles),
## at the real yard positions when `full`.
func _board(shack_at: Vector3, bench_ok: bool, full: bool) -> void:
	var bits: Dictionary = {}
	var shack := Node3D.new()
	shack.position = shack_at
	shack.rotation_degrees = Vector3(0, 90, 0)
	add_child(shack)
	for k: String in ["frame", "roof", "back", "side"]:
		var m := MeshInstance3D.new()
		shack.add_child(m)
		bits[k] = m
		m.visible = full
	(bits["roof"] as Node3D).position = Vector3(0, 2.3, -0.05)
	(bits["roof"] as Node3D).rotation_degrees = Vector3(-9, 0, 2)
	(bits["back"] as Node3D).position = Vector3(0, 1.15, -1.15)
	(bits["side"] as Node3D).position = Vector3(-1.62, 0.8, -0.45)
	var bench := Node3D.new()
	bench.position = Vector3(0, 0, -0.65)
	shack.add_child(bench)
	bench.add_child(MeshInstance3D.new())
	for spec: Array in [["metal_toolbox", Vector3(-0.6, 0.95, 0.0), 0.2], ["clipboard", Vector3(0.35, 0.955, 0.1), 0.0], ["oil_tin", Vector3(0.8, 0.95, -0.2), 0.0], ["metal_jerrycan", Vector3(0.7, 0.26, 0.0), 1.2]]:
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh_lite(spec[0], 3000)
		mi.position = spec[1]
		mi.rotation.y = spec[2]
		bench.add_child(mi)
	bits["bench"] = bench
	if full:
		var bulb := MeshInstance3D.new()
		bulb.position = Vector3(0, 2.15, -0.4)
		shack.add_child(bulb)
		bits["bulb"] = bulb
		var lamp := SpotLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.65)
		lamp.light_energy = 2.0
		lamp.spot_range = 3.5
		lamp.spot_angle = 50.0
		lamp.position = Vector3(0, 2.2, -0.4)
		lamp.rotation_degrees = Vector3(-90, 0, 0)
		shack.add_child(lamp)
		var sl := MeshInstance3D.new()
		sl.position = Vector3(4.2, 0, -3.0)
		add_child(sl)
		var light := SpotLight3D.new()
		light.light_color = Color(1.0, 0.82, 0.6)
		light.spot_range = 12.0
		light.spot_angle = 55.0
		light.shadow_enabled = true
		light.position = sl.position
		light.rotation_degrees = Vector3(-90, 0, 0)
		add_child(light)
		bits["street_lamp"] = sl
		bits["street_light"] = light
		var gen := MeshInstance3D.new()
		add_child(gen)
		bits["generator"] = gen
		var d := Depot.new()
		d.position = Vector3(0, 0, -1.8)
		add_child(d)
		d.process_mode = Node.PROCESS_MODE_DISABLED
		set("depot", d)
	YardArt.dress_board(bits, self if full else null)
	if not bench_ok:  # what camp.gd does to a broken bench
		bench.transform = bench.transform * Transform3D(Basis.from_euler(Vector3(0.06, 0.1, -0.2)), Vector3(0.15, -0.16, 0.05))
	YardArt.bench_state(bench, bench_ok, false)


var depot: Node3D  # read by YardArt.dress_board (like the slice's)
var dressing: Node3D  # holds the stand-in YardSlab (StreetDressing's)


func _build_yard() -> void:
	_board(BOARD_POS + Vector3(-1.3, 0, 0), true, true)
	_board(Vector3(20.0, 0, 0.0), false, false)
	var lk: MeshInstance3D = YardArt.locker().mi(0.12, "Locker")  # systems/camp/locker_cabinet.gd
	lk.position = Vector3(-6.4, 0, 4.6)
	lk.rotation.y = deg_to_rad(90.0)
	add_child(lk)
	YardArt.set_powered(lk, true)


## Batch 2: compost press, CD player stand, robot nursery (models only, no gameplay nodes).
func _build_builds() -> void:
	var cp: Dictionary = YardArt.composter()
	var c := Node3D.new()
	c.position = Vector3(37.5, 0, 0.5)
	c.rotation_degrees = Vector3(0, 180, 0)
	add_child(c)
	c.add_child((cp["body"] as YardArt.Kit).mi(0.2))
	for pair: Array in [["drum", Vector3(1.0, 1.1, 0)], ["head", Vector3(1.0, 1.15, -0.55)]]:
		var m: MeshInstance3D = (cp[pair[0]] as YardArt.Kit).mi(0.2)
		m.position = pair[1]
		c.add_child(m)
	var st: MeshInstance3D = YardArt.radio_stand().mi(0.15)
	st.position = Vector3(41.0, 0, 1.5)
	st.rotation_degrees = Vector3(0, -60, 0)  # front (+X) toward the camera
	add_child(st)
	YardArt.set_powered(st, true)
	var n := Node3D.new()
	n.position = Vector3(44.0, 0, -1.5)
	add_child(n)
	var g: MeshInstance3D = YardArt.nursery(Vector2(5.0, 3.4)).mi(0.15)
	n.add_child(g)
	YardArt.set_powered(g, true)
	n.add_child(YardArt.nursery_grass(Vector2(5.0, 3.4)))


## Batch 3: conveyor, auto-baler, recycler (real nodes, kitified), observatory (its model only).
func _build_stations() -> void:
	var cv := Conveyor.new()
	cv.position = Vector3(50.0, 0, 0)  # [v6yard] clear of the baler
	add_child(cv)
	cv.process_mode = Node.PROCESS_MODE_DISABLED
	var ab := AutoBaler.new()
	ab.position = Vector3(66.0, 0, -1.0)
	add_child(ab)
	ab.process_mode = Node.PROCESS_MODE_DISABLED
	var rc := Recycler.new()
	rc.position = Vector3(72.0, 0, 0)
	add_child(rc)
	rc.process_mode = Node.PROCESS_MODE_DISABLED
	var sc := Telescope.new()
	sc.data = RemoteProgress.cfg()
	sc.call("_spawn", false)
	var model: Node3D = sc.get("_model")
	sc.remove_child(model)
	add_child(model)
	model.position = Vector3(66.0, 0, -9.0)
	sc.free()


## Signal tower tiers 1-4, an air scrubber, a signal jammer.
func _build_towers() -> void:
	for t: int in range(1, 5):
		var d: Dictionary = YardArt.signal_tower(t)
		var m: MeshInstance3D = (d["kit"] as YardArt.Kit).mi(0.15)
		m.position = Vector3(84.0 + (t - 1) * 2.6, 0, 0)
		add_child(m)
		YardArt.set_powered(m, true)
	var su: MeshInstance3D = YardArt.scrubber().mi(0.15)
	su.position = Vector3(95.5, 0, 0.5)
	add_child(su)
	YardArt.set_powered(su, true)
	var fab := FabricatorModel.new()  # building: bay lit, arm posed mid-work
	fab.position = Vector3(114.0, 0, 0)
	add_child(fab)
	fab.set_building(true)
	fab.call("_pose", 1.3)
	var jb: MeshInstance3D = YardArt.jammer_base().mi(0.15)
	jb.position = Vector3(98.0, 0, 0.5)
	add_child(jb)
	var jd: MeshInstance3D = YardArt.jammer_dish().mi(0.15)
	jd.position = Vector3(98.0, 3.0, 0.5)
	add_child(jd)


func _build_bins() -> void:
	for l: int in range(1, 6):
		var d := Depot.new()
		add_child(d)
		d.position = Vector3(-10.0 + (l - 1) * 5.0, 0, -25.0)
		d.process_mode = Node.PROCESS_MODE_DISABLED
		d._build_body(l)
		YardArt.set_powered(d._scale_post, l >= 2)


## [v6yard] The picture signs on posts, the pod, and the hub landmarks (--lm-state=broken|repaired|restored).
func _build_v6() -> void:
	var ids: Array = ["workbench", "trash_bin", "baler", "belt", "composter", "signal_tower", "fabricator"]
	for i: int in ids.size():
		var sp: MeshInstance3D = MachineArt.sign_post(ids[i], 1.7).mi(0.15)
		sp.position = Vector3(130.0 + (i - 3) * 1.1, 0, 0)
		add_child(sp)
	var pod: Node3D = EscapePod.build()
	pod.position = Vector3(150.0, 0, 0)
	pod.rotation.y = PI * 0.8
	add_child(pod)
	EscapePod.set_condition(pod, int(DevHooks.get_f("pod-condition", 0.0)))
	EscapePod.set_open(pod, true, 0.0)
	var st: String = DevHooks.get_s("lm-state", "restored")
	var kinds: Array[String] = HubLandmarks.kinds()
	for i: int in kinds.size():
		var lm: HubLandmarkNode = HubLandmarks.build(kinds[i], st, 1, "verdance")
		lm.position = Vector3(i * 60.0, 0, 200.0)
		add_child(lm)


func _process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		return
	if _i >= 0:
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s_%s.png" % [_out, _shots[_i]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if img:  # null when headless
			img.save_png(path)
			print("[yard_lineup] wrote ", path)
	_i += 1
	if _i >= _shots.size():
		get_tree().quit()
		return
	var s: Array = SHOTS.get(_shots[_i], SHOTS["yard"])
	_cam.position = s[0]
	_cam.look_at(s[1])
	_wait = 12
