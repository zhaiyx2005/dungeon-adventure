## 9-22 修改意见（修改2.docx）复核截图（真实渲染）
## 跑法：python godot_run.py _shot_review2.gd <log> --render
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

	# ---- 1. 主菜单（居中 + 金币右上角） ----
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.9).timeout
	await _shot(current_scene, OUT + "rev2_menu.png")

	# ---- 2. 战斗：手牌（排序 + 清晰度） ----
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var b: Node = current_scene
	await _shot(b, OUT + "rev2_battle_hand.png")

	# 悬停放大
	if b._card_views.size() >= 2:
		var hv: Node = b._card_views[1]
		hv._on_mouse_entered()
		await create_timer(0.3).timeout
		await _shot(b, OUT + "rev2_battle_hover.png")

		# 拖拽贝塞尔箭头（拖向第一个敌方单位）
		var to := Vector2(700.0, 380.0)
		for uv in b._unit_views:
			if uv.monster != null:
				to = uv.global_position + uv.size * 0.5
				break
		var from: Vector2 = hv.global_position + hv.size * 0.5
		var inv: Transform2D = b._arrow.get_global_transform().affine_inverse()
		b._arrow.set_line(inv * from, inv * to, true)
		await create_timer(0.25).timeout
		await _shot(b, OUT + "rev2_battle_arrow.png")
		b._arrow.clear_line()
		hv._on_mouse_exited()

	# ---- 3. 城镇：商店卖卡 / 详情弹窗 / 招募木板 / 卡组 ----
	if gd != null:
		gd.gold = 3000
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	var town: Node = current_scene

	town._switch_tab(0)
	await create_timer(0.3).timeout
	await _shot(town, OUT + "rev2_guild_home.png")

	# 详情弹窗（走真实 clicked 信号）
	var hero: Adventurer = gd.team[0]
	var probe: CardFrame = town._adventurer_card(hero)
	probe.clicked.emit(probe)
	await create_timer(0.35).timeout
	await _shot(town, OUT + "rev2_detail_popup.png")
	town._close_popup()
	await create_timer(0.2).timeout

	# 招募木板（条件换行、卡牌不被撑宽）
	town._on_guild_mode("recruit")
	await create_timer(0.3).timeout
	await _shot(town, OUT + "rev2_recruit.png")

	# 商店（新增卡牌售卖区）
	town._switch_tab(2)
	await create_timer(0.3).timeout
	await _shot(town, OUT + "rev2_shop_cards.png")

	# 卡组界面（左侧=持有卡）
	town._switch_tab(1)
	await create_timer(0.2).timeout
	town._on_open_deck()
	await create_timer(0.3).timeout
	await _shot(town, OUT + "rev2_deck_edit.png")
	town._on_close_deck()

	# ---- 4. 地牢：准备面板 + 地图（右侧已无按钮） ----
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(1.0).timeout
	var rs: Node = current_scene
	await _shot(rs, OUT + "rev2_dungeon_prepare.png")
	rs._on_select_level(1)
	await create_timer(0.6).timeout
	await _shot(rs, OUT + "rev2_dungeon_map.png")

	print("修改意见复核截图完成")
	quit(0)
