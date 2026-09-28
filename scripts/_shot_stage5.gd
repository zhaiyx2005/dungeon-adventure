## 遗留功能截图脚本（真实渲染）
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
	gd.gold = 3000
	gd.inventory.clear()
	for id in ["health_potion", "bomb", "smoke_bomb"]:
		var it = gd.db.get_item(id)
		if it != null:
			gd.inventory.append(it)

	# ---- 任务界面 ----
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(0.9).timeout
	var scene: Node = current_scene
	scene._switch_tab(1)
	await create_timer(0.3).timeout
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_quests.png")

	# ---- 主菜单（含存档/读档）----
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.7).timeout
	await _shot(current_scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_menu_save.png")

	# ---- 战斗背包弹窗 ----
	gd.pending_encounter = {}
	gd.return_scene = ""
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(0.9).timeout
	var battle: Node = current_scene
	await _shot(battle, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_bag_before.png")
	battle._on_bag()
	await create_timer(0.3).timeout
	await _shot(battle, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_bag_popup.png")

	print("全部截图完成")
	quit(0)
