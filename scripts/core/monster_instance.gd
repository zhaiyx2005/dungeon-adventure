## 怪物战斗实例
##
## 由 MonsterData 生成，承载局内状态。
class_name MonsterInstance
extends RefCounted


var data: MonsterData

var current_hp: int = 0
var shield: int = 0
var is_dead: bool = false


func _init(monster_data: MonsterData) -> void:
	data = monster_data
	current_hp = monster_data.hp


func get_display_name() -> String:
	return data.display_name


func get_power() -> float:
	return data.get_power()


func take_damage(amount: int) -> void:
	if is_dead:
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
			is_dead = true


func heal(amount: int) -> void:
	if is_dead:
		return
	current_hp = mini(current_hp + amount, data.hp)


## 回合开始：护盾清空
func on_turn_start() -> void:
	shield = 0


func is_alive() -> bool:
	return not is_dead
