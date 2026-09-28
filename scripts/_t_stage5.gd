## 遗留功能测试：任务系统 + 背包战斗内使用 + 存档读档（10 栏位 + 游玩时长）
extends SceneTree

## 🔴 测试专用存档前缀。**绝不能**用默认前缀：那会覆盖玩家真实栏位里的存档。
const TEST_PREFIX := "user://_test_save_"

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(90.0).timeout
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
	print("\n===== 遗留功能测试 =====\n")

	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		_quit()
		return

	_test_quests(gd)
	await process_frame
	_test_items_in_battle(gd)
	await process_frame
	# 🔴 必须 await：含 await 的函数不 await 只会挂起协程，
	# 后面的断言会打印在汇总之后（数字看着对，其实没计入）
	await _test_save_load(gd)

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _quit() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1)


# ---------------------------------------------------------------------------
# 1. 任务系统
# ---------------------------------------------------------------------------

func _test_quests(gd: Node) -> void:
	print("\n-- 任务系统 --")
	var qm := QuestManager.new()
	qm.roll_quests()
	_ok(qm.available.size() == 3, "生成 3 个任务")

	var q: QuestManager.Quest = qm.available[0]
	_ok(q.monster_id != "", "任务有目标怪物")
	_ok(q.target_count >= 2 and q.target_count <= 5, "击杀数量 2–5（实际 %d）" % q.target_count)
	_ok(q.reward_gold > 0, "有金币奖励")

	# 接取
	_ok(qm.accept(q), "接取任务成功")
	_ok(qm.active.has(q), "任务进入进行中列表")
	_ok(not qm.available.has(q), "任务移出可接列表")

	# 击杀进度
	var target := q.monster_id
	qm.on_kill(target)
	qm.on_kill(target)
	_ok(q.progress == 2, "击杀进度累计（2/%d）" % q.target_count)

	# 提交（先打到目标数）
	while q.progress < q.target_count:
		qm.on_kill(target)
	_ok(qm.is_complete(q), "进度达标可提交")
	var gold_before: int = gd.gold
	var msgs := qm.claim(q)
	_ok(not msgs.is_empty(), "提交有奖励返回")
	_ok(gd.gold >= gold_before + q.reward_gold, "金币奖励入账")
	_ok(q.completed, "任务标记完成")

	# 最多 3 个进行中
	var qm2 := QuestManager.new()
	qm2.roll_quests()
	for i in range(3):
		qm2.accept(qm2.available[0])
	# 生成第 4 个任务再尝试接取（active 已满 3）
	var extra := QuestManager.new()
	extra.roll_quests()
	_ok(qm2.active.size() == 3, "已接满 3 个任务")
	_ok(not qm2.accept(extra.available[0]), "同时进行任务最多 3 个")


# ---------------------------------------------------------------------------
# 2. 背包战斗内使用
# ---------------------------------------------------------------------------

func _test_items_in_battle(gd: Node) -> void:
	print("\n-- 背包战斗内使用 --")
	var bm := BattleManager.new()
	var monsters: Array[MonsterData] = [gd.db.get_monster("boar")]
	bm.setup(gd.team, monsters, gd.deck)
	bm.start()

	var hero: Adventurer = bm.selected_adventurer
	hero.current_action = hero.get_max_action()

	# 回血瓶：先让某人受伤
	var ally: Adventurer = bm.team[0]
	ally.take_damage(30)
	gd.inventory.clear()
	var potion: ItemData = gd.db.get_item("health_potion")
	gd.inventory.append(potion)

	_ok(bm.can_use_item(hero, potion), "回血瓶可用（有人受伤）")
	var hp_before: int = ally.current_hp
	var action_before: int = hero.current_action
	_ok(bm.use_item(hero, potion, ally), "使用回血瓶成功")
	_ok(ally.current_hp > hp_before, "目标回血")
	_ok(hero.current_action == action_before - 1, "消耗 1 行动值")
	_ok(not gd.inventory.has(potion), "道具被消耗")

	# 炸弹：对全体敌人伤害
	var bomb: ItemData = gd.db.get_item("bomb")
	gd.inventory.append(bomb)
	var m_hp_before: int = bm.monsters[0].current_hp
	_ok(bm.use_item(hero, bomb), "使用炸弹成功")
	_ok(bm.monsters[0].current_hp < m_hp_before, "炸弹造成伤害")
	_ok(not gd.inventory.has(bomb), "炸弹被消耗")

	# 满血时回血瓶不可用
	ally.current_hp = ally.get_max_hp()
	gd.inventory.append(potion)
	_ok(not bm.can_use_item(hero, potion), "满血时回血瓶不可用")

	print("\n-- 烟雾弹（脱离战斗）--")
	var smoke: ItemData = gd.db.get_item("smoke_bomb")
	gd.inventory.append(smoke)
	_ok(bm.can_use_item(hero, smoke), "烟雾弹可用")
	_ok(bm.use_item(hero, smoke), "使用烟雾弹")
	_ok(bm.result == BattleManager.Result.VICTORY, "烟雾弹脱离战斗 = 胜利")


# ---------------------------------------------------------------------------
# 3. 存档 / 读档
# ---------------------------------------------------------------------------

func _test_save_load(gd: Node) -> void:
	print("\n-- 存档 / 读档 --")
	SaveManager.active_prefix = TEST_PREFIX   # 隔离，别碰玩家真实存档
	var sm := SaveManager.new()

	# 清理上次跑测试可能残留的栏位
	for i in range(SaveManager.SLOT_COUNT):
		sm.erase(i)

	# 准备一些可辨识的状态
	gd.gold = 7777
	gd.inventory.clear()
	gd.inventory.append(gd.db.get_item("short_sword"))
	gd.storage.clear()
	gd.storage.append(gd.db.get_item("rusty_key"))
	gd.refresh_store = 2
	gd.refresh_recruit = 1
	gd.refresh_quest = 0
	# 游玩时长（9-28）：1 小时 1 分 10 秒
	gd.playtime_seconds = 3670.0

	# 卡池塞一个人
	var tm := TownManager.new()
	var c := tm.roll_recruit()
	gd.roster.append(c["adventurer"])

	# 任务
	gd.quests = QuestManager.new()
	gd.quests.roll_quests()
	gd.quests.accept(gd.quests.available[0])

	# 意见 8：持有卡池也要进存档（多给一张以区别卡组张数）
	var extra_card: CardData = gd.db.get_card("cleave")
	if extra_card == null:
		extra_card = gd.db.get_card("strike")
	gd.add_owned_card(extra_card)
	var owned_snapshot: int = gd.owned_cards.size()

	_ok(sm.save(2), "存档成功（写入栏位 3）")
	_ok(sm.has_save(2), "栏位 3 的文件存在")
	_ok(not sm.has_save(0), "没写过的栏位 1 仍然是空的")
	_ok(sm.list_slots().size() == SaveManager.SLOT_COUNT,
		"共 %d 个栏位（实际 %d）" % [SaveManager.SLOT_COUNT, sm.list_slots().size()])

	# ---- 栏位摘要（面板上显示的那几项）----
	var info: Dictionary = sm.slot_info(2)
	_ok(not bool(info["empty"]), "栏位 3 摘要：非空")
	_ok(int(info["gold"]) == 7777, "栏位 3 摘要：金币 7777（实际 %d）" % int(info["gold"]))
	# 游玩时长由 GameData._process 持续累加 → 存档后必然比刚赋的值略大，用区间判
	_ok(int(info["playtime"]) >= 3670 and int(info["playtime"]) <= 3675,
		"栏位 3 摘要：记录了游玩时长（%d 秒）" % int(info["playtime"]))
	_ok(int(info["saved_at"]) > 0, "栏位 3 摘要：记录了最后保存时间")
	_ok(int(info["created_at"]) > 0, "栏位 3 摘要：记录了建档时间")
	_ok(int(info["team_size"]) == gd.team.size(),
		"栏位 3 摘要：小队 %d 人" % int(info["team_size"]))
	_ok(int(info["deck_size"]) == gd.deck.size(),
		"栏位 3 摘要：卡组 %d 张" % int(info["deck_size"]))
	_ok(bool((sm.slot_info(0))["empty"]), "未写入的栏位 1 摘要为「空」")

	# ---- v1 旧存档：要能区分"没记录时长"和"时长真的是 0" ----
	var v1_path := TEST_PREFIX + "08.json"
	var v1f := FileAccess.open(v1_path, FileAccess.WRITE)
	v1f.store_string('{"version":1,"gold":900,"team":[],"deck":[]}')
	v1f.close()
	var v1info: Dictionary = sm.slot_info(8)
	_ok(not bool(v1info["empty"]), "v1 旧存档被识别为非空")
	_ok(bool(v1info["legacy"]), "v1 旧存档标记 legacy（不假装「游玩 0 分钟」）")
	_ok(not bool(info.get("legacy", true)), "v2 新存档不带 legacy 标记")
	DirAccess.remove_absolute(v1_path)

	# 覆盖同一栏位时，建档时间不该被刷新，但最后保存时间应该更新
	var created_before := int(info["created_at"])
	var saved_before := int(info["saved_at"])
	await create_timer(1.1).timeout
	_ok(sm.save(2), "再次存档（覆盖栏位 3）")
	var info2: Dictionary = sm.slot_info(2)
	_ok(int(info2["created_at"]) == created_before,
		"覆盖存档保留原建档时间（%d）" % int(info2["created_at"]))
	_ok(int(info2["saved_at"]) > saved_before, "覆盖存档刷新最后保存时间")
	var recorded_pts := int(info2["playtime"])

	# 破坏当前状态
	gd.gold = 0
	gd.inventory.clear()
	gd.storage.clear()
	gd.roster.clear()
	gd.team.clear()
	gd.quests = null
	gd.refresh_store = 1
	gd.owned_cards.clear()
	gd.playtime_seconds = 0.0

	_ok(not sm.load(0), "读空栏位 1 失败（不该读出东西）")
	_ok(sm.load(2), "读档成功（栏位 3）")
	_ok(gd.gold == 7777, "金币恢复（%d）" % gd.gold)
	_ok(gd.inventory.size() == 1, "背包恢复 1 件")
	_ok(gd.storage.size() == 1, "仓库恢复 1 件")
	_ok(gd.roster.size() == 1, "卡池恢复 1 人")
	_ok(gd.team.size() > 0, "小队恢复")
	_ok(gd.refresh_store == 2, "刷新次数恢复")
	_ok(gd.refresh_quest == 0, "任务刷新次数恢复")
	_ok(gd.quests != null and gd.quests.active.size() == 1, "任务进度恢复")
	_ok(gd.owned_cards.size() == owned_snapshot, "持有卡池恢复（%d 张，意见8）" % gd.owned_cards.size())
	_ok(absf(gd.playtime_seconds - float(recorded_pts)) < 1.5,
		"游玩时长随存档恢复（%.1f ≈ %d 秒）" % [gd.playtime_seconds, recorded_pts])

	# ---- 多栏位互不干扰 ----
	gd.gold = 111
	_ok(sm.save(0), "写入栏位 1")
	_ok(sm.has_save(0) and sm.has_save(2), "栏位 1 与 3 同时存在")
	_ok(int(sm.slot_info(0)["gold"]) == 111 and int(sm.slot_info(2)["gold"]) == 7777,
		"两个栏位各自保存自己的金币")
	_ok(sm.load(2) and gd.gold == 7777, "读栏位 3 拿到 7777，没被栏位 1 污染")

	# ---- 任务状态为空 → 读回 null ----
	# 存档时 gd.quests 可能还是 null（没进过城镇），写出来是两个空数组；
	# 若读回一个"非空但空"的 QuestManager，城镇 _ready 的 `if gd.quests == null` 就不成立，
	# **任务木板会永久空着**（冒烟测试踩到过）。
	gd.quests = null
	_ok(sm.save(6), "存档：此时任务状态为 null")
	gd.quests = QuestManager.new()
	_ok(sm.load(6), "读档（任务状态为空的档）")
	_ok(gd.quests == null, "任务状态为空的存档读回 null（城镇会重新 roll 任务）")

	# 清理测试存档，避免污染
	for i in range(SaveManager.SLOT_COUNT):
		sm.erase(i)
	_ok(not sm.has_save(0) and not sm.has_save(2), "测试存档已清理")
	_ok(sm.list_slots().all(func(x: Dictionary) -> bool: return bool(x["empty"])),
		"清理后所有栏位都是空的")

	# ---- 格式化：游玩时长 / 时间 ----
	_ok(SaveManager.format_playtime(0) == "0 分钟", "0 秒 → 0 分钟")
	_ok(SaveManager.format_playtime(59) == "不足 1 分钟", "59 秒 → 不足 1 分钟")
	_ok(SaveManager.format_playtime(60) == "1 分钟", "60 秒 → 1 分钟")
	_ok(SaveManager.format_playtime(3670) == "1 小时 1 分", "3670 秒 → 1 小时 1 分")
	_ok(SaveManager.format_playtime(7200) == "2 小时 0 分", "7200 秒 → 2 小时 0 分")
	_ok(SaveManager.format_saved_at(0) == "—", "时间为 0 时显示占位符")
	# 本地时间：用同一套算法反推，验证"不是 UTC 原样输出"
	var now_unix := int(Time.get_unix_time_from_system())
	var tz := Time.get_time_zone_from_system()
	var bias: int = int(tz["bias"]) if tz.has("bias") else 0
	var local := Time.get_datetime_dict_from_unix_time(now_unix + bias * 60)
	var expect := "%02d-%02d %02d:%02d" % [int(local["month"]), int(local["day"]),
		int(local["hour"]), int(local["minute"])]
	_ok(SaveManager.format_saved_at(now_unix) == expect,
		"最后保存时间按本地时区显示（%s）" % SaveManager.format_saved_at(now_unix))

	# ---- 栏位号越界防护 ----
	_ok(not sm.save(-1), "栏位 -1 拒绝写入")
	_ok(not sm.save(SaveManager.SLOT_COUNT), "栏位号越界拒绝写入")
	_ok(not sm.has_save(-1), "栏位 -1 不存在")
	_ok(not sm.load(SaveManager.SLOT_COUNT), "越界栏位读档失败")

	# ---- 旧存档迁移（v1 单文件 save.json → 栏位 1）----
	# 在隔离空间里演练：把 legacy_path 也指到测试前缀下，真实旧存档碰不到
	var legacy := TEST_PREFIX + "legacy.json"
	var slot0_file := TEST_PREFIX + "00.json"
	var mig := SaveManager.new()
	mig.path_prefix = TEST_PREFIX
	mig.legacy_path = legacy
	var lf := FileAccess.open(legacy, FileAccess.WRITE)
	lf.store_string('{"version":1,"gold":3141,"team":[],"deck":[]}')
	lf.close()
	_ok(FileAccess.file_exists(legacy), "造出一份 v1 版旧存档")
	_ok(mig.migrate_legacy_save(), "旧存档迁移成功")
	_ok(not FileAccess.file_exists(legacy), "迁移后旧文件已删除")
	_ok(FileAccess.file_exists(slot0_file), "旧存档落到栏位 1（%s）" % slot0_file)
	_ok(int(mig.slot_info(0)["gold"]) == 3141,
		"迁移后内容原样保留（金币 %d）" % int(mig.slot_info(0)["gold"]))

	# 目标栏位已有存档 → 不迁移、也不删旧文件（不去猜、不覆盖）
	var legacy2 := TEST_PREFIX + "legacy2.json"
	var mig2 := SaveManager.new()
	mig2.path_prefix = TEST_PREFIX
	mig2.legacy_path = legacy2
	var lf2 := FileAccess.open(legacy2, FileAccess.WRITE)
	lf2.store_string('{"version":1,"gold":2718,"team":[],"deck":[]}')
	lf2.close()
	_ok(not mig2.migrate_legacy_save(), "栏位 1 已有存档时不迁移")
	_ok(FileAccess.file_exists(legacy2), "不迁移时旧文件保持原样")

	# 安全闸：前缀被改写时，绝不去动"真实旧存档路径"
	var guarded := SaveManager.new()
	guarded.path_prefix = TEST_PREFIX     # 前缀不是默认
	guarded.legacy_path = SaveManager.LEGACY_PATH   # 真路径
	_ok(not guarded.migrate_legacy_save(), "前缀被改写时不会去碰玩家的真实旧存档")

	# 清理这几个测试文件
	DirAccess.remove_absolute(legacy2)
	for i in range(SaveManager.SLOT_COUNT):
		mig.erase(i)
	_ok(not mig.has_any_save(), "迁移测试留下的栏位已清理")

	# 意见 5：旧存档槽位迁移（旧 6/7/8 = 单手/双手/远程武器 → 新 6 = 武器）
	_ok(sm._migrate_slot(6) == ItemData.Slot.WEAPON, "旧槽位 6（单手）迁移为武器")
	_ok(sm._migrate_slot(7) == ItemData.Slot.WEAPON, "旧槽位 7（双手）迁移为武器")
	_ok(sm._migrate_slot(8) == ItemData.Slot.WEAPON, "旧槽位 8（远程）迁移为武器")
	_ok(sm._migrate_slot(9) == ItemData.Slot.NONE, "旧槽位 9（非装备）迁移为 NONE")
	_ok(sm._migrate_slot(0) == ItemData.Slot.HEAD, "槽位 0（头部）不受影响")
	_ok(sm._migrate_slot(5) == ItemData.Slot.FOOT, "槽位 5（脚部）不受影响")
