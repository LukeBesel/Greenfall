class_name HexField
extends RefCounted
## Simulation data for a flat hex field of junk (the M1 slice). Pure data, no nodes:
## per-hex junk ledger, per-piece arrays, spatial queries, and compact save/load.
## M2's sphere planet keeps the same per-hex API (hex_count, removed_fraction, is_clean...).

signal hex_became_clean(hex_id: int)

var radius: int
var hex_size: float
var seed_value: int
var clean_threshold: float = 0.99

# Hexes
var hex_axial: Array[Vector2i] = []
var axial_to_id: Dictionary = {}
var hex_total: PackedFloat32Array
var hex_left: PackedFloat32Array
var hex_clean: PackedByteArray
var hex_hub: PackedByteArray  # 1 = hub ground (starts clean, not counted)
var hex_pieces: Array[PackedInt32Array] = []
## Junk piles per hex: Vector4(x, z, radius, height). Their mounds shrink as the hex is cleaned.
var hex_piles: Array = []

# Pieces
var piece_pos := PackedVector3Array()
var piece_type := PackedInt32Array()  # index into Economy.junk_ids
var piece_model := PackedStringArray()
var piece_pose := PackedByteArray()  # 0 upright, 1 lying (roll about X), 2 lying (roll about Z)
var piece_vol := PackedFloat32Array()
var piece_hex := PackedInt32Array()
var piece_yaw := PackedFloat32Array()
var piece_scale := PackedFloat32Array()
var piece_tilt := PackedFloat32Array()
## Big immovable wrecks (cars, barriers...) for M1: {model, pos, yaw}. Mega-junk cleanup comes later.
var landmarks: Array[Dictionary] = []
var piece_alive := PackedByteArray()

var cleaned_count: int = 0
var junk_hex_count: int = 0


func _init(p_radius: int = 9, p_hex_size: float = 3.2, p_seed: int = 4471) -> void:
	radius = p_radius
	hex_size = p_hex_size
	seed_value = p_seed


func hex_count() -> int:
	return hex_axial.size()


func piece_count() -> int:
	return piece_pos.size()


func hex_center(id: int) -> Vector3:
	var p: Vector2 = Hex.axial_to_world(hex_axial[id], hex_size)
	return Vector3(p.x, 0.0, p.y)


func hex_at(world: Vector3) -> int:
	var a: Vector2i = Hex.world_to_axial(Vector2(world.x, world.z), hex_size)
	return int(axial_to_id.get(a, -1))


func removed_fraction(id: int) -> float:
	if hex_total[id] <= 0.0:
		return 1.0
	return 1.0 - hex_left[id] / hex_total[id]


func is_clean(id: int) -> bool:
	return hex_clean[id] == 1


## Builds the deterministic field. junk_types: Array of dicts from data/junk.json.
func generate(junk_types: Array, pieces_per_hex: Vector2i = Vector2i(6, 12)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	hex_axial = Hex.spiral(radius)
	axial_to_id.clear()
	for i: int in hex_axial.size():
		axial_to_id[hex_axial[i]] = i
	var n: int = hex_axial.size()
	hex_total = PackedFloat32Array()
	hex_total.resize(n)
	hex_left = PackedFloat32Array()
	hex_left.resize(n)
	hex_clean = PackedByteArray()
	hex_clean.resize(n)
	hex_hub = PackedByteArray()
	hex_hub.resize(n)
	hex_pieces.clear()
	hex_piles.clear()
	for i: int in n:
		hex_pieces.append(PackedInt32Array())
		hex_piles.append([])
	var weights: Array[float] = []
	var wsum: float = 0.0
	for t: Dictionary in junk_types:
		weights.append(float(t.get("weight", 1.0)))
		wsum += weights[-1]
	junk_hex_count = 0
	for id: int in n:
		var dist: int = Hex.distance(hex_axial[id], Vector2i.ZERO)
		if dist <= 1:
			hex_hub[id] = 1
			hex_clean[id] = 1
			continue
		junk_hex_count += 1
		# Each hex leans toward one junk type so Pure Cubes are a reachable skill goal.
		var theme: int = _weighted(rng, weights, wsum)
		var t_dist: float = clampf(float(dist - 2) / maxf(radius - 2, 1), 0.0, 1.0)
		var count: int = int(round(lerpf(pieces_per_hex.x, pieces_per_hex.y, t_dist))) + rng.randi_range(-1, 2)
		var center: Vector3 = hex_center(id)
		var piles: Array = []
		for k: int in rng.randi_range(1, 2 + int(t_dist > 0.5)):
			var pc: Vector2 = Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45)) * hex_size
			piles.append(Vector4(center.x + pc.x, center.z + pc.y, rng.randf_range(0.9, 1.7), rng.randf_range(0.18, 0.45) * (0.7 + t_dist * 0.6)))
		hex_piles[id] = piles
		for k: int in count:
			var type_idx: int = theme if rng.randf() < 0.62 else _weighted(rng, weights, wsum)
			var t: Dictionary = junk_types[type_idx]
			var pos: Vector3
			if rng.randf() < 0.72:
				var pile: Vector4 = piles[rng.randi() % piles.size()]
				var ang: float = rng.randf() * TAU
				var rr: float = absf(rng.randfn(0.0, 0.5)) * pile.z
				pos = Vector3(pile.x + cos(ang) * rr, 0.0, pile.y + sin(ang) * rr)
			else:
				pos = center + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * hex_size * 0.75
			# Keep pieces inside their own hex.
			if hex_at(pos) != id:
				pos = center + (pos - center) * 0.45
			var models: Array = t.get("models", [])
			var mdl: Dictionary = _pick_model(rng, models)
			var vol: float = float(mdl.get("vol", 1.0)) * rng.randf_range(0.85, 1.15)
			var pid: int = piece_pos.size()
			piece_pos.append(pos)
			piece_type.append(type_idx)
			piece_model.append(str(mdl.get("id", "")))
			piece_vol.append(vol)
			piece_hex.append(id)
			piece_yaw.append(rng.randf() * TAU)
			piece_scale.append(rng.randf_range(0.9, 1.1))
			piece_pose.append((1 + rng.randi() % 2) if rng.randf() < float(mdl.get("lie", 0.0)) else 0)
			piece_tilt.append(rng.randf_range(-0.12, 0.12))
			piece_alive.append(1)
			hex_pieces[id].append(pid)
			hex_total[id] += vol
		hex_left[id] = hex_total[id]
	cleaned_count = 0


## Height of the junk mound under a point, shrinking as the hex is cleaned (0 once clean).
func ground_height(id: int, pos: Vector3) -> float:
	if id < 0 or hex_clean[id] == 1:
		return 0.0
	var left: float = 1.0 - removed_fraction(id)
	var h: float = 0.0
	for pile: Vector4 in hex_piles[id]:
		var d: float = Vector2(pos.x - pile.x, pos.z - pile.y).length() / pile.z
		if d < 1.0:
			h = maxf(h, pile.w * sqrt(1.0 - d * d))
	return h * (0.3 + 0.7 * left)


func _pick_model(rng: RandomNumberGenerator, models: Array) -> Dictionary:
	if models.is_empty():
		return {}
	var total: float = 0.0
	for m: Dictionary in models:
		total += float(m.get("w", 1.0))
	var r: float = rng.randf() * total
	for m: Dictionary in models:
		r -= float(m.get("w", 1.0))
		if r <= 0.0:
			return m
	return models[-1]


## Places big wreck props on outer junk hexes (deterministic).
func place_landmarks(defs: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	landmarks.clear()
	var used: Dictionary = {}
	for d: Dictionary in defs:
		for k: int in int(d.get("count", 1)):
			for attempt: int in 20:
				var id: int = rng.randi_range(0, hex_count() - 1)
				var dist: int = Hex.distance(hex_axial[id], Vector2i.ZERO)
				if hex_hub[id] == 1 or dist < 3 or used.has(id):
					continue
				used[id] = true
				var off := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * hex_size * 0.4
				landmarks.append({"model": str(d["id"]), "pos": hex_center(id) + off, "yaw": rng.randf() * TAU, "hex": id})
				break


func _weighted(rng: RandomNumberGenerator, weights: Array[float], wsum: float) -> int:
	var r: float = rng.randf() * wsum
	for i: int in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1


## Removes a piece from the world ledger. Returns true if its hex just became clean.
func remove_piece(pid: int) -> bool:
	if pid < 0 or pid >= piece_alive.size() or piece_alive[pid] == 0:
		return false
	piece_alive[pid] = 0
	var id: int = piece_hex[pid]
	hex_left[id] = maxf(0.0, hex_left[id] - piece_vol[pid])
	if hex_clean[id] == 0 and removed_fraction(id) >= clean_threshold:
		hex_clean[id] = 1
		cleaned_count += 1
		hex_became_clean.emit(id)
		return true
	return false


## Hex ids within `ring` steps of the hex containing `pos`.
func hexes_near(pos: Vector3, ring: int = 1) -> Array[int]:
	var out: Array[int] = []
	var a: Vector2i = Hex.world_to_axial(Vector2(pos.x, pos.z), hex_size)
	for dq: int in range(-ring, ring + 1):
		for dr: int in range(maxi(-ring, -dq - ring), mini(ring, -dq + ring) + 1):
			var id: int = int(axial_to_id.get(a + Vector2i(dq, dr), -1))
			if id >= 0:
				out.append(id)
	return out


## Closest alive piece inside the scoop zone: a forward box widening slightly with distance.
func find_scoop_target(origin: Vector3, forward: Vector3, reach: float, width: float) -> int:
	var fwd: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var best: int = -1
	var best_d: float = INF
	for hid: int in hexes_near(origin, 1 + int(reach / hex_size)):
		for pid: int in hex_pieces[hid]:
			if piece_alive[pid] == 0:
				continue
			var d: Vector3 = piece_pos[pid] - origin
			var z: float = d.dot(fwd)
			if z < -0.3 or z > reach:
				continue
			var x: float = absf(d.dot(right))
			if x > width * 0.5 + maxf(z, 0.0) * 0.25:
				continue
			var dist: float = z * z + x * x * 1.5
			if dist < best_d:
				best_d = dist
				best = pid
	return best


func pieces_within(pos: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2: float = r * r
	for hid: int in hexes_near(pos, 1 + int(r / hex_size)):
		for pid: int in hex_pieces[hid]:
			if piece_alive[pid] == 1 and piece_pos[pid].distance_squared_to(pos) <= r2:
				out.append(pid)
	return out


func nearest_alive(pos: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for ring: int in range(1, radius * 2 + 2):
		for hid: int in hexes_near(pos, ring):
			for pid: int in hex_pieces[hid]:
				if piece_alive[pid] == 0:
					continue
				var d: float = piece_pos[pid].distance_squared_to(pos)
				if d < best_d:
					best_d = d
					best = pid
		if best >= 0:
			return best
	return best


func junk_hexes_cleaned() -> int:
	return cleaned_count


func to_dict() -> Dictionary:
	return {
		"seed": seed_value, "radius": radius,
		"alive": Marshalls.raw_to_base64(piece_alive),
		"clean": Marshalls.raw_to_base64(hex_clean),
	}


## Restores alive/clean flags onto an already generated field with the same seed.
func apply_dict(d: Dictionary) -> bool:
	if int(d.get("seed", -1)) != seed_value or int(d.get("radius", -1)) != radius:
		return false
	var alive: PackedByteArray = Marshalls.base64_to_raw(str(d.get("alive", "")))
	var clean: PackedByteArray = Marshalls.base64_to_raw(str(d.get("clean", "")))
	if alive.size() != piece_alive.size() or clean.size() != hex_clean.size():
		return false
	piece_alive = alive
	hex_clean = clean
	cleaned_count = 0
	for id: int in hex_count():
		hex_left[id] = 0.0
		for pid: int in hex_pieces[id]:
			if piece_alive[pid] == 1:
				hex_left[id] += piece_vol[pid]
		if hex_clean[id] == 1 and hex_hub[id] == 0:
			cleaned_count += 1
	return true
