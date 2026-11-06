extends Node
## Global signal hub. Gameplay emits; UI, audio, story, stats listen.

@warning_ignore_start("unused_signal")
# Junk and cubes
signal junk_scooped(type_id: String, world_pos: Vector3)
signal compartment_changed(fill: float, capacity: float)
signal cube_made(cube_info: Dictionary)
signal cube_cashed(value: BigNum, world_pos: Vector3)
signal currency_changed(currency: String, amount: BigNum)

# World
signal hex_cleaned(hex_id: int, world_pos: Vector3, bonus: BigNum)
signal field_progress_changed(cleaned: int, total: int)

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
@warning_ignore_restore("unused_signal")
