## 数值计算中心
##
## 所有公式的唯一实现处。设计文档改动时，只改这里。
##
## 对应文档：docs/地牢冒险记_数值设计_v1.0.md
##
## 铁律：
## 1. 派生数值一律向下取整（int）
## 2. 人物与怪物战力使用【完全相同】的系数，否则战力无法跨类型比较
## 3. 伤害有 1 点保底，防止完全破不了防
class_name PowerCalculator
extends RefCounted


# ---------------------------------------------------------------------------
# 一、属性 → 派生数值
# ---------------------------------------------------------------------------

## 由四基础属性算出八个派生数值。
## 参数为一级属性：体质 t / 力量 s / 智力 i / 精力 v
## 返回 Dictionary，key 为派生数值名。
static func derive_stats(t: int, s: int, i: int, v: int) -> Dictionary:
	return {
		"hp":        int(t * 6 + v * 2 + s * 1),
		"mana":      int(i * 4 + v * 2 + t * 1),
		"action":    int(v * 1 + t * 0.2),
		"phys_atk":  int(s * 2 + v * 0.5),
		"mag_atk":   int(i * 2 + v * 0.5),
		"phys_res":  int(t * 1 + s * 0.5),
		"mag_res":   int(t * 1 + i * 0.5),
		"technique": int((i * 1 + s * 1) * 0.5),
	}


## 派生数值中文名，用于 UI 显示
static func stat_name_cn(key: String) -> String:
	var names := {
		"hp": "血量",
		"mana": "蓝量",
		"action": "行动值",
		"phys_atk": "物攻",
		"mag_atk": "法攻",
		"phys_res": "物抗",
		"mag_res": "法抗",
		"technique": "技巧",
		"luck": "幸运",
	}
	return names.get(key, key)


# ---------------------------------------------------------------------------
# 二、战力
# ---------------------------------------------------------------------------

## 战力计算。**人物与怪物共用此公式**（除幸运外不计入）。
## stats 需包含 hp / phys_atk / mag_atk / phys_res / mag_res / technique
static func calc_power(stats: Dictionary) -> float:
	var hp: float = stats.get("hp", 0)
	var patk: float = stats.get("phys_atk", 0)
	var matk: float = stats.get("mag_atk", 0)
	var pres: float = stats.get("phys_res", 0)
	var mres: float = stats.get("mag_res", 0)
	var tech: float = stats.get("technique", 0)

	return hp * 0.5 \
		+ (patk + matk) * 1.5 \
		+ (pres + mres) * 1.0 \
		+ tech * 2.0


## 小队总战力。带队伍系数，鼓励组队而非单人堆超人。
static func team_power(member_powers: Array) -> int:
	var n := member_powers.size()
	if n == 0:
		return 0

	var raw := 0.0
	for p in member_powers:
		raw += float(p)

	var coefficient := 1.0
	match n:
		1: coefficient = 1.00
		2: coefficient = 1.05
		3: coefficient = 1.10
		_: coefficient = 1.15  # 4 人及以上

	return int(raw * coefficient)


## 队伍系数，UI 里可以展示给玩家看
static func team_coefficient(member_count: int) -> float:
	match member_count:
		0: return 0.0
		1: return 1.00
		2: return 1.05
		3: return 1.10
		_: return 1.15


# ---------------------------------------------------------------------------
# 三、伤害与暴击
# ---------------------------------------------------------------------------

## 暴击概率。分母含目标等级，所以打高等级敌人暴击率自然下降。
## 上限 75%，下限 0%。
static func calc_crit_chance(attacker_technique: int, defender_level: int) -> float:
	var denom := float(attacker_technique) + 50.0 + defender_level * 10.0
	if denom <= 0.0:
		return 0.0
	var chance := float(attacker_technique) / denom * 0.75
	return clampf(chance, 0.0, 0.75)


## 伤害计算。减法式，1 点保底。
## attacker_atk 为对应的物攻或法攻；defender_res 为对应的物抗或法抗。
## is_crit 为 true 时乘以 1.5。
static func calc_damage(
	attacker_atk: int,
	card_multiplier: float,
	defender_res: int,
	is_crit: bool = false
) -> int:
	var base := float(attacker_atk) * card_multiplier
	var dmg := base - float(defender_res)
	dmg = maxf(dmg, 1.0)
	if is_crit:
		dmg *= 1.5
	return int(dmg)


## 护盾量计算。防御卡为使用者提供护盾，先扣盾后扣血，持续到本回合结束。
static func calc_shield(defender_res: int, card_shield_multiplier: float) -> int:
	return int(float(defender_res) * card_shield_multiplier)


## 治疗量计算
static func calc_heal(caster_intelligence: int, card_heal_multiplier: float) -> int:
	return int(float(caster_intelligence) * card_heal_multiplier)


## 掷暴击判定
static func roll_crit(rng: RandomNumberGenerator, technique: int, defender_level: int) -> bool:
	return rng.randf() < calc_crit_chance(technique, defender_level)


# ---------------------------------------------------------------------------
# 四、成长
# ---------------------------------------------------------------------------

## 升到下一级所需经验
static func exp_to_next_level(current_level: int) -> int:
	var l := float(current_level - 1)
	return int(100.0 + l * 60.0 + l * l * 10.0)


## 累积到指定等级所需的总经验
static func total_exp_for_level(target_level: int) -> int:
	var total := 0
	for lv in range(1, target_level):
		total += exp_to_next_level(lv)
	return total


## 幸运对掉落的加成系数（1.0 表示无加成）
## 每点幸运 +2%
static func luck_drop_bonus(team_luck: int) -> float:
	return 1.0 + float(team_luck) * 0.02


## 层级进入费用：100 × (N−1)²
static func entry_cost_for_level(level_index: int) -> int:
	var n := maxi(level_index - 1, 0)
	return 100 * n * n
