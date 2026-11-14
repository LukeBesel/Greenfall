class_name GlobeSpec
extends RefCounted
## [orbB] Per-planet globe size (owner, Nov 8: planets differ in size, hex size stays 10 m).
## data/planets.json "<id>".globe = {"radius": x Verdance, "frequency": f, "hub_count": n}.
## frequency is the source of truth: the grid has 10·f²+2 cells (SphereGrid.for_freq); radius is
## the target it was picked for (R grows linearly with f, Verdance f = 128 = level 7 ~ 1.84 km).
## A planet without a globe entry gets "_default".globe (Verdance's size). [v7planet]

const HEX_M: float = 10.0
const VERDANCE_FREQ: int = 128
const DEFAULT := {"radius": 1.0, "frequency": VERDANCE_FREQ, "hub_count": 10}


static func of(planet_id: String) -> Dictionary:
	var e: Dictionary = PlanetEnvs.all().get(planet_id, {}) if PlanetEnvs.all().get(planet_id) is Dictionary else {}
	var g: Variant = e.get("globe")
	var out: Dictionary = DEFAULT.duplicate()
	var dg: Variant = PlanetCfg.defaults().get("globe")  # [v7planet] data/planets.json "_default".globe
	if dg is Dictionary:
		for k: String in out:
			if (dg as Dictionary).has(k):
				out[k] = (dg as Dictionary)[k]
	if g is Dictionary:
		for k: String in out:
			if (g as Dictionary).has(k):
				out[k] = (g as Dictionary)[k]
		if not (g as Dictionary).has("frequency") and (g as Dictionary).has("radius"):
			out["frequency"] = freq_for_radius(float(out["radius"]))
	if g is Dictionary and (g as Dictionary).has("seed"):  # [v7planet] the survey/terrain seed, per planet (default 4471)
		out["seed"] = int((g as Dictionary)["seed"])
	out["frequency"] = maxi(1, int(out["frequency"]))
	out["hub_count"] = maxi(1, int(out["hub_count"]))
	out["id"] = planet_id
	return out


static func freq_for_radius(x_verdance: float) -> int:
	return maxi(1, roundi(VERDANCE_FREQ * x_verdance))


static func cells_for(freq: int) -> int:
	return 10 * freq * freq + 2


## The planet the globe slice builds: --orbit-planet=<id>, else Verdance.
static func current_id() -> String:
	return DevHooks.get_s("orbit-planet", "verdance") if DevHooks.has("orbit-planet") else "verdance"
