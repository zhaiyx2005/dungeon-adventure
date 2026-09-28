## 9-25 音频系统复核截图（真实渲染）
##   A. 开屏页（此时应在播标题 BGM —— 画面上看不到，靠日志里的 current_bgm 佐证）
##   B. 主菜单：「游戏设置」已启用（不再是占位）
##   C. 游戏设置面板：三档音量滑杆 + 静音开关 + 返回
##   D. 滑杆拖到 35% / 静音勾选后的实时状态
##   E. 战斗场景（攻击/受击/防御/法术音效的播放侧，画面仅用于确认未被音频改动破坏）
##
## 跑法：python godot_run.py _shot_review9.gd <log> --render
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
	print("截图已保存 -> %s (err=%d)" % [path, img.save_png(path)])


func _audio() -> Node:
	return root.get_node_or_null("/root/AudioManager")


func _find(node: Node, nm: String) -> Node:
	if node == null:
		return null
	if node.name == nm:
		return node
	for ch in node.get_children():
		var hit := _find(ch, nm)
		if hit != null:
			return hit
	return null


func _run() -> void:
	var am := _audio()
	print("\n===== 音频复核 =====")
	if am == null:
		print("拿不到 AudioManager")
		quit(1)
		return

	# ---------- A. 开屏页 ----------
	change_scene_to_file("res://scenes/splash_scene.tscn")
	await create_timer(1.2).timeout
	print("开屏页 BGM = 「%s」，正在播 = %s" % [am.current_bgm(), str(am.is_bgm_playing())])
	await _shot(OUT + "rev9_splash.png")

	# ---------- B. 主菜单 ----------
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.8).timeout
	var menu: Node = current_scene
	print("主菜单 BGM = 「%s」（与开屏同一首 → 未重头播放）" % am.current_bgm())
	await _shot(OUT + "rev9_menu.png")

	# 列出菜单项启用状态
	print("\n菜单项：")
	for btn in menu.get_node("%MenuBox").get_children():
		if btn is Button:
			print("  %-12s disabled=%s" % [(btn as Button).text, str((btn as Button).disabled)])

	# ---------- C/D. 设置面板 ----------
	menu.open_audio_settings()
	await create_timer(0.35).timeout
	await _shot(OUT + "rev9_settings_default.png")

	var music := _find(menu, "Slider_音乐") as HSlider
	var sfx := _find(menu, "Slider_音效") as HSlider
	var master := _find(menu, "Slider_主音量") as HSlider
	if music != null:
		music.value = 0.35
	if sfx != null:
		sfx.value = 0.65
	if master != null:
		master.value = 0.85
	await create_timer(0.25).timeout
	print("\n拖动后：主音量 %.2f / 音乐 %.2f / 音效 %.2f"
		% [float(am.get_master_volume()), float(am.get_music_volume()), float(am.get_sfx_volume())])
	print("总线实测：Master %.3f / Music %.3f / SFX %.3f"
		% [float(am.bus_volume("Master")), float(am.bus_volume("Music")), float(am.bus_volume("SFX"))])
	await _shot(OUT + "rev9_settings_tuned.png")

	var mute := _find(menu, "MuteCheck") as CheckBox
	if mute != null:
		mute.button_pressed = true
		await create_timer(0.2).timeout
		print("勾选静音后 muted=%s，Master 总线音量 %.4f"
			% [str(am.muted), float(am.bus_volume("Master"))])
		await _shot(OUT + "rev9_settings_muted.png")
		mute.button_pressed = false
		await create_timer(0.15).timeout
	print("取消静音后 muted=%s" % str(am.muted))

	# ---------- E. 战斗场景（音频接线不影响画面） ----------
	var gd: Node = root.get_node_or_null("/root/GameData")
	gd.last_battle_result = {}
	gd.pending_encounter = {}
	gd.run = null
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	print("\n战斗场景 BGM = 「%s」" % am.current_bgm())

	# 模拟一轮完整打击：物理起手 + 命中 + 暴击 + 护盾 + 法术
	var scene: Node = current_scene
	am.clear_played_log()
	scene._play_feedback_audio({"kind": "attack_start", "damage_type": "PHYSICAL"})
	scene._play_feedback_audio({"kind": "damage", "damage_type": "PHYSICAL", "amount": 24, "crit": true})
	scene._play_feedback_audio({"kind": "attack_start", "damage_type": "MAGICAL"})
	scene._play_feedback_audio({"kind": "damage", "damage_type": "MAGICAL", "amount": 31})
	scene._play_feedback_audio({"kind": "shield", "amount": 18})
	print("一轮打击触发的音效序列：%s" % str(am.played_log))
	await create_timer(0.35).timeout
	await _shot(OUT + "rev9_battle.png")

	print("\n完成")
	quit(0)
