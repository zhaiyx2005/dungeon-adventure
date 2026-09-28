## 放大复核战斗卡（与卡牌大全完全一致的 desc 字符串）
## 跑法：python godot_run.py _shot_codexzoom.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.4).timeout
	var bg := ColorRect.new()
	bg.color = Color("#2b2b28")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(row)

	for spec in [
		{"id": "fatal_blow", "size": Vector2(256, 358)},
		{"id": "heavy_strike", "size": Vector2(256, 358)},
		{"id": "guard_phys", "size": Vector2(200, 280)},
	]:
		var card: CardData = load("res://data/cards/%s.tres" % spec["id"])
		if card == null:
			card = load("res://data/cards/fireball.tres")
		var cf := CardFrame.new()
		cf.custom_minimum_size = spec["size"]
		cf.style = CardFrame.STYLE_BATTLE
		row.add_child(cf)
		await process_frame
		var cat := card.get_category_name_cn()
		cf.setup(card.display_name, "%s · %s\n%s" % [cat, card.get_rarity_name_cn(), card.description],
			Color(card.art_placeholder), {
				"style": CardFrame.STYLE_BATTLE,
				"tag": cat,
				"badge_l": "%d" % card.action_cost,
				"badge_r": "%d" % card.mana_cost if card.mana_cost > 0 else "",
			})
		print("%s 尺寸%s 名字%s 描述%s 胶囊%s 字号 名=%d 描=%d 签=%d"
			% [card.id, spec["size"], cf._name_label.get_rect(), cf._desc_label.get_rect(),
				cf._art_tag.get_rect(),
				cf._name_label.get_theme_font_size("font_size"),
				cf._desc_label.get_theme_font_size("font_size"),
				cf._art_tag.get_theme_font_size("font_size")])
	await create_timer(0.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	print("-> %s" % img.save_png(OUT + "rev4_codex_zoom.png"))
	quit(0)
