## 城镇新版 UI + 战斗新卡面截图脚本（真实渲染）
## 跑法：python godot_run.py _shot_town2.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"


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

	var gd: Node = root.get_node_or_null("/root/GameData")
	# 准备数据让界面有内容
	if gd != null:
		gd.gold = 3000
		var sample_ids := ["short_sword", "chain_mail", "bat_wing", "health_potion", "ancient_coin"]
		gd.inventory.clear()
		for id in sample_ids:
			var it = gd.db.get_item(id)
			if it != null:
				gd.inventory.append(it)
		gd.storage.clear()
		gd.storage.append(gd.db.get_item("rusty_key"))
		var tm = load("res://scripts/town/town_manager.gd").new()
		for _i in range(2):
			var c = tm.roll_recruit()
			gd.roster.append(c["adventurer"])

	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(0.9).timeout
	var scene: Node = current_scene

	# 1. 工会主页（4 选项 + 小队人物卡）
	scene._switch_tab(0)
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_guild_home.png")

	# 2. 任务木板
	scene._on_guild_mode("quests")
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_quests.png")

	# 3. 招募木板
	scene._on_guild_mode("recruit")
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_recruit.png")

	# 4. 组建队伍
	scene._on_guild_mode("team")
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_team.png")

	# 5. 伟业升级
	scene._on_guild_mode("trophy")
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_trophy.png")

	# 6. 作战整备
	scene._switch_tab(1)
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_prepare.png")

	# 7. 卡组界面
	scene._on_open_deck()
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_deck.png")
	scene._on_close_deck()

	# 8. 商店
	scene._switch_tab(2)
	await create_timer(0.3).timeout
	await _shot(scene, OUT + "shot2_shop.png")

	# 9. 战斗手牌（新卡面）
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var bscene: Node = current_scene
	await _shot(bscene, OUT + "shot2_battle_hand.png")

	print("全部新版截图完成")
	quit(0)
