## 阶段 2d 入口链路测试：主菜单 → 战斗 → 结算 → 回主菜单
##
## 验证整条链路可跑通，且场景切换不残留状态。
extends SceneTree

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(60.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _wait_scene(timeout: float = 3.0) -> Node:
	var t := 0.0
	while t < timeout:
		var cur := current_scene
		if cur != null:
			return cur
		await process_frame
		t += 0.016
	return null


func _run() -> void:
	_watchdog()
	print("\n===== 阶段2d 入口链路测试 =====\n")

	# GameData（autoload）应已就绪
	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
		quit(1)
		return
	_ok(gd.validator_ok, "启动时数据校验通过")
	_ok(gd.team.size() == 3, "默认小队 3 人（实际 %d）" % gd.team.size())
	_ok(gd.deck.size() == 22, "默认卡组 22 张（实际 %d）" % gd.deck.size())
	_ok(DeckManager.is_valid_deck_size(gd.deck.size()), "默认卡组容量合法")
	_ok(gd.team_power() > 0, "小队总战力 %d" % gd.team_power())

	# ---- 进主菜单 ----
	print("\n-- 主菜单 --")
	change_scene_to_file("res://scenes/main_menu.tscn")
	var menu: Node = await _wait_scene()
	_ok(menu != null, "主菜单场景已就位")
	if menu == null:
		print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
		quit(1)
		return
	await process_frame
	await process_frame

	var menu_box: Node = menu.get_node_or_null("%MenuBox")
	_ok(menu_box != null, "主菜单有 MenuBox")
	var quick_btn: Button = null
	if menu_box != null:
		for ch in menu_box.get_children():
			if ch is Button and ch.text.contains("快速战斗"):
				quick_btn = ch
				break
	_ok(quick_btn != null, "存在「快速战斗」入口按钮")

	# 记录战斗前的血量，验证进战斗会重置
	var hp_before := []
	for a in gd.team:
		hp_before.append(a.current_hp)

	# ---- 点快速战斗进战场 ----
	print("\n-- 进入战斗 --")
	if quick_btn != null:
		quick_btn.pressed.emit()
	await process_frame
	var battle_scene: Node = await _wait_scene()
	await process_frame
	await process_frame
	await create_timer(0.15).timeout

	_ok(battle_scene != null, "战斗场景已就位")
	if battle_scene == null:
		print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
		quit(1)
		return
	_ok(battle_scene.battle != null, "战斗已建立")

	# 进战斗血量应重置为满
	var all_full := true
	for a in gd.team:
		if a.current_hp != a.get_max_hp():
			all_full = false
	_ok(all_full, "进入战斗后全队血量重置为满")

	# ---- 打完这场 ----
	print("\n-- 打完这场战斗 --")
	var gold_before: int = gd.gold
	var reward_expected := 0
	var bm: BattleManager = battle_scene.battle
	var guard := 0
	while bm.result == BattleManager.Result.ONGOING and guard < 80:
		guard += 1
		var acted := false
		for a in bm.team:
			if not a.is_alive():
				continue
			for card in bm.deck.hand.duplicate():
				if not bm.can_play(a, card):
					continue
				var tgt: Variant = null
				if card.card_class == CardData.CardClass.ATTACK:
					if bm.living_monsters().is_empty():
						break
					tgt = bm.living_monsters()[0]
				elif card.has_tag("REVIVE"):
					for t in bm.team:
						if t.is_downed:
							tgt = t
							break
				elif card.heal_multiplier > 0.0 and card.needs_target_card():
					var worst: Adventurer = null
					for t in bm.team:
						if t.is_alive() and t.current_hp < t.get_max_hp():
							if worst == null or t.current_hp < worst.current_hp:
								worst = t
					tgt = worst
				if bm.play_card(a, card, tgt):
					acted = true
					break
		if bm.result != BattleManager.Result.ONGOING:
			break
		if not acted:
			battle_scene._on_end_turn()
		await process_frame

	_ok(bm.result != BattleManager.Result.ONGOING, "战斗已分出胜负")
	print("      结果：%s，回合 %d" % [
		["进行中", "胜利", "失败"][bm.result], bm.turn.round_number
	])
	reward_expected = bm.reward_gold
	_ok(gd.gold == gold_before + reward_expected,
		"金币按奖励增加（%d + %d = %d，实际 %d）" % [
			gold_before, reward_expected, gold_before + reward_expected, gd.gold
		])

	# 重复触发 finished 不应重复发奖
	var gold_after_first: int = gd.gold
	battle_scene._on_battle_finished(BattleManager.Result.VICTORY)
	_ok(gd.gold == gold_after_first, "重复结算不再发奖（防重复发放）")

	var result_panel: Control = battle_scene.get_node("%ResultPanel")
	_ok(result_panel.visible, "结算面板可见")

	# ---- 点返回主菜单 ----
	print("\n-- 返回主菜单 --")
	battle_scene.get_node("%ResultButton").pressed.emit()
	await process_frame
	var menu2: Node = await _wait_scene()
	_ok(menu2 != null, "回到主菜单场景")
	if menu2 != null:
		await process_frame
		await process_frame
		var gold_label: Label = menu2.get_node_or_null("%GoldLabel")
		_ok(gold_label != null, "主菜单有金币显示")
		if gold_label != null:
			_ok(gold_label.text.contains(str(gd.gold)),
				"主菜单金币标签与数据一致（%s / %d）" % [gold_label.text, gd.gold])
		# 9-22 修改意见 2：主菜单不再展示状态信息，改为底部临时提示标签
		var toast: Label = menu2.get_node_or_null("%ToastLabel")
		_ok(toast != null, "主菜单保留底部提示标签（状态信息已按要求移除）")

	# ---- 场景无残留 ----
	print("\n-- 场景无残留 --")
	var battle_left := 0
	for ch in root.get_children():
		var n := str(ch.name)
		if n.begins_with("BattleScene"):
			battle_left += 1
	_ok(battle_left == 0, "战斗场景已释放（残留 %d）" % battle_left)

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
