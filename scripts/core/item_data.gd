## 物品卡牌数据结构
##
## 对应数据文件：res://data/items/*.tres
##
## 物品分为五类：装备 / 道具 / 收集品 / 战利品 / 杂物。
## 装备的数值加成写在 stats_bonus 里，key 使用派生数值名，
## 直接与人物数值相加，不参与属性换算公式。
class_name ItemData
extends Resource


## 物品大类
enum ItemClass {
	EQUIPMENT,    ## 装备：可穿戴，提供数值加成
	CONSUMABLE,   ## 道具：消耗品，可在战斗中从背包使用
	COLLECTIBLE,  ## 收集品：卖高价 / 兑换特殊人物
	TROPHY,       ## 战利品：可消耗以提升人物等级
	JUNK,         ## 杂物：只能卖小钱
}

## 装备槽位
## 9-22 修改意见 5：单手 / 双手 / 远程武器统一为「武器」，装备槽位只保留一个
enum Slot {
	HEAD,            ## 头部
	NECK,            ## 颈部
	BODY,            ## 身体
	HAND,            ## 手部
	LEG,             ## 腿部
	FOOT,            ## 脚部
	WEAPON,          ## 武器（单手 / 双手 / 远程统一）
	NONE,            ## 非装备
}


@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var item_class: ItemClass = ItemClass.JUNK
@export var slot: Slot = Slot.NONE

## 数值加成。key 使用派生数值名：
## hp / mana / action / phys_atk / mag_atk / phys_res / mag_res / technique / luck
@export var stats_bonus: Dictionary = {}

## 珍贵值 0–100，决定显示颜色
@export var precious_value: int = 0

@export var sell_price: int = 0

## 能否在战斗中从背包使用（消耗品为 true）
@export var usable_in_battle: bool = false

@export var art_placeholder: String = "#D3D1C7"


## 由珍贵值推导显示颜色
## 白 0–10 / 绿 11–25 / 蓝 26–45 / 紫 46–70 / 金 71–90 / 红 91–100
func get_rarity_color() -> Color:
	if precious_value <= 10:
		return Color("#D3D1C7")   # 白
	elif precious_value <= 25:
		return Color("#97C459")   # 绿
	elif precious_value <= 45:
		return Color("#85B7EB")   # 蓝
	elif precious_value <= 70:
		return Color("#AFA9EC")   # 紫
	elif precious_value <= 90:
		return Color("#EF9F27")   # 金
	else:
		return Color("#E24B4A")   # 红


## 由珍贵值推导稀有度名
func get_rarity_name_cn() -> String:
	if precious_value <= 10:
		return "普通"
	elif precious_value <= 25:
		return "精良"
	elif precious_value <= 45:
		return "稀有"
	elif precious_value <= 70:
		return "史诗"
	elif precious_value <= 90:
		return "传说"
	else:
		return "神话"


func is_equipment() -> bool:
	return item_class == ItemClass.EQUIPMENT


func is_consumable() -> bool:
	return item_class == ItemClass.CONSUMABLE


func get_slot_name_cn() -> String:
	return ItemData.slot_name_cn(slot)


## 物品分类短标签（卡面首行用）
static func class_tag_cn(p_class: int) -> String:
	match p_class:
		ItemClass.EQUIPMENT: return "装"
		ItemClass.CONSUMABLE: return "药"
		ItemClass.COLLECTIBLE: return "集"
		ItemClass.TROPHY: return "奖"
		ItemClass.JUNK: return "杂"
	return "?"


## 数值加成的中文名。放数据类里，卡面 / 详情弹窗 / 文字预算探针三处共用一份。
const STAT_CN := {
	"hp": "血", "mana": "蓝", "phys_atk": "物攻", "mag_atk": "法攻",
	"phys_res": "物抗", "mag_res": "法抗", "technique": "技巧", "luck": "幸运",
	"action": "行动",
}


## 卡面首行：「稀有度 · 部位（装备）/ 分类（其它）」
## 人物版式不再渲染"类型字"，所以类型 / 部位只能并进描述首行。
func get_card_head_cn() -> String:
	var tag := get_slot_name_cn() if is_equipment() else ItemData.class_tag_cn(item_class)
	return "%s · %s" % [get_rarity_name_cn(), tag]


## 数值加成文案，如「物攻+32 技巧+12 血+20」。无加成返回空串。
##
## ⚠️ 分隔符只能用**单个半角空格**。用双空格（或全角空格 / 顿号）时，
## 三条加成的行宽会超过卡面描述框（89px @128 宽卡），被自动换行撑成 **2 行**，
## 加上首行 1 行 + 描述 1~2 行就变成 5 行 —— 而描述框只装得下 4 行，
## 最后一行会被静默吃掉。实测 6 件三加成的装备（碎界、龙鳞甲、命运之眼…）全中招。
## 改这个分隔符之前先跑 `_probe_descfit.gd`，目标是 0 处截断。
func get_bonus_text_cn() -> String:
	var parts: PackedStringArray = []
	for key in stats_bonus:
		parts.append("%s+%d" % [STAT_CN.get(key, str(key)), int(stats_bonus[key])])
	return " ".join(parts)


## 完整卡面描述：首行 → 加成 → 说明。
##
## 抽到数据类里是为了让 `scripts/_probe_descfit.gd`（卡面文字预算探针）能复用同一份拼装。
## 探针要是自己再拼一遍，改了一处忘另一处，"装不下被悄悄截断"就照样漏检 ——
## 卡面是固定尺寸的，多一行字肉眼根本看不出来。
## UI 侧统一走这个方法，不要再在任何地方手拼 item 的卡面文案。
func get_card_desc_cn() -> String:
	var lines := get_card_head_cn()
	var bonus := get_bonus_text_cn()
	if bonus != "":
		lines += "\n%s" % bonus
	if description != "":
		lines += "\n%s" % description
	return lines


## 槽位中文名（静态版：UI 里只有 Slot 枚举、没有 ItemData 实例时用）
static func slot_name_cn(p_slot: int) -> String:
	match p_slot:
		Slot.HEAD: return "头部"
		Slot.NECK: return "颈部"
		Slot.BODY: return "身体"
		Slot.HAND: return "手部"
		Slot.LEG: return "腿部"
		Slot.FOOT: return "脚部"
		Slot.WEAPON: return "武器"
		Slot.NONE: return "—"
	return "未知"


## 全部可穿戴槽位的展示顺序（9-22 修改意见 5：武器已合并为单一槽位）
static func equip_slot_order() -> Array:
	return [Slot.HEAD, Slot.NECK, Slot.BODY, Slot.HAND, Slot.LEG, Slot.FOOT, Slot.WEAPON]
