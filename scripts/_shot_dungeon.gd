## 地牢界面截图脚本（真实渲染）
##
## 跑法：godot --path <项目> --script res://scripts/_shot_dungeon.gd --rendering-driver opengl3
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

	# ---- 1. 选层面板 ----
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(0.9).timeout
	var scene: Node = current_scene
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_dungeon_select.png")

	# ---- 2. 开始第 1 层，截地图 ----
	scene._on_select_level(1)
	await create_timer(0.6).timeout
	await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_dungeon_map.png")

	# ---- 3. 前进一个节点，截进度 ----
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd != null and gd.run != null:
		var target = MapGenerator.find(gd.run.map, 5, 1)
		if target != null and gd.run.move_to(target):
			await create_timer(0.3).timeout
			scene._refresh()
			await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_dungeon_map2.png")

	# ---- 4. 触发一个事件弹窗 ----
	if gd != null and gd.run != null:
		gd.run.resolve_event()
		scene._show_overlay(gd.run.last_event_title, gd.run.last_event_lines, "继续探索", "", "continue", "none")
		await create_timer(0.3).timeout
		await _shot(scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_dungeon_event.png")

	print("全部地牢截图完成")
	quit(0)
