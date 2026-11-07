class_name L10nFmt
extends RefCounted
## [i18n2] Shared display formats that used to be glued together in English: reward suffixes
## ("+25 cubes", "+1 trinket"), rarity + part names ("Rusty Chassis Frame") and research effect
## lines ("+10% Scoopie speed"). Each is one translatable pattern, so a language can reorder the
## words (French "Châssis rouillé", "+10 % de vitesse de Scoopie") and pick plural forms.


static func _t(msg: String, ctx: String = "") -> String:
	return TranslationServer.translate(msg, ctx)


## "+N <currency>" for a reward dictionary key. [money] Only cubes, parts and seeds exist; a legacy
## id (bolts, data, ...) is shown as the currency it pays now, converted at its rate.
static func reward(currency: String, n: int) -> String:
	var c: String = Currencies.canonical(currency)
	if c != currency:
		n = int(round(n * Currencies.rate(currency)))
	match c:
		"cubes":
			return TranslationServer.translate_plural("+%d cube", "+%d cubes", n) % n
		"seeds":
			return TranslationServer.translate_plural("+%d seed", "+%d seeds", n) % n
		"parts":
			return TranslationServer.translate_plural("+%d part", "+%d parts", n) % n
	return "+%d %s" % [n, currency]


## Currencies amount() has its own counted pattern for.
const COUNTED: Array[String] = ["cubes", "seeds", "parts"]  # [money]


static func has_count(currency: String) -> bool:
	return Currencies.canonical(currency) in COUNTED


## "<amount> <currency>" for a big formatted amount ("1.2K cubes", "1 seed"); `plus` prefixes "+".
## [money] Legacy ids are converted to the currency they pay now.
static func amount(currency: String, value: float, plus: bool = false) -> String:
	var c: String = Currencies.canonical(currency)
	if c != currency:
		value *= Currencies.rate(currency)
	var txt: String = Settings.fmt(BigNum.from_float(value))
	var n: int = int(clampf(round(value), 0.0, 1.0e9))
	var out: String
	match c:
		"cubes":
			out = TranslationServer.translate_plural("%s cube", "%s cubes", n) % txt
		"seeds":
			out = TranslationServer.translate_plural("%s seed", "%s seeds", n) % txt
		"parts":
			out = TranslationServer.translate_plural("%s part", "%s parts", n) % txt
		_:
			out = "%s %s" % [txt, _t(currency.replace("_", " "))]
	return ("+" + out) if plus else out


## Every entry of a reward dictionary ({cubes: 25, trinkets: 1}) as "+25 cubes  +1 trinket".
static func rewards(rew: Dictionary, sep: String = "  ") -> String:
	var bits: Array[String] = []
	var f: Dictionary = Currencies.fold(rew)  # [money] legacy keys folded into the three
	for k: String in Currencies.IDS:
		if float(f.get(k, 0.0)) > 0.0:
			bits.append(reward(k, int(round(float(f[k])))))
	return sep.join(bits)


## A part's display name: rarity adjective + part type, in the language's word order.
static func part_name(rarity: int, type_index: int) -> String:
	return part_label(_t(str(Economy.rarity(rarity).get("name", ""))), _t(str(Economy.part_type(type_index).get("name", "part"))))


## Joins an already translated rarity and part name ("Rusty" + "Chassis Frame").
static func part_label(rarity_name: String, part: String) -> String:
	if rarity_name == "":
		return part
	# TRANSLATORS: a part's name. {rarity} is an adjective (Rusty, Polished, Rare...), {part} a part type
	# (Chassis Frame, Battery...). Reorder for your language, e.g. "{part} {rarity}".
	return _t("{rarity} {part}", "part name").format({"rarity": rarity_name, "part": part})


## A research effect line. `amount` is already formatted ("10" or "0.5"); `robot` is a translated
## robot name or ""; `stat` a translated stat name.
static func stat_effect(amount: String, percent: bool, robot: String, stat: String) -> String:
	var args: Dictionary = {"amount": amount, "robot": robot, "stat": stat}
	if robot == "":
		if percent:
			# TRANSLATORS: research effect, e.g. "+20% scoop width". {stat} is a stat name.
			return _t("+{amount}% {stat}").format(args)
		# TRANSLATORS: research effect, e.g. "+2 tank". {stat} is a stat name.
		return _t("+{amount} {stat}").format(args)
	if percent:
		# TRANSLATORS: research effect for one robot model, e.g. "+10% Scoopie speed".
		return _t("+{amount}% {robot} {stat}").format(args)
	# TRANSLATORS: research effect for one robot model, e.g. "+1 Drip tank".
	return _t("+{amount} {robot} {stat}").format(args)
