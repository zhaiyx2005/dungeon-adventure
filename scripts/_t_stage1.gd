## 阶段 1 冒烟测试：数据校验 + 主菜单加载
##
## 跑法见 HANDOFF.md / skill「godot-headless-test」。
extends SceneTree

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(60.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _run() -> void:
	_watchdog()
	print("\n===== 阶段1 冒烟：数据校验 + 主菜单 =====\n")

	# ---- 1. 数据加载 ----
	print("-- 数据加载 --")
	var db := GameDatabase.new()
	db.load_all()
	print("  " + db.summary())

	# 卡牌总数：改卡表（tools/generate_data.py 的 CARDS）后必须同步这里
	# 54 = 43 原有卡 + 5 张廉价法术（9-23 补充）
	#      + 4 张共鸣组件（风/火/霜/雷之符文）+ 2 张联合卡本体（风火龙卷 / 霜雷裁决）
	_ok(db.cards.size() == 54, "卡牌 54 张（实际 %d）" % db.cards.size())
	_ok(db.monsters.size() == 26, "怪物 26 只（实际 %d）" % db.monsters.size())
	_ok(db.items.size() == 67, "物品 67 件（实际 %d）" % db.items.size())
	_ok(db.dungeons.size() == 5, "关卡 5 层（实际 %d）" % db.dungeons.size())

	# ---- 1a2. 目录扫描必须能吃掉导出留下的 `.remap` 后缀 ----
	# 🔴 这条是**导出可用性**的回归保护。
	# 导出时 Godot 默认把文本资源转二进制（convert_text_resources_to_binary），
	# 在原路径留 `<id>.tres.remap` 存根；只按 `.tres` 后缀过滤会扫到 0 个文件，
	# 结果是导出版「所有卡牌不见了」而且**不报任何错**（实测踩过）。
	# 这里断言归一化规则本身，以及四个目录都能扫到东西。
	print("\n-- 目录扫描（导出版 remap 兼容） --")
	_ok(GameDatabase.normalize_entry("aegis.tres.remap") == "aegis.tres",
		"条目名剥掉 .remap → aegis.tres")
	_ok(GameDatabase.normalize_entry("aegis.tres.import") == "aegis.tres",
		"条目名剥掉 .import → aegis.tres")
	_ok(GameDatabase.normalize_entry("aegis.tres") == "aegis.tres",
		"编辑器里的正常名字不变")
	_ok(GameDatabase.normalize_entry("aegis.tres.uid") == "aegis.tres.uid",
		"旁挂文件（.uid）不被误剥")
	for pair in [["res://data/cards/", 54], ["res://data/monsters/", 26],
			["res://data/items/", 67], ["res://data/dungeons/", 5]]:
		var found: PackedStringArray = GameDatabase.list_data_files(String(pair[0]))
		_ok(found.size() == int(pair[1]), "%s 扫到 %d 个 .tres（应 %d）"
			% [pair[0], found.size(), int(pair[1])])

	# ---- 1b. 廉价法术（9-23 需求：多法术流卡池缺口）----
	print("\n-- 廉价法术 --")
	var cheap_spells := ["spark", "wind_blade", "ice_shard", "static_bolt", "flame_wave"]
	for cid in cheap_spells:
		var sp: CardData = db.get_card(cid)
		_ok(sp != null, "取到廉价法术 %s" % cid)
		if sp != null:
			_ok(sp.card_class == CardData.CardClass.ATTACK
				and sp.damage_type == CardData.DamageType.MAGICAL,
				"%s 属于「法术进攻」六分类" % cid)
			_ok(sp.mana_cost > 0, "%s 是法术卡（蓝耗 %d > 0）" % [cid, sp.mana_cost])
			_ok(sp.action_cost <= 1, "%s 行动消耗 ≤ 1（实际 %d）" % [cid, sp.action_cost])
	# 0–1 费法术至少要够铺满一回合的手牌，否则多法术流还是凑不出循环
	var cheap_count := 0
	for c in db.cards.values():
		if (c.card_class == CardData.CardClass.ATTACK
			and c.damage_type == CardData.DamageType.MAGICAL and c.action_cost <= 1):
			cheap_count += 1
	_ok(cheap_count >= 8, "0–1 费法术共 %d 张（目标 ≥ 8）" % cheap_count)

	# ---- 1c. 共鸣体系（9-24 重构：组件卡 → 前置条件 → 联合卡本体）----
	# 组件卡无直接效果，本回合内凑齐本组部件后才能打出该组的联合卡本体。
	print("\n-- 共鸣体系（联合卡牌） --")
	var comps: Array[CardData] = []
	var payoffs: Array[CardData] = []
	for c in db.cards.values():
		var cd := c as CardData
		if cd.is_combo_component():
			comps.append(cd)
		elif cd.is_combo_payoff():
			payoffs.append(cd)
	_ok(comps.size() == 4, "共鸣组件 4 张（实际 %d）" % comps.size())
	_ok(payoffs.size() == 2, "联合卡本体 2 张（实际 %d）" % payoffs.size())

	var all_comp_clean := true
	for c in comps:
		# 组件卡必须"单独打出毫无效果"，而且不能占行动点（否则凑前置会抢出手机会）
		if c.combo_multiplier != 0.0 or c.action_cost != 0 or c.mana_cost <= 0:
			all_comp_clean = false
	_ok(all_comp_clean, "组件卡一律 0 倍率 / 0 行动点 / 有蓝耗（凑前置不抢出手）")

	var tornado: CardData = db.get_card("fire_tornado")
	_ok(tornado != null and tornado.is_combo_payoff(), "风火龙卷是联合卡本体")
	if tornado != null:
		_ok(tornado.card_class == CardData.CardClass.ATTACK
			and tornado.target_type == CardData.TargetType.ALL_ENEMIES,
			"联合卡是全体攻击卡（打出即结算伤害）")
		_ok(is_equal_approx(tornado.multiplier, 3.0)
			and is_equal_approx(tornado.combo_multiplier, 3.0),
			"风火龙卷倍率 3.0（本体与共鸣字段同源：%.1f）" % tornado.multiplier)
		_ok(tornado.action_cost == 2, "联合卡吃 2 行动点（终结技分量：%d）" % tornado.action_cost)
		_ok(tornado.combo_complete.has("wind") and tornado.combo_complete.has("fire"),
			"风火龙卷前置 = 风 + 火（%s）" % str(tornado.combo_complete))
	_ok(tornado != null and tornado.get_combo_hint_cn() != "", "联合卡卡面有前置提示行")

	var verdict: CardData = db.get_card("frost_thunder")
	_ok(verdict != null and verdict.is_combo_payoff() and is_equal_approx(verdict.multiplier, 2.0),
		"霜雷裁决是第二组联合卡（2.0 倍）")
	_ok(verdict != null and verdict.has_tag("BONUS_VS_SHIELD"),
		"霜雷裁决带对盾加成（与风火龙卷拉开定位）")

	# 每一张联合卡的前置条件，都能被同组组件卡完全满足（数据层不会错配）
	var mismatch := 0
	for p in payoffs:
		var provided: Array = []
		for c in comps:
			if c.combo_key == p.combo_key:
				provided.append(c.combo_part)
		for part in p.combo_complete:
			if not provided.has(part):
				mismatch += 1
	_ok(mismatch == 0, "每张联合卡的前置条件都有对应组件卡（缺 %d 个部件）" % mismatch)

	# ---- 2. 校验 ----
	print("\n-- 数据校验 --")
	var ok := Validator.run_all()
	var errs: Array[String] = Validator.get_errors()
	_ok(ok, "Validator.run_all() 通过（错误 %d 条）" % errs.size())
	for e in errs:
		print("      " + e)

	# ---- 3. 关键数据抽样 ----
	print("\n-- 关键数据抽样 --")
	var strike: CardData = db.get_card("strike")
	_ok(strike != null, "取到卡牌 strike")
	if strike != null:
		_ok(strike.card_class == CardData.CardClass.ATTACK, "strike 是攻击卡")
		_ok(is_equal_approx(strike.multiplier, 1.0), "strike 倍率 1.0")

	var rez: CardData = db.get_card("resurrect")
	_ok(rez != null and rez.has_tag("REVIVE"), "复活术带 REVIVE 标签")
	_ok(rez != null and rez.needs_target_card(), "复活术需要指定目标卡")

	var guard: CardData = db.get_card("guard_phys")
	_ok(guard != null and not guard.needs_target_card(), "物理防御是全场卡（不需要目标）")

	var boar: MonsterData = db.get_monster("boar")
	_ok(boar != null and boar.hp == 42, "野猪怪血量 42")

	var lv1: DungeonData = db.get_dungeon("level_01")
	_ok(lv1 != null and lv1.grid_cols == 3 and lv1.grid_rows == 7, "1 层网格 3×7")
	_ok(lv1 != null and lv1.monster_pool.size() == 4, "1 层怪物池 4 种")

	# ---- 3b. 意见6：卡牌六分类（物理/法术 × 进攻/防御/特殊）----
	print("\n-- 意见6：卡牌六分类 --")
	var no_type := 0
	var phys_with_mana := 0
	var mag_without_mana := 0
	var cat_seen := {}
	var cat_list: PackedStringArray = []
	for c in db.cards.values():
		var card := c as CardData
		if card.damage_type == CardData.DamageType.NONE:
			no_type += 1
		elif card.damage_type == CardData.DamageType.MAGICAL:
			if card.mana_cost <= 0:
				mag_without_mana += 1
		elif card.mana_cost != 0:
			phys_with_mana += 1
		var cat_name := card.get_category_name_cn()
		if not cat_seen.has(cat_name):
			cat_seen[cat_name] = true
			cat_list.append(cat_name)
	_ok(no_type == 0, "所有卡牌都有物理/法术属性（NONE 数 %d）" % no_type)
	_ok(phys_with_mana == 0, "物理卡一律不耗蓝（违规 %d 张，意见6）" % phys_with_mana)
	_ok(mag_without_mana == 0, "法术卡一律耗蓝（违规 %d 张，意见6）" % mag_without_mana)
	_ok(cat_list.size() == 6, "六分类齐全（%d 类：%s）" % [cat_list.size(), ", ".join(cat_list)])
	# 抽样：普通物理攻击=物理进攻、烈焰术=法术进攻、普通法术防御=法术防御
	var s2: CardData = db.get_card("strike")
	var fb: CardData = db.get_card("fireball")
	var gm: CardData = db.get_card("guard_mag")
	_ok(s2 != null and s2.get_category_name_cn() == "物理进攻", "strike → 物理进攻")
	_ok(fb != null and fb.get_category_name_cn() == "法术进攻", "fireball → 法术进攻")
	_ok(gm != null and gm.get_category_name_cn() == "法术防御", "guard_mag → 法术防御")
	_ok(gm != null and gm.is_magical(), "guard_mag 是法术卡")

	# ---- 3c. 意见5：武器槽位合一 ----
	print("\n-- 意见5：武器槽位 --")
	var weapon_count := 0
	var bad_slot := 0
	var slot_names := {}
	for it in db.items.values():
		var item := it as ItemData
		slot_names[item.get_slot_name_cn()] = true
		if item.is_equipment() and item.slot == ItemData.Slot.WEAPON:
			weapon_count += 1
		if item.is_equipment() and (item.slot < 0 or item.slot > ItemData.Slot.WEAPON):
			bad_slot += 1
	_ok(weapon_count >= 10, "武器类装备 %d 件统一到 WEAPON 槽（意见5）" % weapon_count)
	_ok(bad_slot == 0, "没有越界的装备槽位（%d）" % bad_slot)
	_ok(slot_names.has("武器"), "槽位名包含「武器」")
	_ok(not slot_names.has("单手武器") and not slot_names.has("双手武器") and not slot_names.has("远程武器"),
		"不再出现单手/双手/远程槽位名（意见5）")

	# ---- 4. 公式自检 ----
	print("\n-- 公式自检（与数值设计 v1.0 对表）--")
	var d := PowerCalculator.derive_stats(6, 7, 4, 6)
	print("  体质6/力量7/智力4/精力6 → %s" % str(d))
	_ok(int(d["hp"]) == 55, "血量 = 6*6+6*2+7 = 55（实际 %d）" % int(d["hp"]))
	_ok(int(d["mana"]) == 34, "蓝量 = 4*4+6*2+6 = 34（实际 %d）" % int(d["mana"]))
	_ok(int(d["action"]) == 7, "行动值 = 6+6*0.2 = 7（实际 %d）" % int(d["action"]))
	_ok(int(d["phys_atk"]) == 17, "物攻 = 7*2+6*0.5 = 17（实际 %d）" % int(d["phys_atk"]))

	# 伤害：max(攻*倍率 - 抗性, 1)
	_ok(PowerCalculator.calc_damage(17, 1.0, 6) == 11, "17×1.0−6 = 11")
	_ok(PowerCalculator.calc_damage(5, 1.0, 99) == 1, "伤害保底 1")
	_ok(PowerCalculator.calc_damage(10, 1.0, 0, true) == 15, "暴击 ×1.5 = 15")

	# 暴击率上限 75%
	# 暴击率：技巧/(技巧+50+等级*10)*0.75，随技巧单调递增、趋近但不超过 0.75
	var c1 := PowerCalculator.calc_crit_chance(50, 1)
	var c2 := PowerCalculator.calc_crit_chance(100, 1)
	var c_max := PowerCalculator.calc_crit_chance(100000, 1)
	_ok(c2 > c1, "技巧越高暴击率越高（50→%s，100→%s）" % [str(c1), str(c2)])
	_ok(c_max <= 0.75, "暴击率不超过上限 0.75（实际 " + str(c_max) + "）")
	_ok(is_equal_approx(PowerCalculator.calc_crit_chance(50, 1), 50.0 / 110.0 * 0.75),
		"技巧50/等级1 暴击率 = 50/110*0.75")

	# 队伍系数
	_ok(PowerCalculator.team_power([100.0]) == 100, "1 人系数 1.00")
	_ok(PowerCalculator.team_power([100.0, 100.0, 100.0]) == 330, "3 人系数 1.10 = 330")

	# ---- 5. 主菜单加载 ----
	print("\n-- 主菜单加载 --")
	var ps: PackedScene = load("res://scenes/main_menu.tscn")
	_ok(ps != null, "main_menu.tscn 可加载")
	if ps != null:
		var menu: Node = ps.instantiate()
		root.add_child(menu)
		await process_frame
		await process_frame
		_ok(menu.get_node_or_null("%MenuBox") != null, "MenuBox 节点存在")
		var box: Node = menu.get_node_or_null("%MenuBox")
		if box != null:
			var btns := 0
			for ch in box.get_children():
				if ch is Button:
					btns += 1
			print("      菜单按钮数：%d" % btns)
			_ok(btns >= 8, "菜单按钮 ≥ 8 个")
		menu.queue_free()
		await process_frame

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
