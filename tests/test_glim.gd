extends GutTest
## [buddy] Glim: discovery rule, the early-day clock, upgrade tracks (costs in the three currencies,
## requirements, max tiers), look unlocks and wearing, the scanner's remaining-piece query and the
## night lift on the sky.

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	GameState.currencies = {"cubes": BigNum.zero(), "parts": BigNum.zero(), "seeds": BigNum.zero()}
	GameState.flags = {}
	GameState.stats = {}
	Glim.dev_all = false


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats


func _give(c: float, p: float = 0.0, s: float = 0.0) -> void:
	GameState.add_currency("cubes", BigNum.from_float(c))
	GameState.add_currency("parts", BigNum.from_float(p))
	GameState.add_currency("seeds", BigNum.from_float(s))


func test_data_uses_only_three_currencies() -> void:
	var n: int = 0
	for t: Variant in Glim.tracks():
		var tiers: Array = (t as Dictionary)["tiers"]
		assert_between(tiers.size(), 1, 3, "1-3 bought tiers per track")
		assert_eq(((t as Dictionary)["values"] as Array).size(), tiers.size() + 1, "a value per tier + base")
		for tr_: Variant in tiers:
			for k: String in ((tr_ as Dictionary)["cost"] as Dictionary):
				assert_true(k in Currencies.IDS, "cost id %s" % k)
				n += 1
	for slot: String in Glim.SLOTS:
		for l: Variant in Glim.looks(slot):
			var u: Dictionary = (l as Dictionary).get("unlock", {})
			for k: String in (u.get("cost", {}) as Dictionary):
				assert_true(k in Currencies.IDS)
	assert_gt(n, 0)
	for id: String in ["light", "scan", "auto", "magnet", "music"]:
		assert_false(Glim.track(id).is_empty(), id)


func test_found_after_time_and_pieces() -> void:
	assert_false(Glim.is_found())
	assert_false(Glim.ready_to_find(100.0, 200), "too early")
	assert_false(Glim.ready_to_find(900.0, 3), "too few pieces")
	assert_true(Glim.ready_to_find(320.0, 30))
	var mins: float = float(Glim.data()["found"]["min_time_s"]) / 60.0
	assert_between(mins, 5.0, 10.0, "unlocks at about minute 5-10")


func test_clock_longer_days_until_found() -> void:
	assert_lt(Glim.clock_mult(0.5), 1.0, "day runs slower")
	assert_gt(Glim.clock_mult(0.0), 1.0, "night runs faster")
	# Day share of one full cycle (0.25..0.75 is day) while Glim is lost.
	var day_s: float = 0.5 / Glim.clock_mult(0.5)
	var night_s: float = 0.5 / Glim.clock_mult(0.0)
	assert_gt(day_s / (day_s + night_s), 0.65)
	Glim.set_found(true)
	assert_eq(Glim.clock_mult(0.5), 1.0)
	assert_eq(Glim.clock_mult(0.0), 1.0)


func test_night_lift_stays_after_found() -> void:
	assert_eq(SkyDirector.night_lift(), 1.0)
	Glim.set_found(true)
	assert_between(SkyDirector.night_lift(), 0.3, 0.99, "gentler, never off")


func test_buy_needs_found_money_and_requirements() -> void:
	assert_false(Glim.buy("light"), "not found yet")
	Glim.set_found(true)
	assert_false(Glim.buy("light"), "no money")
	_give(100000, 10000, 100)
	assert_eq(Glim.block_reason("auto"), "Needs Hex Scanner 1")
	assert_true(Glim.buy("scan"))
	assert_eq(Glim.tier("scan"), 1)
	assert_true(Glim.buy("auto"))
	var c0: float = GameState.get_currency("cubes").to_float()
	var cost: Dictionary = Glim.next_cost("light")
	assert_true(Glim.buy("light"))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), c0 - float(cost.get("cubes", 0.0)), 0.5)
	assert_gt(Glim.value("light", "range"), float(Glim.track("light")["values"][0]["range"]))


func test_tracks_max_out() -> void:
	Glim.set_found(true)
	_give(1.0e7, 1.0e6, 1000)
	for id: String in ["light", "scan", "auto", "magnet", "music"]:
		while Glim.buy(id):
			pass
	for id: String in ["light", "scan", "auto", "magnet", "music"]:
		assert_eq(Glim.tier(id), Glim.max_tier(id), id)
		assert_eq(Glim.block_reason(id), "Maxed")
		assert_true(Glim.next_cost(id).is_empty())
	assert_gt(Glim.value("scan", "ring"), 0.0, "top scanner reaches the neighbours")
	assert_gt(Glim.value("auto", "every"), 0.0)
	assert_gt(Glim.value("magnet", "radius"), 0.0)


func test_looks_locked_until_met() -> void:
	assert_eq(Glim.worn("shells"), "pearl")
	assert_eq(Glim.worn("glows"), "cyan")
	assert_false(Glim.look_unlocked("shells", "sunset"))
	assert_false(Glim.wear("shells", "sunset"))
	assert_false(Glim.buy_look("shells", "sunset"), "no money")
	_give(1000)
	assert_true(Glim.buy_look("shells", "sunset"))
	assert_true(Glim.wear("shells", "sunset"))
	assert_eq(Glim.worn("shells"), "sunset")
	assert_false(Glim.look_unlocked("tops", "sprout"))
	GameState.stats["hexes_cleaned"] = 4.0
	assert_true(Glim.look_unlocked("tops", "sprout"))
	assert_false(Glim.look_unlocked("glows", "ember"))
	(Glim.st()["tiers"] as Dictionary)["light"] = 1
	assert_true(Glim.look_unlocked("glows", "ember"), "one Glim upgrade")


func test_state_survives_serialization() -> void:
	Glim.set_found(true)
	(Glim.st()["tiers"] as Dictionary)["scan"] = 2
	Glim.st()["tops"] = "halo"
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.flags))
	GameState.flags = d
	assert_true(Glim.is_found())
	assert_eq(Glim.tier("scan"), 2, "JSON floats read back as tiers")
	assert_eq(Glim.worn("tops"), "halo")


func test_scanner_lists_remaining_pieces() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var f := HexField.new(5, 3.2, 99)
	f.generate(types)
	var h: int = -1
	for i: int in f.hex_count():
		if not f.is_clean(i) and f.hex_pieces[i].size() > 2:
			h = i
			break
	if h < 0:
		pass_test("no junk hex in this tiny field")
		return
	var all: PackedInt32Array = GlimScan.remaining(f, [h] as Array[int])
	var alive: int = 0
	for pid: int in f.hex_pieces[h]:
		alive += f.piece_alive[pid]
	assert_eq(all.size(), alive)
	f.remove_piece(all[0])
	assert_eq(GlimScan.remaining(f, [h] as Array[int]).size(), alive - 1, "collected pieces drop out")
	assert_eq(GlimScan.remaining(f, [-1] as Array[int]).size(), 0)


func test_night_amount() -> void:
	assert_almost_eq(GlimBot.night_amount(0.5), 0.0, 0.001, "noon: faint")
	assert_almost_eq(GlimBot.night_amount(0.0), 1.0, 0.001, "midnight: full")


func test_music_upgrade_gate() -> void:
	assert_false(Glim.has_music())
	Glim.set_found(true)
	_give(100000, 10000, 100)
	assert_eq(Glim.block_reason("music"), "Needs Lantern 1", "mid-game: after the first lantern tier")
	assert_true(Glim.buy("light"))
	assert_false(Glim.has_music())
	var cost: Dictionary = Glim.next_cost("music")
	for k: String in ["cubes", "parts", "seeds"]:
		assert_gt(float(cost.get(k, 0.0)), 0.0, "costs all three currencies")
	assert_true(Glim.buy("music"))
	assert_true(Glim.has_music())
	assert_gt(Glim.song_bpm(), 0.0)
	Glim.set_found(false)
	assert_false(Glim.has_music(), "no Glim, no music")


func test_scan_hexes_by_tier() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var f := HexField.new(5, 3.2, 99)
	f.generate(types)
	var c: Vector3 = f.hex_center(0)
	var own: Array[int] = GlimDirector.scan_hexes(f, c, 0)
	assert_eq(own.size(), 1, "tier 1: Lumi's own hex")
	assert_eq(own[0], f.hex_at(c))
	assert_gt(GlimDirector.scan_hexes(f, c, 1).size(), 1, "higher tiers reach the neighbours")


func test_amber_for_pieces_too_heavy() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var f := HexField.new(5, 3.2, 99)
	f.generate(types)
	var ups: Dictionary = GameState.upgrades.duplicate()
	GameState.upgrades = {}
	var small: int = -1
	var large: int = -1
	for pid: int in f.piece_count():
		if Pace.piece_size(f, pid) == Pace.SIZE_SMALL and small < 0:
			small = pid
		elif Pace.piece_size(f, pid) == Pace.SIZE_LARGE and large < 0:
			large = pid
	if small >= 0:
		assert_false(GlimScan.too_big(null, f, small), "small pieces are always liftable")
	if large >= 0 and Pace.lift_class() < Pace.SIZE_LARGE:
		assert_true(GlimScan.too_big(null, f, large), "large pieces are amber before Lift Strength 2")
	GameState.upgrades = ups


func test_bench_reasons() -> void:
	Glim.set_found(true)
	assert_eq(GlimBench.reason_text("auto"), TranslationServer.translate("Needs %s %d") % [TranslationServer.translate("Hex Scanner"), 1])
	assert_eq(GlimBench.reason_text("light"), TranslationServer.translate("Not enough cubes, parts or seeds"))
	assert_true(HubBuilds.not_enough(GlimBench.reason_text("light")), "the row shows the short form")
	_give(1.0e6, 1.0e5, 100)
	assert_eq(GlimBench.reason_text("light"), "")


func test_glim_in_locker_targets() -> void:
	GlimDirector.register_cosmetics()
	assert_true(CosmeticTargets.has("glim"))
	assert_false(CosmeticTargets.is_unlocked("glim"), "locked until found")
	Glim.set_found(true)
	assert_true(CosmeticTargets.is_unlocked("glim"))
	var ed: Control = CosmeticTargets.make_editor("glim", null)
	assert_not_null(ed)
	if ed:
		ed.free()


func test_locker_edits_glim() -> void:
	GlimDirector.register_cosmetics()
	Glim.set_found(true)
	GameState.flags["locker_open"] = true
	var lp := LockerPanel.new()
	add_child_autofree(lp)
	await wait_frames(2)
	var ids: Array[String] = []
	for b: Button in lp._who_btns:
		ids.append(str(b.get_meta("who")))
	assert_has(ids, "ct:glim", "Glim has a button in the Locker's bot bar")
	lp.set_editing("ct:glim")
	assert_true(lp._editor is GlimPanel.GlimLooksEditor, "and his looks editor opens")
