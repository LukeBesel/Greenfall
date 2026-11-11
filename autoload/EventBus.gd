extends Node
## Global signal hub. Gameplay emits; UI, audio, story, stats listen.

@warning_ignore_start("unused_signal")
# Junk and cubes
signal junk_scooped(type_id: String, world_pos: Vector3)
signal compartment_changed(fill: float, capacity: float)
signal cube_made(cube_info: Dictionary)
signal cube_cashed(value: BigNum, world_pos: Vector3)
## A loose load was tipped in the bin: the cubes it paid and where.
signal load_tipped(cubes: float, world_pos: Vector3)
signal currency_changed(currency: String, amount: BigNum)

# World
signal hex_cleaned(hex_id: int, world_pos: Vector3, bonus: BigNum)
signal field_progress_changed(cleaned: int, total: int)
signal hex_restored(hex_id: int)
signal hex_level_changed(hex_id: int, level: int)
signal tool_changed(tool: int)

# Progression
signal upgrade_bought(upgrade_id: String, new_level: int)
signal milestone_reached(milestone_id: String)
signal toast(text: String, kind: String)
signal tutorial_changed(text: String)
signal robot_built(robot_name: String)
signal part_found(part_type: int, rarity: int)

# Feel
signal shake_requested(strength: float)
signal hitstop_requested(duration: float, time_scale: float)

# Sim / meta
signal sim_tick(dt: float)
signal game_loaded()
signal game_saved()
signal ui_modal_changed(open: bool)

# Story: easter eggs and the Ledger arc
signal easter_egg_found(egg_id: String)
signal ledger_event(kind: String, data: Dictionary)
@warning_ignore_restore("unused_signal")

# Research / codex / achievements
@warning_ignore_start("unused_signal")
signal research_completed(research_id: String)
signal achievement_unlocked(achievement_id: String)
signal codex_unlocked(entry_key: String)
@warning_ignore_restore("unused_signal")

# [biomes] Frontier districts. cradle_district_complete fires once per save when the Cradle Returns
# landing pad is clean and Sustained and the district is Growing enough (planet/frontier_district.gd).
# It is the hook for the ark finale (story/*): see docs/DECISIONS.md.
@warning_ignore_start("unused_signal")
signal cradle_district_complete(hub_index: int)
@warning_ignore_restore("unused_signal")

# Districts (cities) and the planet's two goals (systems/districts.gd, systems/restoration.gd).
# district_entered fires once per save, the first time the player stands in an unlocked district.
# planet_restoration_changed carries launch progress, 0..1. launch_ready fires once per save when
# the planet's launch rule is met; planet_restored if the whole planet is ever restored.
@warning_ignore_start("unused_signal")
signal district_unlocked(district_id: String)
signal district_stage_changed(district_id: String, stage: int)
## The city stage payout (systems/city_payouts.gd): cubes paid once for the stage just reached.
signal district_stage_paid(district_id: String, stage: int, cubes: float)
signal district_entered(district_id: String)
## Pollution kinds (systems/pollution.gd). pollution_cleared: `amount` units of waste of `kind`
## were cleared, by Lumi's own hands or by robots (robot work arrives batched). pollution_blocked:
## Lumi tried waste of `kind` on hex `cell_id` without the tool it needs.
signal pollution_cleared(kind: String, amount: float, by_player: bool)
signal pollution_blocked(kind: String, cell_id: int)
## Mastery (systems/mastery.gd): Lumi's own work on `kind` reached mastery `level` (once per level).
signal mastery_gained(kind: String, level: int)
## Rigs (systems/rigs.gd). rig_module_unlocked: a module's plan reached the workbench.
## rig_module_built: it was built from the plan. rig_fitted: `module_id` went into `slot`
## ("" = the slot was emptied).
signal rig_module_unlocked(module_id: String)
signal rig_module_built(module_id: String)
signal rig_fitted(slot: String, module_id: String)
## The robot chain (systems/crew/robot_chain.gd). parts_scrounged: parts finders brought `parts`
## Parts to a base. assembler_offered: the Assembler can now be built. assembler_built: it stands.
## robot_assembled: the Assembler's line finished a robot of `type_id` (robot_built fires too).
## salvage_found: Parts found on first arrival in a city.
signal parts_scrounged(parts: float)
signal assembler_offered
signal assembler_built
signal robot_assembled(type_id: String, robot_name: String)
signal salvage_found(district_id: String, parts: float)
signal planet_restoration_changed(value: float)
signal planet_step_reached(planet_id: String, step_id: String)
signal launch_ready(planet_id: String)
signal planet_restored(planet_id: String)
signal ending_shown(planet_id: String)
@warning_ignore_restore("unused_signal")

# Looks (design spec section 13; systems/looks.gd, systems/finds.gd, systems/lumi_style.gd).
# piece_found: a piece of a look was found; source = how ("buried", "wreck", "source", "secret").
# set_completed: the last piece of a design was found. look_changed: Lumi wears a different look.
# source_shut_down: a city's pollution source was stopped (whatever stops it emits this).
# source_job_opened: a city's source job is on offer for the first time. source_step_done: Lumi
# finished step `step` (from 0) of it (systems/sources.gd). source_part_ordered / source_part_built:
# the part of step `step` went to be built / stands ready. source_soiled: a running source fouled
# clean hex `cell_id` of its city again (systems/source_spread.gd).
@warning_ignore_start("unused_signal")
signal piece_found(piece_id: String, source: String)
signal set_completed(design_id: String)
signal look_changed()
signal source_shut_down(district_id: String)
signal source_job_opened(district_id: String)
signal source_step_done(district_id: String, step: int)
signal source_part_ordered(district_id: String, step: int)
signal source_part_built(district_id: String, step: int)
signal source_soiled(district_id: String, cell_id: int)
@warning_ignore_restore("unused_signal")

# The Surge (design spec section 8; systems/surge.gd). hand_tended: Lumi herself planted a seed
# ("plant") or watered plants ("water"); robots' tending does not emit it. surge_charged: her
# Bloom Core filled. surge_released: the player let it go in `district_id`; `output` is how many
# times her hand output it gives, `wave_rings` how many rings of hexes its growth wave reached
# (0 = no wave). surge_ended: the burst ran out.
@warning_ignore_start("unused_signal")
signal hand_tended(action: String)
signal surge_charged()
signal surge_released(district_id: String, output: float, wave_rings: int)
signal surge_ended()
@warning_ignore_restore("unused_signal")
