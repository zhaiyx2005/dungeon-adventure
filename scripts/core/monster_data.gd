## 怪物数据结构
##
## 对应数据文件：res://data/monsters/*.tres
##
## 注意：power（战力）字段不由数据文件提供，而是由 PowerCalculator
## 用与人物完全相同的公式实时计算。这样"战力"才能在人物与怪物
## 之间直接比较，作为全局平衡的统一标尺。
class_name MonsterData
extends Resource


## 怪物档次
enum MonsterTier {
	NORMAL,  ## 普通
	ELITE,   ## 精英
	BOSS,    ## Boss
}

## AI 行为模式
enum AiPattern {
	AGGRESSIVE,  ## 优先攻击血量最低的敌人
	RANDOM,      ## 随机选择目标
	DEFENSIVE,   ## 优先使用防御或减益
}


@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var hp: int = 0
@export var phys_atk: int = 0
@export var mag_atk: int = 0
@export var phys_res: int = 0
@export var mag_res: int = 0
@export var technique: int = 0

@export var monster_tier: MonsterTier = MonsterTier.NORMAL

## 所属层级（1 起）
@export var dungeon_level: int = 1

@export var ai_pattern: AiPattern = AiPattern.AGGRESSIVE

## 掉落表 ID（对应 res://data/drops/*.tres）
@export var drop_table: String = ""

@export var art_placeholder: String = "#97C459"


## 计算战力。公式与人物战力完全一致（见 PowerCalculator）。
func get_power() -> float:
	return hp * 0.5 \
		+ (phys_atk + mag_atk) * 1.5 \
		+ (phys_res + mag_res) * 1.0 \
		+ technique * 2.0


func get_tier_name_cn() -> String:
	match monster_tier:
		MonsterTier.NORMAL: return "普通"
		MonsterTier.ELITE: return "精英"
		MonsterTier.BOSS: return "首领"
	return "未知"


func is_boss() -> bool:
	return monster_tier == MonsterTier.BOSS
