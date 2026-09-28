## 9-23 修改意见（修改1.docx）复核截图（真实渲染）
##   意见1：箭头不吸附、且自身卡（防御）指向释放者本人
##   意见2：战斗卡新版式（左上行动点 / 右上蓝量 / 最上方名字 / 上半图 / 下半描述）
## 跑法：python godot_run.py _shot_review4.gd <log> --render
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
	var err := img.save_png(path)
	print("截图已保存 -> %s (err=%d)" % [path, err])


## 找一张手牌里满足条件的卡
func _find_card(b: Node, want_self: bool) -> Node:
	for v in b._card_views:
		var c: CardData = v.card
		if c == null:
			continue
		if want_self and c.target_type == CardData.TargetType.SELF:
			return v
		if not want_self and c.target_type == CardData.TargetType.SINGLE_ENEMY:
			return v
	return null


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd != null:
		gd.gold = 3000

	# ---- 1. 战斗：新版战斗卡手牌（意见2） ----
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var b: Node = current_scene
	await _shot(OUT + "rev4_battle_hand.png")

	# ---- 2. 悬停放大看细节（意见2：左上行动点 / 右上蓝量） ----
	if b._card_views.size() > 0:
		var hv: Node = b._card_views[0]
		for v in b._card_views:
			if v.card != null and v.card.mana_cost > 0:
				hv = v
				break
		hv._on_mouse_entered()
		await create_timer(0.35).timeout
		await _shot(OUT + "rev4_card_hover_spell.png")
		hv._on_mouse_exited()

	# ---- 3. 意见1a：攻击卡拖到敌人 —— 箭头跟随鼠标（不吸附） ----
	var atk := _find_card(b, false)
	if atk != null and b._unit_views.size() > 0:
		var enemy_uv: Node = null
		for uv in b._unit_views:
			if uv.monster != null:
				enemy_uv = uv
				break
		if enemy_uv != null:
			# 关键：_process 每帧都会用真实鼠标位置重算箭头，
			# 必须先停掉它，否则注入的坐标会被立刻覆盖。
			b.set_process(false)
			var from: Vector2 = atk.global_position + atk.size * 0.5
			b._drag_origin = from
			b._dragging_view = atk
			# 终点取敌人框内的偏侧位置：吸附版会跳到中心，新版应停在鼠标处
			var mp: Vector2 = enemy_uv.global_position + enemy_uv.size * Vector2(0.25, 0.3)
			b._highlight_drop_target(mp)
			var inv: Transform2D = b._arrow.get_global_transform().affine_inverse()
			b._arrow.set_line(inv * from, inv * mp, b._drop_valid)
			print("攻击卡箭头终点 = %s（鼠标注入点）/ 目标中心 = %s / 合法=%s"
				% [mp, enemy_uv.global_position + enemy_uv.size * 0.5, b._drop_valid])
			await create_timer(0.25).timeout
			await _shot(OUT + "rev4_arrow_nosnap.png")
			b._dragging_view = null
			b._arrow.clear_line()
			b.set_process(true)

	# ---- 4. 意见1b：防御卡（自身卡）箭头指向释放者本人 ----
	var self_v := _find_card(b, true)
	if self_v == null and b._card_views.size() > 0:
		# 手牌里没有防御卡 → 临时借一张显示
		self_v = b._card_views[0]
		self_v.card = load("res://data/cards/guard_phys.tres")
	var caster_view: Node = b._unit_view_of_adventurer(b.battle.selected_adventurer)
	if self_v != null and caster_view != null:
		b.set_process(false)
		var f2: Vector2 = self_v.global_position + self_v.size * 0.5
		b._drag_origin = f2
		b._dragging_view = self_v
		var anywhere := Vector2(1150.0, 120.0)          # 故意把鼠标拖到远处
		b._highlight_drop_target(anywhere)
		var tip: Vector2 = b._arrow_tip_for(anywhere)   # 应 = 释放者中心
		var inv2: Transform2D = b._arrow.get_global_transform().affine_inverse()
		b._arrow.set_line(inv2 * f2, inv2 * tip, b._drop_valid)
		print("自身卡箭头终点 = %s / 释放者中心 = %s"
			% [tip, caster_view.global_position + caster_view.size * 0.5])
		await create_timer(0.25).timeout
		await _shot(OUT + "rev4_arrow_self.png")
		b._dragging_view = null
		b._arrow.clear_line()
		b.set_process(true)

	# ---- 5. 城镇：人物卡 / 物品卡 / 战斗卡同一卡面组件 ----
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	var town: Node = current_scene
	town._switch_tab(4)                              # 卡牌大全
	await create_timer(0.4).timeout
	await _shot(OUT + "rev4_codex_cards.png")
	town._switch_tab(2)                              # 商店
	await create_timer(0.4).timeout
	await _shot(OUT + "rev4_shop_cards.png")

	print("9-23 修改意见 复核截图完成")
	quit(0)
