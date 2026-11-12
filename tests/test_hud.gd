extends GutTest
## [hud] The notification stack,
## currency chips, the compact goal tracker and the HUD mode setting.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _mode: int


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	_mode = Settings.hud_mode
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	Settings.hud_mode = _mode


# --- Notifications, currency, goals -------------------------------------------------------------

func test_notify_stack_caps_and_merges() -> void:
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for i: int in 5:
		ns.push("Message %d" % i)
	assert_eq(ns.count(), NotifyStack.MAX, "at most 3 rows")
	ns.push("Message 4")
	assert_eq(ns.count(), NotifyStack.MAX, "a repeat refreshes its row instead of stacking")
	ns.push("")
	assert_eq(ns.count(), NotifyStack.MAX)


func test_currency_chip_appears_on_change() -> void:
	var cc := CurrencyCluster.new()
	add_child_autofree(cc)
	cc._warm = 0.0
	GameState.add_currency("parts", BigNum.from_float(5))
	assert_eq(cc.chip_count(), 1)
	GameState.add_currency("parts", BigNum.from_float(2))
	assert_eq(cc.chip_count(), 1, "same currency updates its chip")
	GameState.add_currency("cubes", BigNum.from_float(100))
	assert_eq(cc.chip_count(), 1, "cubes have their own big readout, no chip")
	GameState.add_currency("seeds", BigNum.from_float(3))
	assert_eq(cc.chip_count(), 2, "[money] seeds get a chip too")
	Currencies.warn_legacy = false
	GameState.add_currency("bolts", BigNum.from_float(1))
	Currencies.warn_legacy = true
	assert_eq(cc.chip_count(), 2, "a legacy id lands on the Parts chip, no new chip")


func test_goal_column_holds_the_card_the_checklist_and_the_goal_readout() -> void:
	var gp := GoalsPanel.new()
	add_child_autofree(gp)
	assert_not_null(gp.objective)
	assert_not_null(gp.readout, "the three goals sit beside the card")
	assert_eq(gp.visible_rows(), 0, "nothing to show before the world has goals")
	gp.toggle()  # no objectives yet: the follow key does nothing
	gp.set_checklist("Hold  LMB  to scoop   2/8")
	assert_true(gp.checklist.visible)
	assert_eq(GoalsPanel._strip_count("Hold  LMB  to scoop   2/8"), "Hold  LMB  to scoop")


func test_hud_mode_setting_persists() -> void:
	var path: String = Settings.settings_path
	Settings.settings_path = "user://test_hud_settings.cfg"
	Settings.hud_mode = Settings.HudMode.FULL
	Settings.save_settings()
	Settings.hud_mode = Settings.HudMode.HIDDEN
	Settings.load_settings()
	assert_eq(Settings.hud_mode, Settings.HudMode.FULL)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.settings_path))
	Settings.settings_path = path
	assert_true(InputMap.has_action("toggle_goals"), "goal tracker toggle is bound")


# The planet readout needs the globe's districts: before they exist it shows nothing. Then it is
# the current city, its regrowth stage and the share toward the next stage, and the cities
# restored: never a planet percentage with decimals.
func test_planet_readout_shows_the_current_city_its_stage_and_the_cities_restored() -> void:
	var w: Node3D = (load("res://scenes/slice.gd") as GDScript).new()
	autofree(w)
	var so := SliceOrbit.new()
	autofree(so)
	w.set("orbit", so)
	w.set("field", HexField.new())
	var hud := HUD.new()
	hud.world = w
	add_child_autofree(hud)
	hud._process(0.016)
	assert_false(hud._field_label.visible, "no planet line before the districts exist")
	assert_false(hud._field_bar.visible)
	assert_false(hud._planet_label.visible)
	assert_eq(hud._field_label.text, "", "and no stale text behind it")
	var fx := DistrictFixture.new(Planets.current_id())
	so.districts = fx.districts
	so.restoration = fx.restoration
	var first: String = fx.districts.ids()[0]
	var total: int = fx.districts.count()
	var need: int = Districts.hexes_needed(PackedInt32Array([fx.districts.land_of(first)]), fx.districts.stage_share)
	fx.set_district_stage(first, 3)
	fx.set_district_stage(first, 4, ceili(need * 0.62))
	hud._process(0.016)
	assert_true(hud._field_label.visible)
	assert_true(hud._planet_label.visible)
	var city: String = fx.districts.name_of(first)
	var stage: String = Districts.stage_name(Planets.current(), 3)
	assert_eq(hud._field_label.text, "%s · %s %d%%" % [city, stage, int(floor(fx.districts.share_of(first) * 100.0))])
	assert_string_contains(hud._field_label.text, " 62%")
	assert_almost_eq(hud._field_frac, fx.districts.share_of(first), 0.0001, "the bar is the share toward the next stage")
	assert_eq(hud._planet_label.text, ("0 of %d cities restored" if total != 1 else "0 of %d city restored") % total)
	fx.set_district_stage(first, 5)
	hud._planet_t = 0.0
	hud._process(0.016)
	assert_eq(hud._field_label.text, "%s · %s" % [city, Districts.stage_name(Planets.current(), 5)], "the last stage has no share to show")
	assert_string_contains(hud._planet_label.text, "1 of %d" % total)
	fx.free_systems()
