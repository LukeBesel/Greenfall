class_name GoalReadout
extends Control
## The three goals beside the story card (story/goals.gd): one row per tier on a single dark
## plate with one clipped corner, in the field-instrument style (docs/STYLE.md section 10).
##   Sell 8 more bales
##   NOW     ------=========            3 / 8
##   Reach Litter mastery 4
##   CITY    ---============            3 / 4
## Each row is the goal, and under it a gauge: the stencilled tier label, a thin engraved rule
## that fills with progress, and the count. A finished goal is stamped DONE in green for a beat, then the next goal of
## its tier slides in. The row whose goal the story card is carrying is left out (it is on the
## card already), and the row the player is following (Objectives.track) carries a pointer.

## As wide as the story card above it, so the column reads as one instrument.
const W: float = ObjectiveCard.W
const PAD: float = 12.0
const ROW_H: float = 46.0
const LINE_H: float = 20.0
const LABEL_W: float = 70.0
const COUNT_W: float = 74.0
const TITLE_W: float = W - PAD * 2.0
const FONT_PX: int = 16
const CLIP: float = 12.0
## A finished goal stays on its row, stamped, this long; the next one takes this long to slide in.
const DONE_S: float = 1.1
const REVEAL_S: float = 0.16
const SLIDE_PX: float = 14.0
const PLATE := Color(0.075, 0.09, 0.105, 0.88)
const EDGE := Color(0.9, 0.9, 0.87, 0.16)
const RULE := Color(0.9, 0.9, 0.87, 0.14)
const CYAN := Color(0.55, 0.9, 1.0)
## One accent per row, top to bottom: Lumi cyan (yours, now), hazard amber, growth green.
const ACCENTS: Array[Color] = [CYAN, Color(1.0, 0.7, 0.26), Color(0.62, 0.86, 0.66)]

var goals: Goals
var objectives: Objectives
var _rows: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_END
	custom_minimum_size = Vector2(W, 0)
	visible = false


func bind(p_goals: Goals) -> void:
	goals = p_goals
	_rows.clear()
	for tier: String in goals.tier_ids():
		_rows.append({"tier": tier, "goal": -1, "key": "", "title": "", "count": "", "shown": 0.0, "done": 0.0, "reveal": 0.0, "on": false})
	goals.completed.connect(_on_completed)


func _process(delta: float) -> void:
	if goals == null:
		return
	var n: int = 0
	for r: Dictionary in _rows:
		_step_row(r, delta)
		n += 1 if r["on"] else 0
	visible = n > 0
	custom_minimum_size = Vector2(W, PAD * 2.0 + ROW_H * n - 8.0 if n > 0 else 0.0)
	queue_redraw()


## Rows on screen (tests).
func visible_rows() -> int:
	var n: int = 0
	for r: Dictionary in _rows:
		n += 1 if r["on"] else 0
	return n if visible else 0


## What each row on screen says: [tier label, title, count] (tests, the clarity log).
func row_texts() -> Array:
	var out: Array = []
	for r: Dictionary in _rows:
		if r["on"]:
			out.append([tr(goals.tier_name(str(r["tier"]))), str(r["title"]), str(r["count"])])
	return out


## The goals the rows show, top to bottom (the order the follow key steps through).
func shown_goals() -> Array[int]:
	var out: Array[int] = []
	for r: Dictionary in _rows:
		if r["on"] and int(r["goal"]) >= 0 and float(r["done"]) <= 0.0:
			out.append(int(r["goal"]))
	return out


func _step_row(r: Dictionary, delta: float) -> void:
	r["reveal"] = maxf(0.0, float(r["reveal"]) - delta)
	if float(r["done"]) > 0.0:  # stamped DONE: hold the finished goal, then let the next one in
		r["done"] = maxf(0.0, float(r["done"]) - delta)
		return
	var want: int = goals.active(str(r["tier"]))
	if want == goals.card_goal:  # the story card is carrying it
		want = -1
	var key: String = "" if want < 0 else "%s#%d" % [str(goals.chain[want]["id"]), goals.times_done(want)]
	if key != str(r["key"]):
		var first: bool = str(r["key"]) == "" and not r["on"]
		r["goal"] = want
		r["key"] = key
		r["on"] = want >= 0
		r["reveal"] = 0.0 if first or Settings.reduced_motion else REVEAL_S
		r["shown"] = goals.progress(want) if want >= 0 else 0.0
	if want < 0:
		return
	r["title"] = goals.text_of(want)
	r["count"] = count_text(goals, want)
	r["shown"] = lerpf(float(r["shown"]), goals.progress(want), clampf(delta * 6.0, 0.0, 1.0))


## "3 / 8" for a count, "62%" for a share, "" for a single thing to do.
static func count_text(g: Goals, i: int) -> String:
	var c: Array[float] = g.counts(i)
	if c[1] > 1.0:
		return "%s / %s" % [_n(floorf(c[0])), _n(c[1])]
	if c[1] < 1.0 or str(g.chain[i].get("type", "")) in [Restoration.MEASURE_LAUNCH, "planet_share"]:
		return "%d%%" % int(floor(c[0] / maxf(c[1], 0.0001) * 100.0))
	return ""


static func _n(v: float) -> String:
	return Settings.fmt(BigNum.from_float(v))


func _on_completed(i: int) -> void:
	for r: Dictionary in _rows:
		if int(r["goal"]) == i and r["on"]:
			r["done"] = DONE_S
			r["shown"] = 1.0
			r["count"] = tr("DONE")


func _draw() -> void:
	if goals == null or size.y <= 0.0:
		return
	var w: float = size.x
	var h: float = size.y
	var plate := PackedVector2Array([Vector2(0, 0), Vector2(w - CLIP, 0), Vector2(w, CLIP), Vector2(w, h), Vector2(0, h)])
	draw_colored_polygon(plate, PLATE)
	plate.append(Vector2(0, 0))
	draw_polyline(plate, EDGE, 1.0)
	var y: float = PAD - 2.0
	var k: int = 0
	for r: Dictionary in _rows:
		if r["on"]:
			_draw_row(r, ACCENTS[mini(k, ACCENTS.size() - 1)], y)
			y += ROW_H
		k += 1


func _draw_row(r: Dictionary, accent: Color, y: float) -> void:
	var font: Font = UITheme.font()
	var done: bool = float(r["done"]) > 0.0
	var slide: float = float(r["reveal"]) / REVEAL_S
	var alpha: float = 1.0 - slide
	var x: float = PAD + slide * slide * SLIDE_PX
	var tracked: bool = objectives != null and objectives.tracked_goal == int(r["goal"]) and not done
	if tracked:  # the pointer: a shape, so the followed row does not rest on colour alone
		draw_colored_polygon(PackedVector2Array([Vector2(1, y + 3), Vector2(8, y + 9), Vector2(1, y + 15)]), CYAN)
	var title_col: Color = UITheme.GREEN if done else UITheme.CREAM
	draw_string(font, Vector2(x, y + FONT_PX), str(r["title"]), HORIZONTAL_ALIGNMENT_LEFT, TITLE_W, FONT_PX, Color(title_col, alpha))
	var gauge: float = y + LINE_H + FONT_PX
	var mark: Color = UITheme.GREEN if done else accent
	draw_string(font, Vector2(PAD, gauge), tr(goals.tier_name(str(r["tier"]))), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, FONT_PX, mark)
	var count_col: Color = UITheme.GREEN if done else UITheme.CREAM
	draw_string(font, Vector2(size.x - PAD - COUNT_W, gauge), str(r["count"]), HORIZONTAL_ALIGNMENT_RIGHT, COUNT_W, FONT_PX, Color(count_col, alpha))
	var rule_x: float = PAD + LABEL_W
	var rule_w: float = size.x - PAD - COUNT_W - 8.0 - rule_x if str(r["count"]) != "" else size.x - PAD - rule_x
	var rule_y: float = gauge - 6.0
	draw_rect(Rect2(rule_x, rule_y, rule_w, 2.0), RULE)
	draw_rect(Rect2(rule_x, rule_y, rule_w * clampf(float(r["shown"]), 0.0, 1.0), 2.0), mark)
