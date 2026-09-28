## 阶段 3 地牢流程测试
##
## 覆盖：地图生成、敌人编成、层级准入、逐层推进、宝箱/事件、Boss 宝箱、死亡惩罚。
## 纯逻辑测试（不加载 UI 场景），RunManager / MapGenerator 直接实例化。
extends SceneTree

## 🔴 测试专用存档前缀。**绝不能**用默认前缀：那会覆盖玩家真实栏位里的存档。
const TEST_PREFIX := "user://_test_save_"

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


func _run() -> void:
	_watchdog()
	print("\n===== 阶段3 地牢流程测试 =====\n")

	# GameData autoload
	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		_quit()
		return

	_test_map_generation(gd)
	await process_frame
	_test_encounter(gd)
	await process_frame
	_test_entry_gate(gd)
	await process_frame
	_test_progression(gd)
	await process_frame
	_test_treasure_event(gd)
	await process_frame
	_test_death_penalty(gd)
	await process_frame
	_test_boss_flow(gd)
	await process_frame
	_test_direct_entry(gd)

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---- 9-24 修改意见 3：通关过的层可付金币直接进入 ----
func _test_direct_entry(gd: Node) -> void:
	print("\n-- 修改意见3：通关层的金币直达 --")
	var probe := RunManager.new()
	var d1: DungeonData = gd.db.get_dungeon_by_level(1)
	var d2: DungeonData = gd.db.get_dungeon_by_level(2)
	var d3: DungeonData = gd.db.get_dungeon_by_level(3)
	_ok(d1 != null and d2 != null and d3 != null, "取到第 1/2/3 层关卡数据")
	if d1 == null or d2 == null or d3 == null:
		return

	# 清空进度，从"一次都没通关"开始
	gd.cleared_levels.clear()
	gd.gold = 100000
	_ok(not gd.is_level_cleared(2), "初始：第 2 层无通关记录")
	_ok(gd.max_cleared_level() == 0, "初始：最高通关层 = 0")

	# 第 1 层是入口层：无需通关记录也能直接进
	_ok(probe.direct_entry_block_reason(d1) == "", "第 1 层永远可直接进入")
	# 未通关的更高层：通用准入过了，但仍被"未通关"挡住
	_ok(probe.enter_block_reason(d2) == "", "第 2 层通用准入通过（战力/金币都够）")
	var r2 := probe.direct_entry_block_reason(d2)
	_ok(r2.contains("尚未通关"), "未通关的第 2 层被直达准入挡住（%s）" % r2)
	_ok(not probe.start_at_level(2), "未通关时 start_at_level(2) 被拒绝")
	_ok(gd.run == null, "被拒绝时不会建立 run")

	# 记录通关：第 2 层解锁直达
	_ok(gd.mark_level_cleared(2), "记录首次通关第 2 层")
	_ok(gd.is_level_cleared(2) and gd.max_cleared_level() == 2, "第 2 层已通关（最高层 2）")
	_ok(not gd.mark_level_cleared(2), "重复记录同一层返回 false（幂等）")
	_ok(probe.direct_entry_block_reason(d2) == "", "通关后第 2 层可直接进入")
	_ok(not probe.direct_entry_block_reason(d3).is_empty(), "第 3 层仍未解锁（互不影响）")

	# 真的进去：金币按第 2 层入场费扣除，run 落在第 2 层
	var gold_b: int = gd.gold
	gd.run = RunManager.new()
	var run: RunManager = gd.run
	_ok(run.start_at_level(2), "通关后 start_at_level(2) 成功")
	_ok(run.dungeon != null and run.dungeon.level_index == 2, "run 落在第 2 层")
	_ok(gd.gold == gold_b - d2.entry_cost,
		"扣掉第 2 层入场费 %d（%d → %d）" % [d2.entry_cost, gold_b, gd.gold])

	# 「继续向下」不受"已通关"限制（下一层本来就没通关过）
	run.current = MapGenerator.get_boss(run.map)
	run.boss_defeated = true
	var gold_c: int = gd.gold
	_ok(run.continue_down(), "Boss 后继续向下进入第 3 层（不受直达限制）")
	_ok(run.dungeon != null and run.dungeon.level_index == 3, "run 已推进到第 3 层")
	_ok(not gd.is_level_cleared(3), "第 3 层此时仍无通关记录（还没打 Boss）")

	# 打通第 3 层 Boss → 第 3 层也解锁
	# （continue_down 会重开一张地图，current 回到入口行，所以要重新站上 Boss 节点）
	run.current = MapGenerator.get_boss(run.map)
	_ok(run.at_boss(), "站上第 3 层 Boss 节点")
	run.on_battle_victory(1, 1)
	_ok(gd.is_level_cleared(3), "击败第 3 层 Boss 后解锁该层直达")
	_ok(gd.max_cleared_level() == 3, "最高通关层更新为 3")

	# 存档往返：通关记录必须持久化（用隔离前缀，不碰玩家真实栏位）
	SaveManager.active_prefix = TEST_PREFIX
	var sm := SaveManager.new()
	_ok(sm.save(), "写入存档")
	_ok(sm.has_save(), "存档文件存在（栏位 1）")
	gd.cleared_levels.clear()
	_ok(gd.max_cleared_level() == 0, "清空内存里的通关记录（模拟重开游戏）")
	_ok(sm.load(), "读回存档")
	_ok(gd.is_level_cleared(2) and gd.is_level_cleared(3),
		"通关记录随存档往返（%s）" % str(gd.cleared_levels))
	_ok(not gd.is_level_cleared(4), "未通关的层不会被误记")

	gd.run = null
	sm.erase()
	_ok(not sm.has_save(), "测试存档已清理")


func _quit() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1)


# ---------------------------------------------------------------------------
# 1. 地图生成
# ---------------------------------------------------------------------------

func _test_map_generation(gd: Node) -> void:
	print("\n-- 地图生成 --")
	var dungeon: DungeonData = gd.db.get_dungeon("level_01")
	_ok(dungeon != null, "取到第 1 层关卡数据")

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var map := MapGenerator.generate(dungeon, rng)

	_ok(map.size() == 17, "地图 17 节点（1 入口 + 15 中间 + 1 Boss，实际 %d）" % map.size())

	var boss := MapGenerator.get_boss(map)
	var start := MapGenerator.get_start(map)
	_ok(boss != null and boss.row == 0, "Boss 房在顶层 row 0")
	_ok(start != null and start.row == 6, "入口在底层 row 6")
	_ok(boss != null and boss.monster_ids == ["boar_king"], "Boss 怪物为 boar_king")

	# 中间行每行 3 节点
	var per_row := {}
	for n in map:
		per_row[n.row] = int(per_row.get(n.row, 0)) + 1
	var mid_rows_ok := true
	for row in range(1, 6):
		if int(per_row.get(row, 0)) != 3:
			mid_rows_ok = false
	_ok(mid_rows_ok, "中间 row 1–5 每行 3 节点")

	# 连通性
	_ok(MapGenerator.is_connected_map(map), "入口可连通到 Boss")

	# 节点类型分布
	var counts := MapGenerator.count_types(map)
	_ok(int(counts[MapGenerator.NodeType.BOSS]) == 1, "恰好 1 个 Boss 节点")
	_ok(int(counts[MapGenerator.NodeType.START]) == 1, "恰好 1 个入口节点")
	var mid := int(counts[MapGenerator.NodeType.BATTLE]) + int(counts[MapGenerator.NodeType.TREASURE]) + int(counts[MapGenerator.NodeType.EVENT])
	_ok(mid == 15, "中间节点共 15 个（战斗/宝箱/事件，实际 %d）" % mid)

	# 类型权重粗检：多种子下三类都应出现过
	print("  -- 类型权重（多种子统计）--")
	var type_seen := {MapGenerator.NodeType.BATTLE: 0, MapGenerator.NodeType.TREASURE: 0, MapGenerator.NodeType.EVENT: 0}
	for s in range(30):
		var r2 := RandomNumberGenerator.new()
		r2.seed = s * 97 + 3
		var m2 := MapGenerator.generate(dungeon, r2)
		for n in m2:
			if n.type == MapGenerator.NodeType.BATTLE or n.type == MapGenerator.NodeType.TREASURE or n.type == MapGenerator.NodeType.EVENT:
				type_seen[n.type] = int(type_seen[n.type]) + 1
	_ok(int(type_seen[MapGenerator.NodeType.BATTLE]) > 0, "战斗节点出现过")
	_ok(int(type_seen[MapGenerator.NodeType.TREASURE]) > 0, "宝箱节点出现过")
	_ok(int(type_seen[MapGenerator.NodeType.EVENT]) > 0, "事件节点出现过")
	# 战斗应显著多于宝箱（70 vs 10 权重）
	_ok(int(type_seen[MapGenerator.NodeType.BATTLE]) > int(type_seen[MapGenerator.NodeType.TREASURE]),
		"战斗节点多于宝箱节点（%d vs %d）" % [type_seen[MapGenerator.NodeType.BATTLE], type_seen[MapGenerator.NodeType.TREASURE]])


# ---------------------------------------------------------------------------
# 2. 敌人编成
# ---------------------------------------------------------------------------

func _test_encounter(gd: Node) -> void:
	print("\n-- 敌人编成 --")
	var dungeon: DungeonData = gd.db.get_dungeon("level_01")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var map := MapGenerator.generate(dungeon, rng)

	var pool_ok := true
	for n in map:
		if n.type != MapGenerator.NodeType.BATTLE:
			continue
		if n.monster_ids.is_empty():
			pool_ok = false
			continue
		if n.monster_ids.size() < 1 or n.monster_ids.size() > 3:
			pool_ok = false
		for mid in n.monster_ids:
			if not dungeon.monster_pool.has(mid) and not dungeon.elite_pool.has(mid):
				pool_ok = false
	_ok(pool_ok, "战斗节点敌人 1–3 只且来自本层怪物池/精英池")

	# 第 3 层有精英池，编成应可能包含精英
	var d3: DungeonData = gd.db.get_dungeon("level_03")
	var saw_elite := false
	for s in range(60):
		var r2 := RandomNumberGenerator.new()
		r2.seed = s * 13 + 5
		var m2 := MapGenerator.generate(d3, r2)
		for n in m2:
			if n.type == MapGenerator.NodeType.BATTLE and n.monster_ids.size() == 1:
				if d3.elite_pool.has(n.monster_ids[0]):
					saw_elite = true
	_ok(saw_elite, "第 3 层（有精英池）能刷出精英单怪")


# ---------------------------------------------------------------------------
# 3. 层级准入
# ---------------------------------------------------------------------------

func _test_entry_gate(gd: Node) -> void:
	print("\n-- 层级准入 --")
	var run := RunManager.new()

	var l1: DungeonData = gd.db.get_dungeon("level_01")
	var l5: DungeonData = gd.db.get_dungeon("level_05")

	_ok(run.can_enter(l1), "第 1 层（战力下限 60）可进入，当前战力 %d" % gd.team_power())
	_ok(not run.can_enter(l5), "第 5 层（战力下限 900）不可进入")

	# 金币不足：把金币清 0，看第 2 层（费用 100）被拒
	var gold_saved: int = gd.gold
	gd.gold = 0
	var reason := run.enter_block_reason(gd.db.get_dungeon("level_02"))
	_ok(reason.contains("金币不足"), "金币不足时拒绝进入（原因：%s）" % reason)
	gd.gold = gold_saved

	# 战力不足原因
	var reason2 := run.enter_block_reason(l5)
	_ok(reason2.contains("战力不足"), "战力不足时拒绝（原因：%s）" % reason2)


# ---------------------------------------------------------------------------
# 4. 逐层推进
# ---------------------------------------------------------------------------

func _test_progression(gd: Node) -> void:
	print("\n-- 逐层推进 --")
	var gold_before: int = gd.gold
	var run := RunManager.new()
	gd.run = run

	_ok(run.start_at_level(1), "从第 1 层开始探索")
	_ok(run.status == RunManager.Status.EXPLORING, "状态为探索中")
	_ok(gd.gold == gold_before, "第 1 层入场费 0，金币不变（%d）" % gd.gold)

	var start := run.current_node()
	_ok(start != null and start.type == MapGenerator.NodeType.START, "初始在入口节点")
	_ok(start.visited, "入口标记已访问")

	# 可达节点：入口可达 row5 全 3 列
	var reachable := run.reachable_nodes()
	_ok(reachable.size() == 3, "入口可达 3 个节点（实际 %d）" % reachable.size())

	# 前进到 row5 中间列
	var target := MapGenerator.find(run.map, 5, 1)
	_ok(run.move_to(target), "移动到 row5 中间节点")
	_ok(run.current_node().row == 5, "当前位置 row 5")

	# 非法移动：跳到不相邻节点应被拒绝
	var far := MapGenerator.find(run.map, 2, 1)
	_ok(not run.move_to(far), "跳行移动被拒绝")

	# 逐行上到 Boss
	var steps := 0
	while run.current_node().row > 0 and steps < 10:
		steps += 1
		var next := run.reachable_nodes()
		if next.is_empty():
			break
		run.move_to(next[0])
	_ok(run.current_node().row == 0, "能一路推进到 Boss 房（用了 %d 步）" % steps)
	_ok(run.at_boss(), "at_boss() 为真")

	gd.run = null


# ---------------------------------------------------------------------------
# 5. 宝箱 / 事件
# ---------------------------------------------------------------------------

func _test_treasure_event(gd: Node) -> void:
	print("\n-- 宝箱 / 事件 --")
	var run := RunManager.new()
	gd.run = run
	run.start_at_level(1)

	var inv_before: int = gd.inventory.size()
	var loot := run.open_treasure()
	_ok(loot.size() >= 0 and gd.inventory.size() == inv_before + loot.size(),
		"宝箱掉落入背包（+%d 件）" % loot.size())
	_ok(run.items_found.size() == loot.size(), "items_found 记录本次物品")

	# 意见 8：宝箱有概率开出战斗卡（70% 掉落，多种子采样必出）
	var owned_before: int = gd.owned_cards.size()
	var card_found_before: int = run.card_found.size()
	var card_drops := 0
	for _i in range(12):
		var n_before: int = gd.owned_cards.size()
		run.open_treasure()
		if gd.owned_cards.size() > n_before:
			card_drops += 1
	_ok(card_drops >= 1, "宝箱能开出战斗卡（12 次中 %d 次掉卡，意见8）" % card_drops)
	_ok(gd.owned_cards.size() == owned_before + card_drops, "掉落的卡进入持有卡池")
	_ok(run.card_found.size() == card_found_before + card_drops, "card_found 记录本次掉卡")

	# 事件：四个分支（经验/金币/物品/空手）中三个有效果。
	# 多次采样，产生过效果即通过（全空手概率 0.2^n，12 次 ≈ 0）。
	var effect_seen := false
	for _i in range(12):
		var gold_b: int = gd.gold
		var exp_b: int = _team_total_exp(gd)
		var inv_b: int = gd.inventory.size()
		run.resolve_event()
		if gd.gold != gold_b or _team_total_exp(gd) != exp_b or gd.inventory.size() != inv_b:
			effect_seen = true
			break
	_ok(effect_seen, "事件能产生效果（金币/经验/物品之一变化）")

	gd.run = null


# ---------------------------------------------------------------------------
# 6. 死亡惩罚
# ---------------------------------------------------------------------------

func _test_death_penalty(gd: Node) -> void:
	print("\n-- 死亡惩罚 --")
	var run := RunManager.new()
	gd.run = run

	# 先给背包塞点东西，记录快照
	var gold_start: int = gd.gold
	var exp_snapshot := {}
	var level_snapshot := {}
	for a in gd.team:
		exp_snapshot[a.id] = a.exp
		level_snapshot[a.id] = a.level

	_ok(run.start_at_level(1), "开始探索（记录死亡回滚快照）")

	# 模拟探索收益：加金币、加经验、背包加物品、甚至升级
	gd.gold += 300
	var extra: ItemData = gd.db.get_item("potion_hp")  # 假设存在回血瓶，不存在则随便取一个
	if extra == null:
		extra = gd.db.items.values()[0] as ItemData
	gd.inventory.append(extra)
	var hero: Adventurer = gd.team[0]
	hero.gain_exp(500)  # 足够升级

	_ok(gd.gold > gold_start, "探索中金币已增加（%d → %d）" % [gold_start, gd.gold])
	_ok(gd.inventory.size() > 0, "探索中背包有物品")

	# 触发死亡
	run.on_battle_defeat()

	_ok(gd.gold == gold_start, "死亡后金币回滚到探索前（%d）" % gd.gold)
	_ok(gd.inventory.is_empty(), "死亡后背包清空")
	for a in gd.team:
		if a.exp != int(exp_snapshot[a.id]) or a.level != int(level_snapshot[a.id]):
			_ok(false, "成员 %s 经验/等级回滚（exp %d→%d lv %d→%d）" % [
				a.display_name, a.exp, exp_snapshot[a.id], a.level, level_snapshot[a.id]
			])
			gd.run = null
			return
	_ok(true, "全员经验与等级回滚到探索前")
	_ok(run.status == RunManager.Status.DEFEATED, "状态为已失败")

	gd.run = null


# ---------------------------------------------------------------------------
# 7. Boss 宝箱与撤离/继续
# ---------------------------------------------------------------------------

func _test_boss_flow(gd: Node) -> void:
	print("\n-- Boss 宝箱与撤离 --")
	var run := RunManager.new()
	gd.run = run
	run.start_at_level(1)

	# 9-22 修改意见 4：Boss 未击败时不能撤离
	_ok(not run.can_retreat(), "Boss 前不可撤离")
	_ok(not run.retreat(), "Boss 前撤离被拒绝")
	_ok(run.status == RunManager.Status.EXPLORING, "撤离被拒后仍在探索中")

	# 直接站上 Boss 节点
	run.current = MapGenerator.get_boss(run.map)
	var inv_before: int = gd.inventory.size()

	run.on_battle_victory(100, 50)
	_ok(run.boss_defeated, "Boss 被标记为已击败")
	_ok(run.can_retreat(), "Boss 后可撤离")
	_ok(gd.inventory.size() == inv_before + 2, "Boss 宝箱必出 2 件物品（+%d）" % (gd.inventory.size() - inv_before))

	# 撤离
	_ok(run.retreat(), "Boss 后撤离成功")
	_ok(run.status == RunManager.Status.RETREATED, "撤离后状态为已撤离")

	# 继续向下：从第 1 层 Boss 继续，应进入第 2 层（战力 306 ≥ 150，费用 100）
	var gold_b: int = gd.gold
	var run2 := RunManager.new()
	gd.run = run2
	run2.start_at_level(1)
	run2.current = MapGenerator.get_boss(run2.map)
	run2.boss_defeated = true
	_ok(run2.continue_down(), "Boss 后继续向下成功")
	_ok(run2.dungeon.level_index == 2, "进入第 2 层")
	_ok(gd.gold == gold_b - 100, "第 2 层入场费 100 已扣除（%d → %d）" % [gold_b, gd.gold])

	gd.run = null


func _team_total_exp(gd: Node) -> int:
	var total := 0
	for a in gd.team:
		total += a.exp
	return total
