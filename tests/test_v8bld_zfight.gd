extends GutTest
## [v8bld] Owner: "building was glitching a bit then stopped". No two faces of the city's
## procedural buildings (BuildingDetail.proxy_building: the town's outer blocks and its
## outskirts towers) may lie on the same plane facing the same way and overlap: such pairs
## z-fight (flicker as the camera moves, still when it stops). CoplanarAudit finds them.


func test_audit_finds_a_known_overlap() -> void:
	var g := BuildingDetail.Geo.new()
	g.abox(Vector3(0, 0, 0), Vector3(4, 3, 4))
	g.abox(Vector3(1, 1, 0), Vector3(2, 1, 1))  # its -z face lies on the first box's -z face
	var r: Dictionary = CoplanarAudit.audit(g.v)
	assert_gt(int(r["pairs"]), 0, "two boxes sharing a face plane overlap there")
	assert_almost_eq(float(r["area"]), 2.0, 0.05, "the shared area is the small box's face")
	var g2 := BuildingDetail.Geo.new()
	g2.abox(Vector3(0, 0, 0), Vector3(4, 3, 4))
	g2.abox(Vector3(1, 1, -0.05), Vector3(2, 1, 1))  # 5 cm proud: no fight
	assert_eq(int(CoplanarAudit.audit(g2.v)["pairs"]), 0)


func test_proxy_buildings_have_no_coplanar_overlaps() -> void:
	var worst: Array = []
	var pairs: int = 0
	var n: int = 0
	for s: int in [4471, 4471 + 7919, 1234, 99]:
		var lay := CityLayout.new(s, 140.0)
		var bd := BuildingDetail.new()
		for b: Dictionary in lay.all_buildings():
			var body := BuildingDetail.Geo.new()
			var det := BuildingDetail.Geo.new()
			bd.proxy_building(b, body, det)
			var r: Dictionary = CoplanarAudit.audit(body.v)
			n += 1
			pairs += int(r["pairs"])
			if int(r["pairs"]) > 0 and worst.size() < 5:
				worst.append("floors %d style %s: %d pairs, %.2f m2 (e.g. at %s)" % [int(b["floors"]), str(b["style"]), int(r["pairs"]), float(r["area"]), str(r["worst"][0][1])])
	gut.p("%d buildings, %d coplanar pairs %s" % [n, pairs, str(worst)])
	assert_gt(n, 100)
	assert_eq(pairs, 0, "z-fighting faces in proxy buildings: %s" % str(worst))


func test_city_blocks_have_no_coplanar_overlaps() -> void:
	# Whole blocks merged as CityView and TownOutskirts merge them: neighbours in a row, the rows
	# back to back, the old overlapping side buildings (CityLayout.drop_overlaps).
	var area: float = 0.0
	var pairs: int = 0
	var blocks: int = 0
	var worst: String = ""
	for s: int in [4471, 1234]:
		var lay := CityLayout.new(s, 140.0)
		var bd := BuildingDetail.new()
		for key: Vector2i in lay.blocks:
			var list: Array = lay.blocks[key]["buildings"]
			if list.is_empty():
				continue
			var body := BuildingDetail.Geo.new()
			var det := BuildingDetail.Geo.new()
			for b: Dictionary in list:
				bd.proxy_building(b, body, det)
			var r: Dictionary = CoplanarAudit.audit(body.v)
			blocks += 1
			pairs += int(r["pairs"])
			area += float(r["area"])
			if float(r["area"]) > 0.3 and worst == "":
				worst = "block %s: %.2f m2" % [str(key), float(r["area"])]
	gut.p("%d blocks, %d small coplanar pairs, %.2f m2 %s" % [blocks, pairs, area, worst])
	assert_gt(blocks, 50)
	# Was about 4300 pairs and 6000 m2 for these two layouts (whole facades inside each other).
	assert_lt(area, 5.0, "z-fighting area over two whole layouts: %s" % worst)
	assert_eq(worst, "", "no block with a z-fighting patch over 0.3 m2")


func test_layout_buildings_do_not_overlap() -> void:
	for s: int in [4471, 99]:
		var lay := CityLayout.new(s, 140.0)
		for key: Vector2i in lay.blocks:
			var list: Array = lay.blocks[key]["buildings"]
			for i: int in list.size():
				for j: int in range(i + 1, list.size()):
					var o: Rect2 = (list[i]["rect"] as Rect2).intersection(list[j]["rect"])
					assert_false(o.size.x > 0.05 and o.size.y > 0.05, "block %s: buildings %d and %d overlap" % [str(key), i, j])


func test_town_visibility_ranges_have_hysteresis() -> void:
	# A range with no margin flips every time the camera swings across it (the follow camera orbits
	# Lumi at up to 26 m): a mural on a facade popped on and off as the player looked round.
	for path: String in ["res://planet/street_dressing.gd", "res://planet/street_furniture.gd", "res://planet/street_power.gd",
			"res://planet/city_view.gd", "res://planet/world_landmark.gd", "res://planet/sites/town_outskirts.gd"]:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var ln: String = lines[i]
			if not ("visibility_range_end = " in ln or "visibility_end = " in ln) or ln.strip_edges().begins_with("#"):
				continue
			var ok: bool = false
			for k: int in range(i, mini(i + 3, lines.size())):
				ok = ok or "margin" in lines[k]
			assert_true(ok, "%s:%d sets a visibility range without a margin" % [path, i + 1])


func test_detailed_buildings_show_facades_not_their_dark_core() -> void:
	# [v9bld] The town's near buildings (CityView detail ring: kit facade in front, a dark box behind
	# the windows, a procedural facade shell on the other sides). The dark box stood 2 cm OUTSIDE the
	# shell, so the sides and backs facing the start yard were flat black slabs. A ray from outside
	# onto any side or back must hit facade, never the dark core.
	var cv := CityView.new()
	cv._kit = {CityView.APT: {}, CityView.FAC: {}}
	var lay := CityLayout.new(4471, 80.0)
	var n: int = 0
	var bad: Array = []
	for key: Vector2i in lay.blocks:
		for bd: Dictionary in lay.blocks[key]["buildings"]:
			cv._body = BuildingDetail.Geo.new()
			cv._det = BuildingDetail.Geo.new()
			cv._build_building(key, bd)
			var g: BuildingDetail.Geo = cv._body
			var r: Rect2 = bd["rect"]
			var face: Vector2 = bd["face"]
			var c: Vector2 = r.get_center()
			for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				if side == face:
					continue  # the kit front: the dark core shows through its windows on purpose
				for y: float in [1.5, float(bd["floors"]) * 1.5]:
					var from := Vector3(c.x + side.x * (r.size.x * 0.5 + 2.0), y, c.y + side.y * (r.size.y * 0.5 + 2.0))
					var dir := Vector3(-side.x, 0, -side.y)
					var best: float = INF
					var kind: int = -1
					for t: int in range(0, g.v.size(), 3):
						var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, g.v[t], g.v[t + 1], g.v[t + 2])
						if hit != null and from.distance_to(hit) < best:
							best = from.distance_to(hit)
							kind = int(g.c[t].a * 16.0)
					n += 1
					if kind == BuildingDetail.K_DARK and bad.size() < 5:
						bad.append("%s face %s side %s y %.1f" % [str(r), str(face), str(side), y])
	cv.free()
	gut.p("%d side rays" % n)
	assert_gt(n, 50)
	assert_eq(bad.size(), 0, "a near building shows its dark core: %s" % str(bad))
