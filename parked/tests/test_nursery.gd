extends GutTest
## Parked in task M3-13 with the robot nursery (parked/extras/nursery/): the nursery tests cut from
## tests/test_extras.gd (they used its before_each / after_each), tests/test_camp.gd and
## tests/test_qafix.gd. They do not run.

# --- Nursery --------------------------------------------------------------------------------

func test_garden_bonus_is_small_and_capped() -> void:
	assert_almost_eq(Nursery.stat_mult("plant_growth"), 1.0, 0.0001)
	for i: int in 3:
		Nursery.list().append({"name": "Bot-%d" % i})
	assert_almost_eq(Nursery.stat_mult("plant_growth"), 1.03, 0.0001)
	assert_almost_eq(Nursery.stat_mult("scoop_rate"), 1.0, 0.0001, "only plant growth")
	for i: int in 20:
		Nursery.list().append({"name": "More-%d" % i})
	assert_almost_eq(Nursery.stat_mult("plant_growth"), 1.0 + Nursery.BONUS_CAP, 0.0001)


func test_only_old_or_low_tier_robots_retire() -> void:
	var r := Robot.new()
	r.robot_name = "Test-01"
	r.tier = 0
	assert_ne(Nursery.retire_block_reason(r), "", "[camp] no nursery built here yet")
	YardBuilds.mark_built("nursery")
	assert_eq(Nursery.retire_block_reason(r), "", "Mk I can retire")
	r.tier = 3
	GameState.stats["time_played"] = 100.0
	Nursery.service()["Test-01"] = 50.0
	assert_ne(Nursery.retire_block_reason(r), "", "a new Mk IV can't")
	GameState.stats["time_played"] = 50.0 + Nursery.OLD_S + 1.0
	assert_eq(Nursery.retire_block_reason(r), "", "after an hour in service it can")
	assert_gt(Nursery.refund_for(3), Nursery.refund_for(0))
	r.free()
