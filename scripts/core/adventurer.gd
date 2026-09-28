## 冒险者（人物）运行时状态
##
## 把「人物卡牌定义」与「局内状态」分开：
##   - 定义（四属性、等级、装备）是持久的，存进存档
##   - 局内状态（当前血量、护盾、是否濒死）每场战斗重置
##
## 这里同时承担两者，方便直接使用。存档时只序列化持久部分。
class_name Adventurer
extends RefCounted


## 每回合回复量（9-22 修改意见 7，用户澄清后订正）
##   行动点：每回合只回复 1 点（回满即停）
##   法力值：每回合回复 5 点（回满即停）
const ACTION_REGEN_PER_TURN := 1
const MANA_REGEN_PER_TURN := 5


# ---- 持久数据 ----
var id: String = ""
var display_name: String = ""

## 四基础属性
var constitution: int = 5   ## 体质
var strength: int = 5       ## 力量
var intelligence: int = 5   ## 智力
var vitality: int = 5       ## 精力

var level: int = 1
var exp: int = 0
var unspent_points: int = 0  ## 未分配属性点

## 装备槽：slot(ItemData.Slot) -> ItemData
var equipment: Dictionary = {}

## 初始幸运（角色自带，可被装备与道具提升）
var base_luck: int = 3

# ---- 局内状态 ----
var current_hp: int = 0
var current_mana: int = 0
var current_action: int = 0
var shield: int = 0          ## 护盾，先扣盾后扣血，回合结束清空
var is_downed: bool = false  ## 濒死：无法使用任何卡牌


# ---------------------------------------------------------------------------
# 数值查询
# ---------------------------------------------------------------------------

## 派生数值（含装备加成），每次查询实时计算，不做缓存以免加装备后忘记刷新
func get_stats() -> Dictionary:
	var base := PowerCalculator.derive_stats(
		constitution, strength, intelligence, vitality
	)
	# 叠加装备加成
	for item in equipment.values():
		var it := item as ItemData
		if it == null:
			continue
		for key in it.stats_bonus.keys():
			var k := str(key)
			if base.has(k):
				base[k] += int(it.stats_bonus[key])
			else:
				base[k] = int(it.stats_bonus[key])
	# 幸运单独处理（不参与派生公式，直接相加）
	base["luck"] = get_luck()
	return base


func get_max_hp() -> int:
	return int(get_stats()["hp"])


func get_max_mana() -> int:
	return int(get_stats()["mana"])


func get_max_action() -> int:
	return int(get_stats()["action"])


func get_luck() -> int:
	var total := base_luck
	for item in equipment.values():
		var it := item as ItemData
		if it != null and it.stats_bonus.has("luck"):
			total += int(it.stats_bonus["luck"])
	return total


## 战力。用与怪物完全相同的公式。
func get_power() -> float:
	return PowerCalculator.calc_power(get_stats())


# ---------------------------------------------------------------------------
# 成长
# ---------------------------------------------------------------------------

## 获得经验，返回是否升级
func gain_exp(amount: int) -> bool:
	exp += amount
	var leveled := false
	while exp >= PowerCalculator.exp_to_next_level(level):
		exp -= PowerCalculator.exp_to_next_level(level)
		level += 1
		unspent_points += 1  # 每级 +1 属性点
		leveled = true
	return leveled


## 分配属性点。stat_key 取 "constitution" / "strength" / "intelligence" / "vitality"
func spend_point(stat_key: String) -> bool:
	if unspent_points <= 0:
		return false
	match stat_key:
		"constitution": constitution += 1
		"strength": strength += 1
		"intelligence": intelligence += 1
		"vitality": vitality += 1
		_: return false
	unspent_points -= 1
	return true


## 消耗战利品直接提升等级
func add_level_from_trophy(count: int = 1) -> void:
	level += count
	unspent_points += count


# ---------------------------------------------------------------------------
# 装备
# ---------------------------------------------------------------------------

## 穿装备，返回被替换下来的旧装备（同槽位互斥）
## 9-22 修改意见 5：武器只有一个槽位，单手 / 双手 / 远程不再分别占位
func equip(item: ItemData) -> ItemData:
	if item == null or not item.is_equipment():
		return null
	if item.slot == ItemData.Slot.NONE:
		return null
	var old: ItemData = equipment.get(item.slot)
	equipment[item.slot] = item
	return old


## 脱下指定槽位，返回被脱下的装备
func unequip(slot: ItemData.Slot) -> ItemData:
	var old: ItemData = equipment.get(slot)
	equipment.erase(slot)
	return old


# ---------------------------------------------------------------------------
# 战斗状态
# ---------------------------------------------------------------------------

## 进入战斗时重置局内状态
func reset_for_battle() -> void:
	current_hp = get_max_hp()
	current_mana = get_max_mana()
	current_action = get_max_action()
	shield = 0
	is_downed = false


## 回合开始（9-22 修改意见 7，用户澄清）：
##   行动点：每回合只回复 1 点（回满即停，不再回满、不累积）
##   法力值：每回合回复 5 点（满则不再回）
##   护盾：清空
func on_turn_start() -> void:
	if is_downed:
		return
	if current_action < get_max_action():
		current_action = mini(current_action + ACTION_REGEN_PER_TURN, get_max_action())
	shield = 0
	if current_mana < get_max_mana():
		current_mana = mini(current_mana + MANA_REGEN_PER_TURN, get_max_mana())


## 受到伤害：先扣盾，再扣血。血量归零进入濒死。
func take_damage(amount: int) -> void:
	if is_downed:
		return
	var remain := amount
	if shield > 0:
		var absorbed := mini(shield, remain)
		shield -= absorbed
		remain -= absorbed
	if remain > 0:
		current_hp -= remain
		if current_hp <= 0:
			current_hp = 0
			is_downed = true


## 治疗（不能治疗濒死者，需用复活术）
func heal(amount: int) -> void:
	if is_downed or amount <= 0:
		return
	current_hp = mini(current_hp + amount, get_max_hp())


## 被复活术救回：血量变为 1
func revive() -> void:
	if not is_downed:
		return
	is_downed = false
	current_hp = 1


## 能否支付一张卡的费用
func can_afford(card: CardData) -> bool:
	if is_downed:
		return false
	return current_action >= card.action_cost and current_mana >= card.mana_cost


## 支付卡牌费用
func pay_for(card: CardData) -> void:
	current_action -= card.action_cost
	current_mana -= card.mana_cost


func is_alive() -> bool:
	return not is_downed
