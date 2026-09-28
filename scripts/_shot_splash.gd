## 截图脚本：验证开屏页（真实渲染）
## 跑法：python godot_run.py _shot_splash.gd <log> --render
## 验证点：
##   1. 开屏图 1（上午）+ 游戏名渐显 + 点击提示
##   2. 约 5 秒后切到开屏图 2（中午）
##   3. 模拟鼠标左键 → 应进入主菜单
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


func _fake_click() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(640, 360)
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(640, 360)
	Input.parse_input_event(release)


func _run() -> void:
	await create_timer(0.5).timeout

	# ---- 1. 开屏首页（上午图 + 标题 + 提示） ----
	change_scene_to_file("res://scenes/splash_scene.tscn")
	await create_timer(2.6).timeout
	await _shot(current_scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_splash_1.png")

	# ---- 2. 等 5 秒切换后（中午图） ----
	await create_timer(3.6).timeout
	await _shot(current_scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_splash_2.png")

	# ---- 3. 模拟鼠标左键 → 主菜单 ----
	_fake_click()
	await create_timer(1.2).timeout
	await _shot(current_scene, "C:/Users/20601/AppData/Local/Temp/wbtask/shot_splash_menu.png")
	print("点击后当前场景 = %s" % current_scene.name)

	print("开屏页截图全部完成")
	quit(0)
