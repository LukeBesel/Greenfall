class_name L10nAudit
extends Node
## [l10n] Finds text that skipped translation. Run with the pseudo-locale, e.g.
##   godot --headless --path . -- --fresh --autoplay --locale=pseudo --l10n-audit --time-scale=4 --quit-after=120
## Every second it reads every visible Label / Button / RichTextLabel / Label3D / LineEdit
## placeholder; pseudo text is accented, so a run of plain ASCII letters outside a [...] pseudo
## segment means a string that was never passed through tr(). report() prints and writes
## screenshots/l10n_audit.txt (unique strings, the node that showed them, how often).

const OUT_PATH: String = "res://screenshots/l10n_audit.txt"

var _seen: Dictionary = {}  # text -> [node path, count]
var _t: float = 0.0
var _plain: RegEx = RegEx.create_from_string("[A-Za-z]{3,}")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.001)
	if _t < 1.0:
		return
	_t = 0.0
	scan(get_tree().root)


## Strips pseudo segments ("[...]"), bbcode tags and {placeholders}; true if plain English is left.
func is_untranslated(text: String) -> bool:
	var s: String = text
	var re := RegEx.create_from_string("\\[[^\\[\\]]*\\]|\\{[^{}]*\\}")
	for _i: int in 4:
		s = re.sub(s, " ", true)
	return _plain.search(s) != null


func scan(root: Node) -> void:
	for n: Node in root.find_children("*", "", true, false):
		var text: String = ""
		if n is Label:
			text = (n as Label).text if (n as Label).is_visible_in_tree() else ""
		elif n is Button:
			text = (n as Button).text if (n as Button).is_visible_in_tree() else ""
		elif n is RichTextLabel:
			text = (n as RichTextLabel).get_parsed_text() if (n as RichTextLabel).is_visible_in_tree() else ""
		elif n is Label3D:
			text = (n as Label3D).text if (n as Label3D).visible else ""
		elif n is LineEdit:
			text = (n as LineEdit).placeholder_text
		if text.strip_edges() == "" or not is_untranslated(text):
			continue
		var key: String = text.strip_edges().replace("\n", " / ").left(160)
		if _seen.has(key):
			_seen[key][1] = int(_seen[key][1]) + 1
		else:
			_seen[key] = [str(n.get_path()).right(70), 1]


func report() -> void:
	var lines: Array[String] = ["[l10n-audit] locale=%s  untranslated texts on screen: %d" % [TranslationServer.get_locale(), _seen.size()]]
	for k: String in _seen:
		lines.append("  %-60s  x%d  %s" % [k, int(_seen[k][1]), _seen[k][0]])
	var out: String = "\n".join(lines)
	print(out)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(out + "\n")
