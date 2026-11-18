class_name Refuse
extends RefCounted
## [v9d] A refused action says why (owner: "easy to understand"): a short line as a toast, at
## most once every GAP_MS for the same line, beside the buzz the action already plays.

const GAP_MS: int = 3000
static var _last: Dictionary = {}


static func say(text: String) -> void:
	if text.strip_edges() == "":
		text = TranslationServer.translate("Not enough cubes or parts.")
	var now: int = Time.get_ticks_msec()
	if now - int(_last.get(text, -100000)) < GAP_MS:
		return
	_last[text] = now
	EventBus.toast.emit(text, "info")


## The usual reason for a refused purchase: what is still missing of `price` ({} = the generic line).
static func short(price: Dictionary = {}) -> void:
	var t: String = ListDetail.short_text(price) if not price.is_empty() else ""
	say(t)
