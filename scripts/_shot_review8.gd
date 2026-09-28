## 9-24 修改意见 3 复核截图（真实渲染）
##   A. 卡组整备：持有卡池自动换行，不再需要左右拖动
##   B. 联合卡体系卡面放大（4 组件 + 2 联合卡本体）
##   C. 出征准备面板：1–5 层阶梯（未通关锁定 → 通关后解锁）
##   D. 战斗内：联合卡前置不足（压暗）/ 齐备（常亮）/ 发动横幅
## 跑法：python godot_run.py _shot_review8.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"
const COMBO_CARDS := ["rune_wind", "rune_fire", "fire_tornado",
	"rune_frost", "rune_thunder", "frost_thunder"]


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("截图失败：拿不到 viewport 图像")
		return
	print("截图已保存 -> %s (err=%d)" % [path, img.save_png(path)])


func _run() -> void:
	await create_timer(0.5).timeout

	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("拿不到 GameData")
		quit(1)
		return
	gd.gold = 5000

	print("\n-- 联合卡体系数据 --")
	for cid in COMBO_CARDS:
		var c: CardData = gd.db.get_card(cid)
		print("  %-13s %s 行动%d 蓝%d 倍率%.1f 部件=%-8s 前置%s payoff=%s"
			% [cid, c.get_combo_hint_cn(), c.action_cost, c.mana_cost,
				c.combo_multiplier, c.combo_part if c.combo_part != "" else "-",
				str(c.combo_complete), str(c.is_combo_payoff())])

	# 让卡池里有这些卡，方便卡组整备界面看得见
	for cid in COMBO_CARDS:
		gd.add_owned_card(gd.db.get_card(cid))

	# ---------- A. 城镇：卡组整备卡池自动换行 ----------
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(0.9).timeout
	var town: Node = current_scene

	town._switch_tab(1)
	await create_timer(0.3).timeout
	town._on_open_deck()
	await create_timer(0.4).timeout
	var town_scroll: ScrollContainer = town.get_node("%Scroll")
	print("\n卡组整备：整页横向滚动模式 = %s（%d=DISABLED）"
		% [str(town_scroll.horizontal_scroll_mode), ScrollContainer.SCROLL_MODE_DISABLED])
	await _shot(OUT + "rev8_deck_pool.png")
	town._on_close_deck()
	await create_timer(0.2).timeout

	# ---------- C. 出征准备面板：层级阶梯 ----------
	# 先造"一次都没通关"的状态
	gd.cleared_levels.clear()
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(0.9).timeout
	var rs: Node = current_scene
	rs._on_prep_tab("overview")
	await create_timer(0.35).timeout
	await _shot(OUT + "rev8_ladder_locked.png")

	# 再模拟"已通关第 1、2 层"
	gd.mark_level_cleared(1)
	gd.mark_level_cleared(2)
	rs._refresh_prep()
	await create_timer(0.35).timeout
	await _shot(OUT + "rev8_ladder_unlocked.png")

	# ---------- D. 战斗内：联合卡的前置闸门 ----------
	# 8 张牌的小卡组 → 进战斗必全在手上（FIRST_DRAW = 8）
	var deck: Array[CardData] = []
	for cid in COMBO_CARDS:
		deck.append(gd.db.get_card(cid))
	deck.append(gd.db.get_card("strike"))
	deck.append(gd.db.get_card("guard_phys"))
	gd.deck = deck
	gd.pending_encounter = {"monster_ids": ["boar", "cave_bat", "boar"], "node_type": "battle"}
	gd.return_scene = "res://scenes/dungeon/run_scene.tscn"

	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.0).timeout
	var bs: Node = current_scene
	var bm: BattleManager = bs.battle
	var caster: Adventurer = bm.selected_adventurer
	caster.current_mana = maxi(caster.get_max_mana(), 120)
	caster.current_action = 9
	bm._emit_state()
	await create_timer(0.3).timeout

	var tornado: CardData = gd.db.get_card("fire_tornado")
	print("\n战场：联合卡前置就绪 = %s（应为 false）" % str(bm.combo_ready(tornado)))
	await _shot(OUT + "rev8_payoff_locked.png")

	# 真出两张组件（走 BattleManager 的正规路径）
	bm.play_card(caster, gd.db.get_card("rune_wind"), null)
	bm.play_card(caster, gd.db.get_card("rune_fire"), null)
	await create_timer(0.35).timeout
	print("战场：出完风火组件后前置就绪 = %s（应为 true）" % str(bm.combo_ready(tornado)))
	print("战场：槽内部件 = %s" % str(bm.combo_parts_of("fire_tornado")))
	await _shot(OUT + "rev8_payoff_ready.png")

	# 发动联合卡 → 横幅 + 飘字 + 抖动
	bm.play_card(caster, tornado, null)
	await create_timer(0.25).timeout
	await _shot(OUT + "rev8_combo_fired.png")
	await create_timer(0.6).timeout
	await _shot(OUT + "rev8_combo_after.png")
	print("战场：发动后槽 = %s，已发动标记 = %s"
		% [str(bm.combo_parts_of("fire_tornado")), str(bm.combo_fired_of("fire_tornado"))])

	# ---------- B. 联合卡体系卡面放大 ----------
	var bg := ColorRect.new()
	bg.color = Color("#3b3a36")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 坑：战斗表现层（fx）的 z_index 是 120，而 z_index 在同一个 canvas 里是全局排序的，
	#     只靠"后 add_child"盖不住它 —— 必须显式给它一个更高的 z，否则横幅/飘字会渗进卡面图。
	bg.z_index = 400
	root.add_child(bg)

	var title := Label.new()
	title.text = "共鸣体系：4 张组件卡（左四）+ 2 张联合卡本体（右二）"
	title.position = Vector2(24, 10)
	bg.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 42.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(row)

	for cid in COMBO_CARDS:
		var c: CardData = gd.db.get_card(cid)
		if c == null:
			continue
		var cf := CardFrame.new()
		cf.custom_minimum_size = Vector2(160, 224)
		# 坑：HBox/VBox 默认把子节点纵向拉满 → 卡面被拉长，量出来的分区比例全是错的
		cf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cf.style = CardFrame.STYLE_BATTLE
		row.add_child(cf)
		await process_frame
		var cat: String = c.get_category_name_cn()
		var tag_text := cat
		if c.is_combo_component():
			tag_text = "共鸣"
		elif c.is_combo_payoff():
			tag_text = "联合"
		var head := "%s · %s" % [cat, c.get_rarity_name_cn()]
		if c.has_combo():
			head = c.get_combo_hint_cn()
		cf.setup(c.display_name, "%s\n%s" % [head, c.description],
			Color(c.art_placeholder),
			{
				"style": CardFrame.STYLE_BATTLE,
				"tag": tag_text,
				"badge_l": "%d" % c.action_cost,
				"badge_r": "%d" % c.mana_cost if c.mana_cost > 0 else "",
			})
		print("卡面 %-13s tag=%s 首行=%s" % [cid, tag_text, head])

	await create_timer(0.4).timeout
	await _shot(OUT + "rev8_cardface.png")

	print("9-24 复核截图完成")
	quit(0)
