## 任务系统
##
## 工会「接任务」：任务 = 目标（击杀 N 只某怪物）+ 奖励（金币/物品）。
## 任务有推荐战力，越高奖励越丰厚。
##
## 结构：Quest 内部类 + 生成器 + 接取/进度/提交结算。
## 遵循 class_name 脚本不引用 autoload 全局名的模式（运行时取 GameData）。
class_name QuestManager
extends RefCounted


## 一个任务
class Quest:
	var id: String = ""
	var title: String = ""
	var description: String = ""
	var monster_id: String = ""      ## 需要击杀的怪物
	var target_count: int = 1        ## 击杀数量
	var progress: int = 0            ## 已击杀
	var recommend_power: int = 0     ## 推荐战力
	var reward_gold: int = 0
	var reward_item_id: String = ""  ## 奖励物品（空则不给）
	var reward_item_count: int = 1
	var reward_card_id: String = ""  ## 奖励战斗卡（9-22 修改意见 8，空则不给）
	var reward_card_count: int = 1
	var accepted: bool = false
	var completed: bool = false      ## 已提交领奖


signal log_added(text: String)
signal quest_changed()


var rng := RandomNumberGenerator.new()

## 当前可接取的任务列表（未接取）
var available: Array = []
## 已接取、进行中的任务
var active: Array = []

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
# 生成
# ---------------------------------------------------------------------------

## 生成一批可接取任务（3 个）
func roll_quests() -> void:
	available.clear()
	for _i in range(3):
		available.append(_roll_one())


func _roll_one() -> Quest:
	var g := _g()
	var q := Quest.new()
	q.id = "quest_%d" % rng.randi()

	# 从全部普通怪里挑一个目标
	var normals: Array[MonsterData] = []
	for m in _db().monsters.values():
		var md := m as MonsterData
		if md.monster_tier == MonsterData.MonsterTier.NORMAL:
			normals.append(md)
	var target: MonsterData = normals[rng.randi_range(0, normals.size() - 1)]
	q.monster_id = target.id
	q.target_count = rng.randi_range(2, 5)

	# 推荐战力：怪物估值与小队总战力各占一半（9-22 修改意见 1：
	# 任务的推荐战力应与当前小队的总战力有关）
	var monster_est := int(target.get_power() * q.target_count * 0.8)
	var squad_power: int = _g().team_power()
	q.recommend_power = monster_est / 2 + squad_power / 2
	q.recommend_power = maxi(q.recommend_power, 50)

	# 奖励：金币 + 可能给一件物品 + 可能给一张战斗卡（9-22 修改意见 8）
	q.reward_gold = 20 + q.target_count * 15
	if rng.randf() < 0.6:
		var item := _random_item()
		if item != null:
			q.reward_item_id = item.id
	if rng.randf() < 0.5:
		var card := _random_card()
		if card != null:
			q.reward_card_id = card.id

	q.title = "讨伐：%s ×%d" % [target.display_name, q.target_count]
	q.description = "击杀 %d 只%s。推荐战力 %d。" % [q.target_count, target.display_name, q.recommend_power]
	return q


## 按稀有度加权抽一张战斗卡（普通 5 / 稀有 3 / 史诗 2 / 传说 1）
func _random_card() -> CardData:
	var pool: Array = []
	for c in _db().cards.values():
		var card := c as CardData
		if card == null:
			continue
		var w := 1
		match card.rarity:
			CardData.Rarity.COMMON:
				w = 5
			CardData.Rarity.RARE:
				w = 3
			CardData.Rarity.EPIC:
				w = 2
			CardData.Rarity.LEGENDARY:
				w = 1
		for _i in range(w):
			pool.append(card)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


func _random_item() -> ItemData:
	var candidates: Array[ItemData] = []
	for it in _db().items.values():
		var item := it as ItemData
		if item != null and item.item_class != ItemData.ItemClass.JUNK:
			candidates.append(item)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


# ---------------------------------------------------------------------------
# 接取 / 进度 / 提交
# ---------------------------------------------------------------------------

## 接取任务
func accept(quest: Quest) -> bool:
	if quest == null or quest.accepted:
		return false
	if active.size() >= 3:
		_log("同时进行的任务最多 3 个")
		return false
	quest.accepted = true
	available.erase(quest)
	active.append(quest)
	_log("接取任务「%s」" % quest.title)
	quest_changed.emit()
	return true


## 记录一次击杀（由战斗结算调用）。更新所有相关任务进度。
func on_kill(monster_id: String) -> void:
	var any_progress := false
	for q in active:
		if q.completed:
			continue
		if q.monster_id == monster_id and q.progress < q.target_count:
			q.progress += 1
			any_progress = true
	if any_progress:
		quest_changed.emit()


## 任务是否可提交
func is_complete(quest: Quest) -> bool:
	return quest != null and quest.accepted and not quest.completed and quest.progress >= quest.target_count


## 提交任务领奖。返回奖励描述。
func claim(quest: Quest) -> Array[String]:
	var g := _g()
	var msgs: Array[String] = []
	if not is_complete(quest):
		return msgs
	quest.completed = true
	g.gold += quest.reward_gold
	msgs.append("获得金币 +%d" % quest.reward_gold)
	if quest.reward_item_id != "":
		var item := _db().get_item(quest.reward_item_id)
		if item != null:
			for _i in range(quest.reward_item_count):
				g.inventory.append(item)
			msgs.append("获得物品 [%s] %s" % [item.get_rarity_name_cn(), item.display_name])
	if quest.reward_card_id != "":
		var card := _db().get_card(quest.reward_card_id)
		if card != null:
			for _i in range(quest.reward_card_count):
				g.add_owned_card(card)
			msgs.append("获得卡牌 [%s] %s" % [card.get_rarity_name_cn(), card.display_name])
	_log("完成任务「%s」" % quest.title)
	quest_changed.emit()
	return msgs


## 刷新任务列表（消耗刷新次数）
func try_refresh_quests() -> bool:
	var g := _g()
	if g.refresh_quest <= 0:
		_log("任务刷新次数已用完")
		return false
	var cost: int = [0, 50, 100][clampi(3 - g.refresh_quest, 0, 2)]
	if g.gold < cost:
		_log("金币不足，无法刷新（需要 %d）" % cost)
		return false
	g.gold -= cost
	g.refresh_quest -= 1
	roll_quests()
	_log("刷新任务列表（花费 %d 金币，剩余 %d 次）" % [cost, g.refresh_quest])
	quest_changed.emit()
	return true


func _log(text: String) -> void:
	print("[任务] " + text)
	log_added.emit(text)
