class_name WorldBanner
extends CanvasLayer
## [late] The arrival card on a new Cradle Mode world: its number and name, world type, the two
## modifiers spelled out, and the Heirloom starting kit. Fades in, holds, fades out.

const HOLD_S: float = 9.0


static func show_world(world: Node, w: Dictionary) -> WorldBanner:
	var b := WorldBanner.new()
	b.name = "WorldBanner"
	world.add_child(b)
	b._build(w)
	return b


func _build(w: Dictionary) -> void:
	layer = 14
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.05, 0.06, 0.78), Color(1, 1, 1, 0.1), 1, 8, 22))
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 0.0
	pc.offset_left = -330
	pc.offset_right = 330
	pc.offset_top = 70
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var sub := UITheme.label(tr("SEED MISSION  ·  WORLD %d") % (int(w.get("index", 0)) + 1), 12, Color(0.4, 0.75, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var t := UITheme.label(str(w.get("name", "")).to_upper(), 40, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var ty: Dictionary = WorldGen.world_type(str(w.get("type", "")))
	var tl := UITheme.label("%s  ·  %s" % [tr(str(ty.get("name", ""))), tr(str(ty.get("desc", "")))], 14, UITheme.CREAM)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tl)
	vb.add_child(UITheme.hazard_strip(4))
	for id: Variant in w.get("modifiers", []):
		var m: Dictionary = WorldGen.modifier(str(id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		row.add_child(UITheme.label(tr(str(m.get("name", id))).to_upper(), 13, UITheme.GOLD))
		var d := UITheme.label(tr(str(m.get("desc", ""))), 13, UITheme.MUTED)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(d)
	var kit := UITheme.label(ArkBridge._kit_text(CradleMode.start_kit(CradleMode.profile.get("heirlooms", {}))), 13, UITheme.GREEN)
	kit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(kit)
	root.modulate.a = 1.0 if DevHooks.has("banner-hold") else 0.0  # shots: already up
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(root, "modulate:a", 1.0, 0.8)
	tw.tween_interval(DevHooks.get_f("banner-hold", HOLD_S))
	tw.tween_property(root, "modulate:a", 0.0, 1.2)
	tw.tween_callback(queue_free)
	Audio.play("chime", 0.8, -6.0)
	EventBus.toast.emit(tr("Lumi's pod is down on %s. A new world, ruined and waiting. Grow something.") % str(w.get("name", "")), "story")
