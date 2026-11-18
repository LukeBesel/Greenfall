class_name ReadableUI
extends RefCounted
## [deck] Readability floor for handheld screens (Steam Deck at 1280x800): every Label, Button
## and RichTextLabel that enters the tree gets at least Settings.MIN_FONT_PX, whatever size its
## screen asked for. One hook instead of editing every screen; sizes below 4 px are treated as
## deliberate (hidden helper labels) and left alone.

const PROPS: Dictionary = {
	"Label": ["font_size"],
	"Button": ["font_size"],
	"RichTextLabel": ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"],
}


static func install(tree: SceneTree) -> void:
	if tree.node_added.is_connected(_on_added):
		return
	tree.node_added.connect(_on_added)


static func _on_added(n: Node) -> void:
	if not n is Control:
		return
	enforce(n as Control)
	# Screens often set the size override right after add_child: check again next frame.
	var ref: WeakRef = weakref(n)
	(func() -> void:
		var c: Object = ref.get_ref()
		if c != null and (c as Node).is_inside_tree():
			enforce(c as Control)).call_deferred()


## Raises `c`'s font size(s) to the floor. Returns true when something changed.
static func enforce(c: Control, floor_px: int = Settings.MIN_FONT_PX) -> bool:
	var props: Array = []
	if c is RichTextLabel:
		props = PROPS["RichTextLabel"]
	elif c is Label:
		props = PROPS["Label"]
	elif c is Button:
		props = PROPS["Button"]
	else:
		return false
	var changed: bool = false
	for p: String in props:
		var fs: int = c.get_theme_font_size(p)
		if fs >= 4 and fs < floor_px:
			c.add_theme_font_size_override(p, floor_px)
			changed = true
	return changed
