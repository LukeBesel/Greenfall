class_name CurrencyIcon
extends Control
## [money] The hairline icon of one of the three currencies (cube / part / seed, HudIcons), so the
## HUD, the workbench, the Command view, the Builder and every cost label use the same glyphs.

var currency: String = "cubes"
var color: Color = UITheme.CREAM
var line_w: float = 1.4


func _init(cur: String = "cubes", px: float = 18.0, col: Color = Color(0, 0, 0, 0)) -> void:
	currency = cur
	custom_minimum_size = Vector2(px, px)
	color = col if col.a > 0.0 else tint(cur)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The currency's colour from data/currencies.json.
static func tint(cur: String) -> Color:
	return Color.html(str(Currencies.def(Currencies.canonical(cur)).get("color", "#f4ecd8")))


func _draw() -> void:
	HudIcons.draw(self, Currencies.icon(currency), size * 0.5, minf(size.x, size.y) * 0.46, color, line_w)
