## 战斗卡牌数据结构
##
## 定义战斗卡牌的全部字段与枚举。
## 对应数据文件：res://data/cards/*.tres
##
## 枚举值必须与 tools/generate_data.py 中的映射保持一致，
## 否则 .tres 文件加载后字段含义会错位。
class_name CardData
extends Resource


## 卡牌大类
enum CardClass {
	ATTACK,   ## 攻击卡：造成伤害
	DEFENSE,  ## 防御卡：提供护盾
	SPECIAL,  ## 特殊卡：治疗 / 增益 / 减益 / 功能
}

## 伤害类型
enum DamageType {
	PHYSICAL,  ## 物理：对应受击方的物抗
	MAGICAL,   ## 法术：对应受击方的法抗
	NONE,      ## 无伤害（防御卡、纯增益卡）
}

## 目标类型
enum TargetType {
	SINGLE_ALLY,   ## 单个友方
	SINGLE_ENEMY,  ## 单个敌方
	ALL_ENEMIES,   ## 全体敌方
	ALL_ALLIES,    ## 全体友方
	SELF,          ## 自身
	FIELD,         ## 全场（拖到战场直接生效）
}

## 稀有度
enum Rarity {
	COMMON,     ## 普通
	RARE,       ## 精良
	EPIC,       ## 史诗
	LEGENDARY,  ## 传说
}


@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var card_class: CardClass = CardClass.ATTACK
@export var damage_type: DamageType = DamageType.PHYSICAL

## 伤害倍率：最终伤害 = 施法者对应攻值 × multiplier − 目标对应抗性
## 仅攻击卡有效
@export var multiplier: float = 0.0

## 护盾倍率：护盾量 = 施法者对应抗性 × shield_multiplier
## 仅防御卡有效
@export var shield_multiplier: float = 0.0

## 治疗倍率：治疗量 = 施法者智力 × heal_multiplier
## 仅治疗类特殊卡有效
@export var heal_multiplier: float = 0.0

## 消耗的行动值
@export var action_cost: int = 0

## 消耗的蓝量（0 表示不消耗，非 0 时视为法术卡）
@export var mana_cost: int = 0

@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var rarity: Rarity = Rarity.COMMON

## 附加效果标签。
## 已实装：`REVIVE`（复活术）、`DRAW`（抽牌）、`BONUS_VS_SHIELD`（对带盾目标倍率 ×1.5）、
##         `COMBO`（共鸣体系卡：组件卡或联合卡本体，配合 combo_* 字段）
## 待 v2.0 状态系统接入：`BUFF_ACTION` / `DEBUFF_DEFENSE` / `HEAL_OVER_TIME`
@export var effect_tags: Array[String] = []

## 纯色占位框颜色（美术阶段替换为真实卡图）
@export var art_placeholder: String = "#B4B2A9"

# ---------------------------------------------------------------------------
# 共鸣（联合卡牌）——9-23 需求，9-24 按用户意见重构
#
# 一组共鸣 = 「若干张组件卡」+「一张联合卡本体」：
#   ・组件卡：打出后没有任何直接效果，只把本组的一个部件登记进共鸣槽。
#   ・联合卡本体：一张高强度卡；只有在本回合内本组部件全部就位时才打得出去，
#     打出后消耗掉这些部件（本回合该组不能再发动）。
#
# 部件可以由同一名角色连出，也可以由两名角色各出一张 —— 共鸣槽是全队共享的。
# 以「我方回合」为界，回合结束清空，所以不能跨回合攒。
#
# 约定：同组所有卡（组件 + 本体）都写相同的 combo_key / combo_name /
#      combo_complete，这样任何一张卡自己就知道"这一组要什么、门槛是什么"。
# ---------------------------------------------------------------------------

## 共鸣组标识（如 "fire_tornado"）；空 = 非共鸣卡
@export var combo_key: String = ""

## 共鸣组的显示名（如「风火龙卷」），用于日志与横幅
@export var combo_name: String = ""

## 本卡在组内的部件名（如 "wind" / "fire"）；联合卡本体为空
@export var combo_part: String = ""

## 本组需要的全部部件（组件卡 = 含自己；联合卡 = 全部前置条件）
@export var combo_complete: Array[String] = []

## 效果倍率。组件卡 = 0（无直接效果）；联合卡 = 打出的**全体**伤害倍率（法术，按施法者法攻算）
@export var combo_multiplier: float = 0.0

## 触发条件的文案，用于日志与卡面提示行
@export var combo_desc: String = ""

## 本卡是否为「联合卡本体」。
## true  = 需要 combo_complete 全部就位才可打出（前置条件型）。
## false = 组件卡（登记部件）/ 非共鸣卡。
@export var combo_payoff: bool = false


## 是否为法术卡（消耗蓝量即视为法术）
func is_spell() -> bool:
	return mana_cost > 0


## 是否为共鸣组件卡（打出只登记部件，无直接效果）
func is_combo_component() -> bool:
	return combo_key != "" and combo_part != "" and not combo_payoff


## 是否为联合卡本体（需要前置条件才能发动的高强度卡）
func is_combo_payoff() -> bool:
	return combo_key != "" and combo_payoff


## 是否属于共鸣体系（组件卡或联合卡本体）
func has_combo() -> bool:
	return combo_key != ""


## 卡面首行提示。
## ⚠️ 卡面下半框在城镇卡尺寸下只装得下约 3 行 8px 字，文案必须短
##    （预算见 docs/数值设计_v2.0.md §5.6.2，改动后跑 scripts/_probe_descfit.gd）。
func get_combo_hint_cn() -> String:
	if is_combo_component():
		return "解锁「%s」" % combo_name
	if is_combo_payoff():
		return "前置：%s" % combo_desc
	return ""


## 是否需要在战场上指定目标卡牌
func needs_target_card() -> bool:
	return target_type == TargetType.SINGLE_ALLY or target_type == TargetType.SINGLE_ENEMY


## 是否对全场生效（拖到战场即使用）
func is_field_card() -> bool:
	return not needs_target_card()


## 取本地化的分类名
func get_class_name_cn() -> String:
	match card_class:
		CardClass.ATTACK: return "攻击"
		CardClass.DEFENSE: return "防御"
		CardClass.SPECIAL: return "特殊"
	return "未知"


## 六分类显示名（9-22 修改意见 6）：
##   物理进攻 / 法术进攻 / 物理防御 / 法术防御 / 物理特殊 / 法术特殊
## 以 damage_type 判定物理 / 法术，以 card_class 判定进攻 / 防御 / 特殊。
func get_category_name_cn() -> String:
	var school := "物理" if damage_type != DamageType.MAGICAL else "法术"
	match card_class:
		CardClass.ATTACK: return school + "进攻"
		CardClass.DEFENSE: return school + "防御"
		CardClass.SPECIAL: return school + "特殊"
	return school + "卡"


## 是否法术卡（物理卡不耗蓝、法术卡耗蓝）
func is_magical() -> bool:
	return damage_type == DamageType.MAGICAL


## 取本地化的稀有度名
func get_rarity_name_cn() -> String:
	match rarity:
		Rarity.COMMON: return "普通"
		Rarity.RARE: return "精良"
		Rarity.EPIC: return "史诗"
		Rarity.LEGENDARY: return "传说"
	return "未知"


## 判断是否带有某个效果标签
func has_tag(tag: String) -> bool:
	return effect_tags.has(tag)
