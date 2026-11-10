class_name ShipTiers
extends RefCounted
## [ship] Which look Lumi's ship has, and which parts it carries (automation/ship_model.gd).
## One base ship that grows as planets are finished: the in-planet tiers (RocketTiers, Mk I-IV,
## bought in the Rockets tab) add wing extensions, better engines, a canopy upgrade, landing gear
## and cargo pods. Looks 5-7 (the interplanetary drive: a longer hull, engine pairs, a fold ring,
## big wings and the seed vault) belong to the parked travel layer and are only shown with
## --ship-tier=N. Gameplay semantics stay with RocketTiers: this only maps its tier to a look.

const MAX_LOOK: int = 7
## Overall model scale per look (index = look); the parts themselves add length and span too.
const SCALES: Array[float] = [1.15, 1.15, 1.15, 1.2, 1.25, 1.35, 1.5, 1.75]
## Landing pad deck scale per look (the pad grows with the ship).
const PAD_SCALES: Array[float] = [1.0, 1.0, 1.0, 1.05, 1.1, 1.3, 1.55, 1.85]


## The ship's look: the in-planet rocket tier (1-4). --ship-tier=N overrides (screenshots).
static func look() -> int:
	if DevHooks.has("ship-tier"):
		return clampi(int(DevHooks.get_f("ship-tier", 1.0)), 1, MAX_LOOK)
	return look_for(RocketTiers.tier())


static func look_for(rocket_tier: int) -> int:
	return clampi(rocket_tier, 1, 4)


static func scale_of(t: int) -> float:
	return SCALES[clampi(t, 0, MAX_LOOK)]


static func pad_scale(t: int) -> float:
	return PAD_SCALES[clampi(t, 0, MAX_LOOK)]


## Part names (meshes in art/models/ship/ship.glb) carried at look t.
static func parts_for(t: int) -> PackedStringArray:
	var p := PackedStringArray(["hull_rear", "hull_front", "wing"])
	p.append("canopy_b" if t >= 3 else "canopy_a")
	p.append("eng_b" if t >= 3 else "eng_a")
	if t >= 4:
		p.append_array(["gear_n", "gear_l", "gear_r", "pods"])
	else:
		p.append_array(["skid_l", "skid_r"])
	if t >= 6:
		p.append("wing_big")
	elif t >= 2:
		p.append("wing_ext")
	if t >= 5:
		p.append_array(["hull_mid", "eng_c", "fins"])
	if t >= 6:
		p.append_array(["ring", "eng_tip"])
	if t >= 7:
		p.append_array(["vault", "eng_core"])
	return p


## Short display name of a look, e.g. "MK V".
static func mark(t: int) -> String:
	return ["", "MK I", "MK II", "MK III", "MK IV", "MK V", "MK VI", "MK VII"][clampi(t, 0, MAX_LOOK)]
