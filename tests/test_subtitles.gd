extends GutTest
## [intro2] The one subtitle line: the reading-time rule, one-line chunks, purposeful glitches.


func _rule(t: String) -> float:
	return maxf(2.5, Subtitles.plain(t).length() * 0.055 + 1.2)


func test_duration_rule() -> void:
	assert_almost_eq(Subtitles.duration_for(""), 2.5, 0.001)
	assert_almost_eq(Subtitles.duration_for("Short."), 2.5, 0.001)
	var long_line: String = "x".repeat(60)
	assert_almost_eq(Subtitles.duration_for(long_line), 60 * 0.055 + 1.2, 0.001)
	# Markup does not count as reading time.
	assert_almost_eq(Subtitles.duration_for("[glitch]" + long_line + "[/glitch]"), 60 * 0.055 + 1.2, 0.001)


func test_all_intro_lines_follow_the_rule() -> void:
	var lines: Dictionary = Intro.lines()
	assert_gt(lines.size(), 8)
	for key: String in lines:
		var text: String = str(lines[key][0])
		if lines[key].size() > 2:
			text = Intro.glitch_tail(text)
		var cs: PackedStringArray = Subtitles.chunks(text)
		assert_gt(cs.size(), 0, key)
		var total: float = 0.0
		var joined: String = ""
		for c: String in cs:
			var p: String = Subtitles.plain(c)
			assert_lte(p.length(), Subtitles.MAX_CHARS, "%s: chunk fits one line: %s" % [key, p])
			var d: float = Subtitles.duration_for(c)
			assert_gte(d, 2.5, key)
			assert_almost_eq(d, _rule(c), 0.001, "%s: 55 ms/char + 1.2 s" % key)
			total += d + Subtitles.FADE_S * 2.0 + Subtitles.GAP_S
			joined += p + " "
		# Nothing lost in the split, and the intro waits for the full time.
		assert_eq(joined.replace(" ", ""), Subtitles.plain(text).replace(" ", ""), key)
		assert_almost_eq(Subtitles.total_time(text), total, 0.001, key)
		assert_gte(Subtitles.total_time(text), _rule(text), key)


func test_chunks_split_at_sentences() -> void:
	var t: String = "Your core runs on green light, the glow living things give off. There's no green left down there. That's why you're fading."
	var cs: PackedStringArray = Subtitles.chunks(t)
	assert_eq(cs.size(), 2)
	assert_eq(cs[0], "Your core runs on green light, the glow living things give off.")
	assert_eq(Subtitles.chunks("Short line.").size(), 1)


func test_glitch_spans_stay_balanced_and_marked() -> void:
	var t: String = "This part reads clean. [glitch]and this part is a corrupted transmission that runs on and on past the line break[/glitch] back to clean."
	for c: String in Subtitles.chunks(t):
		assert_eq(c.count(Subtitles.GLITCH_OPEN), c.count(Subtitles.GLITCH_CLOSE), c)
	var gm: Array = Subtitles.glitch_mask("ok [glitch]bad[/glitch] ok [REDACTED]")
	assert_eq(gm[0], "ok bad ok [REDACTED]")
	var mask: Array = gm[1]
	assert_false(bool(mask[0]))
	assert_true(bool(mask[3]))
	assert_false(bool(mask[7]))
	assert_true(bool(mask[10]))
	assert_true(Intro.glitch_tail("Lumi— hold on— hold on—").ends_with("hold on—[/glitch]"))


func test_one_line_at_a_time() -> void:
	var s := Subtitles.new()
	add_child_autofree(s)
	await get_tree().process_frame
	s.queue_line("First line.", "wren")
	s.queue_line("Second line.", "")
	assert_eq(Subtitles.plain(s.current_text()), "First line.")
	assert_true(s.is_busy("wren"))
	s.show_now("Now.", "ledger")
	assert_eq(s.current_text(), "Now.")
	assert_false(s.is_busy("wren"))
	s.clear()
	assert_false(s.is_busy())
