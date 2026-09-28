## 回合控制器
##
## 只管"回合边界上该发生什么"，不管出牌与伤害结算。
##
## 回合定义（设计草案 §4.1）：
##   从「我方回合开始」到「下一个我方回合开始前」= 1 回合（含敌方行动）
##
## 回合边界动作：
##   我方回合开始 → 行动值回满（不累积）、蓝量 +5、护盾清空、抽 2 张牌
##   我方出牌阶段 → 玩家任意出牌，手动点「结束回合」
##   敌方回合     → 怪物依次行动
class_name TurnController
extends RefCounted


## 战斗阶段
enum Phase {
	PLAYER_TURN,   ## 我方出牌阶段
	ENEMY_TURN,    ## 敌方行动阶段
	FINISHED,      ## 战斗结束
}


var phase: Phase = Phase.PLAYER_TURN

## 已经过的完整回合数（从 1 开始）
var round_number: int = 0


## 在我方回合开始时刷新全部资源。
## 注意：护盾"持续到本回合结束"，所以它在【新的】我方回合开始时清空 ——
## 这意味着它完整覆盖了"我方出牌 → 敌方行动"这一段，正是设计要的效果。
func begin_player_turn(team: Array[Adventurer], monsters: Array[MonsterInstance], deck: DeckManager) -> void:
	phase = Phase.PLAYER_TURN
	round_number += 1

	for a in team:
		a.on_turn_start()

	for m in monsters:
		if m.is_alive():
			m.on_turn_start()

	# 第一个回合的手牌已在"进入节点"时抽好 8 张，这里不再补抽
	if round_number > 1:
		deck.on_turn_start()


func begin_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN


func finish() -> void:
	phase = Phase.FINISHED


func is_player_turn() -> bool:
	return phase == Phase.PLAYER_TURN


func is_finished() -> bool:
	return phase == Phase.FINISHED
