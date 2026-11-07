class_name Streak
extends RefCounted
## Cleaning streak (data/events.json "streak"): every piece Patch scoops adds a point; after a
## short grace period with no scoop the points drain away gently instead of snapping to zero.
## Tiers (every `per_tier` points, up to `max_tier`) add a small bale-value bonus. Pure logic so
## tests can drive it; WorldEvents owns one and the EventHUD draws it.

var per_tier: float = 30.0
var max_tier: int = 5
var bonus_per_tier: float = 0.04
var grace_s: float = 2.2
var drain_per_s: float = 9.0
var cap_extra: float = 0.5

var points: float = 0.0
var since_scoop: float = 999.0
## Best tier reached since the last take_bale_peak() (the bale bonus uses it).
var bale_peak: int = 0


func _init(cfg: Dictionary = {}) -> void:
	per_tier = maxf(float(cfg.get("per_tier", per_tier)), 1.0)
	max_tier = int(cfg.get("max_tier", max_tier))
	bonus_per_tier = float(cfg.get("bonus_per_tier", bonus_per_tier))
	grace_s = float(cfg.get("grace_s", grace_s))
	drain_per_s = float(cfg.get("drain_per_s", drain_per_s))
	cap_extra = float(cfg.get("cap_extra", cap_extra))


func cap() -> float:
	return per_tier * (float(max_tier) + cap_extra)


func tier() -> int:
	return mini(max_tier, int(floor(points / per_tier)))


## 0..1 progress inside the current tier (1 when maxed).
func fill() -> float:
	if tier() >= max_tier:
		return 1.0
	return fmod(points, per_tier) / per_tier


func bonus() -> float:
	return tier() * bonus_per_tier


func max_bonus() -> float:
	return max_tier * bonus_per_tier


## One piece scooped. Returns the new tier if it just went up, else -1.
func add_scoop(n: float = 1.0) -> int:
	var before: int = tier()
	points = minf(points + n, cap())
	since_scoop = 0.0
	var now: int = tier()
	bale_peak = maxi(bale_peak, now)
	return now if now > before else -1


## Advances time. Returns true if the tier dropped.
func tick(dt: float) -> bool:
	since_scoop += dt
	if since_scoop <= grace_s * Designs.mult("streak_grace") or points <= 0.0:  # [skins] Pixel design buff
		return false
	var before: int = tier()
	points = maxf(0.0, points - drain_per_s * dt)
	return tier() < before


## Bonus for the bale just pressed (best tier while it was being filled); resets the peak.
func take_bale_peak() -> float:
	var b: float = maxi(bale_peak, tier()) * bonus_per_tier
	bale_peak = tier()
	return b


func active() -> bool:
	return points > 0.0
