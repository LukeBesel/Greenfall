extends Node3D
## [world2] Dev staging for a bale close-up: --bale-shot lines up freshly made bales of different
## contents (plastic, mixed, metal, overstuffed, a stacked pair) in front of the camera, dropped from
## a little height so they settle physically, plus one dropped onto the nearest junk mound.
## Used with --shot (see tools/shot.sh). --bale-shot=mound frames the mound bale instead.

var world: Node


func _ready() -> void:
	await get_tree().physics_frame
	var p: Node3D = world.patch
	var base := Vector3(1.2, 0.0, 1.0)
	var specs: Array = [
		[{"plastic": 7.0, "paper": 2.0}, false],
		[{"metal": 4.0, "plastic": 3.0, "glass": 2.0, "rubber": 1.0}, false],
		[{"metal": 9.5}, false],
		[{"plastic": 6.0, "rubber": 3.0, "electronics": 2.5}, true],
		[{"paper": 5.0, "glass": 4.0}, false],
	]
	var cubes: Array[JunkCube] = []
	for i: int in specs.size():
		var contents: Dictionary = specs[i][0]
		var cap: float = 10.0 if not bool(specs[i][1]) else 9.0
		var info: Dictionary = Economy.evaluate_cube(contents, cap)
		var c: JunkCube = JunkCube.create(info["value"], info)
		world.add_cube(c)
		c.global_position = base + Vector3((i % 3) * 0.85, 0.6 + (1.2 if i >= 3 else 0.0), -float(i / 3) * 0.9)
		c.rotation.y = 0.35 * i
		cubes.append(c)
	# One onto a junk mound (the "bale in the ground" case).
	var f: HexField = world.field
	var best := Vector4.ZERO
	var bd: float = INF
	for h: int in f.hex_count():
		for pile: Vector4 in f.hex_piles[h]:
			var d: float = Vector2(pile.x, pile.y).length()
			if d < bd and f.hex_clean[h] == 0:
				bd = d
				best = pile
	if bd < INF:
		var info2: Dictionary = Economy.evaluate_cube({"metal": 5.0, "plastic": 4.0}, 10.0)
		var mc: JunkCube = JunkCube.create(info2["value"], info2)
		world.add_cube(mc)
		mc.global_position = Vector3(best.x + 0.4, best.w + 1.5, best.y)
		print("[bale-shot] mound bale over pile %s" % str(best))
		if DevHooks.get_s("bale-shot", "") == "mound":
			p.global_position = Vector3(best.x + 2.6, 0.2, best.y + 2.6)
			base = Vector3(best.x, 0.0, best.y)
	p.global_position = base + Vector3(-1.6, 0.2, 2.2) if DevHooks.get_s("bale-shot", "") != "mound" else p.global_position
	var cam: Node = world.cam
	var to: Vector3 = base + Vector3(0.85, 0, -0.4) - p.global_position
	cam.set("yaw", atan2(-to.x, -to.z))
	cam.set("distance", 2.6)
	cam.set("pitch", -0.32)
	if cam.has_method("snap"):
		cam.call("snap")
	await get_tree().create_timer(3.0).timeout
	for c: JunkCube in cubes:
		print("[bale-shot] bale at %s size %.2f sleeping=%s colors=%s" % [str(c.global_position.snapped(Vector3.ONE * 0.01)), c.size, str(c.sleeping), str(c.info.get("colors", []))])
