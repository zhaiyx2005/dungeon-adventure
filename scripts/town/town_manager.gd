## 城镇管理器
##
## 阶段 4 城镇系统的全部逻辑：工会（招募/组队/提升）、整备（加点/穿脱装备/卡组）、
## 商店（买卖）、仓库（存取）、卡牌大全（只读查询）。
##
## 与 run_manager 一样，这里不直接引用 autoload 全局标识符 `GameData`，
## 而是运行时从场景树取实例（headless --script 编译链解析不到 autoload 全局名）。
class_name TownManager
extends RefCounted


## 组队上限
const MAX_TEAM_SIZE := 4

## 卡组容量
const MIN_DECK := 20
const MAX_DECK := 40

## 招募普通成员的属性总点（战力锚点）
const RECRUIT_STAT_POOL := 20  ## 四属性之和，招募价按此浮动

## 刷新费用阶梯
const REFRESH_COSTS := [0, 50, 100]  ## 第 1/2/3 次刷新费用（0 表示首次免费）

## 战利品升级：消耗 1 件战利品提升的等级数
const TROPHY_LEVELS := 1


signal log_added(text: String)
signal town_changed()


var rng := RandomNumberGenerator.new()

var _gdata: Node = null


func _g() -> Node:
	if _gdata == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			_gdata = tree.root.get_node_or_null("/root/GameData")
	return _gdata


func _db() -> GameDatabase:
	return _g().db as GameDatabase


# ---------------------------------------------------------------------------
# 一、工会：招募
# ---------------------------------------------------------------------------

## 招募价：按属性点折算，200–600 浮动
func recruit_price(pool: int) -> int:
	return clampi(200 + pool * 15, 200, 600)


## 生成一个可招募的普通冒险者（随机属性）。price_out 回填价格。
func roll_recruit() -> Dictionary:
	var a := Adventurer.new()
	a.id = "recruit_%d" % rng.randi()
	# 四属性随机分配 20 点（每项至少 3）
	var remaining := RECRUIT_STAT_POOL
	var stats := [3, 3, 3, 3]
	remaining -= 12
	for _i in range(remaining):
		stats[rng.randi_range(0, 3)] += 1
	a.constitution = stats[0]
	a.strength = stats[1]
	a.intelligence = stats[2]
	a.vitality = stats[3]
	a.base_luck = rng.randi_range(2, 5)
	# 先由属性决定职业原型，再从该职业的名字池取名。
	# 头像也使用同一个职业原型，因此名字、外观和能力倾向始终一致。
	a.display_name = _random_name_for(ArtRegistry.archetype_of(a))
	return {"adventurer": a, "price": recruit_price(RECRUIT_STAT_POOL)}


## 招募一个冒险者入卡池。返回是否成功。
func recruit(adventurer: Adventurer, price: int) -> bool:
	var g := _g()
	if adventurer == null:
		return false
	if g.gold < price:
		_log("金币不足，无法招募（需要 %d）" % price)
		return false
	g.gold -= price
	g.roster.append(adventurer)
	_log("招募了「%s」（花费 %d 金币）" % [adventurer.display_name, price])
	town_changed.emit()
	return true


## 用收集品招募特殊人物（首版简化：消耗指定收集品 + 固定金币）
func recruit_special(name: String, stat_pool: int, gold_cost: int, collectible_id: String) -> bool:
	var g := _g()
	# 校验收集品在背包里
	if not _has_item(collectible_id):
		_log("缺少收集品「%s」，无法招募" % _db().get_item(collectible_id).display_name)
		return false
	if g.gold < gold_cost:
		_log("金币不足，无法招募特殊人物（需要 %d）" % gold_cost)
		return false

	var a := Adventurer.new()
	a.id = "special_%d" % rng.randi()
	a.display_name = name
	_assign_stats(a, stat_pool)
	a.base_luck = 6

	_remove_item_by_id(collectible_id)
	g.gold -= gold_cost
	g.roster.append(a)
	_log("招募了特殊人物「%s」" % name)
	town_changed.emit()
	return true


## 刷新招募列表需要消耗刷新次数（返回是否成功）
func try_refresh_recruit() -> bool:
	var g := _g()
	if g.refresh_recruit <= 0:
		_log("招募刷新次数已用完")
		return false
	var cost: int = REFRESH_COSTS[clampi(3 - g.refresh_recruit, 0, 2)]
	if g.gold < cost:
		_log("金币不足，无法刷新（需要 %d）" % cost)
		return false
	g.gold -= cost
	g.refresh_recruit -= 1
	_log("刷新招募列表（花费 %d 金币，剩余 %d 次）" % [cost, g.refresh_recruit])
	town_changed.emit()
	return true


# ---- 招募木板候选（普通：金钱；特殊：收集品 + 金币，9-22 修改意见 1） ----

## 特殊招募的属性池加成与金币区间
const SPECIAL_STAT_POOL := 26
const SPECIAL_GOLD_MIN := 300
const SPECIAL_GOLD_MAX := 600
const SPECIAL_CHANCE := 0.3


## 生成一个招募候选：普通（只花金币）或特殊（收集品卡牌 + 金币）。
## 形如 {adventurer, price, collectible_id, collectible_name}
func roll_recruit_candidate() -> Dictionary:
	if rng.randf() < SPECIAL_CHANCE:
		return _roll_special_candidate()
	var normal := roll_recruit()
	normal["collectible_id"] = ""
	normal["collectible_name"] = ""
	return normal


func _roll_special_candidate() -> Dictionary:
	var collectible := _random_collectible()
	var a := Adventurer.new()
	a.id = "special_%d" % rng.randi()
	_assign_stats(a, SPECIAL_STAT_POOL)
	a.base_luck = 6
	a.display_name = _random_name_for(ArtRegistry.archetype_of(a))
	var price := rng.randi_range(SPECIAL_GOLD_MIN, SPECIAL_GOLD_MAX)
	if collectible == null:
		# 数据库没有收集品时退化为普通招募
		return {"adventurer": a, "price": recruit_price(RECRUIT_STAT_POOL), "collectible_id": "", "collectible_name": ""}
	return {
		"adventurer": a, "price": price,
		"collectible_id": collectible.id, "collectible_name": collectible.display_name,
	}


## 招募候选是否满足条件（金币 + 收集品）
func can_afford_candidate(cand: Dictionary) -> bool:
	var g := _g()
	var a: Adventurer = cand.get("adventurer")
	if a == null:
		return false
	var price: int = cand.get("price", 0)
	if g.gold < price:
		return false
	var cid: String = cand.get("collectible_id", "")
	if cid != "" and not _has_item(cid):
		return false
	return true


## 招募候选入卡池（扣钱/扣收集品）。返回是否成功。
func recruit_candidate(cand: Dictionary) -> bool:
	var g := _g()
	var a: Adventurer = cand.get("adventurer")
	if a == null:
		return false
	var price: int = cand.get("price", 0)
	var cid: String = cand.get("collectible_id", "")
	if cid == "":
		return recruit(a, price)
	if not _has_item(cid):
		_log("缺少收集品「%s」，无法招募" % cand.get("collectible_name", cid))
		return false
	if g.gold < price:
		_log("金币不足，无法招募（需要 %d）" % price)
		return false
	_remove_item_by_id(cid)
	g.gold -= price
	g.roster.append(a)
	_log("用收集品招募了「%s」（花费收集品「%s」+ %d 金币）" % [a.display_name, cand.get("collectible_name", cid), price])
	town_changed.emit()
	return true


func _random_collectible() -> ItemData:
	var candidates: Array[ItemData] = []
	for it in _db().items.values():
		var item := it as ItemData
		if item != null and item.item_class == ItemData.ItemClass.COLLECTIBLE:
			candidates.append(item)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


# ---------------------------------------------------------------------------
# 二、工会：组队
# ---------------------------------------------------------------------------

## 把卡池里的冒险者加入小队。返回是否成功。
func add_to_team(adventurer: Adventurer) -> bool:
	var g := _g()
	if adventurer == null:
		return false
	if g.team.size() >= MAX_TEAM_SIZE:
		_log("小队已满（最多 %d 人）" % MAX_TEAM_SIZE)
		return false
	if g.team.has(adventurer):
		_log("「%s」已在小队中" % adventurer.display_name)
		return false
	g.roster.erase(adventurer)
	g.team.append(adventurer)
	_log("「%s」加入小队" % adventurer.display_name)
	town_changed.emit()
	return true


## 把小队成员移回卡池（至少保留 1 人；主角永远在队伍之中）
func remove_from_team(adventurer: Adventurer) -> bool:
	var g := _g()
	if adventurer == null:
		return false
	if is_protagonist(adventurer):
		_log("主角无法移出队伍")
		return false
	if g.team.size() <= 1:
		_log("小队至少保留 1 人")
		return false
	if not g.team.has(adventurer):
		return false
	g.team.erase(adventurer)
	g.roster.append(adventurer)
	_log("「%s」移出小队" % adventurer.display_name)
	town_changed.emit()
	return true


## 主角判定（id == "hero"，永远无法移出队伍）
func is_protagonist(adventurer: Adventurer) -> bool:
	return adventurer != null and adventurer.id == "hero"


## 把卡池里的冒险者插入小队指定位置（0 = 1 号位）。返回是否成功。
func insert_into_team(adventurer: Adventurer, idx: int) -> bool:
	var g := _g()
	if adventurer == null:
		return false
	if g.team.has(adventurer):
		return reorder_to(adventurer, idx)
	if g.team.size() >= MAX_TEAM_SIZE:
		_log("小队已满（最多 %d 人）" % MAX_TEAM_SIZE)
		return false
	if idx < 0 or idx > g.team.size():
		idx = g.team.size()
	g.roster.erase(adventurer)
	g.team.insert(idx, adventurer)
	_log("「%s」加入小队（%d 号位）" % [adventurer.display_name, idx + 1])
	town_changed.emit()
	return true


## 小队内部换位（主角可以换位，但不能被移出）
func swap_team_positions(idx_a: int, idx_b: int) -> bool:
	var g := _g()
	if idx_a < 0 or idx_a >= g.team.size() or idx_b < 0 or idx_b >= g.team.size():
		return false
	if idx_a == idx_b:
		return false
	var tmp: Adventurer = g.team[idx_a]
	g.team[idx_a] = g.team[idx_b]
	g.team[idx_b] = tmp
	_log("小队换位：%s ↔ %s" % [g.team[idx_a].display_name, g.team[idx_b].display_name])
	town_changed.emit()
	return true


## 把小队成员移动到目标位置（其余成员顺次让位）
func reorder_to(adventurer: Adventurer, idx: int) -> bool:
	var g := _g()
	if adventurer == null or not g.team.has(adventurer):
		return false
	var from: int = g.team.find(adventurer)
	idx = clampi(idx, 0, g.team.size() - 1)
	if from == idx:
		return false
	g.team.remove_at(from)
	g.team.insert(idx, adventurer)
	_log("「%s」调到 %d 号位" % [adventurer.display_name, idx + 1])
	town_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 三、工会：提升（加点 / 战利品升级）
# ---------------------------------------------------------------------------

## 分配属性点
func spend_point(adventurer: Adventurer, stat_key: String) -> bool:
	if adventurer == null:
		return false
	if adventurer.spend_point(stat_key):
		_log("「%s」%s +1" % [adventurer.display_name, _stat_cn(stat_key)])
		town_changed.emit()
		return true
	return false


## 消耗战利品提升等级
func level_up_with_trophy(adventurer: Adventurer, trophy: ItemData) -> bool:
	var g := _g()
	if adventurer == null or trophy == null:
		return false
	if trophy.item_class != ItemData.ItemClass.TROPHY:
		_log("「%s」不是战利品，不能用于提升等级" % trophy.display_name)
		return false
	if not g.inventory.has(trophy):
		_log("背包里没有「%s」" % trophy.display_name)
		return false
	g.inventory.erase(trophy)
	adventurer.add_level_from_trophy(TROPHY_LEVELS)
	_log("「%s」消耗「%s」提升 %d 级" % [adventurer.display_name, trophy.display_name, TROPHY_LEVELS])
	town_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 四、整备：装备
# ---------------------------------------------------------------------------

## 从背包给冒险者穿装备。返回被替换下来的旧装备（若有）。
func equip(adventurer: Adventurer, item: ItemData) -> bool:
	var g := _g()
	if adventurer == null or item == null:
		return false
	if not item.is_equipment():
		return false
	if not g.inventory.has(item):
		_log("背包里没有「%s」" % item.display_name)
		return false
	g.inventory.erase(item)
	var old := adventurer.equip(item)
	if old != null:
		g.inventory.append(old)
		_log("「%s」装备「%s」，换下「%s」" % [adventurer.display_name, item.display_name, old.display_name])
	else:
		_log("「%s」装备「%s」" % [adventurer.display_name, item.display_name])
	town_changed.emit()
	return true


## 脱下装备回背包
func unequip(adventurer: Adventurer, slot: ItemData.Slot) -> bool:
	var g := _g()
	if adventurer == null:
		return false
	var old := adventurer.unequip(slot)
	if old == null:
		return false
	g.inventory.append(old)
	_log("「%s」脱下「%s」" % [adventurer.display_name, old.display_name])
	town_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 五、整备：卡组
# ---------------------------------------------------------------------------

## 添加一张卡到卡组（上限 40；且编入张数不能超过持有张数）
func add_card_to_deck(card: CardData) -> bool:
	var g := _g()
	if card == null:
		return false
	if g.deck.size() >= MAX_DECK:
		_log("卡组已满（%d 张）" % MAX_DECK)
		return false
	# 9-22 修改意见 8：卡牌需要有获取渠道 —— 只能编入自己持有的卡
	var owned: int = g.owned_card_count(card.id)
	var in_deck: int = g.deck_card_count(card.id)
	if in_deck >= owned:
		_log("没有更多「%s」可编入（持有 %d 张，已编入 %d 张）" % [card.display_name, owned, in_deck])
		return false
	g.deck.append(card)
	_log("卡组加入「%s」（%d 张）" % [card.display_name, g.deck.size()])
	town_changed.emit()
	return true


## 从卡组移除一张卡
func remove_card_from_deck(card: CardData) -> bool:
	var g := _g()
	if card == null or not g.deck.has(card):
		return false
	g.deck.erase(card)
	_log("卡组移除「%s」（%d 张）" % [card.display_name, g.deck.size()])
	town_changed.emit()
	return true


## 卡组是否合法（20–40）
func is_deck_valid() -> bool:
	return DeckManager.is_valid_deck_size(_g().deck.size())


# ---------------------------------------------------------------------------
# 六、商店
# ---------------------------------------------------------------------------

## 买物品入背包
func buy(item: ItemData) -> bool:
	var g := _g()
	if item == null:
		return false
	var price := item.sell_price
	if g.gold < price:
		_log("金币不足，无法购买「%s」（需要 %d）" % [item.display_name, price])
		return false
	g.gold -= price
	g.inventory.append(item)
	_log("购买「%s」（花费 %d 金币）" % [item.display_name, price])
	town_changed.emit()
	return true


## 卖背包物品（价格 = sell_price 折半向下取整，至少 1）
func sell(item: ItemData) -> bool:
	var g := _g()
	if item == null or not g.inventory.has(item):
		return false
	var price := maxi(item.sell_price / 2, 1)
	g.inventory.erase(item)
	g.gold += price
	_log("出售「%s」（获得 %d 金币）" % [item.display_name, price])
	town_changed.emit()
	return true


## 刷新商店商品需要消耗刷新次数
func try_refresh_store() -> bool:
	var g := _g()
	if g.refresh_store <= 0:
		_log("商店刷新次数已用完")
		return false
	var cost: int = REFRESH_COSTS[clampi(3 - g.refresh_store, 0, 2)]
	if g.gold < cost:
		_log("金币不足，无法刷新（需要 %d）" % cost)
		return false
	g.gold -= cost
	g.refresh_store -= 1
	_log("刷新商店（花费 %d 金币，剩余 %d 次）" % [cost, g.refresh_store])
	town_changed.emit()
	return true


## 随机一份商店货架（4 件非杂物物品）
func roll_shop() -> Array[ItemData]:
	var candidates: Array[ItemData] = []
	for it in _db().items.values():
		var item := it as ItemData
		if item != null and item.item_class != ItemData.ItemClass.JUNK:
			candidates.append(item)
	candidates.shuffle()
	var out: Array[ItemData] = []
	for i in range(mini(4, candidates.size())):
		out.append(candidates[i])
	return out


# ---------------------------------------------------------------------------
# 六·二、商人卖卡（9-22 修改意见 8：战斗卡牌可通过商人获取）
# ---------------------------------------------------------------------------

## 卡牌售价（按稀有度）
const CARD_PRICE_BY_RARITY := {
	CardData.Rarity.COMMON: 90,
	CardData.Rarity.RARE: 180,
	CardData.Rarity.EPIC: 320,
	CardData.Rarity.LEGENDARY: 520,
}
const SHOP_CARD_COUNT := 3

## 本店在售卡牌：[{card: CardData, price: int}]
var shop_cards: Array = []


func card_price(card: CardData) -> int:
	if card == null:
		return 0
	return int(CARD_PRICE_BY_RARITY.get(card.rarity, 90))


## 刷新在售卡牌（不重复）
func roll_shop_cards() -> void:
	shop_cards.clear()
	var pool: Array = _db().cards.values()
	if pool.is_empty():
		return
	var guard := 0
	while shop_cards.size() < SHOP_CARD_COUNT and guard < 80:
		guard += 1
		var card := pool[rng.randi_range(0, pool.size() - 1)] as CardData
		var dup := false
		for e in shop_cards:
			if e["card"].id == card.id:
				dup = true
				break
		if dup:
			continue
		shop_cards.append({"card": card, "price": card_price(card)})


## 买卡：扣金币 → 进持有卡池
func buy_card(card: CardData) -> bool:
	var g := _g()
	if card == null:
		return false
	var price := card_price(card)
	if g.gold < price:
		_log("金币不足，无法购买卡牌「%s」（需要 %d）" % [card.display_name, price])
		return false
	g.gold -= price
	g.add_owned_card(card)
	for i in range(shop_cards.size() - 1, -1, -1):
		if shop_cards[i]["card"].id == card.id:
			shop_cards.remove_at(i)
	_log("购买卡牌「%s」（花费 %d 金币，持有 %d 张）" % [card.display_name, price, g.owned_card_count(card.id)])
	town_changed.emit()
	return true


## 直接授予一张卡（任务奖励 / 宝箱掉落）
func grant_card(card: CardData) -> bool:
	var g := _g()
	if card == null:
		return false
	g.add_owned_card(card)
	_log("获得卡牌「%s」（持有 %d 张）" % [card.display_name, g.owned_card_count(card.id)])
	town_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 七、仓库
# ---------------------------------------------------------------------------

## 背包 → 仓库
func store(item: ItemData) -> bool:
	var g := _g()
	if item == null or not g.inventory.has(item):
		return false
	g.inventory.erase(item)
	g.storage.append(item)
	_log("「%s」存入仓库" % item.display_name)
	town_changed.emit()
	return true


## 仓库 → 背包
func retrieve(item: ItemData) -> bool:
	var g := _g()
	if item == null or not g.storage.has(item):
		return false
	g.storage.erase(item)
	g.inventory.append(item)
	_log("「%s」取回背包" % item.display_name)
	town_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 八、卡牌大全（只读）
# ---------------------------------------------------------------------------

## 六分类分组（9-22 修改意见 6）：物理进攻 / 法术进攻 / 物理防御 / 法术防御 / 物理特殊 / 法术特殊
## 返回 [{ name: String, cards: Array[CardData] }]
## only_owned = true 时只列玩家持有的卡（按 id 去重）
func cards_by_category(only_owned: bool = false) -> Array:
	var out: Array = []
	var seen := {}
	for cls in [CardData.CardClass.ATTACK, CardData.CardClass.DEFENSE, CardData.CardClass.SPECIAL]:
		for dt in [CardData.DamageType.PHYSICAL, CardData.DamageType.MAGICAL]:
			var list: Array[CardData] = []
			if only_owned:
				for c in _g().owned_cards:
					var card := c as CardData
					if card == null or card.card_class != cls or card.damage_type != dt:
						continue
					if seen.has(card.id):
						continue
					seen[card.id] = true
					list.append(card)
			else:
				for c in _db().cards.values():
					var card := c as CardData
					if card != null and card.card_class == cls and card.damage_type == dt:
						list.append(card)
			if list.is_empty():
				continue
			var entry := {"name": list[0].get_category_name_cn(), "cards": list}
			out.append(entry)
	return out


## 按分类取全部卡牌
func all_cards_by_class() -> Dictionary:
	var out := {
		CardData.CardClass.ATTACK: [] as Array[CardData],
		CardData.CardClass.DEFENSE: [] as Array[CardData],
		CardData.CardClass.SPECIAL: [] as Array[CardData],
	}
	for c in _db().cards.values():
		var card := c as CardData
		out[card.card_class].append(card)
	return out


## 按分类取「持有卡牌」（去重，卡组编入用；9-22 修改意见 8）
func owned_cards_by_class() -> Dictionary:
	var out := {
		CardData.CardClass.ATTACK: [] as Array[CardData],
		CardData.CardClass.DEFENSE: [] as Array[CardData],
		CardData.CardClass.SPECIAL: [] as Array[CardData],
	}
	var seen := {}
	for c in _g().owned_cards:
		var card := c as CardData
		if card == null or seen.has(card.id):
			continue
		seen[card.id] = true
		out[card.card_class].append(card)
	return out


## 物品分组（9-26）：装备先按**槽位**细分（头/颈/身/手/腿/脚/武器），
## 其余按大类（道具 / 收集品 / 战利品 / 杂物）。
##
## 为什么装备要按槽位拆：装备有 39 件、占全部物品的一半以上，
## 挤在一个"装备"节里要滚很久，而且玩家找装备本来就是按"能穿哪个部位"找的。
##
## 返回 [{ name: String, items: Array[ItemData], chapter: "equip"|"other" }]，空组跳过。
## `chapter` 给 UI 用来分"装备"与"道具与杂物"两个大节 —— 让调用方去猜名字前缀
## （begins_with("装备")）太脆，加个显式字段更清楚。
func items_by_group() -> Array:
	var all: Array[ItemData] = []
	for v in _db().items.values():
		var it := v as ItemData
		if it != null:
			all.append(it)
	# 字典遍历顺序不稳定，同组内改用 id 排序，保证每次打开卡牌大全的排列一致
	all.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.id < b.id)

	var out: Array = []
	for slot in ItemData.equip_slot_order():
		var list: Array[ItemData] = []
		for it in all:
			if it.item_class == ItemData.ItemClass.EQUIPMENT and it.slot == slot:
				list.append(it)
		if not list.is_empty():
			out.append({"name": "装备 · %s" % ItemData.slot_name_cn(slot),
				"items": list, "chapter": "equip"})

	var tail := [
		[ItemData.ItemClass.CONSUMABLE, "道具"],
		[ItemData.ItemClass.COLLECTIBLE, "收集品"],
		[ItemData.ItemClass.TROPHY, "战利品"],
		[ItemData.ItemClass.JUNK, "杂物"],
	]
	for pair in tail:
		var list2: Array[ItemData] = []
		for it in all:
			if it.item_class == pair[0]:
				list2.append(it)
		if not list2.is_empty():
			out.append({"name": pair[1], "items": list2, "chapter": "other"})
	return out


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

func _has_item(item_id: String) -> bool:
	var g := _g()
	for it in g.inventory:
		if it.id == item_id:
			return true
	return false


func _remove_item_by_id(item_id: String) -> void:
	var g := _g()
	for i in range(g.inventory.size() - 1, -1, -1):
		if g.inventory[i].id == item_id:
			g.inventory.remove_at(i)
			return


func _assign_stats(a: Adventurer, pool: int) -> void:
	var remaining := pool - 12
	var stats := [3, 3, 3, 3]
	for _i in range(maxi(remaining, 0)):
		stats[rng.randi_range(0, 3)] += 1
	a.constitution = stats[0]
	a.strength = stats[1]
	a.intelligence = stats[2]
	a.vitality = stats[3]


## 职业原型专属名字池。键与 ArtRegistry 的人物图片原型完全一致。
const ARCHETYPE_NAMES := {
	"warrior": ["铁卫·布兰", "佣兵·洛克", "盾手·格兰", "重甲·哈维"],
	"arch_scholar": ["星术师·莉娅", "学者·赛琳", "秘法师·诺拉", "见习法师·艾琳"],
	"arch_rogue": ["影刃·薇拉", "游荡者·米娅", "夜行者·凯拉", "斥候·蕾妮"],
	"arch_priest": ["司祭·马丁", "牧师·埃文", "圣职者·奥伦", "医者·诺亚"],
	"arch_ranger": ["游侠·艾拉", "猎手·菲恩", "弓手·罗莎", "林地守望·梅芙"],
}


func _random_name_for(archetype: String) -> String:
	var names: Array = ARCHETYPE_NAMES.get(archetype, ARCHETYPE_NAMES["arch_ranger"])
	return String(names[rng.randi_range(0, names.size() - 1)])


func _stat_cn(key: String) -> String:
	match key:
		"constitution": return "体质"
		"strength": return "力量"
		"intelligence": return "智力"
		"vitality": return "精力"
	return key


func _log(text: String) -> void:
	print("[城镇] " + text)
	log_added.emit(text)
