class_name CJKFallback
extends RefCounted
## [i18n] CJK glyphs for the UI. The built-in UI font (Open Sans) and the Ledger's Anonymous Pro have
## no Chinese or Japanese characters, so both get the subset Noto Sans CJK fonts in ui/fonts/cjk/ as
## fallbacks. The font matching the active locale goes first, so shared Han characters take the
## Japanese or Simplified Chinese glyph shape as appropriate. Both stay attached in every locale:
## the language picker shows "简体中文" and "日本語" even in English.
## Rebuild the subsets with tools/build_cjk_fonts.py after editing zh_CN.po or ja.po.

const FONT_SC: String = "res://ui/fonts/cjk/NotoSansSC-Subset.otf"
const FONT_JP: String = "res://ui/fonts/cjk/NotoSansJP-Subset.otf"

static var _cache: Dictionary = {}


static func _font(path: String) -> Font:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path] as Font


## CJK fallbacks in priority order for `locale` (Japanese first for "ja", Chinese first otherwise).
static func fonts_for(locale: String) -> Array[Font]:
	var paths: Array[String] = [FONT_SC, FONT_JP]
	if locale.begins_with("ja"):
		paths.reverse()
	var out: Array[Font] = []
	for p: String in paths:
		var f: Font = _font(p)
		if f != null:
			out.append(f)
	return out


## Puts the CJK fallbacks (ordered for `locale`) after any other fallbacks of the UI fonts.
static func apply(locale: String) -> void:
	var ours: Array[Font] = fonts_for(locale)
	for base: Font in [ThemeDB.fallback_font, LedgerUplink.mono_font()]:
		if base == null:
			continue
		var kept: Array[Font] = []
		for f: Font in base.fallbacks:
			if f != null and not (f.resource_path in [FONT_SC, FONT_JP]):
				kept.append(f)
		kept.append_array(ours)
		base.fallbacks = kept
