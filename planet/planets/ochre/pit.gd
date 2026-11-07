class_name OchrePit
extends RefCounted
## [planet-ochre] Shape of Ochre's open-pit mine: the play field sits on a wide haul bench low in
## the pit; two steps drop to the floor (a sludge pond, an oasis when restored) and nine stepped
## benches climb to the rim, with haul roads spiralling between them. Beyond the rim: a hot
## plateau with tailings heaps, salt pans and layered mesas.
## Pit space: q = (x, z) - CENTER, angle th = atan2(q.y, q.x), radius rho = |q| / squash(th)
## (an elongated, slightly lobed pit). Benches are rings in rho, so the mesh rings follow their
## edges exactly and the terraces stay crisp.

const CENTER := Vector2(0.0, -110.0)
const STEP_H: float = 11.0       # up benches
const STEP_P: float = 17.0       # up bench pitch (rho)
const WALL_W: float = 5.5        # up wall width (rho)
const N_UP: int = 9
const FIELD_IN: float = 57.5     # field bench inner edge (top of the last down wall)
const FIELD_OUT: float = 225.0   # field bench outer edge (toe of the first up wall)
const DOWN_H: float = 10.0
const FLOOR_R: float = 40.0
const POND_R: float = 29.0
const FLOOR_Y: float = -20.0
const RIM_RHO: float = FIELD_OUT + STEP_P * N_UP   # 378
const RIM_Y: float = STEP_H * N_UP                  # 99
const LEVELS: int = 2 + 1 + N_UP                    # floor, -10 bench, field bench, 9 up benches
const R_OUT: float = 1600.0

## A flat or sloped band of the profile: rho a..b, y ya..yb, wall?, level index (0 = floor).
var bands: Array = []
## Haul ramps: {th0, th1, r0, r1, y0, y1, hw}
var ramps: Array = []
var n1 := FastNoiseLite.new()
var n2 := FastNoiseLite.new()
var n3 := FastNoiseLite.new()


func _init(seed_v: int) -> void:
	for k: int in 3:
		var nz: FastNoiseLite = [n1, n2, n3][k]
		nz.seed = seed_v + 31 * (k + 1)
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = 3
		nz.frequency = [0.004, 0.02, 0.0016][k]
	# Floor, down steps (wall 3.5, bench), field bench, nine up steps, the rim.
	bands.append([0.0, FLOOR_R, FLOOR_Y, FLOOR_Y, false, 0])
	bands.append([FLOOR_R, FLOOR_R + 3.5, FLOOR_Y, FLOOR_Y + DOWN_H, true, 0])
	bands.append([FLOOR_R + 3.5, FIELD_IN - 3.5, -DOWN_H, -DOWN_H, false, 1])
	bands.append([FIELD_IN - 3.5, FIELD_IN, -DOWN_H, 0.0, true, 1])
	bands.append([FIELD_IN, FIELD_OUT, 0.0, 0.0, false, 2])
	for k: int in N_UP:
		var r0: float = FIELD_OUT + STEP_P * k
		bands.append([r0, r0 + WALL_W, STEP_H * k, STEP_H * (k + 1), true, 2 + k])
		bands.append([r0 + WALL_W, r0 + STEP_P, STEP_H * (k + 1), STEP_H * (k + 1), false, 3 + k])
	# Haul roads: one ramp per up step, chained into a spiral round the pit (starting behind the
	# field to the west), and two down to the floor on the far side.
	var th: float = PI * 0.5 + 0.95
	for k: int in N_UP:
		var r0: float = FIELD_OUT + STEP_P * k - 4.2
		var r1: float = FIELD_OUT + STEP_P * k + WALL_W + 4.2
		var span: float = 125.0 / ((r0 + r1) * 0.5)
		ramps.append({"th0": th, "th1": th + span, "r0": r0, "r1": r1, "y0": STEP_H * k, "y1": STEP_H * (k + 1), "hw": 3.6})
		th += span + 0.16
	ramps.append({"th0": -PI * 0.5 - 1.3, "th1": -PI * 0.5 + 0.6, "r0": FIELD_IN + 4.0, "r1": FIELD_IN - 7.5, "y0": 0.0, "y1": -DOWN_H, "hw": 3.2})
	ramps.append({"th0": -PI * 0.5 + 0.75, "th1": -PI * 0.5 + 2.8, "r0": FIELD_IN - 7.5, "r1": FLOOR_R - 4.0, "y0": -DOWN_H, "y1": FLOOR_Y, "hw": 3.2})


## World-space stretch of the pit at angle th (rho -> metres).
static func squash(th: float) -> float:
	return 1.0 + 0.18 * cos(2.0 * th) + 0.05 * sin(3.0 * th + 1.0)


func world_at(th: float, rho: float) -> Vector2:
	return CENTER + Vector2(cos(th), sin(th)) * rho * squash(th)


func polar_of(x: float, z: float) -> Vector2:
	var q := Vector2(x, z) - CENTER
	var th: float = atan2(q.y, q.x)
	return Vector2(th, q.length() / squash(th))


## Profile height and data at pit radius rho: [y, level, flat(0/1), across 0..1].
func profile(rho: float) -> Array:
	for b: Array in bands:
		if rho <= float(b[1]):
			var f: float = clampf((rho - float(b[0])) / maxf(float(b[1]) - float(b[0]), 0.001), 0.0, 1.0)
			if bool(b[4]):
				# Walls: steep, with a rounded toe and crest.
				var g: float = f * f * (3.0 - 2.0 * f)
				var w: float = lerpf(f, g, 0.35)
				return [lerpf(float(b[2]), float(b[3]), w), int(b[5]), 0.0, f]
			return [float(b[2]), int(b[5]), 1.0, f]
	return [RIM_Y, LEVELS - 1, 1.0, 1.0]


## Terrain height (world) at pit polar coordinates; also returns the vertex data.
## Returns [y, level, flat, across, pit(1 inside the rim)].
func sample(th: float, rho: float) -> Array:
	var w: Vector2 = world_at(th, rho)
	var pr: Array = profile(rho)
	var y: float = pr[0]
	var flat: float = pr[2]
	if rho < RIM_RHO:
		if flat > 0.5:
			# Bench: a little rubble, and a safety berm along the crest (inner edge).
			var a: float = float(pr[3])
			y += n2.get_noise_2d(w.x, w.y) * 0.25
			if int(pr[1]) >= 1 and int(pr[1]) != 2:
				y += 1.0 * exp(-pow((a - 0.1) / 0.08, 2.0))
			if int(pr[1]) == 0 and rho < POND_R + 2.0:
				y = lerpf(FLOOR_Y - 2.6, FLOOR_Y - 0.1, smoothstep(POND_R - 9.0, POND_R + 2.0, rho))
		else:
			y += n2.get_noise_2d(w.x * 2.0, w.y * 2.0) * 0.6
	else:
		var t: float = rho - RIM_RHO
		var und: float = (n1.get_noise_2d(w.x, w.y) * 0.5 + 0.5) * 18.0 * smoothstep(0.0, 160.0, t)
		# Tailings heaps: long flat-topped spoil dumps just beyond the rim.
		var heap: float = smoothstep(0.15, 0.45, n3.get_noise_2d(w.x * 2.2, w.y * 2.2)) * 16.0
		heap *= smoothstep(12.0, 40.0, t) * (1.0 - smoothstep(110.0, 190.0, t))
		y = RIM_Y + 0.4 + und + heap + n2.get_noise_2d(w.x, w.y) * 0.4
	# Haul roads cut down into whatever they cross.
	for r: Dictionary in ramps:
		var rr: Array = ramp_at(r, th)
		if rr.is_empty():
			continue
		var lat: float = absf(rho - float(rr[1])) * squash(th)
		var hw: float = float(r["hw"]) + 1.5
		if lat < hw + 4.0:
			var cut: float = float(rr[0]) - 0.3
			y = minf(y, lerpf(cut, y, smoothstep(hw, hw + 4.0, lat)))
	return [y, float(pr[1]), flat, float(pr[3]), 1.0 if rho < RIM_RHO + 2.0 else 0.0]


## On a ramp at angle th: [y, rho_centre, t] or [] (angles wrap).
func ramp_at(r: Dictionary, th: float) -> Array:
	var th0: float = r["th0"]
	var span: float = float(r["th1"]) - th0
	var d: float = fposmod(th - th0, TAU)
	if d > span:
		return []
	var t: float = d / span
	var e: float = t * t * (3.0 - 2.0 * t)
	var tt: float = lerpf(t, e, 0.3)
	return [lerpf(float(r["y0"]), float(r["y1"]), tt), lerpf(float(r["r0"]), float(r["r1"]), t), t]


## Ground height at world x, z (props); the field bench is 0.
func height_at(x: float, z: float) -> float:
	var p: Vector2 = polar_of(x, z)
	return float(sample(p.x, p.y)[0])


## The rho rings of the mesh: dense on walls and crests, sparse on wide benches and the plateau.
func rings() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for b: Array in bands:
		var a: float = b[0]
		var c: float = b[1]
		if bool(b[4]):
			for f: float in [0.0, 0.12, 0.3, 0.5, 0.7, 0.88]:
				out.append(lerpf(a, c, f))
		else:
			var n: int = maxi(2, ceili((c - a) / (1.6 if c - a < 20.0 else 6.0)))
			for i: int in n:
				var f2: float = float(i) / float(n)
				out.append(lerpf(a, c, f2))
	out.append(RIM_RHO)
	var r: float = RIM_RHO
	var dr: float = 4.0
	while r < R_OUT:
		r += dr
		dr *= 1.1
		out.append(minf(r, R_OUT))
	return out
