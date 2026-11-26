extends GutTest
## [v14qa] First-90-minutes QA on round Verdance: numbers that must agree, walls that must stop Lumi.

var _cubes: BigNum
var _locale: String


func before_each() -> void:
	_cubes = GameState.get_currency("cubes")
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	GameState.currencies["cubes"] = _cubes
	TranslationServer.set_locale(_locale)


## Play-critic item 8: 49.6 cubes and a price of 55 read "49" on the HUD and "need 5" on the
## bench's upgrade card (55 - 49.6 = 5.4, printed rounded down). The price minus the balance as
## shown is 6, as the cost chips and Currencies.missing say.
func test_upgrade_card_need_is_the_price_minus_the_shown_balance() -> void:
	var uid: String = ""
	for id: String in Economy.upgrade_defs:
		if Economy.is_unlocked(id) and not Economy.is_maxed(id) and Economy.upgrade_cost(id).to_float() >= 20.0:
			uid = id
			break
	assert_ne(uid, "", "an upgrade to look at")
	var cost: float = Economy.upgrade_cost(uid).to_float()
	var card := UpgradeCard.new(uid)
	add_child_autofree(card)
	await get_tree().process_frame
	for short: float in [5.4, 5.0, 0.6, 12.9]:
		GameState.currencies["cubes"] = BigNum.from_float(cost - short)
		card.refresh()
		var want: String = Currencies.missing_text("cubes", cost)
		assert_eq(card._eta.text.get_slice(" · ", 0), "need %s" % want, "%s short of %.0f (HUD shows %s)" % [short, cost, Currencies.have_text(cost - short)])
		assert_eq(int(want), int(ceil(cost)) - int(floor(cost - short)), "price as shown minus balance as shown")
