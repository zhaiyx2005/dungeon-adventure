## 阶段 2 战斗核心逻辑测试
##
## 覆盖：抽牌规则、回合推进与资源恢复、伤害/暴击/护盾、濒死与复活、
##       怪物集火限制（每回合最多 3 只打同一人）、胜负判定、奖励。
extends SceneTree

var _fail := 0
var _pass := 0
var _db: GameDatabase
## 静电束伤害探针的累加器（lambda 按值捕获局部变量，只能用成员变量/数组做累加）
var _raw_damage_acc := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(90.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


# ---------------------------------------------------------------------------
# 构造帮手
# ---------------------------------------------------------------------------

func _make_adventurer(nm: String, t: int, s: int, i: int, v: int) -> Adventurer:
	var a := Adventurer.new()
	a.id = nm
	a.display_name = nm
	a.constitution = t
	a.strength = s
	a.intelligence = i
	a.vitality = v
	a.base_luck = 3
	return a


func _monsters_of(ids: Array) -> Array[MonsterData]:
	var out: Array[MonsterData] = []
	for id in ids:
		var m: MonsterData = _db.get_monster(id)
		if m != null:
			out.append(m)
	return out


func _deck_of(pairs: Array) -> Array[CardData]:
	var out: Array[CardData] = []
	for p in pairs:
		var c: CardData = _db.get_card(p[0])
		for _k in range(int(p[1])):
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# 测试
# ---------------------------------------------------------------------------

func _run() -> void:
	_watchdog()
	print("\n===== 阶段2 战斗核心逻辑测试 =====\n")

	_db = GameDatabase.new()
	_db.load_all()

	_test_deck_manager()
	_test_turn_and_resources()
	_test_damage_and_shield()
	_test_downed_and_revive()
	_test_battle_flow()
	_test_selection_and_shield()
	_test_focus_fire_limit()
	_test_attack_cards()
	_test_play_validity()
	_test_combo_and_feedback()
	_test_cheap_spells()
	_test_full_auto_battle()

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---- 1. DeckManager 抽牌规则 ----
func _test_deck_manager() -> void:
	print("-- 抽牌规则（DeckManager）--")

	# 20 张牌：进节点抽 8，之后每回合抽 2
	var deck := _deck_of([["strike", 20]])
	var dm := DeckManager.new(deck)
	dm.on_enter_battle()
	_ok(dm.hand.size() == 8, "进入节点抽 8 张（实际 %d）" % dm.hand.size())
	_ok(dm.draw_pile.size() == 12, "抽牌堆剩 12 张（实际 %d）" % dm.draw_pile.size())

	dm.on_turn_start()
	_ok(dm.hand.size() == 10, "回合开始再抽 2 张（实际 %d）" % dm.hand.size())

	# 手牌上限 12：抽到 12 后再抽不生效
	dm.on_turn_start()
	_ok(dm.hand.size() == 12 or dm.hand.size() == 12, "手牌到 12 张")
	var extra := dm.draw_cards(2)
	_ok(extra == 0, "手牌满 12 张后禁止抽牌（实抽 %d）" % extra)
	_ok(dm.is_hand_full(), "is_hand_full() 为真")

	# 牌库抽空 → 弃牌堆洗回
	var deck2 := _deck_of([["strike", 5]])
	var dm2 := DeckManager.new(deck2)
	dm2.on_enter_battle()   # 手牌 5，牌库 0
	_ok(dm2.hand.size() == 5, "5 张牌进节点全抽到手上")
	# 弃掉 3 张后牌库空 → 洗回
	dm2.discard_card(dm2.hand[0])
	dm2.discard_card(dm2.hand[0])
	dm2.discard_card(dm2.hand[0])
	var drew := dm2.draw_cards(3)
	_ok(drew == 3, "牌库空时弃牌堆洗回可继续抽（实抽 %d）" % drew)
	_ok(dm2.discard_pile.size() < 3, "洗回后弃牌堆被清空")

	# 卡组容量合法性
	_ok(DeckManager.is_valid_deck_size(20), "20 张是合法卡组")
	_ok(DeckManager.is_valid_deck_size(40), "40 张是合法卡组")
	_ok(not DeckManager.is_valid_deck_size(19), "19 张不合法")
	_ok(not DeckManager.is_valid_deck_size(41), "41 张不合法")


# ---- 2. 回合推进与资源恢复 ----
func _test_turn_and_resources() -> void:
	print("\n-- 回合推进与资源恢复 --")

	var a := _make_adventurer("测试者", 6, 7, 4, 6)   # 血量55 蓝量34 行动7
	_ok(a.current_hp == 0, "新建时未初始化局内血量")

	a.reset_for_battle()
	_ok(a.current_hp == a.get_max_hp(), "进战斗血量回满")
	_ok(a.current_mana == a.get_max_mana(), "进战斗蓝量回满")

	# 消耗后回合开始（9-22 修改意见 7，用户澄清后的正确版本）：
	#   行动点每回合只回 1 点（回满即停，不再回满）
	#   法力值每回合回 5 点
	var strike: CardData = _db.get_card("strike")
	# 意见7 配套：行动点变稀缺后卡牌消耗整体下调（普通攻击 2 → 1）
	_ok(strike != null and strike.action_cost == 1, "普通攻击在新经济下是 1 行动点")
	a.pay_for(strike)
	_ok(a.current_action == a.get_max_action() - strike.action_cost, "出牌按卡牌 action_cost 扣行动点")
	a.current_mana = 0
	var action_before_turn: int = a.current_action
	a.on_turn_start()
	_ok(a.current_action == action_before_turn + Adventurer.ACTION_REGEN_PER_TURN,
		"回合开始行动点只回 %d 点（%d → %d，意见7）" % [
			Adventurer.ACTION_REGEN_PER_TURN, action_before_turn, a.current_action])
	_ok(a.current_mana == Adventurer.MANA_REGEN_PER_TURN,
		"回合开始法力值回 %d 点（实际 %d，意见7）" % [Adventurer.MANA_REGEN_PER_TURN, a.current_mana])

	# 连续回合：行动点继续 +1、法力值继续 +5
	# （先把行动点压低，避免正好撞上行动上限导致 +1 被截断）
	a.current_action = maxi(1, a.get_max_action() - 3)
	var action_after_one: int = a.current_action
	var mana_after_one: int = a.current_mana
	a.on_turn_start()
	_ok(a.current_action == action_after_one + Adventurer.ACTION_REGEN_PER_TURN, "行动点连续回合继续 +1")
	_ok(a.current_mana == mana_after_one + Adventurer.MANA_REGEN_PER_TURN, "法力值连续回合继续 +5")

	# 回满后不再回复（行动点 / 法力值都一样）
	a.current_action = a.get_max_action()
	a.current_mana = a.get_max_mana()
	a.on_turn_start()
	_ok(a.current_action == a.get_max_action(), "行动点满时不再回复（意见7）")
	_ok(a.current_mana == a.get_max_mana(), "法力值满时不再回复（意见7）")

	# 行动点上限截断（从差 1 点开始回）
	a.current_action = a.get_max_action() - 1
	a.on_turn_start()
	_ok(a.current_action == a.get_max_action(), "行动点不超过上限")

	# 蓝量上限截断
	a.current_mana = a.get_max_mana()
	a.on_turn_start()
	_ok(a.current_mana == a.get_max_mana(), "蓝量不超过上限")

	# 护盾回合结束清空
	a.shield = 10
	a.on_turn_start()
	_ok(a.shield == 0, "回合开始护盾清空")


# ---- 3. 伤害与护盾 ----
func _test_damage_and_shield() -> void:
	print("\n-- 伤害与护盾结算 --")

	var a := _make_adventurer("攻击者", 6, 7, 4, 6)
	a.reset_for_battle()
	var strike: CardData = _db.get_card("strike")   # 1.0 倍物攻，物攻=17

	var boar_data: MonsterData = _db.get_monster("boar")  # 血量42 物抗6
	var boar := MonsterInstance.new(boar_data)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var res := DamageResolver.new(rng)

	# 17 * 1.0 - 6 = 11
	var before := boar.current_hp
	var hit := res.hit_monster(a, strike, boar)
	_ok(boar.current_hp == before - 11, "怪物掉 11 血（实际掉 %d）" % (before - boar.current_hp))
	_ok(hit.raw_damage == 11, "raw_damage = 11")

	# 护盾先扣盾后扣血
	boar.shield = 5
	var hp_before := boar.current_hp
	res.hit_monster(a, strike, boar)
	_ok(boar.shield == 0, "护盾被清空")
	_ok(boar.current_hp == hp_before - 6, "护盾吸收 5 后血量只掉 6（实际掉 %d）" % (hp_before - boar.current_hp))

	# 伤害保底 1：物抗远高于攻击
	var tough_data: MonsterData = _db.get_monster("stone_golem")
	if tough_data != null:
		var golem := MonsterInstance.new(tough_data)
		var weak := _make_adventurer("弱者", 1, 1, 1, 1)
		weak.reset_for_battle()
		res.hit_monster(weak, strike, golem)
		_ok(golem.current_hp < tough_data.hp, "打高抗性怪仍有伤害（保底 1）")

	# 防御卡给施法者加护盾：物抗 9 × 2.0 = 18
	var guard: CardData = _db.get_card("guard_phys")
	var shield := res.apply_shield(a, guard)
	_ok(shield == 18, "物抗 9 × 2.0 = 18 护盾（实际 %d）" % shield)
	_ok(a.shield == 18, "施法者获得 18 护盾")

	# 治疗：智力 × 倍率
	var heal: CardData = _db.get_card("heal")
	a.current_hp = 10
	var healed := res.apply_heal(a, heal, a)
	_ok(healed > 0, "治疗生效（实际回复 %d）" % healed)
	_ok(a.current_hp == 10 + healed, "血量正确增加")


# ---- 4. 濒死与复活 ----
func _test_downed_and_revive() -> void:
	print("\n-- 濒死与复活 --")

	var a := _make_adventurer("肉盾", 5, 5, 5, 5)
	a.reset_for_battle()
	var maxhp := a.get_max_hp()

	a.take_damage(maxhp + 100)
	_ok(a.current_hp == 0, "血量归零")
	_ok(a.is_downed, "进入濒死状态")
	_ok(not a.is_alive(), "濒死者不可行动")

	# 濒死者不能出牌
	var strike: CardData = _db.get_card("strike")
	_ok(not a.can_afford(strike), "濒死者无法支付出牌费用")

	# 治疗对濒死者无效
	var res := DamageResolver.new()
	var heal: CardData = _db.get_card("heal")
	var n := res.apply_heal(a, heal, a)
	_ok(n == 0, "治疗术无法治疗濒死者（回复 %d）" % n)
	_ok(a.is_downed, "治疗后仍是濒死")

	# 复活术救回，血量 1
	var ok := res.apply_revive(a)
	_ok(ok, "复活术生效")
	_ok(a.current_hp == 1, "救回后血量为 1（实际 %d）" % a.current_hp)
	_ok(not a.is_downed, "复活后脱离濒死")

	# 已活着的人不能被复活
	_ok(not res.apply_revive(a), "非濒死者复活无效")

	# 护盾能挡伤害
	a.shield = 100
	a.take_damage(50)
	_ok(a.current_hp == 1, "护盾完全吸收伤害，血量不变")
	_ok(a.shield == 50, "护盾剩余 50")


# ---- 5. 战斗流程与胜负 ----
func _test_battle_flow() -> void:
	print("\n-- 战斗流程与胜负判定 --")

	# 胜利：1 个强角色 vs 1 只弱怪
	var hero := _make_adventurer("英雄", 10, 12, 8, 10)
	var bm := BattleManager.new()
	bm.setup([hero], _monsters_of(["giant_rat"]), _deck_of([["strike", 20]]))
	bm.start()

	_ok(bm.turn.round_number == 1, "开局是第 1 回合")
	_ok(bm.turn.is_player_turn(), "开局是我方回合")
	_ok(bm.deck.hand.size() == 8, "开局手牌 8 张")
	_ok(bm.result == BattleManager.Result.ONGOING, "战斗进行中")
	_ok(bm.selected_adventurer == hero, "自动选中第一个可行动角色")

	# 打死怪物
	var strike: CardData = _db.get_card("strike")
	var guard_idx := 0
	while bm.living_monsters().size() > 0 and guard_idx < 40:
		guard_idx += 1
		if not hero.can_afford(strike):
			# 换个能打的牌或结束回合
			bm.end_player_turn()
			if bm.result != BattleManager.Result.ONGOING:
				break
			continue
		bm.play_card(hero, strike, bm.living_monsters()[0])

	_ok(bm.result == BattleManager.Result.VICTORY, "击败全部怪物 → 胜利")
	_ok(bm.turn.is_finished(), "结束后回合阶段为 FINISHED")
	_ok(bm.kills >= 1, "击杀计数 ≥ 1（实际 %d）" % bm.kills)
	_ok(bm.reward_exp > 0, "有经验奖励（%d）" % bm.reward_exp)
	_ok(bm.reward_gold > 0, "有金币奖励（%d）" % bm.reward_gold)

	# 奖励发放
	var lv_msgs := bm.grant_rewards()
	print("      升级信息：%s" % str(lv_msgs))

	# 失败：1 个弱角色 vs 1 只强 Boss，直接点结束回合硬扛
	var weak := _make_adventurer("弱者", 1, 1, 1, 1)
	var bm2 := BattleManager.new()
	bm2.setup([weak], _monsters_of(["boar_king"]), _deck_of([["strike", 20]]))
	bm2.start()
	var guard2 := 0
	while bm2.result == BattleManager.Result.ONGOING and guard2 < 30:
		guard2 += 1
		bm2.end_player_turn()
	_ok(bm2.result == BattleManager.Result.DEFEAT, "全队濒死 → 失败")

	# 失败时拿不到奖励
	var msgs2 := bm2.grant_rewards()
	_ok(msgs2.is_empty(), "失败时不发经验")


# ---- 5b. 释放者选中（意见3）与法抗护盾（意见6） ----
func _test_selection_and_shield() -> void:
	print("\n-- 意见3：默认选主角 + 跨回合保持 --")
	var a1 := _make_adventurer("同伴甲", 8, 8, 4, 8)
	var hero := _make_adventurer("农夫之子", 6, 7, 4, 6)
	hero.id = "hero"
	var a2 := _make_adventurer("同伴乙", 8, 6, 8, 8)
	var bm := BattleManager.new()
	# 主角放在队伍中间，验证「优先主角」而不是「队伍第一个」
	bm.setup([a1, hero, a2], _monsters_of(["giant_rat"]), _deck_of([["guard_phys", 20]]))
	bm.start()
	_ok(bm.selected_adventurer == hero, "开局默认指定主角（即使主角不在第 1 位，意见3）")

	bm.select_adventurer(a2)
	_ok(bm.selected_adventurer == a2, "可以手动改指定同伴乙")
	bm.end_player_turn()
	_ok(bm.selected_adventurer == a2, "结束回合后仍保持指定同伴乙（意见3）")

	# 被指定者濒死 → 自动改选主角
	a2.is_downed = true
	bm.end_player_turn()
	_ok(bm.selected_adventurer == hero, "原指定者濒死后回落到主角（意见3）")
	a2.is_downed = false

	print("\n-- 意见6：物理/法术防御护盾取不同抗性 --")
	# 法师型角色：法抗高、物抗低
	var mage := _make_adventurer("法师", 4, 4, 12, 8)
	mage.id = "hero"
	var bm2 := BattleManager.new()
	bm2.setup([mage], _monsters_of(["giant_rat"]), _deck_of([["guard_phys", 5], ["guard_mag", 5]]))
	bm2.start()
	var stats: Dictionary = mage.get_stats()
	var phys_res := int(stats["phys_res"])
	var mag_res := int(stats["mag_res"])
	var guard_phys: CardData = _db.get_card("guard_phys")
	var guard_mag: CardData = _db.get_card("guard_mag")
	_ok(guard_phys != null and not guard_phys.is_magical(), "普通物理防御是物理卡")
	_ok(guard_mag != null and guard_mag.is_magical(), "普通法术防御是法术卡")
	_ok(guard_mag != null and guard_mag.mana_cost > 0, "法术防御卡耗蓝（%d）" % (guard_mag.mana_cost if guard_mag != null else -1))

	mage.shield = 0
	bm2.play_card(mage, guard_phys, null)
	var expect_phys := PowerCalculator.calc_shield(phys_res, guard_phys.shield_multiplier)
	_ok(mage.shield == expect_phys, "物理防御按物抗算护盾（%d = %d×%.1f）" % [mage.shield, phys_res, guard_phys.shield_multiplier])

	mage.shield = 0
	mage.current_mana = mage.get_max_mana()
	bm2.play_card(mage, guard_mag, null)
	var expect_mag := PowerCalculator.calc_shield(mag_res, guard_mag.shield_multiplier)
	_ok(mage.shield == expect_mag, "法术防御按法抗算护盾（%d = %d×%.1f，意见6）" % [mage.shield, mag_res, guard_mag.shield_multiplier])
	_ok(phys_res != mag_res, "抽样角色法抗≠物抗（%d vs %d），断言有效" % [mag_res, phys_res])


# ---- 6. 怪物集火限制（核心规则） ----
func _test_focus_fire_limit() -> void:
	print("\n-- 怪物集火限制：每回合最多 3 只打同一人 --")

	# 4 只怪物 vs 1 个超级肉的英雄 → 第 4 只必须改打别人
	# 但只有 1 个人物，所以第 4 只应该无目标可用
	var tank := _make_adventurer("坦克", 30, 5, 5, 30)
	var bm := BattleManager.new()
	bm.setup([tank], _monsters_of(["boar", "boar", "boar", "boar"]), _deck_of([["strike", 20]]))
	bm.start()

	var hp_before := tank.current_hp
	bm.end_player_turn()
	var lost := hp_before - tank.current_hp

	var boar_atk := 12
	var boar_res := int(tank.get_stats()["phys_res"])
	var per_hit := maxi(boar_atk - boar_res, 1)

	# 最多 3 只能打到坦克；第 4 只无目标 → 全队只承受 ≤3 次伤害
	_ok(lost <= per_hit * 3, "4 只怪同回合只有 ≤3 次命中（实际掉 %d，单次约 %d）" % [lost, per_hit])
	_ok(lost > 0, "至少有怪物命中（掉 %d）" % lost)

	# 对照：拆成 1 只怪 vs 1 人，应命中 1 次
	var tank2 := _make_adventurer("坦克2", 30, 5, 5, 30)
	var bm2 := BattleManager.new()
	bm2.setup([tank2], _monsters_of(["boar"]), _deck_of([["strike", 20]]))
	bm2.start()
	var hp2 := tank2.current_hp
	bm2.end_player_turn()
	var lost2 := hp2 - tank2.current_hp
	_ok(lost2 == per_hit, "单只怪命中 1 次（掉 %d，预期 %d）" % [lost2, per_hit])

	# 两人编队 + 4 只怪：两只各被 2 次，总量仍是 4 次
	var t_a := _make_adventurer("甲", 30, 5, 5, 30)
	var t_b := _make_adventurer("乙", 30, 5, 5, 30)
	var bm3 := BattleManager.new()
	bm3.setup([t_a, t_b], _monsters_of(["boar", "boar", "boar", "boar"]), _deck_of([["strike", 20]]))
	bm3.start()
	var sum_before := t_a.current_hp + t_b.current_hp
	bm3.end_player_turn()
	var sum_lost := sum_before - (t_a.current_hp + t_b.current_hp)
	_ok(sum_lost == per_hit * 4, "两人编队时 4 只怪全部命中（共掉 %d，预期 %d）" % [sum_lost, per_hit * 4])


# ---- 7. 攻击卡解析 ----
func _test_attack_cards() -> void:
	print("\n-- 攻击卡：单体 / 法术 / 群体 --")

	var mage := _make_adventurer("法师", 4, 3, 9, 6)
	var bm := BattleManager.new()
	bm.setup([mage], _monsters_of(["boar", "cave_bat"]), _deck_of([["fireball", 10], ["strike", 10]]))
	bm.start()
	mage.current_mana = mage.get_max_mana()

	var fireball: CardData = _db.get_card("fireball")
	var strike: CardData = _db.get_card("strike")

	if fireball != null:
		print("      fireball: class=%d, dmg_type=%d, mult=%.2f, target=%d, mana=%d" % [
			fireball.card_class, fireball.damage_type, fireball.multiplier,
			fireball.target_type, fireball.mana_cost
		])

	# 法术卡用蓝
	if fireball != null and fireball.mana_cost > 0:
		var mana_before := mage.current_mana
		bm.play_card(mage, fireball, bm.living_monsters()[0])
		_ok(mage.current_mana == mana_before - fireball.mana_cost, "法术卡消耗蓝量")
		_ok(bm.damage_dealt > 0, "法术卡造成伤害（%d）" % bm.damage_dealt)

	# 物理卡打单体：只有目标掉血
	var bm2 := BattleManager.new()
	bm2.setup([mage], _monsters_of(["boar", "cave_bat"]), _deck_of([["strike", 10]]))
	bm2.start()
	var target_mon := bm2.living_monsters()[1]   # cave_bat
	var other_mon := bm2.living_monsters()[0]    # boar
	var other_hp := other_mon.current_hp
	bm2.play_card(mage, strike, target_mon)
	_ok(other_mon.current_hp == other_hp, "单体攻击不波及他人")
	_ok(target_mon.current_hp < target_mon.data.hp, "目标掉血")

	# 群体攻击：打全场
	var all_cards: Array[CardData] = []
	for c in _db.cards.values():
		var cd := c as CardData
		if cd.card_class == CardData.CardClass.ATTACK and cd.target_type == CardData.TargetType.ALL_ENEMIES:
			all_cards.append(cd)
	if all_cards.size() > 0:
		var aoe := all_cards[0]
		var strong := _make_adventurer("强者", 20, 20, 20, 20)
		var bm3 := BattleManager.new()
		bm3.setup([strong], _monsters_of(["boar", "cave_bat"]), _deck_of([[aoe.id, 10]]))
		bm3.start()
		var before_hps: Array = []
		for m in bm3.living_monsters():
			before_hps.append(m.current_hp)
		bm3.play_card(strong, aoe, null)
		var all_hit := true
		for i in range(bm3.monsters.size()):
			if bm3.monsters[i].current_hp >= int(before_hps[i]):
				all_hit = false
		_ok(all_hit, "群体攻击命中全部敌人（%s）" % aoe.display_name)
	else:
		print("      （本数据集无全体攻击卡，跳过）")


# ---- 7b. 出牌合法性（废牌不该消耗资源） ----
func _test_play_validity() -> void:
	print("\n-- 出牌合法性：无效目标不该消耗资源 --")

	var heal: CardData = _db.get_card("heal")
	var rez: CardData = _db.get_card("resurrect")
	var strike: CardData = _db.get_card("strike")

	# 满血时治疗卡不可打
	var full := _make_adventurer("满血者", 6, 6, 6, 6)
	var bm := BattleManager.new()
	bm.setup([full], _monsters_of(["boar"]), _deck_of([["heal", 5], ["resurrect", 2]]))
	bm.start()
	_ok(not bm.can_play(full, heal), "全员满血时治疗卡不可打")
	var mana_before := full.current_mana
	var hand_before := bm.deck.hand.size()
	_ok(not bm.play_card(full, heal, full), "强行打治疗卡被拒绝")
	_ok(bm.deck.hand.size() == hand_before, "被拒绝时手牌未消耗")
	_ok(full.current_mana == mana_before, "被拒绝时资源未消耗")

	# 无人濒死时复活术不可打
	_ok(not bm.can_play(full, rez), "无人濒死时复活术不可打")

	# 有人濒死时复活术可打
	full.take_damage(9999)
	_ok(full.is_downed, "角色进入濒死")
	# 濒死者自己不能出牌，需要一个活着的施法者
	var healer := _make_adventurer("治疗者", 6, 6, 9, 8)
	var bm2 := BattleManager.new()
	bm2.setup([healer, full], _monsters_of(["boar"]), _deck_of([["resurrect", 3], ["heal", 3]]))
	bm2.start()
	# bm2 setup 会重置全队，所以手动把 full 打濒死
	full.take_damage(9999)
	healer.current_mana = healer.get_max_mana()
	_ok(bm2.can_play(healer, rez), "有人濒死时复活术可打")
	_ok(bm2.can_play(healer, heal) == false, "只剩濒死者时治疗卡仍不可打（治疗对濒死无效）")

	var ok := bm2.play_card(healer, rez, full)
	_ok(ok, "复活术成功打出")
	_ok(full.current_hp == 1 and not full.is_downed, "被救回，血量 1")

	# 有残血者时治疗卡可打
	healer.current_hp = 1
	_ok(bm2.can_play(healer, heal), "有残血者时治疗卡可打")

	# 需要单体目标却没传目标 → 拒绝且不消耗资源
	healer.current_hp = 1
	var mana_b := healer.current_mana
	var hand_b := bm2.deck.hand.size()
	_ok(not bm2.play_card(healer, heal, null), "单体治疗卡未传目标被拒绝")
	_ok(healer.current_mana == mana_b, "未传目标时蓝量未消耗")
	_ok(bm2.deck.hand.size() == hand_b, "未传目标时手牌未消耗")

	# 单体攻击卡未传目标 → 拒绝
	var solo_atk := _make_adventurer("莽夫", 8, 8, 5, 8)
	var bm4 := BattleManager.new()
	bm4.setup([solo_atk], _monsters_of(["boar"]), _deck_of([["strike", 10]]))
	bm4.start()
	var action_b := solo_atk.current_action
	_ok(not bm4.play_card(solo_atk, strike, null), "单体攻击卡未传目标被拒绝")
	_ok(solo_atk.current_action == action_b, "未传目标时行动值未消耗")

	# 已是满血的目标 → 单体治疗被拒绝
	solo_atk.current_hp = solo_atk.get_max_hp()
	solo_atk.current_mana = solo_atk.get_max_mana()
	var heal2: CardData = _db.get_card("heal")
	var bm5 := BattleManager.new()
	bm5.setup([solo_atk], _monsters_of(["boar"]), _deck_of([["heal", 5]]))
	bm5.start()
	_ok(not bm5.play_card(solo_atk, heal2, solo_atk), "对满血目标单体治疗被拒绝")

	# 全员满血 + 有残血者 → 用全体治疗
	var all_heal: CardData = null
	for c in _db.cards.values():
		var cd := c as CardData
		if cd.heal_multiplier > 0.0 and cd.target_type == CardData.TargetType.ALL_ALLIES:
			all_heal = cd
			break
	if all_heal != null:
		print("      全体治疗卡：%s" % all_heal.display_name)

	# 敌人全灭后攻击卡不可打
	var solo := _make_adventurer("强者", 30, 30, 30, 30)
	var bm3 := BattleManager.new()
	bm3.setup([solo], _monsters_of(["giant_rat"]), _deck_of([["strike", 20]]))
	bm3.start()
	bm3.play_card(solo, strike, bm3.living_monsters()[0])
	_ok(bm3.result == BattleManager.Result.VICTORY, "一击败杀")
	_ok(not bm3.can_play(solo, strike), "战斗结束后不可再出牌")


# ---- 7c. 共鸣（联合卡牌）+ 表现层事件（9-23 需求，9-24 重构为前置条件型） ----
func _test_combo_and_feedback() -> void:
	print("\n-- 共鸣（联合卡牌） --")

	var wind: CardData = _db.get_card("rune_wind")
	var fire: CardData = _db.get_card("rune_fire")
	var tornado: CardData = _db.get_card("fire_tornado")
	_ok(wind != null and fire != null and tornado != null, "共鸣体系卡已生成（组件 + 联合卡本体）")
	if wind == null or fire == null or tornado == null:
		return

	# --- 结构：组件卡 / 联合卡本体的语义必须分得清 ---
	_ok(wind.is_combo_component() and not wind.is_combo_payoff(), "风之符文是组件卡")
	_ok(tornado.is_combo_payoff() and not tornado.is_combo_component(), "风火龙卷是联合卡本体")
	_ok(wind.has_combo() and tornado.has_combo(), "两者都属于共鸣体系")
	_ok(wind.combo_key == tornado.combo_key and wind.combo_name == tornado.combo_name,
		"同组同 key 同显示名（%s）" % tornado.combo_name)
	_ok(wind.combo_part != fire.combo_part, "两张组件是不同部件（%s / %s）" % [wind.combo_part, fire.combo_part])
	_ok(wind.combo_complete.has("wind") and wind.combo_complete.has("fire"),
		"组合声明了全部部件（%s）" % str(wind.combo_complete))
	_ok(wind.combo_multiplier == 0.0, "组件卡倍率 0（单独打出无任何效果）")
	_ok(tornado.combo_multiplier > 0.0, "联合卡带全体伤害倍率（%.1f）" % tornado.combo_multiplier)
	_ok(wind.action_cost == 0, "组件卡不占行动点（%d）" % wind.action_cost)
	_ok(tornado.action_cost >= 2, "联合卡占 2 点行动（终结技分量：%d）" % tornado.action_cost)

	# --- 前置条件：没攒够组件时，联合卡打不出来 ---
	var solo := _make_adventurer("法师", 6, 3, 12, 8)
	var bm := BattleManager.new()
	bm.setup([solo], _monsters_of(["boar", "boar"]),
		_deck_of([["rune_wind", 5], ["rune_fire", 5], ["fire_tornado", 5]]))
	bm.start()
	solo.current_mana = maxi(solo.get_max_mana(), 90)
	solo.current_action = 9
	var hp0: Array = []
	for m in bm.living_monsters():
		hp0.append(m.current_hp)

	_ok(not bm.combo_ready(tornado), "开场：联合卡前置未满足")
	_ok(not bm.can_play(solo, tornado), "开场：联合卡打不出去（缺前置）")
	_ok(not bm.play_card(solo, tornado, null), "开场：强行打联合卡被拒绝")
	_ok(bm.damage_dealt == 0, "开场：没有造成任何伤害（%d）" % bm.damage_dealt)

	# --- 组件卡单独打出：任何效果都没有 ---
	_ok(bm.play_card(solo, wind, null), "组件卡可以打出（不占行动点）")
	var changed := 0
	for i in range(bm.monsters.size()):
		if bm.monsters[i].current_hp != int(hp0[i]):
			changed += 1
	_ok(changed == 0, "单独打出组件卡：敌人血量完全不变（无任何效果）")
	_ok(bm.combo_cast.get("fire_tornado", []).size() == 1, "组件已进共鸣槽（1/2）")
	_ok(bm.damage_dealt == 0, "单独打出不计入伤害（%d）" % bm.damage_dealt)
	_ok(not bm.can_play(solo, tornado), "只攒到 1/2：联合卡仍然打不出去")
	_ok(bm.combo_missing_parts(tornado) == ["fire"],
		"差件提示正确（%s）" % str(bm.combo_missing_parts(tornado)))

	# --- 凑齐两张 → 联合卡解锁，打出即全体重击 ---
	_ok(bm.play_card(solo, fire, null), "第二张组件卡打出（仍无直接伤害）")
	_ok(bm.combo_ready(tornado), "凑齐后：联合卡前置条件满足")
	_ok(bm.can_play(solo, tornado), "凑齐后：联合卡可以打出")
	_ok(bm.combo_missing_parts(tornado).is_empty(), "凑齐后：不再缺件")

	var ev: Array = []
	bm.combat_feedback.connect(func(p): ev.append(p))
	var dmg_before: int = bm.damage_dealt
	_ok(bm.play_card(solo, tornado, null), "联合卡成功打出")
	_ok(bm.damage_dealt > dmg_before, "联合卡计入总伤害（%d → %d）" % [dmg_before, bm.damage_dealt])
	var all_hit := true
	for i in range(bm.monsters.size()):
		if bm.monsters[i].current_hp >= int(hp0[i]):
			all_hit = false
	_ok(all_hit, "联合卡对所有敌人造成伤害")

	# --- 打出后消耗前置，本回合该组不能再发动 ---
	_ok(bm.combo_cast.get("fire_tornado", []).is_empty(), "发动后共鸣槽清空（前置被消耗）")
	_ok(bm.combo_fired_of("fire_tornado"), "本回合该组已标记发动")
	_ok(not bm.combo_ready(tornado), "发动后：前置消失，联合卡不再就绪")

	var has_combo_ev := false
	for p in ev:
		if String(p.get("kind", "")) == "combo":
			has_combo_ev = true
	_ok(has_combo_ev, "联合卡发动时发出 combo 事件（供 UI 弹横幅）")

	# --- 跨角色：两人各出一张组件，同样能解锁联合卡 ---
	var a1 := _make_adventurer("甲", 6, 3, 12, 8)
	var a2 := _make_adventurer("乙", 6, 3, 12, 8)
	var bm3 := BattleManager.new()
	bm3.setup([a1, a2], _monsters_of(["boar", "boar"]),
		_deck_of([["rune_wind", 5], ["rune_fire", 5], ["fire_tornado", 5]]))
	bm3.start()
	a1.current_mana = maxi(a1.get_max_mana(), 90)
	a2.current_mana = maxi(a2.get_max_mana(), 90)
	a1.current_action = 9
	a2.current_action = 9
	var hp2: Array = []
	for m in bm3.living_monsters():
		hp2.append(m.current_hp)
	_ok(bm3.play_card(a1, wind, null), "甲打出风之符文")
	_ok(bm3.play_card(a2, fire, null), "乙打出火之符文")
	_ok(bm3.combo_ready(tornado), "槽是全队共享的：两人各出一张也能解锁联合卡")
	_ok(bm3.play_card(a1, tornado, null), "由甲发动联合卡（施法者是甲）")
	var all3 := true
	for i in range(bm3.monsters.size()):
		if bm3.monsters[i].current_hp >= int(hp2[i]):
			all3 = false
	_ok(all3, "跨角色凑前置后，联合卡对全体造成伤害")

	# --- 跨回合攒不出来（前置必须同一回合内齐备） ---
	var tank := _make_adventurer("坦克", 20, 20, 8, 20)
	var bm4 := BattleManager.new()
	bm4.setup([tank], _monsters_of(["boar", "boar"]),
		_deck_of([["rune_wind", 6], ["rune_fire", 6], ["fire_tornado", 6]]))
	bm4.start()
	tank.current_mana = maxi(tank.get_max_mana(), 120)
	tank.current_action = 9
	bm4.play_card(tank, wind, null)
	_ok(bm4.combo_cast.get("fire_tornado", []).size() == 1, "组件进槽（1/2）")
	bm4.end_player_turn()
	_ok(bm4.combo_cast.get("fire_tornado", []).is_empty(), "新回合共鸣槽清空（不能跨回合攒）")
	tank.current_action = 9
	_ok(not bm4.can_play(tank, tornado), "新回合：只打出 1 张组件也打不出联合卡")

	# --- 第二组联合卡（霜雷裁决）：同一套机制，独立的前置与标记 ---
	var frost: CardData = _db.get_card("rune_frost")
	var thunder: CardData = _db.get_card("rune_thunder")
	var verdict: CardData = _db.get_card("frost_thunder")
	_ok(frost != null and thunder != null and verdict != null, "第二组共鸣卡已生成")
	if frost != null and thunder != null and verdict != null:
		_ok(verdict.combo_key != tornado.combo_key, "两组共鸣 key 不同（%s / %s）" % [tornado.combo_key, verdict.combo_key])
		_ok(not frost.combo_complete.has("wind"), "霜之符文不认风部件（前置独立）")
		var sage := _make_adventurer("法师", 6, 3, 12, 8)
		var bm6 := BattleManager.new()
		bm6.setup([sage], _monsters_of(["boar", "boar"]),
			_deck_of([["rune_wind", 3], ["rune_fire", 3], ["rune_frost", 3], ["rune_thunder", 3], ["frost_thunder", 3]]))
		bm6.start()
		sage.current_mana = maxi(sage.get_max_mana(), 120)
		sage.current_action = 9
		bm6.play_card(sage, wind, null)
		bm6.play_card(sage, fire, null)
		_ok(not bm6.combo_ready(verdict), "风火齐备不影响霜雷组（前置互不干扰）")
		_ok(bm6.can_play(sage, tornado), "风火齐备解锁风火龙卷")
		bm6.play_card(sage, frost, null)
		_ok(not bm6.combo_ready(verdict), "只攒到 1/2 的霜雷组仍不就绪")
		bm6.play_card(sage, thunder, null)
		_ok(bm6.combo_ready(verdict), "霜雷齐备 → 霜雷裁决就绪")
		var hp6: Array = []
		for m in bm6.living_monsters():
			hp6.append(m.current_hp)
		_ok(bm6.play_card(sage, verdict, null), "霜雷裁决打出")
		var all6 := true
		for i in range(bm6.monsters.size()):
			if bm6.monsters[i].current_hp >= int(hp6[i]):
				all6 = false
		_ok(all6, "霜雷裁决对全体造成伤害")
		_ok(not bm6.combo_fired_of("fire_tornado"), "发动霜雷不影响风火组的「本回合已发动」标记")

	# --- 表现层事件：payload 字段齐全 ---
	print("\n-- 战斗表现层事件 --")
	var hero := _make_adventurer("主角", 12, 12, 4, 8)
	var bm5 := BattleManager.new()
	bm5.setup([hero], _monsters_of(["boar"]), _deck_of([["strike", 10], ["guard_phys", 10]]))
	bm5.start()
	hero.current_action = 9
	var ev5: Array = []
	bm5.combat_feedback.connect(func(p): ev5.append(p))

	var strike: CardData = _db.get_card("strike")
	bm5.play_card(hero, strike, bm5.living_monsters()[0])
	var kinds: Array = []
	for p in ev5:
		kinds.append(String(p.get("kind", "")))
	_ok(kinds.has("attack_start"), "出手时发出 attack_start（驱动前冲）")
	_ok(kinds.has("damage"), "命中时发出 damage（驱动抖动 + 飘字）")

	var dmg_ev: Dictionary = {}
	for p in ev5:
		if String(p.get("kind", "")) == "damage":
			dmg_ev = p
			break
	_ok(int(dmg_ev.get("amount", 0)) > 0, "damage 带伤害数字（%d）" % int(dmg_ev.get("amount", 0)))
	_ok(dmg_ev.get("unit", null) != null, "damage 带受击者引用（UI 靠它找单位）")
	_ok(dmg_ev.get("source", null) == hero, "damage 带出手者引用（画轨迹线用）")
	_ok(dmg_ev.has("crit"), "damage 带暴击标记（决定字号与颜色）")
	_ok(dmg_ev.has("killed"), "damage 带击杀标记")

	ev5.clear()
	var guard: CardData = _db.get_card("guard_phys")
	bm5.play_card(hero, guard, null)
	var has_shield := false
	for p in ev5:
		if String(p.get("kind", "")) == "shield":
			has_shield = true
	_ok(has_shield, "防御卡发出 shield 事件")

	# 治疗事件
	var cleric := _make_adventurer("牧师", 12, 4, 14, 8)
	var bm6 := BattleManager.new()
	bm6.setup([cleric, hero], _monsters_of(["boar"]), _deck_of([["heal", 10]]))
	bm6.start()
	cleric.current_action = 9
	cleric.current_mana = maxi(cleric.get_max_mana(), 60)
	cleric.current_hp = 1
	var ev6: Array = []
	bm6.combat_feedback.connect(func(p): ev6.append(p))
	var heal_card: CardData = _db.get_card("heal")
	bm6.play_card(cleric, heal_card, cleric)
	var has_heal := false
	for p in ev6:
		if String(p.get("kind", "")) == "heal":
			has_heal = true
	_ok(has_heal, "治疗卡发出 heal 事件")


# ---- 7b. 廉价法术（9-23 需求：多法术流卡池缺口）----
func _test_cheap_spells() -> void:
	print("\n-- 廉价法术 --")

	var ids := ["spark", "wind_blade", "ice_shard", "static_bolt", "flame_wave"]
	var cards: Array[CardData] = []
	for cid in ids:
		var c: CardData = _db.get_card(cid)
		_ok(c != null, "取到廉价法术 %s" % cid)
		if c == null:
			return
		cards.append(c)
		_ok(c.card_class == CardData.CardClass.ATTACK
			and c.damage_type == CardData.DamageType.MAGICAL,
			"%s 归入「法术进攻」" % cid)
		_ok(c.action_cost <= 1, "%s 行动消耗 ≤ 1（实际 %d）" % [cid, c.action_cost])
		_ok(c.mana_cost <= 6, "%s 蓝耗进入廉价档（实际 %d ≤ 6）" % [cid, c.mana_cost])

	# 最多只会有一张 0 行动点的法术（火花术），否则回合内可以无限连打
	var free_action_spells := 0
	for c in cards:
		if c.action_cost == 0:
			free_action_spells += 1
	_ok(free_action_spells == 1, "只有 1 张 0 行动点法术（实际 %d）" % free_action_spells)

	# --- 廉价法术真的能打出去、真的进伤害统计 ---
	var mage := _make_adventurer("见习法师", 4, 3, 9, 6)
	var bm := BattleManager.new()
	bm.setup([mage], _monsters_of(["boar"]), _deck_of([["spark", 6], ["wind_blade", 6]]))
	bm.start()
	mage.current_action = 9
	mage.current_mana = maxi(mage.get_max_mana(), 60)

	var before: int = bm.damage_dealt
	_ok(bm.play_card(mage, cards[0], bm.living_monsters()[0]), "火花术可以打出")
	_ok(bm.damage_dealt > before, "火花术伤害计入统计（+%d）" % (bm.damage_dealt - before))

	before = bm.damage_dealt
	_ok(bm.play_card(mage, cards[1], bm.living_monsters()[0]), "风刃可以打出")
	_ok(bm.damage_dealt > before, "风刃伤害计入统计（+%d）" % (bm.damage_dealt - before))

	# --- 焰浪是全体牌：一次要打到所有存活敌人 ---
	var bm2 := BattleManager.new()
	bm2.setup([mage], _monsters_of(["boar", "boar"]), _deck_of([["flame_wave", 6]]))
	bm2.start()
	mage.current_action = 9
	mage.current_mana = maxi(mage.get_max_mana(), 60)
	var hps: Array = []
	for m in bm2.living_monsters():
		hps.append(m.current_hp)
	bm2.play_card(mage, cards[4], null)
	var hit_all := true
	for i in range(bm2.monsters.size()):
		if bm2.monsters[i].current_hp >= int(hps[i]):
			hit_all = false
	_ok(hit_all, "焰浪打到全部敌人（%s → %s）" % [str(hps), str([bm2.monsters[0].current_hp, bm2.monsters[1].current_hp])])

	# --- 静电束：目标带护盾时倍率 ×1.5（BONUS_VS_SHIELD）---
	var bolt: CardData = cards[3]
	_ok(bolt.has_tag("BONUS_VS_SHIELD"), "静电束带 BONUS_VS_SHIELD 标签")
	_ok(is_equal_approx(bolt.multiplier, 1.0), "静电束基础倍率 1.0（实际 %.2f）" % bolt.multiplier)

	var d_plain := _bolt_damage(bolt, 0)
	var d_shielded := _bolt_damage(bolt, 60)
	_ok(d_shielded > d_plain,
		"目标带护盾时静电束伤害更高（无盾 %d → 有盾 %d）" % [d_plain, d_shielded])
	_ok(float(d_shielded) >= float(d_plain) * 1.3,
		"提升幅度接近 ×1.5（实测 ×%.2f）" % (float(d_shielded) / maxf(float(d_plain), 1.0)))


## 用同一施法者 / 同一目标量一次静电束的**原始**伤害（shield = 目标战前护盾）
## 必须取 damage 事件的 raw_damage：护盾会把净伤害吃成 0，用 damage_dealt 量不到。
func _bolt_damage(bolt: CardData, shield: int) -> int:
	var mage := _make_adventurer("见习法师", 4, 3, 9, 6)
	var bm := BattleManager.new()
	bm.setup([mage], _monsters_of(["boar"]), _deck_of([["static_bolt", 4]]))
	bm.start()
	mage.current_action = 9
	mage.current_mana = maxi(mage.get_max_mana(), 60)
	var target: MonsterInstance = bm.living_monsters()[0]
	target.shield = shield
	_raw_damage_acc = 0
	bm.combat_feedback.connect(_acc_raw_damage)
	bm.play_card(mage, bolt, target)
	bm.combat_feedback.disconnect(_acc_raw_damage)
	return _raw_damage_acc


func _acc_raw_damage(p: Dictionary) -> void:
	if String(p.get("kind", "")) == "damage":
		_raw_damage_acc += int(p.get("amount", 0))


# ---- 8. 全自动打一场完整战斗 ----
func _test_full_auto_battle() -> void:
	print("\n-- 全自动完整战斗（验证流程不卡死）--")

	var team: Array[Adventurer] = [
		_make_adventurer("农夫之子", 6, 7, 4, 6),
		_make_adventurer("佣兵", 8, 6, 3, 5),
		_make_adventurer("见习法师", 4, 3, 9, 6),
	]
	var deck := _deck_of([
		["strike", 8], ["guard_phys", 4], ["heal", 3],
		["fireball", 2], ["quick_jab", 3],
	])

	var bm := BattleManager.new()
	bm.setup(team, _monsters_of(["boar", "boar", "cave_bat"]), deck)
	bm.start()

	print("      队伍战力：%d" % _team_power(team))
	print("      敌方战力：%d" % _enemy_power(bm.monsters))

	var guard := 0
	while bm.result == BattleManager.Result.ONGOING and guard < 200:
		guard += 1
		_auto_play_one_round(bm)

	print("      共进行 %d 回合，结果：%s" % [
		bm.turn.round_number, ["进行中", "胜利", "失败"][bm.result]
	])
	print("      造成伤害 %d / 承受伤害 %d / 击杀 %d" % [
		bm.damage_dealt, bm.damage_taken, bm.kills
	])
	_ok(bm.result != BattleManager.Result.ONGOING, "战斗在 200 回合内分出胜负")
	_ok(bm.turn.round_number <= 30, "回合数合理（≤30，实际 %d）" % bm.turn.round_number)


## 一轮：每个能行动的人都尝试出一张能打的牌，然后结束回合
func _auto_play_one_round(bm: BattleManager) -> void:
	for a in bm.team:
		if not a.is_alive():
			continue
		var played := true
		while played:
			played = false
			if bm.living_monsters().is_empty():
				break
			for card in bm.deck.hand.duplicate():
				if not bm.can_play(a, card):
					continue
				var target: Variant = null
				if card.card_class == CardData.CardClass.ATTACK:
					target = bm.living_monsters()[0]
				elif card.has_tag("REVIVE"):
					for t in bm.team:
						if t.is_downed:
							target = t
							break
				elif card.heal_multiplier > 0.0 and card.needs_target_card():
					# 单体治疗：找最残血的活人
					var worst: Adventurer = null
					for t in bm.team:
						if not t.is_alive():
							continue
						if t.current_hp >= t.get_max_hp():
							continue
						if worst == null or t.current_hp < worst.current_hp:
							worst = t
					target = worst
				if bm.play_card(a, card, target):
					played = true
					break
	if bm.result == BattleManager.Result.ONGOING:
		bm.end_player_turn()


func _team_power(team: Array[Adventurer]) -> int:
	var powers: Array = []
	for a in team:
		powers.append(a.get_power())
	return PowerCalculator.team_power(powers)


func _enemy_power(ms: Array[MonsterInstance]) -> int:
	var total := 0.0
	for m in ms:
		total += m.get_power()
	return int(total)
