extends GutTest
## [v6screens] The subtitle line keeps off Lumi: it sits above the hotbar when there is room under
## her feet, else right under her feet (over the hotbar), and left of a goal stack that reaches
## down beside it. The full check in the real game is `--ui-audit` (tools/ui_audit_run.gd).

var subs: Subtitles


func before_each() -> void:
	subs = Subtitles.new()
	subs.world = Node.new()
	add_child_autofree(subs.world)
	add_child_autofree(subs)
	await get_tree().process_frame


func test_room_above_the_hotbar() -> void:
	subs._feet_y = 461.0  # 1280x720 at scale 1: her feet at 64% of the height
	var spot: Vector2 = subs.play_spot(Rect2(0, 0, 1280, 720), Vector2(700, 44))
	assert_eq(spot.y, 720.0 - Subtitles.PLAY_BOTTOM)
	assert_gt(spot.y - 44.0, 461.0, "the pill's top is under her feet")
	assert_eq(spot.x, 0.0)


func test_big_interface_goes_under_her_feet() -> void:
	subs._feet_y = 307.0  # 853x480 (scale 1.5): no room above the hotbar
	var spot: Vector2 = subs.play_spot(Rect2(0, 0, 853, 480), Vector2(600, 44))
	assert_eq(spot.y - 44.0, 307.0 + Subtitles.FEET_GAP, "top just under her feet")
	assert_lt(spot.y, 480.0)


func test_never_below_the_screen() -> void:
	subs._feet_y = 470.0  # zoomed right in: she fills the screen
	var spot: Vector2 = subs.play_spot(Rect2(0, 0, 853, 480), Vector2(600, 44))
	assert_eq(spot.y, 480.0 - Subtitles.MIN_BOTTOM)


func test_cover_rect_empty_when_idle() -> void:
	assert_eq(subs.cover_rect(), Rect2())


func test_moves_left_of_a_tall_goal_stack() -> void:
	var view := Rect2(0, 0, 853, 480)
	var goal := Rect2(531, 85, 300, 260)  # expanded goals reaching down beside the line
	var spot: Vector2 = Subtitles.spot_for(view, Vector2(500, 44), 307.0, INF, goal)
	var right: float = 853.0 * 0.5 + 250.0 + spot.x
	assert_lt(spot.x, 0.0)
	assert_lte(right, 531.0 - 12.0 + 0.01, "the pill ends left of the goal stack")
	assert_gte(853.0 * 0.5 - 250.0 + spot.x, 11.99, "and stays on screen")


func test_rises_above_the_prompt() -> void:
	var spot: Vector2 = Subtitles.spot_for(Rect2(0, 0, 1280, 720), Vector2(600, 44), 461.0, 530.0, Rect2())
	assert_eq(spot.y, 524.0)
