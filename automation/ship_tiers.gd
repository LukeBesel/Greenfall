class_name ShipTiers
extends RefCounted
## [ship] Which look Lumi's ship has, and which parts it carries (automation/ship_model.gd).
## One base ship that grows as planets are finished: the in-planet tiers (RocketTiers, Mk I-IV,
## bought in the Rockets tab) add wing extensions, better engines, a canopy upgrade, landing gear
## and cargo pods; the interplanetary drive (Homeward, Mk V-VII, wt/home) lengthens the hull, adds
## engine pairs, a fold ring, big wings and finally the seed vault. Gameplay semantics stay with
## RocketTiers / Homeward: this only maps them to a look (1..7).

const MAX_LOOK: int = 7
const HOMEWARD_PATH := "res://systems/homeward.gd"
## Overall model scale per look (index = look); the parts themselves add length and span too.
const SCALES: Array[float] = [1.15, 1.15, 1.15, 1.2, 1.25, 1.35, 1.5, 1.75]
## Landing pad deck scale per look (the pad grows with the ship).
const PAD_SCALES: Array[float] = [1.0, 1.0, 1.0, 1.05, 1.1, 1.3, 1.55, 1.85]


## The ship's look: Homeward's drive tier (5-7) once built, else the in-planet rocket tier (1-4).
## --ship-tier=N overrides (screenshots).
static func look() -> int:
	if DevHooks.has("ship-tier"):
		return clampi(int(DevHooks.get_f("ship-tier", 1.0)), 1, MAX_LOOK)
	return look_for(RocketTiers.tier(), drive_tier())


static func look_for(rocket_tier: int, drive: int) -> int:
	if drive >= 5:
		return clampi(drive, 5, MAX_LOOK)
	return clampi(rocket_tier, 1, 4)


## Homeward's interplanetary drive tier (0, 5, 6, 7); 0 when Homeward is not in this build.
## Called dynamically so this file compiles with or without wt/home merged.
static func drive_tier() -> int:
	if DevHooks.has("drive"):
		return int(DevHooks.get_f("drive", 0.0))
	if not ResourceLoader.exists(HOMEWARD_PATH):
		return 0
	var s: Script = load(HOMEWARD_PATH)
	if s == null or not ("drive" in s.get_script_method_list().map(func(m: Dictionary) -> String: return str(m["name"]))):
		return 0
	return int(s.call("drive"))


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
