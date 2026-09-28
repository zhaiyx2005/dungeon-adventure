## AI 自动对战数据采集（平衡调优）
##
## 用默认队伍 + 默认卡组，自动出牌打各种怪物编成，跑多局统计：
##   胜率 / 平均回合数 / 平均剩余血量 / 是否有人濒死
##
## 目的：定位第 1 层难度是否合理，为 PowerCalculator 调参提供数据。
## 跑法：godot --headless --path <项目> --script res://scripts/_sim_balance.gd
extends SceneTree

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


## 自动打一场，返回 Dictionary：{victory, rounds, hp_left_ratio}
## action_regen：开发期测量用 —— 把「行动点每回合回复量」补到该值
## （正式规则见 Adventurer.ACTION_REGEN_PER_TURN，默认 1）
func _auto_battle(gd: Node, monster_ids: Array, action_regen: int = 1) -> Dictionary:
	var monsters: Array[MonsterData] = []
	for id in monster_ids:
		var m: MonsterData = gd.db.get_monster(id)
		if m != null:
			monsters.append(m)

	var bm := BattleManager.new()
	bm.log_enabled = false  # 模拟对战不刷战斗日志
	bm.setup(gd.team, monsters, gd.deck)
	bm.start()

	var guard := 0
	while bm.result == BattleManager.Result.ONGOING and guard < 200:
		guard += 1
		var acted := false
		for a in bm.team:
			if not a.is_alive():
				continue
			for card in bm.deck.hand.duplicate():
				if not bm.can_play(a, card):
					continue
				var tgt: Variant = null
				if card.card_class == CardData.CardClass.ATTACK:
					if bm.living_monsters().is_empty():
						break
					tgt = bm.living_monsters()[0]
				elif card.has_tag("REVIVE"):
					for t in bm.team:
						if t.is_downed:
							tgt = t
							break
				elif card.heal_multiplier > 0.0 and card.needs_target_card():
					var worst: Adventurer = null
					for t in bm.team:
						if t.is_alive() and t.current_hp < t.get_max_hp():
							if worst == null or t.current_hp < worst.current_hp:
								worst = t
					tgt = worst
				if bm.play_card(a, card, tgt):
					acted = true
					break
		if bm.result != BattleManager.Result.ONGOING:
			break
		if not acted:
			bm.end_player_turn()
			_topup_action(bm, action_regen)

	var victory := bm.result == BattleManager.Result.VICTORY
	var hp_sum := 0
	var hp_max := 0
	for a in bm.team:
		hp_sum += a.current_hp
		hp_max += a.get_max_hp()
	var hp_ratio := 0.0 if hp_max == 0 else float(hp_sum) / float(hp_max)
	return {
		"victory": victory,
		"rounds": bm.turn.round_number,
		"hp_ratio": hp_ratio,
	}


## 跑 N 局统计
func _simulate(gd: Node, monster_ids: Array, n: int, action_regen: int = 1) -> Dictionary:
	var wins := 0
	var rounds_sum := 0
	var hp_sum := 0.0
	for _i in range(n):
		var r := _auto_battle(gd, monster_ids, action_regen)
		if r["victory"]:
			wins += 1
		rounds_sum += int(r["rounds"])
		hp_sum += float(r["hp_ratio"])
	return {
		"total": n,
		"wins": wins,
		"win_rate": float(wins) / float(n),
		"avg_rounds": float(rounds_sum) / float(n),
		"avg_hp_ratio": hp_sum / float(n),
	}


func _run() -> void:
	print("\n===== AI 自动对战数据采集 =====\n")
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("GameData 未注册")
		quit(1)
		return

	print("默认小队战力：%d" % gd.team_power())
	print("默认卡组：%d 张\n" % gd.deck.size())

	var scenarios := [
		{"name": "第1层 单只普通怪(boar)", "ids": ["boar"], "n": 100},
		{"name": "第1层 单只普通怪(goblin)", "ids": ["goblin"], "n": 100},
		{"name": "第1层 2只怪(boar+boar)", "ids": ["boar", "boar"], "n": 100},
		{"name": "第1层 3只怪(boar+cave_bat+goblin)", "ids": ["boar", "cave_bat", "goblin"], "n": 100},
		{"name": "第1层 Boss(boar_king)", "ids": ["boar_king"], "n": 100},
		{"name": "第2层 2只怪(hobgoblin+dire_wolf)", "ids": ["hobgoblin", "dire_wolf"], "n": 100},
		{"name": "第3层 单只精英(troll)", "ids": ["troll"], "n": 100},
	]

	print("%-40s %8s %8s %8s %8s" % ["场景", "胜率", "平均回合", "剩余血比", "样本"])
	print("-".repeat(80))

	for s in scenarios:
		var ids: Array = s["ids"]
		var n: int = s["n"]
		var result := _simulate(gd, ids, n)
		var name: String = s["name"]
		var win_rate: float = result["win_rate"]
		var avg_rounds: float = result["avg_rounds"]
		var avg_hp: float = result["avg_hp_ratio"]
		var total: int = result["total"]
		print("%-40s %7.0f%% %8.1f %8.0f%% %8d" % [
			name,
			win_rate * 100.0,
			avg_rounds,
			avg_hp * 100.0,
			total,
		])

	# ---- 行动点回复量对胜率的影响（9-22 修改意见 7 调参参考）----
	# 正式规则是每回合 +1 行动点，这里额外测几档，供权衡用
	print("\n【行动点每回合回复量 → 第1层 Boss / 3 怪 胜率】")
	print("%-16s %12s %12s" % ["每回合行动点", "Boss 胜率", "3怪 胜率"])
	print("-".repeat(44))
	for regen in [1, 2, 3, 4, 6]:
		var rb := _simulate(gd, ["boar_king"], 60, regen)
		var r3 := _simulate(gd, ["boar", "cave_bat", "goblin"], 60, regen)
		print("%-16s %11.0f%% %11.0f%%" % [
			"+%d 点" % regen,
			float(rb["win_rate"]) * 100.0,
			float(r3["win_rate"]) * 100.0,
		])

	# ---- 行动消耗档位扫描（找合适的 ACTION_COST_MAP） ----
	_sweep_action_cost(gd)

	print("\n===== 采集完成 =====\n")
	quit(0)


## 「顶级」卡（原设计 4/5 行动：旋风斩 / 致命一击 / 连锁闪电 / 群体治愈 / 陨石术）
## 用于测试「只有顶级卡保留 2 点、其余压到 ≤1」的方案
const HEAVY_CARD_IDS := [
	"whirlwind", "assassinate", "chain_lightning", "mass_heal", "meteor",
]


## 调参扫描：行动消耗档位 → 胜率（只改内存里的 CardData，不落盘）
## 用于找到合适的 ACTION_COST_MAP，再回写到 tools/generate_data.py
func _sweep_action_cost(gd: Node) -> void:
	print("\n【行动消耗档位 → 胜率（调参用，仅内存，不落盘）】")
	var snapshot := {}
	for c in gd.db.cards.values():
		snapshot[(c as CardData).id] = (c as CardData).action_cost

	var variants := [
		{"name": "上限压到 1（全 1）", "mode": 2},
		{"name": "仅陨石术 2 点", "mode": 5},
		{"name": "顶级 5 张 2 点", "mode": 4},
		{"name": "现盘（生成器已下调）", "mode": 0},
	]
	for v in variants:
		for c in gd.db.cards.values():
			var card := c as CardData
			var base: int = snapshot[card.id]
			match int(v["mode"]):
				1:
					card.action_cost = maxi(0, base - 1)
				2:
					card.action_cost = mini(1, base)
				3:
					card.action_cost = 0
				4:
					card.action_cost = 2 if HEAVY_CARD_IDS.has(card.id) else mini(1, base)
				5:
					card.action_cost = 2 if card.id == "meteor" else mini(1, base)
				_:
					card.action_cost = base
		var rb := _simulate(gd, ["boar_king"], 60)
		var r2 := _simulate(gd, ["hobgoblin", "dire_wolf"], 60)
		print("  %-22s 第1层Boss %3.0f%%   第2层2怪 %3.0f%%" % [
			v["name"], float(rb["win_rate"]) * 100.0, float(r2["win_rate"]) * 100.0])

	# 还原
	for c in gd.db.cards.values():
		var card := c as CardData
		card.action_cost = int(snapshot[card.id])


## 开发期测量用：把「行动点每回合回复」补到指定值
## （正式规则每回合只 +1，这里给模拟补差额，等价于改回复量）
func _topup_action(bm: BattleManager, regen: int) -> void:
	var extra := regen - Adventurer.ACTION_REGEN_PER_TURN
	if extra <= 0:
		return
	for a in bm.team:
		if a.is_alive():
			a.current_action = mini(a.current_action + extra, a.get_max_action())
