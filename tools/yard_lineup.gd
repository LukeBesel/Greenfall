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
	"bins": [Vector3(0.0, 4.4, -18.0), Vector3(0.0, 0.8, -26.5)],
}
const BOARD_POS := Vector3(-3.6, 0, 2.2)  # scenes/slice.gd

var _shots: PackedStringArray
var _i: int = -1
var _wait: int = 0
var _out: String
var _cam: Camera3D


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/yard/lineup")
	_shots = DevHooks.get_s("shots", "yard,shack,bench,locker,bins").split(",")
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
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = AssetLib.pbr_material("dirty_concrete", 0.25, Color(0.7, 0.62, 0.52), true)
	add_child(ground)
	var slab := MeshInstance3D.new()  # stands in for StreetDressing's painted yard slab
	var sp := PlaneMesh.new()
	sp.size = Vector2(17, 17)
	slab.mesh = sp
	slab.position.y = 0.012
	slab.material_override = AssetLib.pbr_material("concrete_floor_worn_001", 0.3, Color(0.85, 0.83, 0.8), true)
	add_child(slab)
	_build_yard()
	_build_bins()
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


func _build_yard() -> void:
	_board(BOARD_POS + Vector3(-1.3, 0, 0), true, true)
	_board(Vector3(20.0, 0, 0.0), false, false)
	var lk: MeshInstance3D = YardArt.locker().mi(0.12, "Locker")  # systems/camp/locker_cabinet.gd
	lk.position = Vector3(-6.4, 0, 4.6)
	lk.rotation.y = deg_to_rad(90.0)
	add_child(lk)
	YardArt.set_powered(lk, true)


func _build_bins() -> void:
	for l: int in range(1, 6):
		var d := Depot.new()
		add_child(d)
		d.position = Vector3(-10.0 + (l - 1) * 5.0, 0, -25.0)
		d.process_mode = Node.PROCESS_MODE_DISABLED
		d._build_body(l)
		YardArt.set_powered(d._scale_post, l >= 2)


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
