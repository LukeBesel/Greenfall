class_name GlimBench
extends VBoxContainer
## [buddy] The "Glim" section of the workbench Upgrades tab (ui/upgrades_panel.gd): one BenchRow
## per Glim track (Lantern, Hex Scanner, Auto-Scan, Tidy Tug, Music). Hidden until Glim is found.
## Buying goes through Glim.buy (cubes / parts / seeds); the hold-F Glim panel stays a shortcut.

var world: Node
var _rows: Dictionary = {}  # track id -> BenchRow


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(BenchKit.caps(tr("Glim")))
	for t: Variant in Glim.tracks():
		var id: String = str((t as Dictionary)["id"])
		var row := BenchRow.new()
		add_child(row)
		_rows[id] = row
		row.pressed.connect(func() -> void:
			if Glim.buy(id):
				Audio.play("buy", 1.05, -2.0)
				var d: GlimDirector = GlimDirector.of(world)
				if d:
					d.refresh()
			else:
				Audio.play("buzz", 1.2, -8.0)
				Refuse.say("")  # [v9d] say why
			refresh())
	refresh()


## Player-facing reason a track can't be bought now ("" = buyable).
static func reason_text(id: String) -> String:
	var why: String = Glim.block_reason(id)
	if why.begins_with("Needs "):
		var req: Dictionary = Glim.track(id).get("requires", {})
		for k: String in req:
			if Glim.tier(k) < int(req[k]):
				return TranslationServer.translate("Needs %s %d") % [TranslationServer.translate(str(Glim.track(k).get("name", k))), int(req[k])]
	if why != "":
		return TranslationServer.translate(why)
	if not GameState.can_afford_all(Glim.next_cost(id)):
		return TranslationServer.translate("Not enough cubes, parts or seeds")
	return ""


func refresh() -> void:
	visible = Glim.is_found()
	if not visible:
		return
	for id: String in _rows:
		var t: Dictionary = Glim.track(id)
		var row: BenchRow = _rows[id]
		var tier: int = Glim.tier(id)
		var mx: int = Glim.max_tier(id)
		var maxed: bool = tier >= mx
		var reason: String = reason_text(id)
		row.show_entry(tr(str(t.get("name", id))), "%d / %d" % [tier, mx], tr(str(t.get("desc", ""))),
			{} if maxed else Glim.next_cost(id), tr("Maxed") if maxed else tr("Upgrade"), reason, HubBuilds.not_enough(reason))
