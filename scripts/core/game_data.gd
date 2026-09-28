## 全局数据总线（Autoload 单例）
##
## 启动时加载全部游戏数据并跑一次校验，然后作为全局入口提供给所有场景使用。
## 用法：
##     GameData.db.get_card("strike")
##     GameData.validator_ok
##
## 为什么做成 Autoload：数据是只读的、全局唯一的一份，每个场景各自 new 一个
## GameDatabase 会重复扫描磁盘、还会让缓存失去意义。
extends Node


## 数据加载器实例
var db: GameDatabase

## 校验是否通过（启动时跑一次）
var validator_ok: bool = false

## 校验错误列表，调试时可直接打印
var validator_errors: Array[String] = []

## 当前进行中的战斗上下文（由 battle_scene 写入，供结算界面读取）
var last_battle_result: Dictionary = {}

## 玩家存档态（首版先放内存里，存档系统后续再做）
var gold: int = 200

## 当前小队（Adventurer 数组）
var team: Array[Adventurer] = []

## 当前卡组（CardData 数组）
var deck: Array[CardData] = []

## 玩家持有的战斗卡（可重复；卡组只能从持有卡里编入）
## 获取渠道：完成任务 / 商人购买 / 宝箱掉落（9-22 修改意见 8）
var owned_cards: Array[CardData] = []

## 背包（随身物品，阶段 3 死亡惩罚作用对象：全队濒死时清空）
var inventory: Array[ItemData] = []

## 待进入的战斗遭遇。地牢节点写入，battle_scene 读取。
## 形如 { "monster_ids": ["boar","cave_bat"], "node_type": "battle"|"elite"|"boss" }
var pending_encounter: Dictionary = {}

## 战斗结束后返回的场景（地牢 run 时为 run_scene，快速战斗为主菜单）
var return_scene: String = ""

## 当前进行中的地牢 run（由 run_scene 创建并挂载）
var run: RunManager = null

## 任务系统（由 town_scene 创建并挂载，跨场景存活以追踪击杀进度）
var quests: QuestManager = null

## 仓库（长期存储，死亡惩罚不清空；阶段 4 城镇系统用）
var storage: Array[ItemData] = []

## 人物卡池（已招募但未上阵的冒险者，阶段 4 工会招募用）
var roster: Array[Adventurer] = []

## 城镇刷新次数（商店 / 招募 / 任务各最多积攒 3 次）
var refresh_store: int = 1
var refresh_recruit: int = 1
var refresh_quest: int = 1

## 进入城镇时要打开的标签页标题（主菜单传入，城镇场景读取后清空）
var pending_initial_tab: String = ""

## 已通关过层 Boss 的地牢层级（9-24 修改意见 3）。
## 每通关一层 Boss，该层就会加进来 —— 之后可以在出征准备面板付金币直接进入该层，
## 不必从第 1 层重新走一遍。
var cleared_levels: Array[int] = []

## 当前进度的**累计游玩时长**（秒）—— 9-28 需求。
##
## 由 `_process` 逐帧累加；存档时写进栏位、读档时从栏位恢复，
## 所以"这个档玩了多久"是跟着档走的，而不是跟着程序进程走的。
var playtime_seconds: float = 0.0

## **本次启动**游戏的时刻（unix 秒）—— 9-28 需求「记录游戏启动时间」。
## 与累计时长分开：前者说明"这次是什么时候开的"，后者说明"这个档一共玩了多久"。
var session_started_at: int = 0


## 某层是否已通关过（第 1 层永远算"可进入"，但通关记录仍如实反映）
func is_level_cleared(level_index: int) -> bool:
	return cleared_levels.has(level_index)


## 记录"通关过第 N 层"。返回是否为首次通关。
func mark_level_cleared(level_index: int) -> bool:
	if level_index <= 0 or cleared_levels.has(level_index):
		return false
	cleared_levels.append(level_index)
	print("[进度] 首次通关第 %d 层地牢 Boss —— 之后可用金币直接进入该层" % level_index)
	return true


## 已解锁「金币直达」的最高层（无通关记录时为 0）
func max_cleared_level() -> int:
	var best := 0
	for lv in cleared_levels:
		if lv > best:
			best = lv
	return best


func _ready() -> void:
	session_started_at = int(Time.get_unix_time_from_system())

	db = GameDatabase.new()
	db.load_all()

	validator_ok = Validator.run_all()
	validator_errors = Validator.get_errors()

	if validator_ok:
		print("[GameData] 数据加载完成：", db.summary())
	else:
		push_error("[GameData] 数据校验失败，共 %d 条错误" % validator_errors.size())
		for e in validator_errors:
			push_error("  " + e)

	_build_default_team()
	_build_default_deck()
	_init_owned_cards()

	# 9-28：v1 时代只有一个 user://save.json，第一次跑新版本时把它搬进栏位 1，
	# 免得玩家以为进度丢了（"看起来像丢档"比真丢档更常见）
	SaveManager.new().migrate_legacy_save()


## 累计游玩时长（9-28 需求）。放在 autoload 上累加，跨场景始终在走。
func _process(delta: float) -> void:
	playtime_seconds += delta


## 当前进度的游玩时长文案（"2 小时 13 分"）
func playtime_text() -> String:
	return SaveManager.format_playtime(int(playtime_seconds))


## 9-22 修改意见 8：战斗卡牌需要有获取渠道。
## owned_cards = 玩家实际持有的卡（可重复），初始等于默认卡组；
## 之后通过「完成任务 / 商人购买 / 宝箱」增加，卡组只能从持有卡里编入。
func _init_owned_cards() -> void:
	owned_cards.clear()
	for c in deck:
		owned_cards.append(c)


## 持有张数
func owned_card_count(card_id: String) -> int:
	var n := 0
	for c in owned_cards:
		if c != null and c.id == card_id:
			n += 1
	return n


## 卡组中已编入张数
func deck_card_count(card_id: String) -> int:
	var n := 0
	for c in deck:
		if c != null and c.id == card_id:
			n += 1
	return n


## 获得新卡（任务奖励 / 商人购买 / 宝箱掉落）
func add_owned_card(card: CardData) -> bool:
	if card == null:
		return false
	owned_cards.append(card)
	return true


# ---------------------------------------------------------------------------
# 首版默认队伍与卡组
# ---------------------------------------------------------------------------
# 阶段 3/4 做地牢与城镇后，这两处会被「工会招募 + 卡组编辑」取代。
# 现阶段先造一支能立刻开打的队伍，让战斗玩法可以先跑起来。

## 造一支 3 人小队：主角 + 两名同伴
func _build_default_team() -> void:
	team.clear()

	var hero := Adventurer.new()
	hero.id = "hero"
	hero.display_name = "农夫之子"
	hero.constitution = 6
	hero.strength = 7
	hero.intelligence = 4
	hero.vitality = 6
	hero.base_luck = 4
	team.append(hero)

	var warrior := Adventurer.new()
	warrior.id = "warrior"
	warrior.display_name = "佣兵"
	warrior.constitution = 8
	warrior.strength = 6
	warrior.intelligence = 3
	warrior.vitality = 5
	warrior.base_luck = 3
	team.append(warrior)

	var mage := Adventurer.new()
	mage.id = "mage"
	mage.display_name = "见习法师"
	mage.constitution = 4
	mage.strength = 3
	mage.intelligence = 9
	mage.vitality = 6
	mage.base_luck = 3
	team.append(mage)


## 造一副 22 张的默认卡组（含破防手段，保证新手能打完第 1 层 Boss）
func _build_default_deck() -> void:
	deck.clear()
	_add_cards("strike", 8)
	_add_cards("heavy_strike", 2)   # 强力物理攻击：1.8 倍物攻，破高抗怪的关键
	_add_cards("guard_phys", 5)
	_add_cards("heal", 3)
	_add_cards("fireball", 2)
	_add_cards("resurrect", 1)
	_add_cards("quick_jab", 1)


func _add_cards(card_id: String, count: int) -> void:
	var card := db.get_card(card_id)
	if card == null:
		push_warning("[GameData] 默认卡组引用了不存在的卡牌：%s" % card_id)
		return
	for _i in range(count):
		deck.append(card)


# ---------------------------------------------------------------------------
# 对外便捷接口
# ---------------------------------------------------------------------------

## 小队总战力
func team_power() -> int:
	var powers: Array = []
	for a in team:
		powers.append(a.get_power())
	return PowerCalculator.team_power(powers)


## 某个冒险者能装备的物品（按槽位整理），UI 用
func equipment_options_for(a: Adventurer, slot: ItemData.Slot) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for it in db.items.values():
		var item := it as ItemData
		if item.is_equipment() and item.slot == slot:
			out.append(item)
	return out


## 重置全队到战斗初始状态
func reset_team_for_battle() -> void:
	for a in team:
		a.reset_for_battle()


## 全队是否还有能行动的人
func team_has_active_member() -> bool:
	for a in team:
		if a.is_alive():
			return true
	return false
