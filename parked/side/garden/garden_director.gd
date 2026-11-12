class_name GardenDirector
extends Node
## Wires Garden Mode into the world (one call from scenes/slice_orbit.gd): the placement screen
## (ui/garden_placer.gd) over the current hub's decorations (systems/decor.gd, one Decor node per
## hub in the HubFrame). Dev hooks:
##   --open=garden        open Garden Mode at start (--garden-type=ID selects a decoration,
##                        --garden-cell=x,z moves the cursor)
##   --garden             Garden Mode unlocked here;  --decor-sample places a small garden near the base
##   --garden-cam=x,z,yaw,dist,pitch  fixed camera for Garden shots

var world: Node
var decor: Decor
var placer: GardenPlacer


static func attach(slice: Node) -> GardenDirector:
	var d := GardenDirector.new()
	d.name = "GardenDirector"
	d.world = slice
	slice.add_child(d)
	d._setup()
	return d


static func of(slice: Node) -> GardenDirector:
	return slice.get_node_or_null("GardenDirector") as GardenDirector if slice else null


func _setup() -> void:
	# Each hub's Decor lives in the orbit's HubFrame; the placer follows it.
	var hf: HubFrame = (world.orbit as SliceOrbit).hub_frame
	decor = hf.node("Decor") as Decor
	placer = GardenPlacer.new()
	placer.name = "GardenPlacer"
	placer.world = world
	placer.decor = decor
	world.add_child(placer)
	hf.hub_changed.connect(_on_hub_changed)
	if DevHooks.has("decor-sample") and decor:
		_decor_sample.call_deferred()
	if DevHooks.get_s("open", "") == "garden":
		_dev_open.call_deferred()
	elif DevHooks.has("garden-cam"):
		_garden_cam.call_deferred()


func open_garden() -> bool:
	return placer.open() if placer else false


func _on_hub_changed(_hub: int) -> void:
	decor = (world.orbit as SliceOrbit).hub_frame.node("Decor") as Decor
	placer.set_decor(decor)


func _dev_open() -> void:
	placer.open()
	if DevHooks.has("garden-type"):
		placer.select(DevHooks.get_s("garden-type", "bench"))
	if DevHooks.has("garden-cell"):
		var gc: PackedStringArray = DevHooks.get_s("garden-cell", "0,12").split(",")
		placer.move_to(Vector2i(int(gc[0]), int(gc[1])))
	_garden_cam()


## Dev: a small finished garden near the base (shots).
func _decor_sample() -> void:
	var plan: Array = sample_plan()
	var placed: int = 0
	for p: Array in plan:
		if decor.place(str(p[0]), Vector2i(int(p[1]), int(p[2])), int(p[3]), false, false):
			placed += 1
	print("[garden] decor sample: %d / %d placed, charm %.1f" % [placed, plan.size(), decor.charm()])


## A little plaza south of the base: a fountain with benches, lamps, beds and a path.
static func sample_plan() -> Array:
	var out: Array = [["fountain", -1, 13, 0], ["lumi_sculpture", -1, 18, 0], ["bench", -4, 13, 1], ["bench", 3, 13, 1],
		["lamp", -4, 11, 0], ["lamp", 3, 11, 0], ["lamp", -4, 16, 0], ["lamp", 3, 16, 0],
		["flower_bed", -3, 10, 0], ["flower_bed", 1, 10, 0], ["planter", -2, 16, 0], ["planter", 1, 16, 0],
		["bird_bath", 5, 14, 0], ["statue", 6, 17, 0], ["wren_kite", -6, 14, 0]]
	for z: int in range(9, 21):
		out.append(["path", 0 if z < 12 or z > 15 else -2, z, 0])
	return out


func _garden_cam() -> void:
	if not DevHooks.has("garden-cam"):
		return
	var v: PackedStringArray = DevHooks.get_s("garden-cam", "0,14,3.14,9,-0.5").split(",")
	world.shot_camera(Vector2(float(v[0]), float(v[1])), float(v[2]) if v.size() > 2 else 0.0,
		float(v[3]) if v.size() > 3 else 9.0, float(v[4]) if v.size() > 4 else -0.5)
