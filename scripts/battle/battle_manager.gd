## 战斗管理器
##
## 一场战斗的全部状态与流程都在这里。UI 只读它的状态、调它的方法，不自己算数值。
##
## 流程：
##   setup() → start() → [玩家出牌 … 结束回合 → 敌人行动] × N → 分出胜负
##
## 关键规则（来自设计草案 §4 / HANDOFF.md）：
##   - 小队共享回合，回合内任意出牌，手动结束回合
##   - 行动值每人各自持有，每回合回满；蓝量每回合 +5，上限为派生蓝量
##   - 护盾先扣后血，持续到本回合结束（能挡敌人攻击）
##   - 濒死者不能出牌，但仍在场，需复活术救回
##   - 全队濒死 → 战斗失败
##   - 怪物每回合最多 3 只攻击同一个人物
class_name BattleManager
extends RefCounted


## 战斗结果
enum Result {
	ONGOING,
	VICTORY,      ## 敌人全灭
	DEFEAT,       ## 全队濒死
}

## 每回合最多几只怪物能打同一个人物（设计草案硬性规则）
const MAX_ATTACKERS_PER_TARGET := 3

## 「对带盾目标」的倍率系数（tag: BONUS_VS_SHIELD）——9-23 补充的廉价法术用
const BONUS_VS_SHIELD_MULT := 1.5


signal state_changed()
signal log_added(text: String)
signal battle_finished(result: Result)

## 战斗表现层事件（9-23 需求：飘字 / 抖动 / 打击特效）。
## 只描述"发生了什么"，怎么演由战斗场景决定。payload 字段：
##   kind   : "attack_start" | "damage" | "heal" | "shield" | "combo"
##   unit   : MonsterInstance | Adventurer  —— 受击 / 受益者（attack_start 时为 null）
##   source : Adventurer | MonsterInstance  —— 出手者（可为 null）
##   amount : int   实际数字
##   crit   : bool  是否暴击
##   killed : bool  是否因此被击杀（怪物）
##   downed : bool  是否因此进入濒死（人物）
##   text   : String  combo 用的事件名
signal combat_feedback(payload: Dictionary)


var team: Array[Adventurer] = []
var monsters: Array[MonsterInstance] = []

var deck: DeckManager
var turn := TurnController.new()
var resolver: DamageResolver

## 当前选中的释放者（UI 里点人物卡牌选中）
var selected_adventurer: Adventurer = null

var result: Result = Result.ONGOING

## 本轮战斗的简要记录，供结算界面使用
var kills: int = 0
var damage_dealt: int = 0
var damage_taken: int = 0
var reward_exp: int = 0
var reward_gold: int = 0

var rng := RandomNumberGenerator.new()

## 是否输出战斗日志（模拟对战时可关闭避免刷屏）
var log_enabled: bool = true

## 共鸣槽（9-23 需求，9-24 重构）：本回合各共鸣组已登记的部件
##   { combo_key: Array[String] 已就位的部件名 }
## 槽是全队共享的 —— 部件可以由同一名角色连出，也可以两名角色各出一张。
## 以「我方回合」为界，回合结束清空 —— 所以部件必须同一回合内凑齐。
var combo_cast: Dictionary = {}

## 本回合已经发动过的共鸣组：{ combo_key: true }
## 联合卡打出后该组本回合作废（不能靠再攒一轮重复发动）。
var combo_fired: Dictionary = {}


# ---------------------------------------------------------------------------
# 建立战斗
# ---------------------------------------------------------------------------

## 用一支队伍 vs 一组怪物建立战斗
func setup(
	p_team: Array[Adventurer],
	monster_datas: Array[MonsterData],
	p_deck: Array[CardData]
) -> void:
	rng.randomize()
	resolver = DamageResolver.new(rng)

	team = p_team
	monsters.clear()
	for md in monster_datas:
		monsters.append(MonsterInstance.new(md))

	deck = DeckManager.new(p_deck)

	result = Result.ONGOING
	kills = 0
	damage_dealt = 0
	damage_taken = 0
	turn.round_number = 0

	# 进战斗：全队局内状态重置
	for a in team:
		a.reset_for_battle()

	# 计算本次战斗的经验/金币奖励（按怪物战力折算）
	_calc_rewards()

	_log("—— 战斗开始 ——")


## 按怪物战力折算奖励。普通怪按战力给，Boss 加倍。
func _calc_rewards() -> void:
	var total := 0.0
	for m in monsters:
		total += m.get_power()
	reward_exp = int(total * 0.15)
	reward_gold = int(total * 0.10)


# ---------------------------------------------------------------------------
# 流程推进
# ---------------------------------------------------------------------------

## 开始战斗：进入节点先抽 8 张，然后进入第一个我方回合
func start() -> void:
	deck.on_enter_battle()
	_log("进入战斗节点，抽 %d 张牌" % DeckManager.FIRST_DRAW)
	_clear_combo_state()
	turn.begin_player_turn(team, monsters, deck)
	_auto_select_first()
	_emit_state()


## 玩家点「结束回合」：进入敌方回合，敌人依次行动，然后回到我方回合
func end_player_turn() -> void:
	if turn.is_finished():
		return

	turn.begin_enemy_turn()
	_emit_state()

	_enemy_act()

	if result != Result.ONGOING:
		return

	# 共鸣必须在同一回合内凑齐：新回合开始即清空
	_clear_combo_state()
	turn.begin_player_turn(team, monsters, deck)
	_auto_select_first()
	_emit_state()


## 敌方回合：每只活着的怪物依次出手
func _enemy_act() -> void:
	# 每个回合内，记录每名人物已被多少只怪物攻击
	var attackers_per_target := {}

	for m in monsters:
		if not m.is_alive():
			continue
		if _all_team_downed():
			break

		var target := _pick_monster_target(m, attackers_per_target)
		if target == null:
			continue

		attackers_per_target[target.id] = int(attackers_per_target.get(target.id, 0)) + 1

		_emit_feedback({
			"kind": "attack_start", "source": m, "unit": null,
			"damage_type": "PHYSICAL",
		})
		var hit := resolver.hit_adventurer(m, target)
		damage_taken += hit.damage
		_emit_feedback({
			"kind": "damage", "unit": target, "source": m,
			"amount": hit.raw_damage, "crit": hit.is_crit,
			"killed": false, "downed": hit.downed,
			"damage_type": "PHYSICAL",
		})
		_log(hit.total_display())

	_check_battle_end()


## 选怪物攻击目标。
## AGGRESSIVE：优先血量最低；RANDOM：随机；DEFENSIVE：也打，但优先血量最低（后续可扩展为防御行为）
## 硬性约束：同一个目标已被 ≥3 只怪物打过时，必须改打别人。
func _pick_monster_target(m: MonsterInstance, attackers_per_target: Dictionary) -> Adventurer:
	var candidates: Array[Adventurer] = []
	for a in team:
		if not a.is_alive():
			continue
		var used := int(attackers_per_target.get(a.id, 0))
		if used >= MAX_ATTACKERS_PER_TARGET:
			continue
		candidates.append(a)

	if candidates.is_empty():
		return null

	match m.data.ai_pattern:
		MonsterData.AiPattern.RANDOM:
			return candidates[rng.randi_range(0, candidates.size() - 1)]
		_:
			# AGGRESSIVE / DEFENSIVE：选当前血量最低的
			var best: Adventurer = candidates[0]
			for a in candidates:
				if a.current_hp < best.current_hp:
					best = a
			return best


# ---------------------------------------------------------------------------
# 出牌
# ---------------------------------------------------------------------------

## 检查某张牌当前能否打出（含施法者资源校验 + 目标存在性校验）
func can_play(caster: Adventurer, card: CardData) -> bool:
	if turn.is_finished() or not turn.is_player_turn():
		return false
	if caster == null or caster.is_downed:
		return false
	if not team.has(caster):
		return false
	if not caster.can_afford(card):
		return false

	# 需要敌方目标的牌必须有活着的敌人
	if card.card_class == CardData.CardClass.ATTACK:
		if not _has_living_monster():
			return false

	# 联合卡本体：必须本回合内已凑齐本组全部前置部件才打得出去。
	# 这是"高强度的代价"——没攒够前置时它只是一张打不出的废牌（UI 会把它压暗）。
	if card.is_combo_payoff() and not combo_ready(card):
		return false

	# 共鸣组件卡：场上没有敌人就无处发作，不该允许白打
	if card.is_combo_component() and not _has_living_monster():
		return false

	# 复活术必须有濒死者才可打（否则是废牌，不该消耗资源）
	if card.has_tag("REVIVE"):
		if not _has_downed_member():
			return false

	# 治疗卡必须有人真的能回血（满血 / 濒死都算无效目标），
	# 但要排除"全体治疗且有人未满血"的情况
	if card.heal_multiplier > 0.0 and not card.has_tag("REVIVE"):
		if not _has_healable_member():
			return false

	return true


## 打出卡牌。target 含义随卡牌类型变化：
##   单体敌人 → MonsterInstance；单体友方 → Adventurer；其余可传 null
## 返回是否成功打出。
##
## 结算顺序：先确认结算"真的产生了效果"，再扣资源与弃牌。
## 这样"需要指定单体目标的牌但没传目标"这类调用错误不会白白吃掉玩家的资源。
func play_card(caster: Adventurer, card: CardData, target: Variant = null) -> bool:
	if not can_play(caster, card):
		return false

	# 需要单一目标的牌：目标缺失或非法 → 直接拒绝，不消耗任何资源
	if card.needs_target_card():
		if target == null:
			return false
		if card.target_type == CardData.TargetType.SINGLE_ENEMY:
			var tm := target as MonsterInstance
			if tm == null or not tm.is_alive():
				return false
		else:
			var ta := target as Adventurer
			if ta == null:
				return false
			if card.has_tag("REVIVE") and not ta.is_downed:
				return false
			if card.heal_multiplier > 0.0 and not card.has_tag("REVIVE"):
				if ta.is_downed or ta.current_hp >= ta.get_max_hp():
					return false

	# 结算
	# 共鸣组件卡单独打出没有任何直接效果——只登记进共鸣槽
	if card.is_combo_component():
		_note_combo_part(caster, card)
	else:
		# 联合卡本体：先宣告（弹横幅），再走普通攻击结算 —— 倍率就写在卡本体上，
		# 所以伤害路径与其它全体攻击卡完全一致，不需要单独一套结算代码。
		if card.is_combo_payoff():
			_announce_combo(caster, card)
		match card.card_class:
			CardData.CardClass.ATTACK:
				_resolve_attack(caster, card, target)
			CardData.CardClass.DEFENSE:
				_resolve_defense(caster, card)
			CardData.CardClass.SPECIAL:
				_resolve_special(caster, card, target)
		if card.is_combo_payoff():
			_consume_combo(card)

	caster.pay_for(card)
	deck.play_card(card)

	_check_battle_end()
	_emit_state()
	return true


func _resolve_attack(caster: Adventurer, card: CardData, target: Variant) -> void:
	var targets := _resolve_enemy_targets(card, target)
	if targets.is_empty():
		return
	_emit_feedback({
		"kind": "attack_start", "source": caster, "unit": null,
		"damage_type": dtype_name(card),
	})
	var total := 0
	for m in targets:
		# 「对带盾目标额外提升」（9-23 补充的廉价法术：静电束）：
		# 命中前按目标当前护盾决定倍率。tag 由数据表声明，v2.0 状态系统接入后仍走同一入口。
		var mult := -1.0
		if card.has_tag("BONUS_VS_SHIELD") and (m as Variant).shield > 0:
			mult = card.multiplier * BONUS_VS_SHIELD_MULT
		var hit := resolver.hit_monster(caster, card, m, mult)
		total += hit.damage
		if hit.killed:
			kills += 1
			_notify_quest_kill(m)
		_emit_feedback({
			"kind": "damage", "unit": m, "source": caster,
			"amount": hit.raw_damage, "crit": hit.is_crit,
			"killed": hit.killed, "downed": false,
			"damage_type": dtype_name(card),
		})
		_log("%s 用「%s」→ %s" % [caster.display_name, card.display_name, hit.total_display()])
	damage_dealt += total


## 表现层用的伤害类型名（字符串）。
##
## 用字符串而不是 CardData.DamageType 枚举：表现层（含音效选型）只需要区分
## "物理还是法术"，把枚举绑进 payload 会让场景与数据类耦合，也让 payload 难读。
func dtype_name(card: CardData) -> String:
	if card == null:
		return "PHYSICAL"
	return "MAGICAL" if card.damage_type == CardData.DamageType.MAGICAL else "PHYSICAL"


# ---------------------------------------------------------------------------
# 共鸣（联合卡牌）——9-23 需求，9-24 按用户意见重构为「前置条件 → 联合卡本体」
#
# 规则：
#   ・组件卡打出后没有任何直接效果，只把本组的一个部件登记进共鸣槽
#   ・联合卡本体是一张高强度卡；只有本回合内本组部件全部就位时才打得出去
#   ・打出联合卡后消耗掉这些部件，本回合该组不能再发动
#   ・部件可以由同一名角色连出，也可以两名角色各出一张（槽是全队共享的）
#   ・以「我方回合」为界，回合结束清空 —— 不能跨回合攒
# ---------------------------------------------------------------------------

## 清空共鸣状态（战斗开始 / 新回合开始调用）
func _clear_combo_state() -> void:
	combo_cast.clear()
	combo_fired.clear()


## 某张联合卡的前置条件是否已满足（本回合未发动过 + 部件齐备）
func combo_ready(card: CardData) -> bool:
	if card == null or not card.is_combo_payoff():
		return false
	if combo_fired.has(card.combo_key):
		return false
	var parts: Array = combo_cast.get(card.combo_key, [])
	for p in card.combo_complete:
		if not parts.has(String(p)):
			return false
	return true


## 某组已就位的部件（UI 提示用）
func combo_parts_of(key: String) -> Array:
	return combo_cast.get(key, [])


## 某组是否本回合已发动过
func combo_fired_of(key: String) -> bool:
	return combo_fired.has(key)


## 某组还差哪些部件（UI 提示用，空数组 = 已齐备）
func combo_missing_parts(card: CardData) -> Array:
	var out: Array = []
	if card == null or not card.is_combo_payoff():
		return out
	var parts: Array = combo_cast.get(card.combo_key, [])
	for p in card.combo_complete:
		if not parts.has(String(p)):
			out.append(String(p))
	return out


## 登记一个共鸣部件。返回登记后本组是否已齐备。
func _note_combo_part(caster: Adventurer, card: CardData) -> bool:
	var key := card.combo_key
	var parts: Array = combo_cast.get(key, [])
	if not parts.has(card.combo_part):
		parts.append(card.combo_part)
	combo_cast[key] = parts

	var need: Array = card.combo_complete
	var miss: Array = []
	for p in need:
		if not parts.has(String(p)):
			miss.append(String(p))

	if not miss.is_empty():
		_log("%s 打出「%s」→ 组件就位（%s %d/%d）；还差：%s（本回合内凑齐即可打出「%s」）" % [
			caster.display_name, card.display_name,
			card.combo_name, need.size() - miss.size(), need.size(),
			"、".join(miss), card.combo_name,
		])
		return false

	_log("★ 已凑齐「%s」的全部组件 —— 本回合可以打出联合卡了！" % card.combo_name)
	return true


## 联合卡发动：弹横幅 + 表现层事件（伤害由 _resolve_attack 按卡本体倍率结算）
func _announce_combo(caster: Adventurer, card: CardData) -> void:
	var parts: Array = combo_cast.get(card.combo_key, [])
	_log("★ %s 发动联合卡「%s」（%d 件组件齐备）！%s" % [
		caster.display_name, card.combo_name, parts.size(), card.description,
	])
	_emit_feedback({
		"kind": "combo", "unit": null, "source": caster,
		"text": card.combo_name,
		"detail": "联合卡 · %d 件组件齐备" % parts.size(),
	})


## 联合卡结算完毕：消耗本组部件 + 标记本回合已发动
func _consume_combo(card: CardData) -> void:
	combo_cast.erase(card.combo_key)
	combo_fired[card.combo_key] = true


## 发一条表现层事件
func _emit_feedback(payload: Dictionary) -> void:
	combat_feedback.emit(payload)


## 击杀怪物时通知任务系统（若存在）
func _notify_quest_kill(m: MonsterInstance) -> void:
	var gd := _get_game_data()
	if gd == null or gd.quests == null:
		return
	gd.quests.on_kill(m.data.id)


func _get_game_data() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/GameData")


func _resolve_defense(caster: Adventurer, card: CardData) -> void:
	# 全体友方防御卡：给每人各自算一份护盾
	# 9-22 修改意见 6：法术防御按法抗、物理防御按物抗
	var res_key := "mag_res" if card.is_magical() else "phys_res"
	if card.target_type == CardData.TargetType.ALL_ALLIES:
		var total := 0
		for a in team:
			var res := int(a.get_stats()[res_key])
			var amount := PowerCalculator.calc_shield(res, card.shield_multiplier)
			resolver.grant_shield(a, amount)
			total += amount
			_emit_feedback({
				"kind": "shield", "unit": a, "source": caster,
				"amount": amount, "crit": false, "killed": false, "downed": false,
			})
		_log("%s 用「%s」→ 全队共获得 %d 护盾" % [caster.display_name, card.display_name, total])
	else:
		var amount := resolver.apply_shield(caster, card)
		_emit_feedback({
			"kind": "shield", "unit": caster, "source": caster,
			"amount": amount, "crit": false, "killed": false, "downed": false,
		})
		_log("%s 用「%s」→ 获得 %d 护盾" % [caster.display_name, card.display_name, amount])


func _resolve_special(caster: Adventurer, card: CardData, target: Variant) -> void:
	# 复活术
	if card.has_tag("REVIVE"):
		var t := target as Adventurer
		if t != null and resolver.apply_revive(t):
			_emit_feedback({
				"kind": "heal", "unit": t, "source": caster,
				"amount": 1, "crit": false, "killed": false, "downed": false,
			})
			_log("%s 用「%s」→ %s 被救回，血量 1" % [caster.display_name, card.display_name, t.display_name])
		return

	# 治疗（heal_multiplier > 0）
	if card.heal_multiplier > 0.0:
		var healed_total := 0
		var names: PackedStringArray = []
		for a in _resolve_ally_targets(card, target):
			var amount := resolver.apply_heal(caster, card, a)
			if amount > 0:
				healed_total += amount
				names.append(a.display_name)
				_emit_feedback({
					"kind": "heal", "unit": a, "source": caster,
					"amount": amount, "crit": false, "killed": false, "downed": false,
				})
		if healed_total > 0:
			_log("%s 用「%s」→ %s 共回复 %d 血量" % [
				caster.display_name, card.display_name, "、".join(names), healed_total
			])
		else:
			_log("%s 用「%s」→ 无有效目标（濒死者需用复活术）" % [caster.display_name, card.display_name])
		return

	# 抽牌类
	if card.has_tag("DRAW"):
		var n := deck.draw_cards(1)
		_log("%s 用「%s」→ 抽 %d 张牌" % [caster.display_name, card.display_name, n])
		return

	# 其余特殊卡首版先记为"生效"，具体 buff/debuff 数值系统后续接入
	_log("%s 用「%s」（效果待接入）" % [caster.display_name, card.display_name])


## 单体 / 全体敌人的目标解析
func _resolve_enemy_targets(card: CardData, target: Variant) -> Array[MonsterInstance]:
	var out: Array[MonsterInstance] = []
	if card.target_type == CardData.TargetType.ALL_ENEMIES:
		for m in monsters:
			if m.is_alive():
				out.append(m)
	else:
		var m := target as MonsterInstance
		if m != null and m.is_alive():
			out.append(m)
	return out


## 单体 / 全体友方的目标解析
func _resolve_ally_targets(card: CardData, target: Variant) -> Array[Adventurer]:
	var out: Array[Adventurer] = []
	if card.target_type == CardData.TargetType.SELF:
		if selected_adventurer != null:
			out.append(selected_adventurer)
	elif card.target_type == CardData.TargetType.ALL_ALLIES:
		for a in team:
			out.append(a)
	else:
		var a := target as Adventurer
		if a != null:
			out.append(a)
	return out


# ---------------------------------------------------------------------------
# 弃牌
# ---------------------------------------------------------------------------

## 手动弃掉一张手牌（右侧弃牌键）
func discard_card(card: CardData) -> bool:
	var ok := deck.discard_card(card)
	if ok:
		_log("弃掉「%s」" % card.display_name)
		_emit_state()
	return ok


# ---------------------------------------------------------------------------
# 背包道具（战斗内使用）
# ---------------------------------------------------------------------------

## 道具使用消耗的行动值（设计：道具与出牌抢行动值）
const ITEM_ACTION_COST := 1

## 检查道具当前能否由某成员使用
func can_use_item(user: Adventurer, item: ItemData) -> bool:
	if turn.is_finished() or not turn.is_player_turn():
		return false
	if user == null or user.is_downed:
		return false
	if item == null or not item.usable_in_battle:
		return false
	if user.current_action < ITEM_ACTION_COST:
		return false
	# 回血瓶：有人需要治疗（且不濒死）才可用；回蓝瓶：蓝未满
	match item.id:
		"health_potion", "greater_health_potion":
			return _has_healable_member()
		"mana_potion", "greater_mana_potion":
			return user.current_mana < user.get_max_mana()
		"bomb":
			return _has_living_monster()
		"smoke_bomb":
			return true
		"antidote", "luck_potion":
			return true
	return true


## 使用一个道具。target 可为 Adventurer（回血/回蓝目标）。
## 返回是否成功。
func use_item(user: Adventurer, item: ItemData, target: Adventurer = null) -> bool:
	var gd := _get_game_data()
	if gd == null:
		return false
	if not can_use_item(user, item):
		return false

	var consumed := false
	match item.id:
		"health_potion":
			var t := target if target != null else user
			if t != null and t.is_alive() and t.current_hp < t.get_max_hp():
				t.heal(20)
				_emit_feedback({
					"kind": "heal", "unit": t, "source": user, "amount": 20,
					"crit": false, "killed": false, "downed": false,
				})
				_log("%s 使用「%s」→ %s 回复 20 血量" % [user.display_name, item.display_name, t.display_name])
				consumed = true
		"greater_health_potion":
			var t2 := target if target != null else user
			if t2 != null and t2.is_alive() and t2.current_hp < t2.get_max_hp():
				t2.heal(50)
				_emit_feedback({
					"kind": "heal", "unit": t2, "source": user, "amount": 50,
					"crit": false, "killed": false, "downed": false,
				})
				_log("%s 使用「%s」→ %s 回复 50 血量" % [user.display_name, item.display_name, t2.display_name])
				consumed = true
		"mana_potion":
			if user.current_mana < user.get_max_mana():
				user.current_mana = mini(user.current_mana + 20, user.get_max_mana())
				_emit_feedback({
					"kind": "mana", "unit": user, "source": user, "amount": 20,
					"crit": false, "killed": false, "downed": false,
				})
				_log("%s 使用「%s」→ 回复 20 蓝量" % [user.display_name, item.display_name])
				consumed = true
		"greater_mana_potion":
			if user.current_mana < user.get_max_mana():
				user.current_mana = mini(user.current_mana + 50, user.get_max_mana())
				_emit_feedback({
					"kind": "mana", "unit": user, "source": user, "amount": 50,
					"crit": false, "killed": false, "downed": false,
				})
				_log("%s 使用「%s」→ 回复 50 蓝量" % [user.display_name, item.display_name])
				consumed = true
		"bomb":
			if _has_living_monster():
				var total := 0
				_emit_feedback({
					"kind": "attack_start", "source": user, "unit": null,
					"damage_type": "PHYSICAL",
				})
				for m in monsters:
					if m.is_alive():
						var dmg := maxi(15 - m.data.phys_res, 1)
						m.take_damage(dmg)
						total += dmg
						if m.is_dead:
							kills += 1
							_notify_quest_kill(m)
						_emit_feedback({
							"kind": "damage", "unit": m, "source": user,
							"amount": dmg, "crit": false,
							"killed": m.is_dead, "downed": false,
							"damage_type": "PHYSICAL",
						})
				damage_dealt += total
				_log("%s 使用「%s」→ 对全体敌人造成 %d 伤害" % [user.display_name, item.display_name, total])
				consumed = true
		"smoke_bomb":
			# 脱离战斗 = 直接胜利（首版简化：视为逃脱成功）
			_log("%s 使用「%s」→ 脱离战斗" % [user.display_name, item.display_name])
			consumed = true
			_finish(Result.VICTORY)
		"antidote", "luck_potion":
			_log("%s 使用「%s」（效果待接入）" % [user.display_name, item.display_name])
			consumed = true

	if consumed:
		user.current_action -= ITEM_ACTION_COST
		gd.inventory.erase(item)
		_emit_state()
	return consumed


# ---------------------------------------------------------------------------
# 状态查询
# ---------------------------------------------------------------------------

func living_monsters() -> Array[MonsterInstance]:
	var out: Array[MonsterInstance] = []
	for m in monsters:
		if m.is_alive():
			out.append(m)
	return out


func living_team() -> Array[Adventurer]:
	var out: Array[Adventurer] = []
	for a in team:
		if a.is_alive():
			out.append(a)
	return out


func _has_living_monster() -> bool:
	for m in monsters:
		if m.is_alive():
			return true
	return false


## 队里是否有人处于濒死（复活术的有效前提）
func _has_downed_member() -> bool:
	for a in team:
		if a.is_downed:
			return true
	return false


## 队里是否有人"能被治疗"：活着且未满血。
## 濒死者不算（治疗术对濒死无效），这是设计明确规定的。
func _has_healable_member() -> bool:
	for a in team:
		if a.is_alive() and a.current_hp < a.get_max_hp():
			return true
	return false


func _all_team_downed() -> bool:
	for a in team:
		if a.is_alive():
			return false
	return true


## 确保有一个「该由谁释放」的目标（9-22 修改意见 3）：
##   1. 已有选中且该成员仍存活 → 保持不变（跨回合延续上次指定的人）
##   2. 否则优先主角（id == "hero"）
##   3. 再否则取第一个存活成员
func _auto_select_first() -> void:
	if selected_adventurer != null and team.has(selected_adventurer) and selected_adventurer.is_alive():
		return
	selected_adventurer = null
	for a in team:
		if a.is_alive() and a.id == "hero":
			selected_adventurer = a
			return
	for a in team:
		if a.is_alive():
			selected_adventurer = a
			return


## 自动选择一个"该由谁释放"的角色：优先当前选中的，否则第一个能行动的
func select_adventurer(a: Adventurer) -> void:
	selected_adventurer = a
	_emit_state()


# ---------------------------------------------------------------------------
# 胜负判定
# ---------------------------------------------------------------------------

func _check_battle_end() -> void:
	if result != Result.ONGOING:
		return

	if not _has_living_monster():
		_finish(Result.VICTORY)
	elif _all_team_downed():
		_finish(Result.DEFEAT)


func _finish(r: Result) -> void:
	result = r
	turn.finish()
	if r == Result.VICTORY:
		_log("—— 战斗胜利 ——")
	else:
		_log("—— 全队濒死，任务失败 ——")
	battle_finished.emit(r)
	_emit_state()


## 给存活成员发经验，返回每人升级情况
func grant_rewards() -> Array[String]:
	var msgs: Array[String] = []
	if result != Result.VICTORY:
		return msgs
	for a in team:
		# 濒死者拿不到经验
		if a.is_downed:
			continue
		var leveled := a.gain_exp(reward_exp)
		if leveled:
			msgs.append("%s 升到 Lv.%d（+1 属性点）" % [a.display_name, a.level])
	return msgs


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _log(text: String) -> void:
	if log_enabled:
		print("[战斗] " + text)
	log_added.emit(text)


func _emit_state() -> void:
	state_changed.emit()
