class_name KitLineupItems
extends RefCounted
## [kit] What the lineup scene shows. Each item: {name, span, height, dist, build: Callable(state) -> Node3D}.


static func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"name": "swatches", "span": 9.0, "height": 2.0, "dist": 11.0, "build": swatches})
	out.append({"name": "wall", "span": 9.0, "height": 4.0, "dist": 15.0, "build": wall})
	out.append({"name": "props", "span": 12.0, "height": 4.0, "dist": 17.0, "build": props})
	var spans: Dictionary = {"module_small": [11.0, 5.0], "module_medium": [14.0, 8.0], "module_large": [18.0, 8.0],
		"tower": [11.0, 14.0], "hangar": [17.0, 8.0], "tank_farm": [16.0, 7.0], "machine_housing": [12.0, 5.0]}
	for k: String in KitBuilding.KINDS:
		var sp: Array = spans[k]
		out.append({"name": k, "span": sp[0], "height": sp[1], "dist": sp[0] * 1.9,
			"build": func(st: String) -> Node3D: return KitBuilding.create(k, st, 1)})
	return out


## Every prop helper side by side.
static func props(state: String) -> Node3D:
	var root := Node3D.new()
	root.add_child(KitMesh.ground_patch(Vector2(10, 7), state, 11))
	var b := KitMesh.Builder.new(13, {}, state)
	KitProps.lamp_post(b, KitMesh.xf(Vector3(-4.2, 0, 2.4)), 4.2, state)
	KitProps.antenna(b, KitMesh.xf(Vector3(-4.0, 0, -2.0)), 4.5, state)
	KitProps.dish(b, KitMesh.xf(Vector3(-1.6, 0, -2.2), Vector3(0, 20, 0)), 1.0, state)
	KitProps.tank(b, KitMesh.xf(Vector3(1.6, 0, -2.0)), 1.0, 2.6, "paint:accent", state)
	KitProps.solar_panel(b, KitMesh.xf(Vector3(4.2, 0, -2.0)), Vector2(2.0, 1.2), state)
	KitProps.crate_stack(b, KitMesh.xf(Vector3(-1.2, 0, 1.0)), 5, state)
	KitProps.barrel(b, KitMesh.xf(Vector3(0.9, 0, 1.8)))
	KitProps.barrel(b, KitMesh.xf(Vector3(1.6, 0, 2.2)), "paint:accent", state == "broken")
	KitProps.vent(b, KitMesh.xf(Vector3(2.6, 0, 0.2)), Vector2(1.0, 0.8))
	KitProps.stairs(b, KitMesh.xf(Vector3(4.0, 0, 0.0)), 1.6, 2.4, 0.9, "paint:rail", state)
	KitProps.ladder(b, KitMesh.xf(Vector3(-2.8, 0, 0.0)), 3.0)
	KitProps.planter(b, KitMesh.xf(Vector3(0.6, 0, 3.0)), 2.0, state)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(-4.5, 0.6, 0.6), Vector3(-3.5, 0.6, 0.6), Vector3(-3.5, 2.0, 0.6), Vector3(-1.8, 2.0, -0.2)]), 0.12)
	KitProps.cable(b, Transform3D.IDENTITY, Vector3(-4.0, 4.0, -2.0), Vector3(-4.2, 3.6, 2.4), 0.6)
	KitProps.hatch(b, KitMesh.xf(Vector3(2.4, 0.08, 2.8)), Vector2(1.2, 2.2), state)
	KitProps.wind_turbine(b, KitMesh.xf(Vector3(4.6, 0, -4.6)), 9.0, state)
	var rotor := MeshInstance3D.new()
	rotor.mesh = KitProps.turbine_rotor(state, 4.0)
	rotor.position = Vector3(4.6, 0, -4.6) + KitProps.turbine_hub(9.0)
	rotor.rotation.z = 0.4
	KitMat.apply(rotor, state, true)
	root.add_child(rotor)
	if state == "broken":
		KitProps.debris(b, Transform3D.IDENTITY, 4.0, 10)
	root.add_child(KitMesh.instance(b))
	for l: Dictionary in b.lights:
		if state != "broken":
			var o := OmniLight3D.new()
			o.position = l["pos"]
			o.light_color = l["color"]
			o.omni_range = l["range"]
			o.light_energy = l["energy"]
			root.add_child(o)
	return root


## Material swatches: every paint colour on a bevelled box, plus steel / rusty / concrete /
## hazard / rubber / glass / trims on cylinders, all on a ground patch.
static func swatches(state: String) -> Node3D:
	var root := Node3D.new()
	root.add_child(KitMesh.ground_patch(Vector2(7, 5), state, 3))
	var b := KitMesh.Builder.new(5, {}, state)
	var names: Array = KitMat.PALETTE.keys()
	for k: int in names.size():
		var x: float = -2.75 + (k % 6) * 1.1
		var z: float = -1.2 + (k / 6) * 1.2
		b.box_on("paint:" + str(names[k]), Vector3(0.8, 0.8, 0.8), Vector3(x, 0.08, z), Vector3(0, 12, 0), 0.08)
	var cyls: PackedStringArray = ["steel", "dark_steel", "rusty", "concrete", "hazard", "rubber", "glass", "trim:warm", "trim:cool"]
	for k: int in cyls.size():
		var x: float = -3.0 + k * 0.75
		b.cyl(cyls[k], 0.28, 0.9 if not cyls[k].begins_with("trim") else 0.5, KitMesh.xf(Vector3(x, 0.08, 1.4)), 0.06, 20)
	root.add_child(KitMesh.instance(b))
	return root


static func wall(state: String) -> Node3D:
	var root := Node3D.new()
	root.add_child(KitMesh.ground_patch(Vector2(8, 4), state, 7))
	var b := KitMesh.Builder.new(9, {"main": "cream", "accent": "teal", "broken_main": "#8a8274"}, state)
	var broken: bool = state == "broken"
	KitMesh.panel_wall(b, 7.0, 3.6, KitMesh.xf(Vector3(-3.5, 0.08, -0.8)), {
		"key": "paint:main", "key2": "paint:accent", "missing": 0.25 if broken else 0.0,
		"tilt": 1.0 if broken else 0.0, "trim": "trim:cool", "hazard": true})
	b.decal("label_hub", Vector2(1.6, 0.4), KitMesh.xf(Vector3(0, 2.6, -0.62)))
	b.decal("num_01", Vector2(0.7, 0.7), KitMesh.xf(Vector3(-2.4, 1.6, -0.62)))
	var mi := KitMesh.instance(b)
	root.add_child(mi)
	return root
