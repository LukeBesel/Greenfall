class_name RocketCharge
extends Node
## The rocket's energy cells charge faster while Lumi works in the city where it stands (design
## decision after the full-planet bot: a hop never means waiting with nothing to do). Her own work
## counts: waste she clears (EventBus.pollution_cleared with by_player), a bale she presses
## (cube_made) and a seed she plants or a plant she waters (hand_tended). Each keeps her "working"
## for a short window; while it lasts the cells gain extra charge on top of the clock, and a
## pressed bale adds a lump at once. Robots never charge the cells.
## When the cells fill after a hop, a toast says the rocket is ready.
##
## Data: data/rockets.json "work_charge" (window_s, extra_rate, per_bale_s, ready_toast); the
## cells' state is RocketTiers' (GameState.flags rocket_ready_unix).
## Use: var rc := RocketCharge.new(); rc.in_city_fn = func() -> bool: ...; world.add_child(rc)

## Whether Lumi stands in the city whose pad the rocket is on (set by OrbitSites). Unset: always.
var in_city_fn: Callable
## Seconds of "working" left (refreshed by each piece of work).
var working_s: float = 0.0
## Seconds of charge Lumi's work added since the last hop (reports, tests).
var gained_s: float = 0.0

var _was_charging: bool = false


func _enter_tree() -> void:
	if not EventBus.pollution_cleared.is_connected(_on_pollution_cleared):
		EventBus.pollution_cleared.connect(_on_pollution_cleared)
	if not EventBus.cube_made.is_connected(_on_cube_made):
		EventBus.cube_made.connect(_on_cube_made)
	if not EventBus.hand_tended.is_connected(_on_hand_tended):
		EventBus.hand_tended.connect(_on_hand_tended)


func _exit_tree() -> void:
	if EventBus.pollution_cleared.is_connected(_on_pollution_cleared):
		EventBus.pollution_cleared.disconnect(_on_pollution_cleared)
	if EventBus.cube_made.is_connected(_on_cube_made):
		EventBus.cube_made.disconnect(_on_cube_made)
	if EventBus.hand_tended.is_connected(_on_hand_tended):
		EventBus.hand_tended.disconnect(_on_hand_tended)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the window by `dt` game seconds and adds the working bonus to the cells.
func step(dt: float) -> void:
	var left: float = RocketTiers.recharge_left()
	if left > 0.0:
		_was_charging = true
		if working_s > 0.0 and _in_city():
			gained_s += RocketTiers.charge_by(float(RocketTiers.work_cfg().get("extra_rate", 0.0)) * minf(dt, working_s))
	elif _was_charging:
		_was_charging = false
		gained_s = 0.0
		if bool(RocketTiers.work_cfg().get("ready_toast", false)):
			EventBus.toast.emit(tr("Energy cells full. The rocket is ready to fly."), "info")
	working_s = maxf(0.0, working_s - dt)


## Lumi did a piece of work: she counts as working for the next window_s seconds.
func worked() -> void:
	working_s = float(RocketTiers.work_cfg().get("window_s", 0.0))


func _in_city() -> bool:
	return not in_city_fn.is_valid() or bool(in_city_fn.call())


func _on_pollution_cleared(_kind: String, amount: float, by_player: bool) -> void:
	if by_player and amount > 0.0:
		worked()


func _on_cube_made(_info: Dictionary) -> void:
	worked()
	if _in_city():
		gained_s += RocketTiers.charge_by(float(RocketTiers.work_cfg().get("per_bale_s", 0.0)))


func _on_hand_tended(_action: String) -> void:
	worked()
