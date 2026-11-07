extends SceneTree
func _init() -> void:
	await process_frame
	var eco: Node = root.get_node("Economy")
	var cfg: Dictionary = eco.planet.get("slice_field", {})
	var layout := CityLayout.new(4471, 150.0, false)
	var field := HexField.new(int(cfg.get("radius", 3)), float(cfg.get("hex_size", 10.0)), 4471, layout)
	var types: Array = []
	for id: String in eco.junk_ids:
		types.append(eco.junk_types[id])
	var ppx: Array = cfg.get("pieces_per_hex", [6, 12])
	field.generate(types, Vector2i(int(ppx[0]), int(ppx[1])))
	var tot_vol: float = 0.0
	var n_junk: int = 0
	for h: int in field.hex_count():
		var kind: String = "hub" if field.hex_hub[h] == 1 else ("blocked" if field.hex_hub[h] == 2 else ("water" if field.is_water(h) else "junk"))
		var c: Vector3 = field.hex_center(h)
		var d: int = Hex.distance(field.hex_axial[h], Vector2i.ZERO)
		if kind == "junk":
			n_junk += 1
			tot_vol += field.hex_total[h]
		print("hex %2d d%d %-7s blk%d n=%4d vol=%7.1f at (%.0f,%.0f)" % [h, d, kind, layout.block_type_at(c.x, c.z), field.hex_pieces[h].size(), field.hex_total[h], c.x, c.z])
	# Coverage: share of 1 m cells (inside junk hexes, not buildings) with a piece within 0.8 m, by surface.
	var cov: Dictionary = {}
	for x: int in range(-80, 81):
		for z: int in range(-80, 81):
			var p := Vector3(x + 0.5, 0, z + 0.5)
			var h: int = field.hex_at(p)
			if h < 0 or field.is_water(h):
				continue
			var s: int = layout.surface_at(p.x, p.z)
			if s == CityLayout.Surface.BUILDING:
				continue
			var key: String = ["lot", "road", "walk", "bld", "yard"][s] + ("_d1" if Hex.distance(field.hex_axial[h], Vector2i.ZERO) <= 1 else "") + ("_hub" if field.hex_hub[h] == 1 else ("_blk" if field.hex_hub[h] == 2 else ""))
			var arr: Array = cov.get(key, [0, 0])
			arr[0] += 1
			if not field.pieces_within(p, 0.8).is_empty():
				arr[1] += 1
			cov[key] = arr
	for k: String in cov:
		print("coverage %-8s %5.1f%% of %d m2" % [k, 100.0 * cov[k][1] / cov[k][0], cov[k][0]])
	for h: int in field.hex_count():
		if field.hex_hub[h] == 2:
			var c: Vector3 = field.hex_center(h)
			var own: Dictionary = {}
			for k: int in 40:
				var p := c + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
				if field.hex_at(p) == h and layout.surface_at(p.x, p.z) != CityLayout.Surface.BUILDING:
					var o: int = field.owner_hex(p)
					own[o] = int(own.get(o, 0)) + 1
			print("blocked %d at %s owners %s" % [h, str(c), str(own)])
	print("pieces=%d junk_hexes=%d vol=%.0f" % [field.piece_count(), n_junk, tot_vol])
	quit()
