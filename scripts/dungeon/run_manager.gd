## 地牢 run 管理器
##
## 一次「进入地下城 → 逐节点推进 → 撤离 / 死亡 / 通关」的完整流程状态。
## UI 只读它的状态、调它的方法；数值结算统一走 PowerCalculator，不硬编码。
##
## 关键规则（HANDOFF.md §4 阶段 3）：
##   - 3×7 地图随机连线，逐行向上推进
##   - 节点类型权重 战斗 70 / 宝箱 10 / 事件 20
##   - 层 Boss 房胜利必出宝箱；打完 Boss 可选撤离或继续下一层
##   - 撤离规则（9-22 修改意见 4）：必须击败本层 Boss 后才能撤离
##   - 层级准入：队伍总战力 ≥ recommend_power_min；金币直达还要"已通关过该层"
##   - 死亡惩罚：全队濒死 → 清空背包 + 回滚本次探索的金币/经验（保留卡组与已穿装备）
##
## 注意：这里不直接引用 autoload 全局标识符 `GameData`，而是运行时从场景树
## 取实例。原因是 headless --script 测试模式下，class_name 脚本的编译链里
## 解析不到 autoload 全局名（见 godot-headless-test skill §6）。场景脚本
## （如 run_scene.gd）运行时加载则无此限制。
class_name RunManager
extends RefCounted


## run 状态
enum Status {
	IDLE,       ## 未开始
	EXPLORING,  ## 探索中
	RETREATED,  ## 已撤离（带回战利品）
	DEFEATED,   ## 全队濒死（死亡惩罚已结算）
	CLEARED,    ## 通关（打完最后一层 Boss）
}

signal log_added(text: String)
signal run_changed()


var dungeon: DungeonData = null
var map: Array = []                    ## MapGenerator.MapNode
var current: MapGenerator.MapNode = null

var status: int = Status.IDLE
var rng := RandomNumberGenerator.new()

## 本次探索统计（展示用；实际入账在战斗/事件结算时直接写 GameData）
var gold_earned: int = 0
var exp_earned: int = 0
var items_found: Array[ItemData] = []
## 本次探索掉落的战斗卡（9-22 修改意见 8：宝箱可开出卡牌）
var card_found: Array[CardData] = []

## 最近一次战斗/宝箱/事件的结果描述，UI 弹窗用
var last_event_title: String = ""
var last_event_lines: Array[String] = []

## 当前层的 Boss 是否已被击败（决定是否出现「撤离 / 继续向下」选择）
var boss_defeated: bool = false

## 死亡回滚快照
var _start_gold: int = 0
var _start_exp: Dictionary = {}
var _start_level: Dictionary = {}
var _start_points: Dictionary = {}

var _gdata: Node = null


## 运行时获取 GameData 单例（autoload）
func _g() -> Node:
	if _gdata == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			_gdata = tree.root.get_node_or_null("/root/GameData")
	return _gdata


func _db() -> GameDatabase:
	return _g().db as GameDatabase


# ---------------------------------------------------------------------------
# 开始 / 选层
# ---------------------------------------------------------------------------

## 用队伍总战力判定能否进入该层
func can_enter(d: DungeonData) -> bool:
	if d == null:
		return false
	return d.can_enter(_g().team_power())


## 进入某层失败原因（空串 = 可进入）
## 这是「通用准入」：战力 + 金币。继续向下的路径也走这一关（下一层不一定通关过）。
func enter_block_reason(d: DungeonData) -> String:
	var g := _g()
	if d == null:
		return "关卡数据缺失"
	if not d.can_enter(g.team_power()):
		return "战力不足（需要 ≥ %d，当前 %d）" % [d.recommend_power_min, g.team_power()]
	if g.gold < d.entry_cost:
		return "金币不足（需要 %d，当前 %d）" % [d.entry_cost, g.gold]
	return ""


## 「金币直达」的准入（9-24 修改意见 3）。
## 在通用准入之上再加一条前置：要能付金币直接跳到第 N 层，必须先通关过第 N 层的 Boss。
## 第 1 层永远可直接进入（它是入口层，费用为 0）。
func direct_entry_block_reason(d: DungeonData) -> String:
	var base := enter_block_reason(d)
	if base != "":
		return base
	if d.level_index > 1 and not _g().is_level_cleared(d.level_index):
		# 文案要能塞进按钮（约 18 个汉字），完整解释放 tooltip
		return "尚未通关第 %d 层（需先打败其 Boss）" % d.level_index
	return ""


## 从第 level_index 层开始探索（金币直达路径）。成功返回 true。
func start_at_level(level_index: int) -> bool:
	var d := _db().get_dungeon_by_level(level_index)
	if d == null:
		return false
	var reason := direct_entry_block_reason(d)
	if reason != "":
		_log("无法直接进入「%s」：%s" % [d.display_name, reason])
		return false
	return start(d)


## 开始一次探索。校验准入 + 扣费 + 生成地图 + 记录死亡回滚快照。
func start(d: DungeonData) -> bool:
	var g := _g()
	var reason := enter_block_reason(d)
	if reason != "":
		_log("无法进入「%s」：%s" % [d.display_name, reason])
		return false

	g.gold -= d.entry_cost
	g.reset_team_for_battle()

	dungeon = d
	rng.randomize()
	map = MapGenerator.generate(d, rng)
	current = MapGenerator.get_start(map)

	# 快照（死亡回滚用）。入场费是进层即付、死亡不退，故快照记扣费后的金币。
	_start_gold = g.gold
	for a in g.team:
		_start_exp[a.id] = a.exp
		_start_level[a.id] = a.level
		_start_points[a.id] = a.unspent_points

	status = Status.EXPLORING
	gold_earned = 0
	exp_earned = 0
	items_found.clear()
	card_found.clear()
	boss_defeated = false
	last_event_title = ""
	last_event_lines.clear()

	_log("进入「%s」（危险 %s，推荐战力 %d–%d，入场费 %d）" % [
		d.display_name, d.get_danger_name(),
		d.recommend_power_min, d.recommend_power_max, d.entry_cost,
	])
	run_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 推进
# ---------------------------------------------------------------------------

func current_node() -> MapGenerator.MapNode:
	return current


## 当前可前进的节点（上一行的可达节点）
func reachable_nodes() -> Array:
	var out: Array = []
	if current == null:
		return out
	for col in current.next:
		var n := MapGenerator.find(map, current.row - 1, col)
		if n != null:
			out.append(n)
	return out


## 前进到指定节点。到达后节点内容由调用方按 node.type 处理。
func move_to(node: MapGenerator.MapNode) -> bool:
	if node == null or current == null:
		return false
	if node.row != current.row - 1 or not current.next.has(node.col):
		return false
	current = node
	node.visited = true
	run_changed.emit()
	return true


func at_boss() -> bool:
	return current != null and current.type == MapGenerator.NodeType.BOSS


func is_battle_node() -> bool:
	return current != null and current.type == MapGenerator.NodeType.BATTLE


## 战斗节点敌人编成（普通/精英），返回 monster id 列表
func build_encounter() -> Array[String]:
	if current == null:
		return []
	return current.monster_ids


func boss_id() -> String:
	var b := MapGenerator.get_boss(map)
	if b == null or b.monster_ids.is_empty():
		return dungeon.boss_id
	return b.monster_ids[0]


# ---------------------------------------------------------------------------
# 战斗结算
# ---------------------------------------------------------------------------

## 战斗胜利。Boss 战胜利额外必出宝箱，并把该层记入「已通关」（解锁金币直达）。
func on_battle_victory(reward_exp: int, reward_gold: int) -> void:
	gold_earned += reward_gold
	exp_earned += reward_exp
	if at_boss():
		boss_defeated = true
		_log("击败层 Boss「%s」！" % dungeon.display_name)
		# 9-24 修改意见 3：通关记录进存档 —— 之后能付金币直接回到这一层
		if _g().mark_level_cleared(dungeon.level_index):
			_log("第 %d 层已解锁「金币直达」：下次可在出征准备面板直接进入。" % dungeon.level_index)
		_grant_loot(2, "Boss 宝箱")
	run_changed.emit()


## 战斗失败 = 全队濒死 → 死亡惩罚。
func on_battle_defeat() -> void:
	_log("全队濒死，任务失败。")
	_apply_death_penalty()
	status = Status.DEFEATED
	run_changed.emit()


# ---------------------------------------------------------------------------
# 宝箱 / 事件
# ---------------------------------------------------------------------------

func open_treasure() -> Array[ItemData]:
	var loot := _roll_loot(1)
	for it in loot:
		_add_item(it)
	last_event_title = "宝箱"
	last_event_lines.clear()
	if loot.is_empty():
		last_event_lines.append("宝箱是空的…")
	else:
		for it in loot:
			last_event_lines.append("获得 [%s] %s" % [it.get_rarity_name_cn(), it.display_name])
	# 9-22 修改意见 8：宝箱有概率掉落战斗卡牌
	var card := _roll_card()
	if card != null:
		_g().add_owned_card(card)
		last_event_lines.append("获得卡牌 [%s] %s" % [card.get_rarity_name_cn(), card.display_name])
		card_found.append(card)
	_log("开启宝箱，获得 %d 件物品%s" % [loot.size(), "，1 张卡牌" if card != null else ""])
	run_changed.emit()
	return loot


## 宝箱掉卡：70% 概率，稀有度加权（普通 5 / 稀有 3 / 史诗 2 / 传说 1）
func _roll_card() -> CardData:
	if rng.randf() > 0.7:
		return null
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


## 事件节点：随机一种效果（经验 / 金币 / 物品 / 空手）。
func resolve_event() -> void:
	var g := _g()
	var roll := rng.randf()
	last_event_title = "事件"
	last_event_lines.clear()

	if roll < 0.30:
		var amount := rng.randi_range(0, 80)
		for a in g.team:
			if a.is_alive():
				a.gain_exp(amount)
		exp_earned += amount
		last_event_lines.append("你在废墟中觅得古籍，阅读后获得经验。")
		last_event_lines.append("全队存活成员各 +%d 经验" % amount)
		_log("事件：获得 %d 经验" % amount)
	elif roll < 0.55:
		var amount := rng.randi_range(15, 40)
		g.gold += amount
		gold_earned += amount
		last_event_lines.append("你在一具骷髅的怀里找到钱袋。")
		last_event_lines.append("金币 +%d" % amount)
		_log("事件：获得 %d 金币" % amount)
	elif roll < 0.80:
		var loot := _roll_loot(1)
		if loot.is_empty():
			last_event_lines.append("你在角落发现一个宝箱，但它已经空了。")
		else:
			var it: ItemData = loot[0]
			_add_item(it)
			last_event_lines.append("你在暗格中发现一件物品。")
			last_event_lines.append("获得 [%s] %s" % [it.get_rarity_name_cn(), it.display_name])
			_log("事件：获得物品「%s」" % it.display_name)
	else:
		last_event_lines.append("这里空无一物，只有风吹过的回响。")
		_log("事件：空手而归")
	run_changed.emit()


# ---------------------------------------------------------------------------
# 撤离 / 继续
# ---------------------------------------------------------------------------

## 撤离规则（9-22 修改意见 4）：必须击败本层 Boss 后才能撤离
func can_retreat() -> bool:
	return status == Status.EXPLORING and boss_defeated


## 撤离。Boss 未击败时拒绝并返回 false。
func retreat() -> bool:
	if not can_retreat():
		_log("必须先击败本层 Boss 才能撤离。")
		return false
	status = Status.RETREATED
	_log("你带着战利品撤回了城镇。")
	run_changed.emit()
	return true


## Boss 胜利后继续向下：进入下一层。成功返回 true。
func continue_down() -> bool:
	if dungeon == null:
		return false
	var next_level := dungeon.level_index + 1
	var next := _db().get_dungeon_by_level(next_level)
	if next == null:
		_log("已经是最深处，没有更深的层了。")
		status = Status.CLEARED
		run_changed.emit()
		return false
	_log("继续向下，前往「%s」…" % next.display_name)
	return start(next)


# ---------------------------------------------------------------------------
# 内部：掉落 / 死亡惩罚
# ---------------------------------------------------------------------------

## 队伍总幸运（所有成员幸运之和）
func _team_luck() -> int:
	var total := 0
	for a in _g().team:
		total += a.get_luck()
	return total


func _roll_loot(count: int) -> Array[ItemData]:
	var out: Array[ItemData] = []
	var candidates: Array[ItemData] = []
	for it in _db().items.values():
		var item := it as ItemData
		if item != null and item.item_class != ItemData.ItemClass.JUNK:
			candidates.append(item)
	if candidates.is_empty():
		return out

	var luck_bonus := PowerCalculator.luck_drop_bonus(_team_luck())
	for _i in range(count):
		var chosen := _weighted_pick(candidates, luck_bonus)
		if chosen != null:
			out.append(chosen)
	return out


func _weighted_pick(candidates: Array[ItemData], luck_bonus: float) -> ItemData:
	var total := 0.0
	var weights: Array[float] = []
	for it in candidates:
		var w := 1.0 + float(it.precious_value) * luck_bonus
		weights.append(w)
		total += w
	if total <= 0.0:
		return candidates[0]
	var r := rng.randf() * total
	var acc := 0.0
	for i in range(candidates.size()):
		acc += weights[i]
		if r <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func _add_item(it: ItemData) -> void:
	_g().inventory.append(it)
	items_found.append(it)


## Boss 胜利宝箱
func _grant_loot(count: int, title: String) -> void:
	var loot := _roll_loot(count)
	last_event_title = title
	last_event_lines.clear()
	for it in loot:
		_add_item(it)
		last_event_lines.append("获得 [%s] %s" % [it.get_rarity_name_cn(), it.display_name])
	if loot.is_empty():
		last_event_lines.append("宝箱是空的…")
	for it in loot:
		_log("Boss 宝箱：获得「%s」" % it.display_name)


## 死亡惩罚：清空背包 + 回滚本次探索的金币/经验。
## 保留：卡组、人物已穿装备、人物卡本身。
func _apply_death_penalty() -> void:
	var g := _g()
	g.gold = _start_gold
	for a in g.team:
		if _start_exp.has(a.id):
			a.exp = int(_start_exp[a.id])
		if _start_level.has(a.id):
			a.level = int(_start_level[a.id])
		if _start_points.has(a.id):
			a.unspent_points = int(_start_points[a.id])
	g.inventory.clear()
	_log("死亡惩罚：失去背包内所有物品与本次探索的金币、经验。")


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _log(text: String) -> void:
	print("[地牢] " + text)
	log_added.emit(text)
