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

# Pieces
var piece_pos := PackedVector3Array()
var piece_type := PackedInt32Array()  # index into Economy.junk_ids
var piece_shape := PackedStringArray()
var piece_vol := PackedFloat32Array()
var piece_hex := PackedInt32Array()
var piece_yaw := PackedFloat32Array()
var piece_scale := PackedFloat32Array()
var piece_color := PackedColorArray()
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
	for i: int in n:
		hex_pieces.append(PackedInt32Array())
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
		var cluster: Vector2 = Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * hex_size
		for k: int in count:
			var type_idx: int = theme if rng.randf() < 0.62 else _weighted(rng, weights, wsum)
			var t: Dictionary = junk_types[type_idx]
			var off: Vector2
			if rng.randf() < 0.5:
				off = cluster + Vector2(rng.randfn(0.0, 0.5), rng.randfn(0.0, 0.5)) * hex_size * 0.35
			else:
				off = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * hex_size * 0.75
			var pos: Vector3 = center + Vector3(off.x, 0.0, off.y)
			# Keep pieces inside their own hex.
			if hex_at(pos) != id:
				pos = center + Vector3(off.x, 0.0, off.y) * 0.45
			var vol_range: Array = t.get("volume", [0.6, 1.2])
			var vol: float = rng.randf_range(float(vol_range[0]), float(vol_range[1]))
			var shapes: Array = t.get("shapes", ["can"])
			var colors: Array = t.get("colors", ["#ffffff"])
			var pid: int = piece_pos.size()
			piece_pos.append(pos)
			piece_type.append(type_idx)
			piece_shape.append(str(shapes[rng.randi() % shapes.size()]))
			piece_vol.append(vol)
			piece_hex.append(id)
			piece_yaw.append(rng.randf() * TAU)
			piece_scale.append(lerpf(0.85, 1.25, (vol - float(vol_range[0])) / maxf(float(vol_range[1]) - float(vol_range[0]), 0.01)))
			piece_color.append(Color.html(str(colors[rng.randi() % colors.size()])))
			piece_alive.append(1)
			hex_pieces[id].append(pid)
			hex_total[id] += vol
		hex_left[id] = hex_total[id]
	cleaned_count = 0


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
