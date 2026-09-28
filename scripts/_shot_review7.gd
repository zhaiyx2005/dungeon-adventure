## 9-23 需求复核截图（真实渲染）—— 5 张廉价法术
##   A. 城镇「卡牌大全」：新法术已归入「法术进攻」六分类
##   B. 卡组编辑「卡池」：新法术可被编入（先发到持有卡池）
##   C. 卡面放大：5 张新法术 + 1 张共鸣组件对照，核对角标 / 名字 / 描述分区
## 跑法：python godot_run.py _shot_review7.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"
const CHEAP := ["spark", "wind_blade", "ice_shard", "static_bolt", "flame_wave"]


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("截图失败：拿不到 viewport 图像")
		return
	print("截图已保存 -> %s (err=%d)" % [path, img.save_png(path)])


func _run() -> void:
	await create_timer(0.5).timeout

	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("拿不到 GameData")
		quit(1)
		return
	gd.gold = 5000

	# 新法术发到持有卡池，好让卡组编辑界面里能看到
	for cid in CHEAP:
		for _i in range(2):
			gd.add_owned_card(gd.db.get_card(cid))

	# 打印数据侧实况，便于与截图对照
	print("\n-- 5 张新法术数据 --")
	for cid in CHEAP:
		var c: CardData = gd.db.get_card(cid)
		print("  %-12s %s/%s 行动%d 蓝%d 倍率%.1f 目标%s 稀有%s 标签%s"
			% [cid, c.get_category_name_cn(), c.damage_type, c.action_cost,
				c.mana_cost, c.multiplier, c.target_type, c.get_rarity_name_cn(),
				str(c.effect_tags)])

	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(0.9).timeout
	var scene: Node = current_scene

	# A. 卡牌大全（tab 4）——法术进攻组里应能看到 5 张新卡
	scene._switch_tab(4)
	await create_timer(0.35).timeout
	await _shot(OUT + "rev7_codex.png")

	# B. 卡组编辑卡池（入口在「作战整备」标签页上）
	scene._switch_tab(1)
	await create_timer(0.3).timeout
	scene._on_open_deck()
	await create_timer(0.35).timeout
	await _shot(OUT + "rev7_deck_pool.png")
	scene._on_close_deck()
	await create_timer(0.2).timeout

	# C. 卡面放大（横向一排，深底衬托）
	var bg := ColorRect.new()
	bg.color = Color("#3b3a36")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var title := Label.new()
	title.text = "9-23 补充的 5 张廉价法术（右一为共鸣组件对照）"
	title.position = Vector2(24, 10)
	bg.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 42.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(row)

	for cid in CHEAP + ["rune_wind"]:
		var c: CardData = gd.db.get_card(cid)
		if c == null:
			continue
		var cf := CardFrame.new()
		cf.custom_minimum_size = Vector2(168, 235)
		# 坑：HBox/VBox 默认把子节点纵向拉满 → 卡面被拉长，量出来的分区比例全是错的
		cf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cf.style = CardFrame.STYLE_BATTLE
		row.add_child(cf)
		await process_frame
		var cat: String = c.get_category_name_cn()
		var tag_text := "共鸣" if c.has_combo() else cat
		var head := "%s · %s" % [cat, c.get_rarity_name_cn()]
		if c.has_combo():
			head = c.get_combo_hint_cn()
		cf.setup(c.display_name,
			"%s\n%s" % [head, c.description],
			Color(c.art_placeholder),
			{
				"style": CardFrame.STYLE_BATTLE,
				"tag": tag_text,
				"badge_l": "%d" % c.action_cost,
				"badge_r": "%d" % c.mana_cost if c.mana_cost > 0 else "",
			})
		print("卡面 %-12s tag=%s 名=%s 行动角标=%s 蓝角标=%s"
			% [cid, tag_text, c.display_name, cf._badge_l.text, cf._badge_r.text])

	await create_timer(0.4).timeout
	await _shot(OUT + "rev7_cardface.png")

	# D. 手牌尺寸（112×157）下的描述文字预算 —— 与 _probe_descfit.gd 的数值结论互相印证
	for c in bg.get_children():
		c.queue_free()
	await process_frame
	var t2 := Label.new()
	t2.text = "手牌尺寸 112×157：guard_phys / static_bolt / rune_wind（描述框仅 46px，行高 12px）"
	t2.position = Vector2(24, 10)
	bg.add_child(t2)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 18)
	row2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row2.offset_top = 42.0
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(row2)
	for cid in ["guard_phys", "static_bolt", "rune_wind"]:
		var c: CardData = gd.db.get_card(cid)
		if c == null:
			continue
		var cf := CardFrame.new()
		cf.custom_minimum_size = Vector2(112, 157)
		cf.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 同上：别被容器拉长
		cf.style = CardFrame.STYLE_BATTLE
		row2.add_child(cf)
		await process_frame
		var cat: String = c.get_category_name_cn()
		var head := "%s · %s" % [cat, c.get_rarity_name_cn()]
		if c.has_combo():
			head = c.get_combo_hint_cn()
		cf.setup(c.display_name, "%s\n%s" % [head, c.description],
			Color(c.art_placeholder),
			{
				"style": CardFrame.STYLE_BATTLE,
				"tag": "共鸣" if c.has_combo() else cat,
				"badge_l": "%d" % c.action_cost,
				"badge_r": "%d" % c.mana_cost if c.mana_cost > 0 else "",
			})
		print("手牌尺寸 %-12s 描述框 %s 字号 %d"
			% [cid, str(cf._desc_label.get_rect().size),
				cf._desc_label.get_theme_font_size("font_size")])
	await create_timer(0.4).timeout
	await _shot(OUT + "rev7_hand_size.png")

	print("廉价法术复核截图完成")
	quit(0)
