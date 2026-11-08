class_name KitLineupItems
extends RefCounted
## [kit] What the lineup scene shows. Each item: {name, span, height, dist, build: Callable(state) -> Node3D}.


static func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"name": "swatches", "span": 9.0, "height": 2.0, "dist": 11.0, "build": swatches})
	out.append({"name": "wall", "span": 9.0, "height": 4.0, "dist": 15.0, "build": wall})
	return out


## Material swatches: every paint colour on a bevelled box, plus steel / rusty / concrete /
## hazard / rubber / glass / trims on cylinders, all on a ground patch.
static func swatches(state: String) -> Node3D:
	var root := Node3D.new()
	root.add_child(KitMesh.ground_patch(Vector2(7, 5), state, 3))
	var b := KitMesh.Builder.new(5)
	var names: Array = KitMat.PALETTE.keys()
	for k: int in names.size():
		var x: float = -2.75 + (k % 6) * 1.1
		var z: float = -1.2 + (k / 6) * 1.2
		b.box_on("paint:" + str(names[k]), Vector3(0.8, 0.8, 0.8), Vector3(x, 0.08, z), Vector3(0, 12, 0), 0.08)
	var cyls: PackedStringArray = ["steel", "dark_steel", "rusty", "concrete", "hazard", "rubber", "glass", "trim:warm", "trim:cool"]
	for k: int in cyls.size():
		var x: float = -3.0 + k * 0.75
		b.cyl(cyls[k], 0.28, 0.9 if not cyls[k].begins_with("trim") else 0.5, KitMesh.xf(Vector3(x, 0.08, 1.4)), 0.06, 20)
	root.add_child(KitMesh.instance(b, state, state != "broken"))
	return root


static func wall(state: String) -> Node3D:
	var root := Node3D.new()
	root.add_child(KitMesh.ground_patch(Vector2(8, 4), state, 7))
	var b := KitMesh.Builder.new(9)
	var broken: bool = state == "broken"
	KitMesh.panel_wall(b, 7.0, 3.6, KitMesh.xf(Vector3(-3.5, 0.08, -0.8)), {
		"key": "paint:main", "key2": "paint:accent", "missing": 0.25 if broken else 0.0,
		"tilt": 1.0 if broken else 0.0, "trim": "trim:cool", "hazard": true})
	b.decal("label_hub", Vector2(1.6, 0.4), KitMesh.xf(Vector3(0, 2.6, -0.62)))
	b.decal("num_01", Vector2(0.7, 0.7), KitMesh.xf(Vector3(-2.4, 1.6, -0.62)))
	var mi := KitMesh.instance(b, state, not broken, {"main": "cream", "accent": "teal", "broken_main": "#8a8274"})
	root.add_child(mi)
	return root
