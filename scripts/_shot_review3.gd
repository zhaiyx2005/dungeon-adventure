## 9-22 修改意见（修改3.docx）复核截图（真实渲染）
## 跑法：python godot_run.py _shot_review3.gd <log> --render
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
	if gd != null:
		gd.gold = 3000

	# ---- 1. 整备：装备栏（意见5：武器只有一个槽） ----
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	var town: Node = current_scene
	town._switch_tab(1)
	await create_timer(0.4).timeout
	await _shot(town, OUT + "rev3_prepare_slots.png")

	# ---- 2. 卡牌大全（意见6：六分类） ----
	town._switch_tab(4)
	await create_timer(0.4).timeout
	await _shot(town, OUT + "rev3_codex_six.png")

	# ---- 3. 卡组界面（六分类 + 持有/编入） ----
	town._switch_tab(1)
	await create_timer(0.2).timeout
	town._on_open_deck()
	await create_timer(0.4).timeout
	await _shot(town, OUT + "rev3_deck_six.png")
	town._on_close_deck()

	# ---- 4. 商店（意见8：刷新按钮在最上面） ----
	town._switch_tab(2)
	await create_timer(0.4).timeout
	await _shot(town, OUT + "rev3_shop_top.png")

	# ---- 5. 战斗：手牌六分类 + 悬停放大 ----
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var b: Node = current_scene
	await _shot(b, OUT + "rev3_battle_hand.png")
	if b._card_views.size() >= 2:
		var hv: Node = b._card_views[1]
		hv._on_mouse_entered()
		await create_timer(0.3).timeout
		await _shot(b, OUT + "rev3_battle_hover.png")
		# 意见2/5：拖拽时卡牌留在原位，只画箭头
		var to := Vector2(700.0, 380.0)
		for uv in b._unit_views:
			if uv.monster != null:
				to = uv.global_position + uv.size * 0.5
				break
		var from: Vector2 = hv.global_position + hv.size * 0.5
		b._drag_origin = from
		b._dragging_view = hv
		var inv: Transform2D = b._arrow.get_global_transform().affine_inverse()
		b._arrow.set_line(inv * from, inv * to, true)
		await create_timer(0.25).timeout
		await _shot(b, OUT + "rev3_battle_arrow.png")
		b._dragging_view = null
		b._arrow.clear_line()
		hv._on_mouse_exited()

	# ---- 6. 地牢准备面板（意见1：重进不再卡在旧地图） ----
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(1.0).timeout
	await _shot(current_scene, OUT + "rev3_dungeon_prepare.png")

	print("修改3 复核截图完成")
	quit(0)
