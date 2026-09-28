## 地牢地图生成器
##
## 生成一张 3 列 × 7 行的路线图，供玩家逐行向上（向 Boss）推进。
##
## 结构（自上而下 row 0 → 6）：
##   row 0    Boss 房（1 个节点，居中）
##   row 1–5  中间节点行（每行 3 列），类型按权重随机：战斗 / 宝箱 / 事件
##   row 6    入口（1 个节点，居中）
##
## 连线规则：每个节点连到「上一行」的相邻列节点，保证：
##   - 入口总能走到 Boss（连通性）
##   - 每行可走多条路线（可选择性）
##
## 纯逻辑，不依赖场景树，便于 headless 测试。
class_name MapGenerator
extends RefCounted


## 节点内容类型
enum NodeType {
	BATTLE,    ## 战斗（普通 / 精英）
	TREASURE,  ## 宝箱
	EVENT,     ## 事件
	BOSS,      ## 层 Boss 房
	START,     ## 入口
}

## 战斗节点里，精英出现的概率（当本层有精英池时）
const ELITE_CHANCE := 0.15

## 普通战斗的敌人数量范围
const MIN_NORMAL_ENEMIES := 1
const MAX_NORMAL_ENEMIES := 3


## 地图上的一个节点
class MapNode:
	var row: int = 0
	var col: int = 0
	var type: int = NodeType.BATTLE
	var monster_ids: Array[String] = []  ## 战斗节点预生成的敌人
	var next: Array[int] = []            ## 可前进到的上一行（row-1）节点的列索引
	var visited: bool = false            ## 玩家是否到过


## 生成一张地图。返回 Array[MapNode]（自上而下：row 0 在前）。
static func generate(dungeon: DungeonData, rng: RandomNumberGenerator) -> Array:
	var nodes: Array = []

	# ---- Boss 房（row 0）----
	var boss := MapNode.new()
	boss.row = 0
	boss.col = 1
	boss.type = NodeType.BOSS
	boss.monster_ids = [dungeon.boss_id]
	nodes.append(boss)

	# ---- 中间行 row 1..5，每行 3 列 ----
	for row in range(1, 6):
		for col in range(3):
			var n := MapNode.new()
			n.row = row
			n.col = col
			n.type = _roll_type(dungeon, rng)
			if n.type == NodeType.BATTLE:
				n.monster_ids = _roll_battle_encounter(dungeon, rng)
			nodes.append(n)

	# ---- 入口（row 6）----
	var start := MapNode.new()
	start.row = 6
	start.col = 1
	start.type = NodeType.START
	start.visited = true  # 玩家从这出发
	nodes.append(start)

	# ---- 连线（row 之间）----
	_connect(nodes)

	return nodes


## 按权重抽一个节点类型
static func _roll_type(dungeon: DungeonData, rng: RandomNumberGenerator) -> int:
	var t := dungeon.roll_node_type(rng)
	match t:
		"treasure": return NodeType.TREASURE
		"event": return NodeType.EVENT
		_: return NodeType.BATTLE


## 生成战斗节点敌人编成。返回怪物 id 列表。
## 普通：从 monster_pool 抽 1–3 只；精英：从 elite_pool 抽 1 只（池空则退回普通编成）。
static func _roll_battle_encounter(dungeon: DungeonData, rng: RandomNumberGenerator) -> Array[String]:
	var has_elite := not dungeon.elite_pool.is_empty()
	if has_elite and rng.randf() < ELITE_CHANCE:
		var elite := dungeon.elite_pool[rng.randi_range(0, dungeon.elite_pool.size() - 1)]
		return [elite]

	var count := rng.randi_range(MIN_NORMAL_ENEMIES, MAX_NORMAL_ENEMIES)
	var out: Array[String] = []
	for _i in range(count):
		if dungeon.monster_pool.is_empty():
			break
		out.append(dungeon.monster_pool[rng.randi_range(0, dungeon.monster_pool.size() - 1)])
	return out


## 连线。规则：
##   - 入口（row 6）连到 row 5 的 3 个节点（全部可达）
##   - 中间行节点连到上一行的相邻列节点（col±1 内，中间列可连 3 列）
##   - row 1 的所有节点连到 Boss（row 0）
static func _connect(nodes: Array) -> void:
	var by_pos := {}
	for n in nodes:
		by_pos[Vector2i(n.row, n.col)] = n

	# 入口 → row5 全列
	var start: MapNode = by_pos[Vector2i(6, 1)]
	start.next = [0, 1, 2]

	# row 5..2 的每个节点 → 上一行相邻列
	for row in range(2, 6):
		for col in range(3):
			var n: MapNode = by_pos[Vector2i(row, col)]
			n.next = _neighbor_cols(col)

	# row 1 的每个节点 → Boss
	for col in range(3):
		var n: MapNode = by_pos[Vector2i(1, col)]
		n.next = [1]


## 某列节点可前进到的上一行列索引（相邻列）
static func _neighbor_cols(col: int) -> Array[int]:
	match col:
		0: return [0, 1]
		1: return [0, 1, 2]
		_: return [1, 2]
	return [1]


# ---------------------------------------------------------------------------
# 便捷查询
# ---------------------------------------------------------------------------

## 取某行某列的节点，找不到返回 null
static func find(nodes: Array, row: int, col: int) -> MapNode:
	for n in nodes:
		if n.row == row and n.col == col:
			return n
	return null


## 取 Boss 节点
static func get_boss(nodes: Array) -> MapNode:
	for n in nodes:
		if n.type == NodeType.BOSS:
			return n
	return null


## 取入口节点
static func get_start(nodes: Array) -> MapNode:
	for n in nodes:
		if n.type == NodeType.START:
			return n
	return null


## 是否所有节点都能从入口走到 Boss（连通性自检）
## 从入口（row 6）向上 BFS，看能否到达 Boss（row 0）。
static func is_connected_map(nodes: Array) -> bool:
	var start := get_start(nodes)
	if start == null or get_boss(nodes) == null:
		return false

	var reachable := {Vector2i(start.row, start.col): true}
	for row in range(start.row, 0, -1):  # row 6..1 向上
		for col in range(3):
			if not reachable.has(Vector2i(row, col)):
				continue
			var n := find(nodes, row, col)
			if n == null:
				continue
			for target_col in n.next:
				reachable[Vector2i(row - 1, target_col)] = true
	return reachable.has(Vector2i(0, 1))


## 统计各类型节点数量，用于测试与展示
static func count_types(nodes: Array) -> Dictionary:
	var out := {NodeType.BATTLE: 0, NodeType.TREASURE: 0, NodeType.EVENT: 0, NodeType.BOSS: 0, NodeType.START: 0}
	for n in nodes:
		out[n.type] = int(out[n.type]) + 1
	return out
