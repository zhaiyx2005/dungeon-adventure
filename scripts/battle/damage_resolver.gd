## 伤害结算器
##
## 战斗的全部"一次效果如何落地"都在这里。它只做结算，不管流程（流程在 BattleManager）。
##
## 铁律：所有数值一律调用 PowerCalculator，此文件内不出现任何硬编码系数。
class_name DamageResolver
extends RefCounted


var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


## 一次攻击的完整结果，供 UI 显示飘字与日志
class HitResult:
	extends RefCounted
	var target_name: String = ""
	var damage: int = 0          ## 实际扣掉的血量
	var shield_absorbed: int = 0 ## 被护盾吃掉的量
	var is_crit: bool = false
	var killed: bool = false
	var downed: bool = false     ## 人物被打到濒死
	var raw_damage: int = 0      ## 未减去护盾的伤害（飘字用）

	func total_display() -> String:
		var s := "%s 受到 %d 伤害" % [target_name, raw_damage]
		if shield_absorbed > 0:
			s += "（护盾吸收 %d）" % shield_absorbed
		if is_crit:
			s += " [暴击]"
		if downed:
			s += " [濒死]"
		elif killed:
			s += " [击杀]"
		return s


## 攻击一个怪物。返回结算结果。
## mult_override ≥ 0 时用传入倍率结算（共鸣等"非卡牌本体倍率"的效果走这条），
## 否则用 card.multiplier。
func hit_monster(
	attacker: Adventurer, card: CardData, target: MonsterInstance,
	mult_override: float = -1.0
) -> HitResult:
	var res := HitResult.new()
	res.target_name = target.get_display_name()

	var atk := _attack_value_of_adventurer(attacker, card)
	var resistance := _resistance_of_monster(target, card)
	var mult := card.multiplier if mult_override < 0.0 else mult_override

	var is_crit := PowerCalculator.roll_crit(rng, int(attacker.get_stats()["technique"]), target.data.dungeon_level)
	res.is_crit = is_crit

	var dmg := PowerCalculator.calc_damage(atk, mult, resistance, is_crit)
	res.raw_damage = dmg

	var hp_before := target.current_hp
	var shield_before := target.shield
	target.take_damage(dmg)
	res.shield_absorbed = shield_before - target.shield
	res.damage = hp_before - target.current_hp
	res.killed = target.is_dead
	return res


## 攻击一个冒险者（怪物出手，或友方误伤类效果）
func hit_adventurer(monster: MonsterInstance, target: Adventurer) -> HitResult:
	var res := HitResult.new()
	res.target_name = target.display_name

	# 怪物没有卡牌，倍率固定 1.0；伤害类型按它的物攻/法攻哪边高决定
	var use_phys := monster.data.phys_atk >= monster.data.mag_atk
	var atk := monster.data.phys_atk if use_phys else monster.data.mag_atk
	var resistance := int(target.get_stats()["phys_res"] if use_phys else target.get_stats()["mag_res"])

	# 怪物暴击：目标等级就是冒险者等级
	var is_crit := PowerCalculator.roll_crit(rng, monster.data.technique, target.level)
	res.is_crit = is_crit

	var dmg := PowerCalculator.calc_damage(atk, 1.0, resistance, is_crit)
	res.raw_damage = dmg

	var hp_before := target.current_hp
	var shield_before := target.shield
	target.take_damage(dmg)
	res.shield_absorbed = shield_before - target.shield
	res.damage = hp_before - target.current_hp
	res.downed = target.is_downed
	return res


## 防御卡：给使用者加护盾
## 9-22 修改意见 6：区分物理 / 法术防御 —— 法术防御卡按法抗算护盾，物理防御卡按物抗算
func apply_shield(caster: Adventurer, card: CardData) -> int:
	var resistance := int(caster.get_stats()["mag_res"] if card.is_magical() else caster.get_stats()["phys_res"])
	var amount := PowerCalculator.calc_shield(resistance, card.shield_multiplier)
	caster.shield += amount
	return amount


## 给某个冒险者加护盾（用于全体防御卡）
func grant_shield(target: Adventurer, amount: int) -> void:
	target.shield += amount


## 治疗。返回实际治疗量（濒死者治疗无效，返回 0）
func apply_heal(caster: Adventurer, card: CardData, target: Adventurer) -> int:
	if target.is_downed:
		return 0
	var amount := PowerCalculator.calc_heal(caster.intelligence, card.heal_multiplier)
	var before := target.current_hp
	target.heal(amount)
	return target.current_hp - before


## 复活：把濒死者救回，血量 1
func apply_revive(target: Adventurer) -> bool:
	if not target.is_downed:
		return false
	target.revive()
	return true


# ---------------------------------------------------------------------------
# 内部取值
# ---------------------------------------------------------------------------

## 攻击方对应攻值：物理卡取物攻，法术卡取法攻
func _attack_value_of_adventurer(a: Adventurer, card: CardData) -> int:
	var stats := a.get_stats()
	if card.damage_type == CardData.DamageType.MAGICAL:
		return int(stats["mag_atk"])
	return int(stats["phys_atk"])


## 受击方对应抗性
func _resistance_of_monster(m: MonsterInstance, card: CardData) -> int:
	if card.damage_type == CardData.DamageType.MAGICAL:
		return m.data.mag_res
	return m.data.phys_res
