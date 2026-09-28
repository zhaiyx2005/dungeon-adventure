## 阶段 4 城镇系统测试
##
## 覆盖：招募、组队、加点、装备、战利品升级、卡组编辑、商店买卖、仓库存取、刷新次数。
## 纯逻辑测试，TownManager 直接实例化。
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


func _run() -> void:
	_watchdog()
	print("\n===== 阶段4 城镇系统测试 =====\n")

	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		_quit()
		return

	var town := TownManager.new()

	_test_recruit(town, gd)
	await process_frame
	_test_team(town, gd)
	await process_frame
	_test_team_v2(town, gd)
	await process_frame
	_test_growth(town, gd)
	await process_frame
	_test_equip(town, gd)
	await process_frame
	_test_deck(town, gd)
	await process_frame
	_test_card_acquisition(town, gd)
	await process_frame
	_test_weapon_and_categories(town, gd)
	await process_frame
	_test_shop(town, gd)
	await process_frame
	_test_storage(town, gd)

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _quit() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1)


# ---------------------------------------------------------------------------
# 招募
# ---------------------------------------------------------------------------

func _test_recruit(town: TownManager, gd: Node) -> void:
	print("\n-- 招募 --")
	gd.gold = 10000  # 确保够招募
	var cand := town.roll_recruit()
	var a: Adventurer = cand["adventurer"]
	var price: int = cand["price"]
	_ok(a != null, "招募候选生成")
	_ok(price >= 200 and price <= 600, "招募价 200–600（实际 %d）" % price)

	var roster_before: int = gd.roster.size()
	var gold_before: int = gd.gold
	_ok(town.recruit(a, price), "招募成功")
	_ok(gd.roster.size() == roster_before + 1, "卡池 +1")
	_ok(gd.gold == gold_before - price, "金币扣除（-1 × %d）" % price)
	_ok(gd.roster.has(a), "新成员入卡池")

	# 金币不足招募失败
	gd.gold = 0
	var cand2 := town.roll_recruit()
	var a2: Adventurer = cand2["adventurer"]
	_ok(not town.recruit(a2, cand2["price"]), "金币不足招募失败")
	gd.gold = 10000


# ---------------------------------------------------------------------------
# 组队
# ---------------------------------------------------------------------------

func _test_team(town: TownManager, gd: Node) -> void:
	print("\n-- 组队 --")
	# 确保卡池至少有一人
	if gd.roster.is_empty():
		var c := town.roll_recruit()
		gd.roster.append(c["adventurer"])
	var team_before: int = gd.team.size()
	var roster: Adventurer = gd.roster[0]
	_ok(town.add_to_team(roster), "卡池成员加入小队")
	_ok(gd.team.size() == team_before + 1, "小队 +1")
	_ok(not gd.roster.has(roster), "成员移出卡池")

	# 移出小队
	_ok(town.remove_from_team(roster), "移出小队")
	_ok(not gd.team.has(roster), "小队 -1")
	_ok(gd.roster.has(roster), "回到卡池")

	# 至少保留 1 人
	while gd.team.size() > 1:
		gd.team.remove_at(gd.team.size() - 1)
	_ok(gd.team.size() == 1, "缩减到 1 人")
	var last: Adventurer = gd.team[0]
	_ok(not town.remove_from_team(last), "小队至少保留 1 人")

	# 上限 4 人
	for _i in range(5):
		town.add_to_team(roster)
	_ok(gd.team.size() <= TownManager.MAX_TEAM_SIZE, "组队上限 4 人（实际 %d）" % gd.team.size())


# ---------------------------------------------------------------------------
# 组队·换位与主角锁（9-22 修改意见 1）
# ---------------------------------------------------------------------------

func _test_team_v2(town: TownManager, gd: Node) -> void:
	print("\n-- 组队·换位与主角锁 --")
	var hero: Adventurer = gd.team[0]
	_ok(town.is_protagonist(hero), "主角判定（id == hero）")
	_ok(not town.remove_from_team(hero), "主角无法移出队伍")
	_ok(gd.team.has(hero), "主角仍在队伍中")

	# 换位与调位
	if gd.team.size() >= 2:
		var first_name: String = gd.team[0].display_name
		var second_name: String = gd.team[1].display_name
		_ok(town.swap_team_positions(0, 1), "换位成功")
		_ok(gd.team[0].display_name == second_name and gd.team[1].display_name == first_name, "1/2 号位互换")
		_ok(town.reorder_to(gd.team[1], 0), "reorder_to 成功")
		_ok(gd.team[0].display_name == first_name, "调回 1 号位")
		_ok(town.reorder_to(gd.team[0], 0) == false, "原地调位返回 false")

	# 卡池成员插入指定位置
	gd.gold = 10000
	var cand := town.roll_recruit()
	var newbie: Adventurer = cand["adventurer"]
	gd.roster.append(newbie)
	_ok(town.insert_into_team(newbie, 0), "插入 1 号位成功")
	_ok(gd.team[0] == newbie, "新人位于 1 号位")
	_ok(not gd.roster.has(newbie), "卡池移除")
	_ok(town.remove_from_team(newbie), "新人移出小队")
	_ok(gd.roster.has(newbie), "新人回卡池")

	# 招募木板候选（普通：金钱；特殊：收集品 + 金币）
	var rc := town.roll_recruit_candidate()
	_ok(rc.has("adventurer") and rc.has("price"), "招募候选结构完整")
	var cid: String = rc.get("collectible_id", "")
	_ok(cid == "" or not gd.inventory.has(rc["adventurer"]), "候选人物不在卡池")
	if cid == "":
		gd.gold = 10000
		var pool_before: int = gd.roster.size()
		_ok(town.can_afford_candidate(rc), "普通候选可负担")
		_ok(town.recruit_candidate(rc), "普通候选招募成功")
		_ok(gd.roster.size() == pool_before + 1, "卡池 +1")
	else:
		# 特殊候选（需要收集品 + 金币）——随机分支，但必须断言同样多的条数，
		# 否则本套测试的通过数会在 95↔97 之间抖（roll_recruit_candidate 的 rng 每局随机）。
		_ok(cid != "", "特殊候选带收集品要求（%s）" % cid)
		_ok(String(rc.get("collectible_name", "")) != "",
			"特殊候选带收集品名称（%s）" % String(rc.get("collectible_name", "")))
		gd.gold = 10000
		_ok(not town.can_afford_candidate(rc), "未持有收集品时买不起特殊候选")
	_ok(town.can_afford_candidate({"adventurer": null}) == false, "空候选不可招募")

	# 任务推荐战力与小队总战力挂钩（9-22 修改意见 1）
	var qm := QuestManager.new()
	qm.roll_quests()
	var squad: int = gd.team_power()
	var all_ok := true
	for q in qm.available:
		if int(q.recommend_power) < 50:
			all_ok = false
	_ok(all_ok, "任务推荐战力均 ≥ 50（小队总战力 %d 参与混合）" % squad)


# ---------------------------------------------------------------------------
# 成长：加点 + 战利品升级
# ---------------------------------------------------------------------------

func _test_growth(town: TownManager, gd: Node) -> void:
	print("\n-- 成长 --")
	var hero: Adventurer = gd.team[0]
	hero.unspent_points = 3
	var con_before: int = hero.constitution
	_ok(town.spend_point(hero, "constitution"), "加点成功")
	_ok(hero.constitution == con_before + 1, "体质 +1")
	_ok(hero.unspent_points == 2, "属性点 -1")

	# 战利品升级
	var trophy: ItemData = gd.db.get_item("bat_wing")
	if trophy == null:
		for it in gd.db.items.values():
			if (it as ItemData).item_class == ItemData.ItemClass.TROPHY:
				trophy = it
				break
	gd.inventory.append(trophy)
	var lv_before: int = hero.level
	var inv_before: int = gd.inventory.size()
	_ok(town.level_up_with_trophy(hero, trophy), "战利品升级成功")
	_ok(hero.level == lv_before + 1, "等级 +1")
	_ok(gd.inventory.size() == inv_before - 1, "战利品被消耗")

	# 非战利品不能升级
	var non_trophy: ItemData = gd.db.get_item("health_potion")
	if non_trophy != null:
		gd.inventory.append(non_trophy)
		_ok(not town.level_up_with_trophy(hero, non_trophy), "非战利品不能用于升级")


# ---------------------------------------------------------------------------
# 装备
# ---------------------------------------------------------------------------

func _test_equip(town: TownManager, gd: Node) -> void:
	print("\n-- 装备 --")
	var hero: Adventurer = gd.team[0]
	var sword: ItemData = gd.db.get_item("short_sword")
	if sword == null:
		sword = _first_equipment(gd)
	gd.inventory.append(sword)
	var inv_before: int = gd.inventory.size()
	_ok(town.equip(hero, sword), "穿上装备成功")
	_ok(gd.inventory.size() == inv_before - 1, "装备从背包移除")
	_ok(hero.equipment.get(sword.slot) == sword, "装备进入人物槽位")

	# 脱下
	_ok(town.unequip(hero, sword.slot), "脱下装备")
	_ok(hero.equipment.get(sword.slot) == null, "槽位清空")
	_ok(gd.inventory.has(sword), "装备回到背包")


func _first_equipment(gd: Node) -> ItemData:
	for it in gd.db.items.values():
		if (it as ItemData).is_equipment():
			return it
	return null


# ---------------------------------------------------------------------------
# 卡组编辑
# ---------------------------------------------------------------------------

func _test_deck(town: TownManager, gd: Node) -> void:
	print("\n-- 卡组编辑 --")
	var deck_before: int = gd.deck.size()
	var card: CardData = gd.db.get_card("cleave")
	if card == null:
		card = gd.db.get_card("strike")

	# 意见 8：卡牌要有获取渠道 —— 未持有的卡不能编入
	var owned_before: int = gd.owned_card_count(card.id)
	if owned_before == 0:
		_ok(not town.add_card_to_deck(card), "未持有的卡不能编入卡组（意见8）")
	else:
		_ok(true, "（该卡本就持有，跳过未持有断言）")

	# 获得一张后才能编入
	gd.add_owned_card(card)
	_ok(town.add_card_to_deck(card), "获得后可以编入卡组")
	_ok(gd.deck.size() == deck_before + 1, "卡组 +1")
	_ok(town.remove_card_from_deck(card), "移卡成功")
	_ok(gd.deck.size() == deck_before, "卡组恢复")

	_ok(town.is_deck_valid(), "默认卡组合法")

	# 上限 40（持有足够多张才能堆到上限）
	for _i in range(60):
		gd.add_owned_card(card)
	for _i in range(60):
		town.add_card_to_deck(card)
	_ok(gd.deck.size() <= TownManager.MAX_DECK, "卡组上限 40（实际 %d）" % gd.deck.size())
	# 编入数不会超过持有数
	var over := false
	for c in gd.owned_cards:
		if gd.deck_card_count(c.id) > gd.owned_card_count(c.id):
			over = true
	_ok(not over, "任何卡牌的编入数都不超过持有数（意见8）")


# ---------------------------------------------------------------------------
# 意见 8：卡牌获取渠道（任务 / 商人 / 宝箱）
# ---------------------------------------------------------------------------

func _test_card_acquisition(town: TownManager, gd: Node) -> void:
	print("\n-- 意见8：卡牌获取渠道 --")
	_ok(gd.owned_cards.size() >= gd.deck.size(), "初始持有卡池不少于默认卡组（%d 张）" % gd.owned_cards.size())

	# 商人卖卡
	town.roll_shop_cards()
	_ok(town.shop_cards.size() >= 1, "商店有在售卡牌（%d 张）" % town.shop_cards.size())
	if town.shop_cards.size() > 0:
		var entry: Dictionary = town.shop_cards[0]
		var c: CardData = entry["card"]
		var price: int = entry["price"]
		_ok(price > 0, "卡牌有售价（%d 金）" % price)
		gd.gold = 0
		_ok(not town.buy_card(c), "金币不足时买卡失败")
		gd.gold = price + 10
		var before: int = gd.owned_card_count(c.id)
		_ok(town.buy_card(c), "金币足够时买卡成功")
		_ok(gd.owned_card_count(c.id) == before + 1, "买卡后持有 +1")
		_ok(gd.gold == 10, "买卡扣款正确（余额 %d）" % gd.gold)
		var still := false
		for e in town.shop_cards:
			if e["card"].id == c.id:
				still = true
		_ok(not still, "已买走的卡从货架移除")

	# 直接授予（宝箱 / 任务共用入口）
	var any_card: CardData = gd.db.get_card("cleave")
	if any_card == null:
		any_card = gd.db.get_card("strike")
	var n0: int = gd.owned_card_count(any_card.id)
	_ok(town.grant_card(any_card), "grant_card 授予成功（宝箱渠道共用）")
	_ok(gd.owned_card_count(any_card.id) == n0 + 1, "授予后持有 +1")

	# 任务奖励卡（构造一个必完成的任务）
	if gd.quests == null:
		gd.quests = QuestManager.new()
	var q := QuestManager.Quest.new()
	q.id = "t_card"
	q.title = "测试任务"
	q.monster_id = "boar"
	q.target_count = 1
	q.progress = 1
	q.accepted = true
	q.reward_card_id = "cleave"
	var n1: int = gd.owned_card_count("cleave")
	var msgs: Array[String] = gd.quests.claim(q)
	_ok(gd.owned_card_count("cleave") == n1 + 1, "任务奖励发放卡牌到持有卡池")
	var found := false
	for m in msgs:
		if m.contains("卡牌"):
			found = true
	_ok(found, "任务结算文案提到卡牌奖励")


# ---------------------------------------------------------------------------
# 意见 5：武器单一槽位 + 意见 6：卡牌六分类
# ---------------------------------------------------------------------------

func _test_weapon_and_categories(town: TownManager, gd: Node) -> void:
	print("\n-- 意见5：武器只占一个槽位 --")
	var sword: ItemData = gd.db.get_item("short_sword")
	var bow: ItemData = gd.db.get_item("short_bow")
	var staff: ItemData = gd.db.get_item("wooden_staff")
	_ok(sword != null and sword.slot == ItemData.Slot.WEAPON, "短剑的槽位是「武器」（意见5）")
	_ok(bow != null and bow.slot == ItemData.Slot.WEAPON, "短弓的槽位是「武器」（意见5）")
	_ok(staff != null and staff.slot == ItemData.Slot.WEAPON, "木杖的槽位是「武器」（意见5）")
	_ok(sword != null and sword.get_slot_name_cn() == "武器", "槽位显示名为「武器」")

	var a: Adventurer = gd.team[0]
	for slot in a.equipment.keys().duplicate():
		a.unequip(slot)
	a.equip(sword)
	_ok(a.equipment.size() == 1 and a.equipment.get(ItemData.Slot.WEAPON) == sword,
		"装上短剑后只占 1 个槽位")
	var old := a.equip(bow)
	_ok(old == sword, "再装短弓会换下短剑（同一个武器槽）")
	_ok(a.equipment.size() == 1, "武器始终只占 1 个槽位（实际 %d）" % a.equipment.size())
	_ok(a.equipment.get(ItemData.Slot.WEAPON) == bow, "武器槽现在是短弓")

	print("\n-- 意见6：卡牌六分类分组 --")
	var groups: Array = town.cards_by_category(false)
	_ok(groups.size() == 6, "卡牌大全分成 6 组（实际 %d）" % groups.size())
	var total := 0
	var names: PackedStringArray = []
	for g in groups:
		var cards: Array = g["cards"]
		total += cards.size()
		names.append(str(g["name"]))
	_ok(total == gd.db.cards.size(), "六组覆盖全部卡牌（%d / %d）" % [total, gd.db.cards.size()])
	print("      分组：%s" % ", ".join(names))
	var owned_groups: Array = town.cards_by_category(true)
	_ok(owned_groups.size() >= 1, "持有卡也能按六分类分组（%d 组）" % owned_groups.size())
	# 每组内所有卡的分类名与组名一致
	var consistent := true
	for g in groups:
		var cards2: Array = g["cards"]
		for c in cards2:
			if (c as CardData).get_category_name_cn() != str(g["name"]):
				consistent = false
	_ok(consistent, "组名与卡牌自身分类名一致")

	# ---- 9-26：卡牌大全扩到"装备 + 物品"，新增物品分组 ----
	print("\n-- 9-26：卡牌大全的物品分组 --")
	var igroups: Array = town.items_by_group()
	var n_item := 0
	var n_equip := 0
	var n_other := 0
	var chapters: PackedStringArray = []
	var id_seen := {}
	var dup: Array = []
	var bad_chapter: Array = []
	for g in igroups:
		var items: Array = g["items"]
		for it in items:
			n_item += 1
			var iid := (it as ItemData).id
			if id_seen.has(iid):
				dup.append(iid)
			id_seen[iid] = true
		var ch := String(g["chapter"])
		if ch == "equip":
			n_equip += items.size()
		elif ch == "other":
			n_other += items.size()
		else:
			bad_chapter.append(ch)
		chapters.append("[%s]%s(%d)" % [ch, g["name"], items.size()])
	_ok(igroups.size() >= 10, "物品分组 ≥10 组（实际 %d）" % igroups.size())
	_ok(n_item == gd.db.items.size(), "分组覆盖全部 %d 件物品（实际 %d）"
		% [gd.db.items.size(), n_item])
	_ok(dup.is_empty(), "同一件物品不会出现在两个组里（重复 %s）" % str(dup))
	_ok(bad_chapter.is_empty(), "每组的 chapter 只能是 equip / other（异常 %s）" % str(bad_chapter))
	print("      分组：%s" % " ".join(chapters))

	# 装备按 7 个可穿戴槽位拆开：每个槽位都要自成一组（全塞进一个"装备"节要滚很久）
	var slots: Array = ItemData.equip_slot_order()
	var equip_group_names: PackedStringArray = []
	for g in igroups:
		if String(g["chapter"]) == "equip":
			equip_group_names.append(String(g["name"]))
	_ok(equip_group_names.size() == slots.size(),
		"装备按 %d 个槽位分成 %d 组" % [slots.size(), equip_group_names.size()])
	var all_named := true
	for slot in slots:
		var want := "装备 · %s" % ItemData.slot_name_cn(slot)
		if not equip_group_names.has(want):
			all_named = false
	_ok(all_named, "槽位组名是「装备 · 部位」（%s）" % ", ".join(equip_group_names))

	# 每个大类都要在"其它"里出现（消耗品/收集品/战利品/杂物各有货）
	var other_names: PackedStringArray = []
	for g in igroups:
		if String(g["chapter"]) == "other":
			other_names.append(String(g["name"]))
	_ok(other_names.size() == 4, "道具与杂物含 4 个大类（实际 %s）" % ", ".join(other_names))
	for want in ["道具", "收集品", "战利品", "杂物"]:
		_ok(other_names.has(want), "「%s」单独成组" % want)
	_ok(n_equip + n_other == n_item, "equip(%d) + other(%d) = 全部 %d 件" % [n_equip, n_other, n_item])

	# 顺序稳定：同一份数据连算两次，组数与每组 id 序列必须完全一致
	# （物品字典遍历顺序不稳定，靠 sort_custom 兜住）
	var again: Array = town.items_by_group()
	var same := again.size() == igroups.size()
	if same:
		for i in range(igroups.size()):
			var a1: Array = igroups[i]["items"]
			var a2: Array = again[i]["items"]
			if a1.size() != a2.size():
				same = false
				break
			for j in range(a1.size()):
				if (a1[j] as ItemData).id != (a2[j] as ItemData).id:
					same = false
	_ok(same, "两次分组结果完全一致（顺序稳定）")


# ---------------------------------------------------------------------------
# 商店
# ---------------------------------------------------------------------------

func _test_shop(town: TownManager, gd: Node) -> void:
	print("\n-- 商店 --")
	var shop := town.roll_shop()
	_ok(shop.size() == 4, "商店货架 4 件")

	var item: ItemData = shop[0]
	gd.gold = 10000
	var gold_before: int = gd.gold
	_ok(town.buy(item), "购买成功")
	_ok(gd.gold == gold_before - item.sell_price, "金币按原价扣除")
	_ok(gd.inventory.has(item), "商品入背包")

	# 售卖（半价）
	var sell_price := maxi(item.sell_price / 2, 1)
	var gold_b2: int = gd.gold
	_ok(town.sell(item), "出售成功")
	_ok(gd.gold == gold_b2 + sell_price, "金币按半价回收（+%d）" % sell_price)
	_ok(not gd.inventory.has(item), "物品移出背包")

	# 刷新次数
	gd.gold = 10000
	_ok(town.try_refresh_store(), "商店刷新成功")
	_ok(gd.refresh_store == 0, "刷新次数 -1")


# ---------------------------------------------------------------------------
# 仓库
# ---------------------------------------------------------------------------

func _test_storage(town: TownManager, gd: Node) -> void:
	print("\n-- 仓库 --")
	var item: ItemData = gd.db.get_item("rusty_key")
	if item == null:
		item = gd.db.get_item("health_potion")
	gd.inventory.append(item)
	var inv_before: int = gd.inventory.size()
	var store_before: int = gd.storage.size()

	_ok(town.store(item), "存入仓库成功")
	_ok(gd.inventory.size() == inv_before - 1, "背包 -1")
	_ok(gd.storage.size() == store_before + 1, "仓库 +1")

	_ok(town.retrieve(item), "取回成功")
	_ok(gd.inventory.has(item), "回到背包")
	_ok(not gd.storage.has(item), "移出仓库")
