## 9-23 需求（第二轮）复核截图（真实渲染）
##
##   1. 战斗表现层：每次攻击/受击都出数字，停留约 2 秒后消失
##   2. 暴击数字更大更亮
##   3. 受击抖动 + 出手前冲
##   4. 联合卡牌（共鸣）：组件卡面、单独打出无效果、同一回合凑齐触发全体重击
##
## 跑法：python godot_run.py _shot_review6.gd <log> --render
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
	img.save_png(path)
	print("截图已保存 -> %s" % path)


func _hps(bm) -> Array:
	var out: Array = []
	for m in bm.monsters:
		out.append(m.current_hp)
	return out


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")

	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var b: Node = current_scene
	var bm = b.battle
	await _shot(OUT + "rev6_battle_base.png")

	# =====================================================================
	# 1. 真实出一张牌 → 走完整事件链（前冲 + 轨迹 + 抖动 + 飘字）
	# =====================================================================
	var hero = bm.team[0]
	bm.selected_adventurer = hero
	hero.current_action = 9
	hero.current_mana = hero.get_max_mana()

	var atk: CardData = null
	for c in bm.deck.hand:
		if c.card_class == CardData.CardClass.ATTACK \
				and c.target_type == CardData.TargetType.SINGLE_ENEMY:
			atk = c
			break
	if atk != null and not bm.living_monsters().is_empty():
		print("真实出牌：%s" % atk.display_name)
		bm.play_card(hero, atk, bm.living_monsters()[0])
		await create_timer(0.05).timeout
		await _shot(OUT + "rev6_real_hit.png")
		await create_timer(0.6).timeout

	# =====================================================================
	# 2. 普通伤害 vs 暴击：并排对比（暴击更大更亮）
	# =====================================================================
	var mons = bm.living_monsters()
	if mons.size() >= 2:
		b._on_combat_feedback({
			"kind": "damage", "unit": mons[0], "source": hero,
			"amount": 18, "crit": false, "killed": false, "downed": false,
		})
		b._on_combat_feedback({
			"kind": "damage", "unit": mons[1], "source": hero,
			"amount": 87, "crit": true, "killed": false, "downed": false,
		})
		await create_timer(0.09).timeout
		await _shot(OUT + "rev6_crit_compare.png")
		print("飘字节点数（弹出瞬间）：%d" % b._fx.get_child_count())
		await create_timer(1.2).timeout
		await _shot(OUT + "rev6_floats_lingering.png")
		print("飘字节点数（1.3s 后仍在）：%d" % b._fx.get_child_count())
		await create_timer(1.2).timeout
		await _shot(OUT + "rev6_floats_gone.png")
		print("飘字节点数（2.5s 后已消失）：%d" % b._fx.get_child_count())

	# =====================================================================
	# 3. 受击抖动：静止 / 抖动中 两帧对照
	# =====================================================================
	var mon_view: Node = null
	for u in b._unit_views:
		if u.monster != null:
			mon_view = u
			break
	if mon_view != null:
		await _shot(OUT + "rev6_shake_before.png")
		mon_view.play_hit(true)
		await process_frame
		await _shot(OUT + "rev6_shake_during.png")
		print("抖动瞬间 VisualRoot 偏移 = %s" % str(mon_view._visual_root.position))
		await create_timer(0.6).timeout

	# =====================================================================
	# 4. 联合卡牌（共鸣）
	# =====================================================================
	var wind: CardData = gd.db.get_card("rune_wind")
	var fire: CardData = gd.db.get_card("rune_fire")
	print("组件卡：%s / %s   组合=%s  倍率=%.1f  行动费=%d  蓝耗=%d" % [
		wind.display_name, fire.display_name, wind.combo_name,
		wind.combo_multiplier, wind.action_cost, wind.mana_cost,
	])

	# 把两张组件卡塞进手牌（另加几张普通卡让手牌看起来正常）
	bm.deck.hand.clear()
	bm.deck.hand.append(wind)
	bm.deck.hand.append(fire)
	for i in range(3):
		var filler: CardData = gd.db.get_card("strike")
		if filler != null:
			bm.deck.hand.append(filler)
	b._refresh_hand()
	await create_timer(0.35).timeout
	await _shot(OUT + "rev6_combo_hand.png")

	# 把敌人血量整体调高（连最大值一起改，避免血条出现 223/42 这种假数据），
	# 让共鸣打得出来但不至于一击秒杀 —— 纯为截图可读
	var scaled := {}
	for m in bm.monsters:
		if not scaled.has(m.data.id):
			m.data.hp = m.data.hp * 8
			scaled[m.data.id] = true
		m.current_hp = m.data.hp
		m.shield = 0
	hero.intelligence = 18
	hero.current_mana = 200
	hero.current_action = 9
	await process_frame
	b._refresh_units()

	var hp_before := _hps(bm)

	# 第一张：只登记，不造成任何伤害
	bm.play_card(hero, wind, null)
	await create_timer(0.35).timeout
	await _shot(OUT + "rev6_combo_first.png")
	print("打出第一张后 → 敌人血量：%s（应与出牌前一致）" % str(_hps(bm)))
	print("共鸣槽：%s" % str(bm.combo_cast))

	# 第二张：触发共鸣
	bm.play_card(hero, fire, null)
	await create_timer(0.05).timeout
	await _shot(OUT + "rev6_combo_trigger.png")
	await create_timer(0.12).timeout
	await _shot(OUT + "rev6_combo_banner.png")
	print("打出第二张后 → 敌人血量：%s" % str(_hps(bm)))
	print("共鸣后共鸣槽（应已清空）：%s" % str(bm.combo_cast))
	print("本场累计伤害：%d" % bm.damage_dealt)

	await create_timer(1.0).timeout
	await _shot(OUT + "rev6_combo_after.png")

	quit(0)
