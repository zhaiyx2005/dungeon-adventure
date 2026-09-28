## 放大卡面版式核对（真实渲染）
## 把战斗卡 / 人物卡各放大渲染一张，逐区检查文字与分区是否落在正确位置。
## 跑法：python godot_run.py _shot_cardface.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("截图失败")
		return
	print("截图已保存 -> %s (err=%d)" % [path, img.save_png(path)])


func _run() -> void:
	await create_timer(0.4).timeout

	# 造一个纯净容器，背景填深色以便看清卡面轮廓
	var bg := ColorRect.new()
	bg.color = Color("#3b3a36")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(row)

	# 法术卡（有蓝耗）—— 三张不同尺寸覆盖典型用法
	var spell: CardData = load("res://data/cards/meteor.tres")
	if spell == null:
		spell = load("res://data/cards/fireball.tres")
	var common: CardData = load("res://data/cards/heavy_strike.tres")
	var def: CardData = load("res://data/cards/guard_phys.tres")

	for spec in [
		{"card": spell, "size": Vector2(300, 420), "label": "战斗卡·法术 300x420"},
		{"card": common, "size": Vector2(200, 280), "label": "战斗卡·物理 200x280"},
		{"card": def, "size": Vector2(128, 179), "label": "战斗卡·防御 128x179"},
	]:
		var c: CardData = spec["card"]
		if c == null:
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		row.add_child(cell)
		var cf := CardFrame.new()
		cf.custom_minimum_size = spec["size"]
		cf.style = CardFrame.STYLE_BATTLE
		cell.add_child(cf)
		await process_frame
		cf.setup(c.display_name,
			"%s · %s\n%s" % [c.get_category_name_cn(), c.get_rarity_name_cn(), c.description],
			Color(c.art_placeholder),
			{
				"style": CardFrame.STYLE_BATTLE,
				"tag": c.get_category_name_cn(),
				"badge_l": "%d" % c.action_cost,
				"badge_r": "%d" % c.mana_cost if c.mana_cost > 0 else "",
			})
		var tip := Label.new()
		tip.text = spec["label"]
		cell.add_child(tip)
		# 打印各分区实际像素矩形，便于与素材比例对照
		print("%s → 名字 %s / 图片 %s / 描述 %s / 行动点 %s / 蓝量 %s"
			% [spec["label"], cf._name_label.get_rect(), cf._art_clip.get_rect(),
				cf._desc_label.get_rect(), cf._badge_l.get_rect(), cf._badge_r.get_rect()])
		print("   名字可见=%s 面板可见=%s 文本=%s"
			% [cf._name_label.visible, cf._name_panel.visible, cf._name_label.text])

	await create_timer(0.4).timeout
	await _shot(OUT + "rev4_cardface_zoom.png")

	print("卡面放大核对完成")
	quit(0)
