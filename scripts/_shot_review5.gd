## 9-23 修改意见（修改2.docx）复核截图（真实渲染）
##   意见1：新战斗卡边框 —— 中间名字栏文字不再溢出
##   意见2：手牌清晰度（卡面 112×157 + 字号下限抬高 + 默认窗口 1600×900）
##   意见3：弃牌模式 —— 手牌放大平铺 + 点选红框 + 「确认弃牌 / 取消」
##   意见4：任务木板改成纯色圆角块（不再用卡牌边框）
##   意见5：人物卡上半区纯色框内无文字
##   意见6：出征前整备面板（队伍加点 / 装备 / 背包道具）
## 跑法：python godot_run.py _shot_review5.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("截图失败：拿不到 viewport 图像")
		return
	var err := img.save_png(path)
	print("截图已保存 -> %s (err=%d)" % [path, err])


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd != null:
		gd.gold = 3000

	# ---- 意见1 / 2：战斗手牌（新边框 + 清晰度） ----
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var b: Node = current_scene
	await _shot(OUT + "rev5_battle_hand.png")

	# 悬停放大：看单张卡的名字栏有没有溢出、字号够不够
	if b._card_views.size() > 0:
		var hv: Node = b._card_views[0]
		for v in b._card_views:
			if v.card != null and v.card.display_name.length() >= 4:
				hv = v
				break
		hv._on_mouse_entered()
		await create_timer(0.35).timeout
		print("悬停卡：%s（名字字号 %d / 描述字号 %d）" % [
			hv.card.display_name,
			hv._frame._name_label.get_theme_font_size("font_size"),
			hv._frame._desc_label.get_theme_font_size("font_size"),
		])
		await _shot(OUT + "rev5_card_hover_name.png")
		hv._on_mouse_exited()

	# ---- 意见3：弃牌模式 ----
	b._on_discard_mode()
	await create_timer(0.35).timeout
	print("弃牌模式 = %s / 底部栏高 %.0f / 放大倍率 %.2f" % [
		b._discard_mode,
		(b.get_node("%Bottom") as PanelContainer).custom_minimum_size.y,
		(b._card_views[0] as Control).scale.x if b._card_views.size() > 0 else 0.0,
	])
	await _shot(OUT + "rev5_discard_mode.png")

	# 选中两张 → 看红框选中态
	if b._card_views.size() >= 2:
		b._on_hand_card_clicked(b._card_views[0])
		b._on_hand_card_clicked(b._card_views[1])
		await create_timer(0.25).timeout
		await _shot(OUT + "rev5_discard_selected.png")
		print("选中张数 = %d" % b._card_views.filter(func(v): return v.selected).size())
	b._set_discard_mode(false)
	await create_timer(0.25).timeout
	await _shot(OUT + "rev5_discard_exited.png")

	# 极限：手牌补满 12 张，看折行后是否仍然不重叠
	while b.battle.deck.hand.size() < 12 and b.battle.deck.draw_pile.size() > 0:
		b.battle.deck.hand.append(b.battle.deck.draw_pile.pop_back())
	b._refresh_hand()
	await create_timer(0.25).timeout
	b._on_discard_mode()
	await create_timer(0.35).timeout
	if b._card_views.size() > 0:
		var c0: Control = b._card_views[0]
		print("12 张弃牌布局：张数 %d / 倍率 %.2f / 首卡位置 %s / 末卡位置 %s" % [
			b._card_views.size(), c0.scale.x, c0.position, (b._card_views[-1] as Control).position])
	await _shot(OUT + "rev5_discard_12cards.png")
	b._set_discard_mode(false)
	await create_timer(0.25).timeout

	# ---- 意见4 / 5：城镇（任务木板纯色块 + 人物卡上半区无文字） ----
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	var town: Node = current_scene

	town._on_guild_mode("quests")
	await create_timer(0.4).timeout
	await _shot(OUT + "rev5_quest_blocks.png")

	town._on_guild_mode("home")
	await create_timer(0.4).timeout
	await _shot(OUT + "rev5_person_cards.png")

	town._on_guild_mode("recruit")
	await create_timer(0.4).timeout
	await _shot(OUT + "rev5_recruit_cards.png")

	# 单张人物卡放大对照（上半区应只有纯色，无任何文字）
	if gd != null and not gd.team.is_empty():
		var c: CardFrame = town._adventurer_card(gd.team[0])
		c.custom_minimum_size = Vector2(312, 436)
		c.position = Vector2(120, 120)
		c.z_index = 900
		town.add_child(c)
		await create_timer(0.35).timeout
		await _shot(OUT + "rev5_person_card_zoom.png")
		c.queue_free()

	# ---- 意见6：出征前整备面板 4 个标签页 ----
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(1.0).timeout
	var run_scene: Node = current_scene
	# 给点资源，各页才有内容可看
	if gd != null:
		var gear: ItemData = gd.db.get_item("chain_mail")
		if gear != null and not gd.inventory.has(gear):
			gd.inventory.append(gear)
		var potion: ItemData = gd.db.get_item("health_potion")
		if potion != null and not gd.inventory.has(potion):
			gd.inventory.append(potion)
		if not gd.team.is_empty() and gd.team[0].unspent_points <= 0:
			gd.team[0].unspent_points = 3
	run_scene._refresh_prep()          # 资源是进场景后才塞的，要重画一次概要页
	await create_timer(0.3).timeout

	await _shot(OUT + "rev5_prep_overview.png")
	for tab: String in ["team", "equip", "bag"]:
		run_scene._on_prep_tab(tab)
		await create_timer(0.45).timeout
		await _shot(OUT + "rev5_prep_%s.png" % tab)

	print("9-23 修改意见（修改2）复核截图完成")
	quit(0)
