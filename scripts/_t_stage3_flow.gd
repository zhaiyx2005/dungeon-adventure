## 阶段 3d 链路测试：主菜单 → 地牢选层 → 战斗节点 → battle_scene → 胜利 → 回地牢 → 撤离
extends SceneTree

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(120.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


## 按文字找按钮（跳过已被 queue_free 的残留节点 —— _refresh_prep 只做 queue_free，
## 同帧内旧节点仍在树上，直接遍历会摸到陈旧按钮）
func _find_buttons(root: Node, text: String) -> Array:
	var out: Array = []
	if root is Button:
		var b := root as Button
		if b.text == text and is_instance_valid(b) and b.is_inside_tree():
			out.append(b)
	for ch in root.get_children():
		out.append_array(_find_buttons(ch, text))
	return out


## 按节点名递归找按钮（层级按钮被包在行容器里，不能再靠 get_node_or_null）
func _find_button(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for ch in root.get_children():
		var got := _find_button(ch, node_name)
		if got != null:
			return got
	return null


## 把一棵控件子树里的所有可见文字拼起来（用来断言"某个词出现在界面上"）
func _all_text(root: Node) -> String:
	var s := ""
	if root is Label:
		s += (root as Label).text + "\n"
	if root is Button:
		s += (root as Button).text + "\n"
	for ch in root.get_children():
		s += _all_text(ch)
	return s


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
	print("\n===== 阶段3d 地牢链路测试 =====\n")

	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		_quit()
		return

	# ---- 进主菜单，点地下城探索 ----
	print("\n-- 主菜单 → 地下城 --")
	change_scene_to_file("res://scenes/main_menu.tscn")
	var menu: Node = await _wait_scene()
	await process_frame
	var dungeon_btn: Button = null
	var menu_box: Node = menu.get_node_or_null("%MenuBox")
	if menu_box != null:
		for ch in menu_box.get_children():
			if ch is Button and ch.text.contains("地下城探索"):
				dungeon_btn = ch
				break
	_ok(dungeon_btn != null, "主菜单有「地下城探索」按钮")
	if dungeon_btn == null:
		_quit()
		return
	dungeon_btn.pressed.emit()
	await process_frame
	var run_scene: Node = await _wait_scene()
	await process_frame
	await process_frame
	_ok(run_scene != null and run_scene.get_script() != null, "进入地牢场景")
	_ok(run_scene.get_node_or_null("%SelectPanel") != null, "准备面板存在")
	_ok(run_scene.get_node("%SelectPanel").visible, "准备面板已显示")
	# 9-24 修改意见 3：概要页 = 第 1–5 层阶梯，每层一个进入按钮。
	# 第 1 层永远可进；未通关过的第 2–5 层锁定，并把原因写在按钮上。
	var enter_btn: Button = _find_button(run_scene.get_node("%SelectList"), "EnterDungeonButton")
	_ok(enter_btn != null and not enter_btn.disabled, "准备面板提供「进入地牢」按钮（第 1 层）")
	var locked_layers := 0
	var explained := 0
	for lv in range(2, 6):
		var lb: Button = _find_button(run_scene.get_node("%SelectList"), "EnterFloorButton%d" % lv)
		if lb == null:
			continue
		if lb.disabled:
			locked_layers += 1
		if lb.text.length() > 0:
			explained += 1
	_ok(locked_layers == 4, "未通关过的第 2–5 层全部锁定（实际 %d 层）" % locked_layers)
	_ok(explained == 4, "每层按钮都写明准入状态（实际 %d 层）" % explained)
	# 意见7「默认从第 1 层进入」仍然成立：默认路径就是第 1 层那个按钮
	_ok(enter_btn != null and enter_btn.text.contains("第 1 层"), "默认入口仍是第 1 层（%s）" % enter_btn.text)

	# ---- 9-24 修改意见 3：通关后按钮解锁 + 点击真的进那一层 ----
	print("\n-- 修改意见3：层级直达按钮 --")
	var gold_keep: int = gd.gold
	gd.cleared_levels.clear()
	gd.gold = 20000
	run_scene._on_prep_tab("overview")
	await process_frame
	await process_frame
	var d2: DungeonData = gd.db.get_dungeon_by_level(2)
	_ok(d2 != null, "取到第 2 层关卡数据")
	var l2_locked: Button = _find_button(run_scene.get_node("%SelectList"), "EnterFloorButton2")
	_ok(l2_locked != null and l2_locked.disabled, "未通关时第 2 层按钮锁定并写明原因")
	_ok(l2_locked != null and l2_locked.text.contains("尚未通关"), "锁定原因写在按钮上（%s）" % l2_locked.text)

	gd.mark_level_cleared(2)
	run_scene._refresh_prep()
	await process_frame
	await process_frame
	var l2_open: Button = _find_button(run_scene.get_node("%SelectList"), "EnterFloorButton2")
	_ok(l2_open != null and not l2_open.disabled, "通关过第 2 层后按钮解锁")
	_ok(l2_open != null and l2_open.text.contains("第 2 层"), "按钮写明目标层（%s）" % l2_open.text)
	if l2_open != null and not l2_open.disabled:
		var gold_before: int = gd.gold
		l2_open.pressed.emit()
		await process_frame
		_ok(gd.run != null and gd.run.dungeon != null and gd.run.dungeon.level_index == 2,
			"点按钮直接落在第 2 层")
		_ok(gd.gold == gold_before - d2.entry_cost,
			"扣掉第 2 层入场费 %d（%d → %d）" % [d2.entry_cost, gold_before, gd.gold])
		_ok(not run_scene.get_node("%SelectPanel").visible, "进入后准备面板自动收起")

	# 复位：后面的用例仍从第 1 层走
	gd.run = null
	gd.cleared_levels.clear()
	gd.gold = gold_keep
	run_scene._show_select_panel()
	await process_frame
	await process_frame

	# ---- 9-23 意见 6：准备面板内可整备（加点 / 装备 / 背包道具）----
	print("\n-- 意见6：出征前整备面板 --")
	var tabs: Node = run_scene.get_node_or_null("%SelectTabs")
	var slist: Node = run_scene.get_node("%SelectList")
	_ok(tabs != null, "准备面板有标签栏 %SelectTabs")
	_ok(run_scene.get_node_or_null("%SelectScroll") != null, "标签内容放进可滚动容器")
	var want_tabs := ["PrepTab_overview", "PrepTab_team", "PrepTab_equip", "PrepTab_bag"]
	var got_tabs: Array = []
	if tabs != null:
		for ch in tabs.get_children():
			got_tabs.append(String(ch.name))
	for wn in want_tabs:
		_ok(got_tabs.has(wn), "存在标签按钮 %s" % wn)
	_ok(got_tabs.size() == want_tabs.size(),
		"标签正好 %d 个（实际 %d）" % [want_tabs.size(), got_tabs.size()])
	_ok(run_scene._prep_tab == "overview", "默认停在「出征概要」")
	# 9-24 修改意见 3：概要页改成「1–5 层阶梯」，每层一个进入按钮
	# （第 1 层按钮沿用旧名 EnterDungeonButton，层级按钮在行容器里，所以要递归找）
	_ok(_find_button(slist, "EnterDungeonButton") != null, "概要页有第 1 层「进入地牢」按钮")
	var floor_btns := 0
	for lv in range(1, 6):
		if lv == 1:
			continue
		if _find_button(slist, "EnterFloorButton%d" % lv) != null:
			floor_btns += 1
	_ok(floor_btns == 4, "概要页列出第 2–5 层的直达按钮（实际 %d 个）" % floor_btns)

	# --- 队伍加点 ---
	# 兜底给 1 点剩余属性点：否则加点按钮全灰，真实点击路径测不到
	if not gd.team.is_empty() and gd.team[0].unspent_points <= 0:
		gd.team[0].unspent_points = 1
	run_scene._on_prep_tab("team")
	await process_frame
	await process_frame
	_ok(run_scene._prep_tab == "team", "切到「队伍加点」")
	var plus_btns := _find_buttons(slist, "+")
	_ok(plus_btns.size() >= gd.team.size() * 4,
		"每名成员 4 项属性各有一个加点按钮（%d 个）" % plus_btns.size())
	var non_hero := 0
	for a in gd.team:
		if a.id != "hero":
			non_hero += 1
	var out_btns := _find_buttons(slist, "移出小队")
	_ok(out_btns.size() == non_hero,
		"只有非主角成员有「移出小队」（%d 个 / 非主角 %d 人）" % [out_btns.size(), non_hero])
	var spender: Adventurer = null
	for a in gd.team:
		if a.unspent_points > 0:
			spender = a
			break
	if spender != null:
		var stat_before := 0
		var left_total_before := 0
		for a in gd.team:
			stat_before += a.constitution + a.strength + a.intelligence + a.vitality
			left_total_before += a.unspent_points
		# 走真实按钮路径（历史上 bind 形参不匹配会让点击静默失效）
		var spend_btn: Button = null
		for b in plus_btns:
			if not (b as Button).disabled:
				spend_btn = b
				break
		_ok(spend_btn != null, "有剩余点数时加点按钮可用")
		if spend_btn != null:
			spend_btn.pressed.emit()
			await process_frame
			await process_frame
			var stat_after := 0
			var left_total_after := 0
			for a in gd.team:
				stat_after += a.constitution + a.strength + a.intelligence + a.vitality
				left_total_after += a.unspent_points
			_ok(left_total_after == left_total_before - 1,
				"点「+」消耗 1 点剩余属性点（%d → %d）" % [left_total_before, left_total_after])
			_ok(stat_after == stat_before + 1,
				"属性总和正好 +1（%d → %d）" % [stat_before, stat_after])
	else:
		_ok(true, "（小队当前无剩余属性点，跳过加点断言）")

	# --- 装备 ---
	var gear: ItemData = gd.db.get_item("chain_mail")
	if gear != null:
		gd.inventory.append(gear)
	run_scene._on_prep_tab("equip")
	await process_frame
	await process_frame
	_ok(run_scene._prep_tab == "equip", "切到「装备」")
	var member_btns := 0
	for ch in slist.get_children():
		if ch is HBoxContainer:
			for c2 in (ch as HBoxContainer).get_children():
				if String(c2.name).begins_with("PrepMember_"):
					member_btns += 1
	_ok(member_btns == gd.team.size(),
		"每位小队成员一个选择按钮（%d / %d）" % [member_btns, gd.team.size()])
	_ok(run_scene._prep_member != null, "装备页默认选中一名成员")
	# 7 个装备槽位名都在（含合并后的单「武器」槽）
	var slist_text := _all_text(slist)
	var slot_missing: Array = []
	for slot in ItemData.equip_slot_order():
		if not slist_text.contains(ItemData.slot_name_cn(slot)):
			slot_missing.append(ItemData.slot_name_cn(slot))
	_ok(slot_missing.is_empty(), "7 个装备槽位都有展示（缺 %s）" % (slot_missing if not slot_missing.is_empty() else "无"))
	var target_a: Adventurer = run_scene._prep_member
	if gear != null and target_a != null:
		var eq_btns := _find_buttons(slist, "装备")
		_ok(eq_btns.size() >= 1, "背包里的装备旁有「装备」按钮（%d 个）" % eq_btns.size())
		if eq_btns.size() >= 1:
			var inv_before: int = gd.inventory.size()
			var worn_before: int = target_a.equipment.size()
			eq_btns[0].pressed.emit()
			await process_frame
			await process_frame
			_ok(target_a.equipment.size() > worn_before,
				"点「装备」后物品穿到身上（%d → %d）" % [worn_before, target_a.equipment.size()])
			_ok(gd.inventory.size() == inv_before - 1,
				"穿上后背包少一件（%d → %d）" % [inv_before, gd.inventory.size()])
			var off_btns := _find_buttons(slist, "卸下")
			_ok(off_btns.size() >= 1, "已装备的物品旁有「卸下」按钮")
			if off_btns.size() >= 1:
				var worn_now: int = target_a.equipment.size()
				off_btns[0].pressed.emit()
				await process_frame
				await process_frame
				_ok(target_a.equipment.size() == worn_now - 1, "点「卸下」后装备脱回背包")
				_ok(gd.inventory.size() == inv_before, "卸下后背包件数复原")
	else:
		_ok(true, "（未取到装备素材，跳过穿脱断言）")

	# --- 背包 / 道具 ---
	var potion: ItemData = gd.db.get_item("health_potion")
	var injured: Adventurer = gd.team[0]
	if potion != null and not gd.inventory.has(potion):
		gd.inventory.append(potion)
	injured.current_hp = maxi(injured.get_max_hp() - 30, 1)   # 先扣血，道具才有用武之地
	run_scene._prep_member = injured
	run_scene._on_prep_tab("bag")
	await process_frame
	await process_frame
	_ok(run_scene._prep_tab == "bag", "切到「背包道具」")
	_ok(_all_text(slist).contains("道具使用对象"), "背包页可指定道具使用对象")
	var use_btns := _find_buttons(slist, "使用")
	_ok(use_btns.size() >= 1, "消耗品旁有「使用」按钮（%d 个）" % use_btns.size())
	var potion_btn: Button = null
	for b in use_btns:
		if String(b.name) == "PrepUse_" + potion.id:
			potion_btn = b
	_ok(potion_btn != null, "血药按钮按 PrepUse_%s 命名" % potion.id)
	if potion_btn != null:
		var hp_before: int = injured.current_hp
		var inv_before2: int = gd.inventory.size()
		potion_btn.pressed.emit()
		await process_frame
		await process_frame
		_ok(injured.current_hp > hp_before, "出征前用血药回血（%d → %d）" % [hp_before, injured.current_hp])
		_ok(gd.inventory.size() == inv_before2 - 1, "用掉后背包 -1（%d → %d）" % [inv_before2, gd.inventory.size()])

	# 切回概要仍然可用
	run_scene._on_prep_tab("overview")
	await process_frame
	await process_frame
	_ok(run_scene._prep_tab == "overview" and _find_button(slist, "EnterDungeonButton") != null,
		"切回概要后「进入地牢」按钮仍在")

	# ---- 选第 1 层 ----
	print("\n-- 选层开始探索 --")
	run_scene._on_select_level(1)
	await process_frame
	await process_frame
	var run = gd.run
	_ok(run != null, "run 已创建")
	_ok(run.status == RunManager.Status.EXPLORING, "探索中")

	# ---- 找一个战斗节点前进 ----
	print("\n-- 前进到战斗节点 --")
	var battle_node = null
	var guard := 0
	while battle_node == null and guard < 6:
		guard += 1
		for n in run.reachable_nodes():
			if n.type == MapGenerator.NodeType.BATTLE:
				battle_node = n
				break
		if battle_node == null:
			# 当前行全是宝箱/事件 → 向上走一格继续找
			run.move_to(run.reachable_nodes()[0])
	if battle_node == null:
		_ok(false, "找不到战斗节点")
		_quit()
		return

	var expected_ids: Array = battle_node.monster_ids
	_ok(battle_node.monster_ids.size() >= 1, "战斗节点编成 %d 只：%s" % [expected_ids.size(), ", ".join(expected_ids)])

	gd.last_battle_result = {}
	run_scene._on_node_pressed(battle_node)
	await process_frame
	var battle: Node = await _wait_scene()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	_ok(battle != null and battle.battle != null, "已进入战斗场景")
	var bm: BattleManager = battle.battle
	_ok(bm.monsters.size() == expected_ids.size(),
		"战斗怪物数与编成一致（%d vs %d）" % [bm.monsters.size(), expected_ids.size()])
	var ids_match := true
	for i in range(bm.monsters.size()):
		if bm.monsters[i].data.id != expected_ids[i]:
			ids_match = false
	_ok(ids_match, "战斗怪物 id 与编成完全一致")

	# ---- 自动打完战斗 ----
	print("\n-- 自动战斗 --")
	var gold_before: int = gd.gold
	var g := 0
	while bm.result == BattleManager.Result.ONGOING and g < 120:
		g += 1
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
			battle._on_end_turn()
		await process_frame

	_ok(bm.result == BattleManager.Result.VICTORY, "战斗胜利（回合 %d）" % bm.turn.round_number)
	if bm.result != BattleManager.Result.VICTORY:
		_quit()
		return
	_ok(gd.gold == gold_before + bm.reward_gold, "金币已入账（+%d）" % bm.reward_gold)
	_ok(gd.last_battle_result.has("victory"), "结算结果已写入 GameData")
	_ok(run.gold_earned == bm.reward_gold, "run 统计金币 earned（%d）" % run.gold_earned)
	_ok(run.current_node() == battle_node and battle_node.visited, "当前位置停在战斗节点且已标记")

	# ---- 点返回 → 应回到地牢场景 ----
	print("\n-- 返回地牢 --")
	battle.get_node("%ResultButton").pressed.emit()
	await process_frame
	var back: Node = await _wait_scene()
	await process_frame
	await process_frame
	_ok(back == run_scene or (back != null and back.get_node_or_null("%MapArea") != null), "已回到地牢场景")
	_ok(back != null and back.get_node_or_null("%Overlay") != null and back.get_node("%Overlay").visible,
		"战斗结果过渡面板已弹出")
	_ok(not gd.last_battle_result.has("victory"), "结算结果已被消费")

	# 点继续探索
	back.get_node("%OverlayButton").pressed.emit()
	await process_frame
	_ok(not back.get_node("%Overlay").visible, "过渡面板已关闭，回到地图")

	# ---- 撤离（9-22 修改意见 7：右侧不再有「撤离 / 返回主菜单」按钮，
	#      撤离按层级，改为打完层 Boss 后在弹出面板里选择） ----
	print("\n-- 撤离（按层级） --")
	_ok(back.get_node_or_null("%RetreatButton") == null, "右侧面板已无「撤离带回战利品」按钮（意见7）")
	_ok(back.get_node_or_null("%BackButton") == null, "右侧面板已无「返回主菜单」按钮（意见7）")
	_ok(not run.can_retreat(), "Boss 未击败时不可撤离")
	_ok(not run.retreat(), "Boss 前 retreat() 被拒绝")
	_ok(run.status == RunManager.Status.EXPLORING, "拒绝后仍在探索")
	run.current = MapGenerator.get_boss(run.map)
	run.boss_defeated = true
	back._refresh()
	await process_frame
	_ok(run.can_retreat(), "击败 Boss 后可撤离")
	back._show_boss_choice()
	await process_frame
	_ok(back.get_node("%Overlay").visible, "Boss 后弹出选择面板")
	_ok(back.get_node("%OverlayButton").text.contains("撤离"), "面板提供「撤离」选项")
	_ok(back.get_node("%OverlayButton2").text.contains("继续"), "面板提供「继续向下」选项")
	back._on_retreat()
	await process_frame
	_ok(run.status == RunManager.Status.RETREATED, "状态为已撤离")
	_ok(back.get_node("%Overlay").visible, "撤离结算面板已弹出")
	back.get_node("%OverlayButton").pressed.emit()
	await process_frame
	var menu2: Node = await _wait_scene()
	_ok(menu2 != null and menu2.get_node_or_null("%MenuBox") != null, "回到主菜单")
	_ok(gd.run == null or gd.run.status == RunManager.Status.RETREATED, "run 状态保留（战利品已带走）")

	# ---- 意见 1：上一轮已结束的 run 必须丢弃，重进不能再卡在已通关的旧地图 ----
	print("\n-- 意见1：重进地牢不卡死 --")
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	var rs2: Node = await _wait_scene()
	await process_frame
	await process_frame
	_ok(gd.run == null, "重进后旧的已结束 run 已被丢弃（意见1）")
	_ok(rs2.get_node("%SelectPanel").visible, "重进显示准备面板（不再卡在旧地图）")
	var enter2: Button = _find_button(rs2.get_node("%SelectList"), "EnterDungeonButton")
	_ok(enter2 != null and not enter2.disabled, "可以重新开始探索（意见1）")
	rs2._on_select_level(1)
	await process_frame
	await process_frame
	_ok(gd.run != null and gd.run.status == RunManager.Status.EXPLORING, "重进后能正常开始新一轮")
	_ok(gd.run != null and gd.run.reachable_nodes().size() > 0, "新地图有可前进节点（不卡死，意见1）")

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _quit() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1)
