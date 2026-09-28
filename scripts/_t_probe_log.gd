## 战斗记录面板探针：文本内容 + 实际像素可见性
## 跑法：python godot_run.py _t_probe_log.gd <log> --render
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.5).timeout
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	var t := 0.0
	while t < 5.0 and current_scene == null:
		await process_frame
		t += 0.016
	await create_timer(0.8).timeout
	var scene: Node = current_scene
	var bm: BattleManager = scene.battle
	print("\n===== 战斗记录面板探针 =====")

	# 出一张牌 + 结束回合，产生更多日志
	var a: Adventurer = bm.selected_adventurer
	if a == null:
		for m in bm.team:
			if m.is_alive():
				a = m
				break
	for card in bm.deck.hand.duplicate():
		if bm.can_play(a, card):
			var tgt: Variant = null
			if card.card_class == CardData.CardClass.ATTACK and not bm.living_monsters().is_empty():
				tgt = bm.living_monsters()[0]
			bm.play_card(a, card, tgt)
			break
	await create_timer(0.3).timeout
	scene._on_end_turn()
	await create_timer(0.8).timeout

	var lbl: RichTextLabel = scene.get_node_or_null("%LogLabel")
	if lbl == null:
		print("探针失败：找不到 %LogLabel")
		quit(1)
		return
	print("面板文本长度 = %d" % lbl.text.length())
	print("面板文本前 120 字：")
	print(lbl.text.substr(0, 120))
	print("面板大小 = %s / visible = %s" % [lbl.size, lbl.visible])
	print("主题字色 default_color = %s" % lbl.get_theme_color("default_color"))
	print("主题 normal_font_size = %d" % lbl.get_theme_font_size("normal_font_size"))
	print("get_line_count() = %d" % lbl.get_line_count())

	# ---- 像素检查：面板矩形内是否真有深色文字像素 ----
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var gr: Rect2 = Rect2(lbl.global_position, lbl.size)
	var dark := 0
	var total := 0
	var x0: int = maxi(0, int(gr.position.x))
	var y0: int = maxi(0, int(gr.position.y))
	var x1: int = mini(img.get_width() - 1, int(gr.position.x + gr.size.x))
	var y1: int = mini(img.get_height() - 1, int(gr.position.y + gr.size.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c: Color = img.get_pixel(x, y)
			total += 1
			if c.get_luminance() < 0.6:
				dark += 1
	print("面板全局矩形 = %s" % gr)
	print("面板区域像素 %d，深色像素 %d（%.2f%%）" % [total, dark, 100.0 * float(dark) / maxf(1.0, float(total))])
	print("结论：%s" % ("文字可见" if dark > 20 else "文字不可见（白底白字）"))
	quit(0)
