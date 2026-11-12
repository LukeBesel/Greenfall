class_name MasteryRewards
extends Node
## What a mastery level pays (the planet's pollution table, mastery.level_reward). Mastery comes
## from Lumi's own hands only, so this is hand-work pay: robots never earn it. Each level gained in
## any kind is one step; step N pays what level N of the parked Lumi Level bar paid, with the same
## formula and numbers (docs/DECISIONS.md, side systems trimmed): about cube_secs of current income, floored at
## min_cubes_per_step x N and capped at max(cap_cubes_base x N^1.5, cap_earned_frac x lifetime
## cubes); every seeds_every-th step also pays seeds once the garden is open. The step is the sum
## of mastery levels over every kind plus one, so the first level gained is step 2.
## A planet without the block pays nothing. Saves need no state: the step is read from Mastery.
## Use: var r := MasteryRewards.new(); r.world = world; world.add_child(r)

const KEY: String = "level_reward"

var world: Node


func _ready() -> void:
	if not EventBus.mastery_gained.is_connected(_on_mastery_gained):
		EventBus.mastery_gained.connect(_on_mastery_gained)


func _exit_tree() -> void:
	if EventBus.mastery_gained.is_connected(_on_mastery_gained):
		EventBus.mastery_gained.disconnect(_on_mastery_gained)


## The planet's reward block ({} = mastery pays nothing here).
static func cfg() -> Dictionary:
	return (Economy.planet_table(Pollution.TABLE).get(MasteryRules.KEY, {}) as Dictionary).get(KEY, {})


## The reward for step `step` (no side effects): {cubes, seeds}. `income_cubes` is the
## progress-scaled cube amount for one step (about cube_secs of income); `earned` is lifetime cubes
## earned (lifts the cap late in the game).
static func reward_plan(step: int, income_cubes: float, earned: float, seeds_unlocked: bool, c: Dictionary) -> Dictionary:
	if c.is_empty():
		return {"cubes": 0.0, "seeds": 0}
	var floor_c: float = float(c.get("min_cubes_per_step", 0.0)) * step
	var cap_c: float = maxf(float(c.get("cap_cubes_base", 0.0)) * pow(float(step), 1.5), earned * float(c.get("cap_earned_frac", 0.0)))
	var out: Dictionary = {"cubes": round(clampf(income_cubes, floor_c, maxf(cap_c, floor_c))), "seeds": 0}
	var se: int = int(c.get("seeds_every", 0))
	if seeds_unlocked and se > 0 and step % se == 0:
		@warning_ignore("integer_division")
		out["seeds"] = int(c.get("seeds", 0)) + int(c.get("seeds_per_10_steps", 0)) * (step / 10)
	return out


## The step a level-up reaches: every mastery level so far, over all kinds, plus one.
static func step_of(mastery: Mastery) -> int:
	var n: int = 1
	for kind: String in mastery.kinds():
		n += mastery.level(kind)
	return n


## Pays the reward for one level gained; returns what it paid as a short line ("" for nothing).
func pay(step: int) -> String:
	var c: Dictionary = cfg()
	if c.is_empty():
		return ""
	var earned: float = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	var income: float = maxf(WorldEvents.progress_cubes(float(c.get("cube_secs", 0.0))), 0.0)
	var plan: Dictionary = reward_plan(step, income, earned, bool(GameState.flags.get("seeds_unlocked", false)), c)
	var bits: Array[String] = []
	if float(plan["cubes"]) > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(float(plan["cubes"])))
		bits.append(L10nFmt.amount("cubes", float(plan["cubes"]), true))
	if int(plan["seeds"]) > 0:
		GameState.add_currency("seeds", BigNum.from_float(int(plan["seeds"])))
		bits.append(L10nFmt.amount("seeds", int(plan["seeds"]), true))
	return "  ".join(bits)


func _on_mastery_gained(kind: String, level: int) -> void:
	var mastery: Mastery = Mastery.of(world)
	if mastery == null:
		return
	var text: String = pay(step_of(mastery))
	if text == "":
		return
	GameState.inc_stat("mastery_rewards")
	if DevHooks.has("autoplay"):
		print("[mastery] %s %d at %.1f min (%s)" % [kind, level, float(GameState.stats.get("time_played", 0.0)) / 60.0, text])
	var patch: Node3D = world.get("patch") as Node3D
	if patch:
		var at: Vector3 = patch.global_position + OrbitUp.up(patch.global_position) * 2.0
		Vfx.float_text(at, text, Color(0.75, 1.0, 0.85), 0.55, 1.6)
	Audio.play("coin", 1.1, -6.0)
