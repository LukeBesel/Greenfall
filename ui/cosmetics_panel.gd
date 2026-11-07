class_name CosmeticsPanel
extends VBoxContainer
## Workbench "Cosmetics" tab: swap the main bot's colorway. Colorways unlock through play.

# l10n:begin
const UNLOCKS: Dictionary = {
	"aurora": "Default",
	"patch": "Clean 10 hexes",
	"bolt": "Build 3 robots",
	"sprout": "Grow your first sprout",
	"pixel": "Read 4 memory shards",
	"nova": "Upgrade any robot fleet to Mk III",
}
# l10n:end

var world: Node
var _grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label(tr("DESIGNS"), 20, UITheme.CREAM))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	add_child(_grid)
	refresh()


static func check_unlocks() -> void:
	var have: Array = GameState.flags.get("skins_unlocked", ["aurora"])
	var add := func(id: String) -> void:
		if not (id in have):
			have.append(id)
			EventBus.toast.emit(TranslationServer.translate("New design unlocked: %s. Try it at the workbench.") % TranslationServer.translate(str(PatchModel.VARIANTS[id]["name"])), "story")
	if float(GameState.stats.get("hexes_cleaned", 0)) >= 10:
		add.call("patch")
	if float(GameState.stats.get("robots_built", 0)) >= 3:
		add.call("bolt")
	if GameState.flags.get("first_sprout", false):
		add.call("sprout")
	if float(GameState.stats.get("shards_found", 0)) >= 4:
		add.call("pixel")
	for rid: String in Economy.robot_order:
		if int(GameState.flags.get("tier_" + rid, 0)) >= 2:
			add.call("nova")
	GameState.flags["skins_unlocked"] = have


func refresh() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	var have: Array = GameState.flags.get("skins_unlocked", ["aurora"])
	var current: String = str(GameState.flags.get("patch_skin", "aurora"))
	for id: String in PatchModel.VARIANTS:
		var v: Dictionary = PatchModel.VARIANTS[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # [vqa] long names ellipsize, never widen the workbench
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var unlocked: bool = id in have
		b.text = "%s%s\n%s" % [tr(str(v["name"])), tr("   (wearing)") if id == current else "", "" if unlocked else tr("Locked: %s") % tr(str(UNLOCKS.get(id, "")))]
		b.disabled = not unlocked
		b.add_theme_color_override("font_color", (v["glow"] as Color).lightened(0.3))
		b.pressed.connect(func() -> void:
			GameState.flags["patch_skin"] = id
			if world and world.patch:
				world.patch.model.set_variant(id)
				Vfx.burst("sparkle", world.patch.global_position + Vector3(0, 0.8, 0), v["glow"])
			Audio.play("buy", 1.2, -4.0)
			refresh())
		_grid.add_child(b)
