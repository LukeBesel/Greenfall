class_name CargoPods
extends Node
## Rocket Cargo research: robots left working in other districts you have visited keep earning.
## Every minute their cargo pods land here with cubes (a quarter of a Scoopie's bale rate each).
## Rocket upgrades (automation/rocket_tiers.gd) make the pods bigger and more frequent.

const PERIOD_S: float = 60.0
const PER_ROBOT: float = 6.0

var world: Node
var _t: float = 0.0


func remote_robots() -> int:
	var n: int = 0
	for k: Variant in GameState.districts:
		if int(k) == GameState.current_hub:
			continue
		n += (GameState.districts[k] as Dictionary).get("robots", []).size()
	return n


func _process(delta: float) -> void:
	if not Research.has("rocket_cargo"):
		return
	_t += delta
	var tdef: Dictionary = RocketTiers.def()
	if _t < float(tdef.get("cargo_period_s", PERIOD_S)):
		return
	_t = 0.0
	var n: int = remote_robots()
	if n <= 0:
		return
	var amount: float = PER_ROBOT * float(n) * maxf(Economy.stat("cube_value_mult"), 1.0) * float(tdef.get("cargo_mult", 1.0))
	GameState.add_currency("cubes", BigNum.from_float(amount))
	GameState.inc_stat("cargo_pods")
	EventBus.toast.emit("Cargo pod landed: %s cubes from %d robots in other districts." % [Settings.fmt(BigNum.from_float(amount)), n], "info")
	if world and world.get("depot") != null:
		Vfx.burst("dust", world.depot.global_position + Vector3(2, 0.3, -2), Color(0.8, 0.75, 0.65), 0.8)
	Audio.play("thud", 0.9, -8.0)
