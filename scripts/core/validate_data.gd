## 数据校验脚本
##
## 在编辑器里跑一次，确认所有数据文件自洽。
## 用法（Godot 命令行）：
##     godot --headless --script res://scripts/core/validate_data.gd
## 或在任意脚本里：Validator.run_all()
##
## 校验项（对应 docs/数据字段规范 第八节）：
##   1. 所有资源的 id 非空且与文件名一致
##   2. id 全局唯一
##   3. 卡牌按 card_class 必须有对应倍率字段
##   4. 枚举值在合法范围内
##   5. 关卡引用的 monster_pool / elite_pool / boss_id 必须真实存在
##   6. 装备的 slot 与 item_class 匹配
##   7. 共鸣组自检：组件卡与联合卡本体必须成对、部件不重复、声明一致
class_name Validator
extends RefCounted


static var _errors: Array[String] = []
static var _warnings: Array[String] = []


static func run_all() -> bool:
	_errors.clear()
	_warnings.clear()

	var db := GameDatabase.new()
	db.load_all()

	_check_file_names(GameDatabase.CARD_DIR, db.cards)
	_check_file_names(GameDatabase.MONSTER_DIR, db.monsters)
	_check_file_names(GameDatabase.ITEM_DIR, db.items)
	_check_file_names(GameDatabase.DUNGEON_DIR, db.dungeons)

	_check_cards(db)
	_check_combos(db)
	_check_monsters(db)
	_check_items(db)
	_check_dungeons(db)

	return _report()


# ---------------------------------------------------------------------------
# 各项检查
# ---------------------------------------------------------------------------

## 校验「文件名 == id」。
## 🔴 目录列举必须走 GameDatabase.list_data_files：导出后条目名是 `<id>.tres.remap`，
## 直接用 `ends_with(".tres")` 过滤会一条都拿不到，这项校验会**静默失效**。
static func _check_file_names(dir_path: String, dict: Dictionary) -> void:
	var files := GameDatabase.list_data_files(dir_path)
	if files.is_empty():
		_errors.append("目录下没有数据资源: %s" % dir_path)
		return
	for full_path in files:
		var expect := full_path.get_file().get_basename()
		var res := load(full_path)
		if res != null and "id" in res and res.id != expect:
			_errors.append("%s: id '%s' 与文件名不符" % [full_path.get_file(), res.id])


static func _check_cards(db: GameDatabase) -> void:
	for card in db.cards.values():
		var c := card as CardData
		if c.display_name == "":
			_errors.append("卡牌 '%s' 缺少 display_name" % c.id)

		if c.card_class < 0 or c.card_class > CardData.CardClass.SPECIAL:
			_errors.append("卡牌 '%s' card_class 越界" % c.id)
		if c.damage_type < 0 or c.damage_type > CardData.DamageType.NONE:
			_errors.append("卡牌 '%s' damage_type 越界" % c.id)

		# 按类型校验必须的倍率字段
		match c.card_class:
			CardData.CardClass.ATTACK:
				if c.multiplier <= 0.0:
					_errors.append("攻击卡 '%s' 缺少 multiplier" % c.id)
				if c.damage_type == CardData.DamageType.NONE:
					_errors.append("攻击卡 '%s' 的 damage_type 不应为 NONE" % c.id)
			CardData.CardClass.DEFENSE:
				if c.shield_multiplier <= 0.0:
					_errors.append("防御卡 '%s' 缺少 shield_multiplier" % c.id)
			CardData.CardClass.SPECIAL:
				pass  # 特殊卡倍率可为空（增益/减益类）

		if c.action_cost < 0:
			_errors.append("卡牌 '%s' action_cost 为负" % c.id)
		if c.mana_cost < 0:
			_errors.append("卡牌 '%s' mana_cost 为负" % c.id)

		# 9-22 修改意见 6：六分类 = (物理/法术) × (进攻/防御/特殊)
		#   规则：物理卡不耗蓝、法术卡耗蓝；因此不允许 NONE（无法归类）
		if c.damage_type == CardData.DamageType.NONE:
			_errors.append("卡牌 '%s' 缺少物理/法术属性（还是 NONE，无法归入六分类）" % c.id)
		elif c.damage_type == CardData.DamageType.MAGICAL:
			if c.mana_cost <= 0:
				_errors.append("法术卡 '%s' 必须耗蓝（当前 mana_cost=%d）" % [c.id, c.mana_cost])
		else:
			if c.mana_cost != 0:
				_errors.append("物理卡 '%s' 不应耗蓝（当前 mana_cost=%d）" % [c.id, c.mana_cost])


## 共鸣（联合卡牌）体系自检 —— 9-24 重构后新增。
## 一组共鸣 = 若干「组件卡」+「一张联合卡本体」：
##   组件卡只登记部件，联合卡本体需要本组部件全部就位才打得出去。
## 这里保证「组件永远配得上本体、本体永远等得到组件」，数据层错配不会被静默吞掉。
static func _check_combos(db: GameDatabase) -> void:
	var groups: Dictionary = {}
	for card in db.cards.values():
		var c := card as CardData
		if not c.has_combo():
			continue
		if c.combo_name == "":
			_errors.append("共鸣卡 '%s' 缺少 combo_name" % c.id)
		if c.combo_complete.is_empty():
			_errors.append("共鸣卡 '%s' 未声明 combo_complete（本组需要哪些部件）" % c.id)
		if not groups.has(c.combo_key):
			groups[c.combo_key] = {"components": [], "payoffs": [], "needs": {}}
		var grp: Dictionary = groups[c.combo_key]

		if c.is_combo_payoff():
			grp["payoffs"].append(c)
			if c.card_class != CardData.CardClass.ATTACK:
				_errors.append("联合卡 '%s' 必须是攻击卡（否则打出后不结算伤害）" % c.id)
			if c.multiplier <= 0.0:
				_errors.append("联合卡 '%s' 缺少 multiplier" % c.id)
			if c.target_type != CardData.TargetType.ALL_ENEMIES:
				_errors.append("联合卡 '%s' 的目标应为 ALL_ENEMIES（联合卡设计为全体打击）" % c.id)
		elif c.is_combo_component():
			grp["components"].append(c)
			if c.combo_multiplier != 0.0:
				_errors.append("组件卡 '%s' 的 combo_multiplier 应为 0（单独打出无任何效果）" % c.id)
			if not c.combo_complete.has(c.combo_part):
				_errors.append("组件卡 '%s' 的 combo_complete 里没有自己（%s）" % [c.id, c.combo_part])
		else:
			_errors.append("共鸣卡 '%s' 既不是组件卡也不是联合卡（combo_key 非空但语义不完整）" % c.id)

		grp["needs"][c.id] = c.combo_complete

	for key in groups.keys():
		var g: Dictionary = groups[key]
		var components: Array = g["components"]
		var payoffs: Array = g["payoffs"]

		if payoffs.is_empty():
			_errors.append("共鸣组 '%s' 没有联合卡本体 —— %d 张组件卡永远用不出去" % [key, components.size()])
		if components.is_empty():
			_errors.append("共鸣组 '%s' 没有组件卡 —— 联合卡的前置条件永远无法满足" % key)

		# 同一组的"需要哪些部件"必须完全一致，否则是手写数据打错
		var first_id := ""
		var first_need: Array = []
		for cid in g["needs"].keys():
			if first_id == "":
				first_id = cid
				first_need = g["needs"][cid]
				continue
			if g["needs"][cid] != first_need:
				_errors.append("共鸣组 '%s' 内 '%s' 与 '%s' 的 combo_complete 不一致" % [key, cid, first_id])

		# 同组不允许两个组件卡抢同一个部件名
		var seen: Dictionary = {}
		for c in components:
			var part: String = (c as CardData).combo_part
			if seen.has(part):
				_errors.append("共鸣组 '%s' 内部件 '%s' 被多张组件卡占用（%s / %s）" % [
					key, part, seen[part], (c as CardData).id,
				])
			seen[part] = (c as CardData).id

		# 联合卡的前置条件必须能被本组组件卡全部满足
		for p in payoffs:
			for part in (p as CardData).combo_complete:
				if not seen.has(part):
					_errors.append("联合卡 '%s' 需要部件 '%s'，但本组没有提供该部件的组件卡" % [
						(p as CardData).id, part,
					])


static func _check_monsters(db: GameDatabase) -> void:
	for m in db.monsters.values():
		var mon := m as MonsterData
		if mon.hp <= 0:
			_errors.append("怪物 '%s' 血量必须为正" % mon.id)
		if mon.dungeon_level < 1:
			_errors.append("怪物 '%s' dungeon_level 必须 ≥ 1" % mon.id)
		if mon.monster_tier < 0 or mon.monster_tier > MonsterData.MonsterTier.BOSS:
			_errors.append("怪物 '%s' monster_tier 越界" % mon.id)


static func _check_items(db: GameDatabase) -> void:
	for it in db.items.values():
		var item := it as ItemData
		if item.precious_value < 0 or item.precious_value > 100:
			_errors.append("物品 '%s' precious_value 越界（应在 0–100）" % item.id)
		if item.sell_price < 0:
			_errors.append("物品 '%s' sell_price 为负" % item.id)

		# 装备必须有槽位，非装备必须为 NONE
		if item.item_class == ItemData.ItemClass.EQUIPMENT:
			if item.slot == ItemData.Slot.NONE:
				_errors.append("装备 '%s' 的 slot 不应为 NONE" % item.id)
		else:
			if item.slot != ItemData.Slot.NONE:
				_warnings.append("非装备 '%s' 设置了 slot，将被忽略" % item.id)


static func _check_dungeons(db: GameDatabase) -> void:
	var monster_ids := db.monsters.keys()

	for d in db.dungeons.values():
		var dun := d as DungeonData

		if dun.recommend_power_min > dun.recommend_power_max:
			_errors.append("关卡 '%s' 推荐战力下限大于上限" % dun.id)
		if dun.grid_cols != 3 or dun.grid_rows != 7:
			_warnings.append("关卡 '%s' 网格为 %d×%d，设计规定为 3×7" % [
				dun.id, dun.grid_cols, dun.grid_rows
			])
		if dun.get_total_weight() <= 0:
			_errors.append("关卡 '%s' 节点权重总和为 0" % dun.id)

		var refs: Array[String] = []
		refs.append_array(dun.monster_pool)
		refs.append_array(dun.elite_pool)
		if dun.boss_id != "":
			refs.append(dun.boss_id)

		for r in refs:
			if not monster_ids.has(r):
				_errors.append("关卡 '%s' 引用了不存在的怪物 '%s'" % [dun.id, r])

		if dun.boss_id == "":
			_errors.append("关卡 '%s' 未设置 boss_id" % dun.id)


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

static func _report() -> bool:
	print("========== 数据校验 ==========")
	if _warnings.size() > 0:
		print("警告 %d 条：" % _warnings.size())
		for w in _warnings:
			print("  [WARN] ", w)
	if _errors.size() > 0:
		print("错误 %d 条：" % _errors.size())
		for e in _errors:
			print("  [ERROR] ", e)
		print("========== 校验失败 ==========")
		return false
	print("========== 校验通过 ==========")
	return true


static func get_errors() -> Array[String]:
	return _errors.duplicate()
