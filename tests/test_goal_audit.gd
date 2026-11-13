extends GutTest
## [v9d] Every goal and achievement left on Verdance can complete (tools/goal_audit.gd, data checks;
## --walk-goals adds the globe's checks: eggs placed, hubs, the Recycler, Radio and Nursery).


func test_every_verdance_goal_can_complete() -> void:
	var fails: Array[String] = GoalAudit.audit(null)
	assert_eq(fails.size(), 0, "\n".join(fails))


func test_audit_catches_a_dead_goal() -> void:
	var closed: Dictionary = GoalAudit.closed_keys()
	assert_ne(GoalAudit.goal_problem({"id": "x", "type": "stat", "key": "water_tanks", "target": 1}, null, closed), "")
	assert_ne(GoalAudit.goal_problem({"id": "x", "type": "zone", "key": "B", "target": 5}, null, closed), "")
	assert_ne(GoalAudit.goal_problem({"id": "x", "type": "stat", "key": "no_such_stat", "target": 1}, null, closed), "")
	assert_ne(GoalAudit.goal_problem({"id": "x", "type": "stat", "key": "research_done", "target": 99}, null, closed), "")
	assert_eq(GoalAudit.goal_problem({"id": "x", "type": "stat", "key": "hexes_cleaned", "target": 3}, null, closed), "")


func test_every_card_step_has_a_picture() -> void:
	var kinds: Dictionary = {}
	for o: Dictionary in Economy.read_json("res://data/objectives.json").get("objectives", []):
		kinds[ObjectiveCard.icon_of(o)] = true
	for g: Variant in GoalAudit.verdance_goals():
		assert_ne(ObjectiveCard.icon_of(g as Dictionary), "", "goal %s has a picture" % str((g as Dictionary).get("id", "")))
	assert_gt(kinds.size(), 4, "the story steps use several pictures, not one for all: %s" % str(kinds.keys()))
