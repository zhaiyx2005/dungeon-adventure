## 城镇界面截图脚本（真实渲染）
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

	var gd: Node = root.get_node_or_null("/root/GameData")
	# 准备点数据让界面有内容
	if gd != null:
		gd.gold = 3000
		# 背包塞几件装备/战利品/收集品
		var sample_ids := ["short_sword", "chain_mail", "bat_wing", "health_potion", "ancient_coin"]
		gd.inventory.clear()
		for id in sample_ids:
			var it = gd.db.get_item(id)
			if it != null:
				gd.inventory.append(it)
		gd.storage.clear()
		gd.storage.append(gd.db.get_item("rusty_key"))
		# 卡池塞两个招募成员
		var tm = load("res://scripts/town/town_manager.gd").new()
		for _i in range(2):
			var c = tm.roll_recruit()
			gd.roster.append(c["adventurer"])

	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(0.9).timeout
	var scene: Node = current_scene

	# 工会
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_town_guild.png")

	# 整备
	scene._switch_tab(1)
	await create_timer(0.3).timeout
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_town_prepare.png")

	# 商店
	scene._switch_tab(2)
	await create_timer(0.3).timeout
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_town_shop.png")

	# 仓库
	scene._switch_tab(3)
	await create_timer(0.3).timeout
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_town_storage.png")

	# 卡牌大全
	scene._switch_tab(4)
	await create_timer(0.3).timeout
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_town_codex.png")

	print("全部城镇截图完成")
	quit(0)
