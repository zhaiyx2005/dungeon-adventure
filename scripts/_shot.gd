## 截图脚本：加载战斗场景，出几张牌，保存截图
##
## 用真实渲染（非 --headless）跑，才能拿到画面。
## 跑法：
##   godot --path <项目> --script res://scripts/_shot.gd
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _shot(node: Node, path: String) -> void:
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

	# ---- 1. 主菜单 ----
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.8).timeout
	await _shot(current_scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_menu.png")

	# ---- 2. 战斗首屏 ----
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(0.9).timeout
	var scene: Node = current_scene
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_battle_1.png")

	# ---- 3. 出几张牌后的画面 ----
	if scene != null and scene.battle != null:
		var bm: BattleManager = scene.battle
		# 选第二个成员当释放者
		var idx := 0
		for uv in scene._unit_views:
			if uv.adventurer != null:
				idx += 1
				if idx == 2:
					scene._on_unit_clicked(uv)
					break
		await create_timer(0.2).timeout

		# 打一张攻击牌
		var played := 0
		for card in bm.deck.hand.duplicate():
			if played >= 2:
				break
			if not bm.can_play(bm.selected_adventurer, card):
				continue
			var tgt: Variant = null
			if card.card_class == CardData.CardClass.ATTACK:
				tgt = bm.living_monsters()[0]
			if bm.play_card(bm.selected_adventurer, card, tgt):
				played += 1
		await create_timer(0.3).timeout
		await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_battle_2.png")

		# ---- 4. 结束回合（看敌方行动后） ----
		scene._on_end_turn()
		await create_timer(0.6).timeout
		await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_battle_3.png")

		# ---- 5. 强行结算，看结算面板 ----
		for m in bm.monsters:
			m.take_damage(99999)
		bm._check_battle_end()
		await create_timer(0.5).timeout
		await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_result.png")

	print("全部截图完成")
	quit(0)
