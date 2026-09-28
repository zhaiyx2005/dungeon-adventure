## 关卡（地牢层级）数据结构
##
## 对应数据文件：res://data/dungeons/*.tres
##
## 每层是一张 3 列 × 7 行的路线图，玩家从最下方进入，向层 Boss 推进。
class_name DungeonData
extends Resource


## 危险等级
enum DangerRating {
	D,  ## 最低
	C,
	B,
	A,
	S,  ## 最高
}


@export var id: String = ""
@export var display_name: String = ""

## 层级序号（1 起）
@export var level_index: int = 1

@export var danger_rating: DangerRating = DangerRating.D

## 推荐总战力区间。队伍总战力必须 ≥ recommend_power_min 才允许进入。
@export var recommend_power_min: int = 0
@export var recommend_power_max: int = 0

## 直接进入本层的金币费用
@export var entry_cost: int = 0

## 网格尺寸，固定 3 × 7
@export var grid_cols: int = 3
@export var grid_rows: int = 7

## 节点内容权重（战斗 / 宝箱 / 事件）
@export var node_weight_battle: int = 70
@export var node_weight_treasure: int = 10
@export var node_weight_event: int = 20

## 本层可出现怪物 ID 列表
@export var monster_pool: Array[String] = []

## 本层精英怪 ID 列表
@export var elite_pool: Array[String] = []

## 层 Boss 的怪物 ID
@export var boss_id: String = ""

@export var bg_placeholder: String = "#F1EFE8"


func get_danger_name() -> String:
	return ["D", "C", "B", "A", "S"][danger_rating]


## 节点总数
func get_node_count() -> int:
	return grid_cols * grid_rows


## 总权重，用于随机抽取节点内容
func get_total_weight() -> int:
	return node_weight_battle + node_weight_treasure + node_weight_event


## 按权重抽一个节点类型。返回 "battle" / "treasure" / "event"
func roll_node_type(rng: RandomNumberGenerator) -> String:
	var total := get_total_weight()
	if total <= 0:
		return "battle"
	var r := rng.randi_range(1, total)
	if r <= node_weight_battle:
		return "battle"
	elif r <= node_weight_battle + node_weight_treasure:
		return "treasure"
	else:
		return "event"


## 判定队伍能否进入本层
func can_enter(team_power: float) -> bool:
	return team_power >= float(recommend_power_min)
