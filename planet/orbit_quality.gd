class_name OrbitQuality
extends RefCounted
## [orbE] Per-preset budgets for the round planet (docs/PERFORMANCE.md, "Round planet"):
## how far full-detail (LOD 0) and mid (LOD 1) terrain chunks reach, the far-shell distance,
## how many chunk meshes apply per frame (main-thread cost), how far the Future Layer draws, and
## whether the moon casts shadows. Medium is the owner's Mac target (60 fps): it keeps phase A's
## radii. Low trims the rings for integrated GPUs and the Deck. Densities (junk per hex) are not
## touched: the game density is part of the design (~70 pieces per 10 m hex).

const BUDGETS: Array[Dictionary] = [
	{"lod0_m": 180.0, "lod1_m": 520.0, "far_m": 1700.0, "apply": 1, "future_m": 220.0, "moon_shadow": false},  # Low
	{"lod0_m": 240.0, "lod1_m": 650.0, "far_m": 2000.0, "apply": 2, "future_m": 320.0, "moon_shadow": true},  # Medium
	{"lod0_m": 280.0, "lod1_m": 760.0, "far_m": 2300.0, "apply": 2, "future_m": 380.0, "moon_shadow": true},  # High
	{"lod0_m": 320.0, "lod1_m": 860.0, "far_m": 2600.0, "apply": 3, "future_m": 420.0, "moon_shadow": true},  # Ultra
]
## Globe radius (m) the far distances in BUDGETS were tuned on (a frequency-128 globe).
const REFERENCE_R: float = 1840.0


static func budget(q: int) -> Dictionary:
	return BUDGETS[clampi(q, 0, BUDGETS.size() - 1)]


## Before streamer.setup / settle. far_m also scales with the globe (a bigger planet's horizon
## from Command height is farther away; the far shell covers the rest).
static func apply_streamer(st: SphereStreamer, q: int, radius_m: float) -> void:
	var b: Dictionary = budget(q)
	st.lod0_m = float(b["lod0_m"])
	st.lod1_m = float(b["lod1_m"])
	st.far_m = float(b["far_m"]) * clampf(radius_m / REFERENCE_R, 0.85, 1.4)
	st.apply_per_frame = int(b["apply"])


static func apply_world(sky: SkyDirector, future: FutureLayerSphere, q: int) -> void:
	var b: Dictionary = budget(q)
	if sky and sky.moon:
		sky.moon.shadow_enabled = bool(b["moon_shadow"])
	if future:
		future.range_m = float(b["future_m"])
