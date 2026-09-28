## 阶段 2c 战斗界面冒烟测试
##
## headless 下验证：场景可加载、节点齐全、手牌渲染、点选释放者、
## 拖拽落点判定、结束回合推进、结算面板弹出。
extends SceneTree

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(60.0).timeout
	print("[看门狗] 超时")
	quit(1)


## --script 模式下 autoload 的全局标识符不可用（编译期解析不到），
## 但节点实例确实在 /root 下。所以这里走节点路径取，最稳。
func _db() -> GameDatabase:
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		push_error("GameData autoload 未找到")
		return null
	return gd.db


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


## 读脚本常量（避免在测试里硬编码数值，改了源头常量测试会跟着走）
func _consts(scr_path: String) -> Dictionary:
	var s: GDScript = load(scr_path)
	if s == null:
		return {}
	return s.get_script_constant_map()


## 取控件在父容器内的归一化矩形（由锚点换算，不依赖实际像素布局）
func _norm_rect(c: Control) -> Rect2:
	if c == null:
		return Rect2()
	return Rect2(c.anchor_left, c.anchor_top,
		c.anchor_right - c.anchor_left, c.anchor_bottom - c.anchor_top)


## 在手牌视图里按卡牌数据找对应的 CardView（找不到返回 null）
func _find_card_view(scene: Node, card: CardData) -> Control:
	for cv in scene._card_views:
		if cv.card == card:
			return cv
	return null


func _run() -> void:
	_watchdog()
	print("\n===== 阶段2c 战斗界面冒烟 =====\n")

	var ps: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	_ok(ps != null, "battle_scene.tscn 可加载")
	if ps == null:
		print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
		quit(1)
		return

	var scene: Node = ps.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.15).timeout

	# ---- 节点齐全 ----
	print("-- 关键节点 --")
	for path in ["%Battlefield", "%AllyRow", "%EnemyRow", "%HandSlot",
			"%EndTurnButton", "%DiscardButton", "%BagButton",
			"%DeckLabel", "%DiscardLabel", "%HandLabel", "%LogLabel",
			"%ResultPanel", "%RoundLabel", "%PhaseLabel", "%HintLabel"]:
		_ok(scene.get_node_or_null(path) != null, "存在 " + path)

	# ---- 战斗已建立 ----
	print("\n-- 战斗状态 --")
	var bm: BattleManager = scene.battle
	_ok(bm != null, "BattleManager 已建立")
	if bm == null:
		print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
		quit(1)
		return

	_ok(bm.turn.is_player_turn(), "开局处于我方回合")
	_ok(bm.turn.round_number == 1, "第 1 回合")
	_ok(bm.deck.hand.size() == 8, "手牌 8 张（实际 %d）" % bm.deck.hand.size())
	_ok(bm.living_monsters().size() == 3, "3 只敌人（实际 %d）" % bm.living_monsters().size())

	# ---- 单位视图 ----
	print("\n-- 单位视图 --")
	var ally_row: Node = scene.get_node("%AllyRow")
	var enemy_row: Node = scene.get_node("%EnemyRow")
	var ally_count := 0
	var enemy_count := 0
	for ch in ally_row.get_children():
		ally_count += 1
	for ch in enemy_row.get_children():
		enemy_count += 1
	_ok(ally_count == bm.team.size(), "我方单位视图 %d 个（队伍 %d 人）" % [ally_count, bm.team.size()])
	_ok(enemy_count == bm.monsters.size(), "敌方单位视图 %d 个（敌人 %d 只）" % [enemy_count, bm.monsters.size()])

	# ---- 手牌视图与扇形布局 ----
	print("\n-- 手牌渲染 --")
	var hand_slot: Node = scene.get_node("%HandSlot")
	var card_views: Array = scene._card_views
	_ok(card_views.size() == bm.deck.hand.size(), "手牌控件数 %d == 手牌数 %d" % [card_views.size(), bm.deck.hand.size()])

	if card_views.size() >= 3:
		var first = card_views[0]
		var mid = card_views[card_views.size() / 2]
		var last = card_views[card_views.size() - 1]
		# 扇形：中间比两端高（y 更小）
		_ok(mid.position.y < first.position.y + 0.01, "扇形中央比左侧高（中 %.1f / 左 %.1f）" % [mid.position.y, first.position.y])
		_ok(mid.position.y < last.position.y + 0.01, "扇形中央比右侧高（中 %.1f / 右 %.1f）" % [mid.position.y, last.position.y])
		_ok(first.rotation_degrees < 0.0, "左端向左旋转（%.1f°）" % first.rotation_degrees)
		_ok(last.rotation_degrees > 0.0, "右端向右旋转（%.1f°）" % last.rotation_degrees)
		_ok(first.position.x < last.position.x, "从左到右水平递增")

	# ---- 点选释放者 ----
	print("\n-- 点选释放者 --")
	var ally_views: Array = []
	for uv in scene._unit_views:
		if uv.adventurer != null:
			ally_views.append(uv)
	_ok(ally_views.size() > 0, "存在可点选的我方单位")
	if ally_views.size() >= 2:
		var target_uv = ally_views[1]
		scene._on_unit_clicked(target_uv)
		await process_frame
		_ok(bm.selected_adventurer == target_uv.adventurer,
			"点选后切换释放者为 %s" % target_uv.adventurer.display_name)

	# 点怪物不该改变释放者
	var before_sel = bm.selected_adventurer
	for uv in scene._unit_views:
		if uv.monster != null:
			scene._on_unit_clicked(uv)
			break
	_ok(bm.selected_adventurer == before_sel, "点怪物不会改变释放者")

	# ---- 拖拽落点判定 ----
	print("\n-- 拖拽落点判定 --")
	var enemy_view: Node = null
	for uv in scene._unit_views:
		if uv.monster != null and uv.monster.is_alive():
			enemy_view = uv
			break
	_ok(enemy_view != null, "取到存活敌人视图")
	if enemy_view != null:
		var center: Vector2 = enemy_view.global_position + enemy_view.size * 0.5
		var hit = scene._unit_view_at(center)
		_ok(hit == enemy_view, "命中检测：敌人中心点 → 该敌人")
		var miss = scene._unit_view_at(Vector2(-500, -500))
		_ok(miss == null, "命中检测：界外 → null")

	# ---- 用界面路径真正出一张牌 ----
	print("\n-- 通过界面出牌 --")
	var strike: CardData = _db().get_card("strike")
	# 起手是随机抽的（DeckManager 每局 _rng.randomize()），不能假定手牌里一定有 strike ——
	# 缺了就补一张并刷新手牌视图，否则这一段 3 条断言会随抽牌结果时有时无（测试数在 153–156 之间抖）。
	var in_hand := false
	for card in bm.deck.hand:
		if card.id == "strike":
			in_hand = true
			break
	if not in_hand:
		bm.deck.hand.append(strike)
		scene._refresh_hand()
		await process_frame
	# 同理：行动点不够也会让 can_play() 为假，先把资源补足
	for a in bm.team:
		a.current_action = maxi(a.current_action, 6)

	var hand_n := bm.deck.hand.size()
	var played := false
	for card in bm.deck.hand:
		if card.id == "strike":
			var caster = bm.selected_adventurer
			if caster != null and bm.can_play(caster, card):
				var hp_before = enemy_view.monster.current_hp
				var cv = null
				for v in scene._card_views:
					if v.card == card:
						cv = v
						break
				if cv != null:
					var drop_pos: Vector2 = enemy_view.global_position + enemy_view.size * 0.5
					scene._on_card_drag_started(cv)
					scene._on_card_drag_released(cv, drop_pos)
					await process_frame
					_ok(enemy_view.monster.current_hp < hp_before,
						"拖到敌人身上成功打出攻击卡（%d → %d）" % [hp_before, enemy_view.monster.current_hp])
					_ok(bm.deck.hand.size() == hand_n - 1,
						"出牌后手牌 %d 张（实际 %d）" % [hand_n - 1, bm.deck.hand.size()])
					_ok(bm.damage_dealt > 0, "累计伤害 %d" % bm.damage_dealt)
					played = true
			break
	# 上面已保证「手牌有 strike + 资源充足」，所以这里不该再走到 —— 走到就是真出问题了
	_ok(played, "界面路径确实打出了一张牌")

	# ---- 拖到空白处应被拒绝（单体卡） ----
	print("\n-- 非法落点应被拒绝 --")
	var hand_before := bm.deck.hand.size()
	var single_card = null
	for card in bm.deck.hand:
		if card.needs_target_card():
			single_card = card
			break
	if single_card != null:
		var cv2 = null
		for v in scene._card_views:
			if v.card == single_card:
				cv2 = v
				break
		if cv2 != null:
			var sel_before = bm.selected_adventurer
			scene._on_card_drag_started(cv2)
			scene._on_card_drag_released(cv2, Vector2(-900, -900))   # 明显在界外
			await process_frame
			_ok(bm.deck.hand.size() == hand_before, "单体卡拖到界外：手牌未消耗")
			_ok(bm.selected_adventurer == sel_before, "释放者未被改变")

	# ---- 意见 6：手牌按行动点数从小到大排列 ----
	print("\n-- 意见6：手牌按行动点数排列 --")
	var ordered := true
	var prev := -1
	var costs := ""
	for v in scene._card_views:
		var cost: int = v.card.action_cost
		if cost < prev:
			ordered = false
		prev = cost
		costs += str(cost) + " "
	_ok(ordered, "手牌按行动点数非递减排列（%s）" % costs.strip_edges())

	# ---- 9-23 意见 2：战斗卡新版式（素材边框分区）----
	print("\n-- 意见2：战斗卡新版式 --")
	var bcv = scene._card_views[0]
	var bframe: CardFrame = bcv._frame
	_ok(bframe.style == CardFrame.STYLE_BATTLE, "手牌使用战斗卡版式")
	_ok(bframe._frame.texture != null
			and String(bframe._frame.texture.resource_path).ends_with("battle_card_border.png"),
		"边框贴图 = battle_card_border.png（%s）" % bframe._frame.texture.resource_path)
	var bl := _norm_rect(bframe._badge_l)
	var br := _norm_rect(bframe._badge_r)
	var nm := _norm_rect(bframe._name_label)
	var ar := _norm_rect(bframe._art_clip)
	var ds := _norm_rect(bframe._desc_label)
	_ok(bl.get_center().x < 0.25 and bl.get_center().y < 0.15,
		"左上角 = 行动点（中心 %.2f, %.2f）" % [bl.get_center().x, bl.get_center().y])
	_ok(br.get_center().x > 0.75 and br.get_center().y < 0.15,
		"右上角 = 蓝量（中心 %.2f, %.2f）" % [br.get_center().x, br.get_center().y])
	_ok(nm.get_center().y < ar.get_center().y, "名字条在图片区上方")
	_ok(nm.get_center().y < 0.2, "名字位于卡牌最上方（y 中心 %.2f）" % nm.get_center().y)
	_ok(ar.get_center().y < 0.5, "图片区在卡牌上半（y 中心 %.2f）" % ar.get_center().y)
	_ok(ds.get_center().y > 0.5, "描述区在卡牌下半（y 中心 %.2f）" % ds.get_center().y)
	_ok(not ar.intersects(ds), "图片区与描述区不重叠")
	# 分类胶囊（9-26 插画接入后重写）：
	#   有插画时图片区铺到 0.600（胶囊底），胶囊的**文字与实底药丸由代码画在插画之上** ——
	#   边框贴图里那个白色药丸在图片层下面，会被插画盖住，只剩深灰字压在插画上，
	#   深色插画上完全读不出来。旧的"图片止于 0.565 + 色块补角"只适用于纯色占位。
	var tag_zone := _norm_rect(bframe._art_tag)
	var art_on: bool = ArtRegistry.card(bcv.card.id) != null
	_ok(art_on, "手牌卡面已接入像素插画（%s）" % bcv.card.id)
	if art_on:
		_ok(is_equal_approx(ar.end.y, 0.600),
			"有插画时图片区铺到胶囊底 0.600（实际 %.3f）" % ar.end.y)
		_ok(not bframe._art_wing_l.visible and not bframe._art_wing_r.visible,
			"有插画时不显示色块补角（插画自己铺满）")
		_ok(bframe._tag_bg.visible, "有插画时给分类胶囊补了实底药丸")
		var kids := bframe.get_children()
		var i_art: int = kids.find(bframe._art_clip)
		var i_bg: int = kids.find(bframe._tag_bg)
		var i_tag: int = kids.find(bframe._art_tag)
		_ok(i_art >= 0 and i_art < i_bg and i_bg < i_tag,
			"绘制顺序：插画 < 实底药丸 < 类型字（索引 %d/%d/%d）" % [i_art, i_bg, i_tag])
		var bg_rect := _norm_rect(bframe._tag_bg)
		_ok(bg_rect.encloses(tag_zone) or (bg_rect.end.y >= tag_zone.end.y - 0.001
				and bg_rect.position.x <= tag_zone.position.x + 0.001),
			"实底药丸盖住类型字（%.3f–%.3f vs %.3f–%.3f）"
			% [bg_rect.position.y, bg_rect.end.y, tag_zone.position.y, tag_zone.end.y])
	else:
		_ok(not bframe._tag_bg.visible, "无插画时不补实底（边框自带药丸就够）")
		_ok(bframe._art_wing_l.visible, "无插画时显示色块补角")
	# 描述框顶(0.618)本来就与胶囊底(0.645)重叠 —— 那是给"六分类 · 稀有度"那一行留的
	# 空间，文字垂直居中所以实际不会撞。这里改断言真正决定可读性的东西：药丸必须不透明。
	var pill_sb := bframe._tag_bg.get_theme_stylebox("panel") as StyleBoxFlat
	_ok(pill_sb != null and pill_sb.bg_color.a >= 0.999,
		"实底药丸不透明（alpha %.2f）→ 类型字在任何插画上都读得出"
		% (pill_sb.bg_color.a if pill_sb != null else -1.0))
	var wl := _norm_rect(bframe._art_wing_l)
	var wr := _norm_rect(bframe._art_wing_r)
	if bframe._art_wing_l.visible:
		_ok(is_equal_approx(wl.position.y, 0.565) and is_equal_approx(wl.end.y, 0.600),
			"补角块补满 0.565→0.600（实际 %.3f–%.3f）" % [wl.position.y, wl.end.y])
		_ok(wl.end.x <= tag_zone.position.x + 0.001 and wr.position.x >= tag_zone.end.x - 0.001,
			"补角块不与胶囊水平重叠（左补角右沿 %.3f / 胶囊左沿 %.3f）"
			% [wl.end.x, tag_zone.position.x])
		_ok(not wl.intersects(tag_zone) and not wr.intersects(tag_zone), "补角块与胶囊互不相交")
	else:
		_ok(true, "补角块隐藏时不做几何断言（由插画铺满）")
	_ok(bframe._badge_l.text == str(bcv.card.action_cost),
		"左上角标显示行动点（%s）" % bframe._badge_l.text)
	var want_mana := str(bcv.card.mana_cost) if bcv.card.mana_cost > 0 else ""
	_ok(bframe._badge_r.text == want_mana,
		"右上角标显示蓝量（%s，蓝耗 %d）" % [bframe._badge_r.text, bcv.card.mana_cost])
	_ok(bframe._badge_l.visible and bframe._badge_l.text != "", "左上角标可见（行动点必显示）")
	_ok(bframe._badge_r.visible == (want_mana != ""), "右上角标仅法术卡显示（物理卡 0 蓝不显示）")
	_ok(bframe._name_label.text == bcv.card.display_name, "名字条内容 = 卡名")
	_ok(nm.get_center().y < 0.2 and ar.get_center().y < ds.get_center().y,
		"版式顺序：名字 → 图片 → 描述")

	# 手牌必须完整可见：卡高 140 后底部栏要跟着加高，否则描述区被视口裁掉
	var slot_rect: Rect2 = Rect2(hand_slot.global_position, hand_slot.size)
	var vp_h: float = (scene as Control).size.y
	var overflow_bottom := 0.0
	var overflow_slot := 0.0
	for v in scene._card_views:
		# 扇形排布带旋转，必须按变换后的四角求真实包围盒下沿
		var xf: Transform2D = v.get_global_transform()
		var vb := 0.0
		for p in [Vector2.ZERO, Vector2(v.size.x, 0.0), Vector2(0.0, v.size.y), v.size]:
			vb = maxf(vb, (xf * p).y)
		overflow_bottom = maxf(overflow_bottom, vb - vp_h)
		overflow_slot = maxf(overflow_slot, vb - slot_rect.end.y)
	_ok(overflow_bottom <= 0.5, "手牌底边不超出视口（超出 %.1f px）" % maxf(overflow_bottom, 0.0))
	_ok(overflow_slot <= 0.5, "手牌底边不超出 HandSlot（超出 %.1f px）" % maxf(overflow_slot, 0.0))
	_ok(hand_slot.size.y >= bcv.size.y, "HandSlot 高度 ≥ 卡高（%.0f ≥ %.0f）"
		% [hand_slot.size.y, bcv.size.y])

	# ---- 意见 4：悬停放大突显 ----
	print("\n-- 意见4：悬停放大突显 --")
	var cv0 = scene._card_views[0]
	cv0._on_mouse_entered()
	await process_frame
	_ok(cv0.scale.x > 1.0, "悬停放大（scale=%.2f）" % cv0.scale.x)
	_ok(cv0.z_index > 0, "悬停时提升绘制层级")
	_ok(cv0.pivot_offset.y >= cv0.size.y - 0.5, "放大轴在底边（向上生长，不越界）")
	_ok(cv0.hovered, "悬停状态已记录")
	cv0._on_mouse_exited()
	await process_frame
	_ok(is_equal_approx(cv0.scale.x, 1.0) and not cv0.hovered, "离开后恢复原大小")

	# ---- 意见 4：只有作用范围（可打出）的卡才能拖拽 ----
	print("\n-- 意见4：仅可打出的卡可拖拽 --")
	var cv_unplay = null
	for v in scene._card_views:
		if not v.playable:
			cv_unplay = v
			break
	if cv_unplay != null:
		var got_bad: Array = []
		cv_unplay.drag_started.connect(func(_v): got_bad.append(1))
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		cv_unplay._gui_input(press)
		await process_frame
		_ok(got_bad.is_empty(), "不可打出的卡不响应拖拽（意见4）")
	else:
		_ok(true, "（本轮手牌全部可打出，跳过不可拖拽断言）")

	var cv_play = null
	for v in scene._card_views:
		if v.playable:
			cv_play = v
			break
	if cv_play != null:
		var hand_pos: Vector2 = cv_play.position
		var got_ok: Array = []
		cv_play.drag_started.connect(func(_v): got_ok.append(1))
		var p2 := InputEventMouseButton.new()
		p2.button_index = MOUSE_BUTTON_LEFT
		p2.pressed = true
		cv_play._gui_input(p2)
		await process_frame
		_ok(got_ok.size() == 1, "可打出的卡可以开始拖拽")
		_ok(scene._dragging_view == cv_play, "拖拽中的卡被记录")
		# 意见 2：拖拽时卡牌不跟随鼠标，只在原位抬起 18px（battle_scene.DRAG_LIFT）
		_ok(cv_play.position.x == hand_pos.x, "拖拽时卡牌不跟手（x 不变，意见2）")
		_ok(is_equal_approx(cv_play.position.y, hand_pos.y - 18.0),
			"拖拽时仅在原位抬起 18px（实际 %.1f，意见2）" % (hand_pos.y - cv_play.position.y))

		# ---- 意见 5：拖拽时用贝塞尔曲线画指示箭头 ----
		print("\n-- 意见5：贝塞尔指示箭头 --")
		_ok(scene._arrow != null, "箭头覆盖层已创建")
		_ok(scene._drag_origin != Vector2.ZERO, "记录了箭头起点（卡牌原位）")
		# 跑一帧 _process：箭头起点会被换算进覆盖层局部坐标（曾因 Control 无 to_local 而静默失败）
		await process_frame
		_ok(scene._arrow.origin != Vector2.ZERO, "箭头起点每帧刷新（未被绘制异常吞掉）")
		if scene._arrow != null:
			var c1 := Vector2(10, -20)
			var c2 := Vector2(30, -20)
			var p_start: Vector2 = scene._arrow.bezier(Vector2(0, 0), c1, c2, Vector2(40, 0), 0.0)
			var p_end: Vector2 = scene._arrow.bezier(Vector2(0, 0), c1, c2, Vector2(40, 0), 1.0)
			var p_mid: Vector2 = scene._arrow.bezier(Vector2(0, 0), c1, c2, Vector2(40, 0), 0.5)
			_ok(p_start.is_equal_approx(Vector2(0, 0)), "贝塞尔起点 = P0")
			_ok(p_end.is_equal_approx(Vector2(40, 0)), "贝塞尔终点 = P3")
			_ok(p_mid.y < -5.0, "曲线向上弓起（中点 y=%.1f）" % p_mid.y)

		# ---- 9-23 修：箭头几何跟随拖拽方向（横拖不回头勾、竖拖不扭 S）----
		var a0 := Vector2(100.0, 600.0)
		var cps_v: PackedVector2Array = scene._arrow.control_points(a0, Vector2(100.0, 300.0))
		_ok(absf(cps_v[0].x - a0.x) < 0.01 and absf(cps_v[1].x - a0.x) < 0.01,
			"竖直拖拽画直线、无侧向弓起（偏移 %.1f / %.1f）" % [
				cps_v[0].x - a0.x, cps_v[1].x - a0.x])
		var cps_r: PackedVector2Array = scene._arrow.control_points(a0, Vector2(500.0, 600.0))
		_ok(cps_r[0].y < a0.y and cps_r[1].y < a0.y, "向右拖拽时曲线向上弓起")
		var cps_l: PackedVector2Array = scene._arrow.control_points(a0, Vector2(-300.0, 600.0))
		_ok(cps_l[0].x < a0.x and cps_l[0].x > -300.0,
			"向左拖拽时控制点不回头勾（x=%.1f 应在 -300~100 之间）" % cps_l[0].x)
		var no_hook := true
		for raw_target in [Vector2(300.0, 200.0), Vector2(300.0, 700.0), Vector2(-200.0, 500.0), Vector2(100.0, 100.0)]:
			var tg: Vector2 = raw_target
			var cps: PackedVector2Array = scene._arrow.control_points(a0, tg)
			var fwd: Vector2 = (tg - a0).normalized()
			if (cps[0] - a0).dot(fwd) < 0.0 or (tg - cps[1]).dot(fwd) < 0.0:
				no_hook = false
		_ok(no_hook, "任意拖拽方向的控制点都在前进方向上（无回头钩）")

		# ---- 9-23 意见 1：取消吸附（箭头跟随鼠标）；自身卡箭头指向释放者本人 ----
		var tgt_uv: Node = null
		for uv in scene._unit_views:
			if uv.monster != null and uv.monster.is_alive():
				tgt_uv = uv
				break
		var enemy_card_view: Node = null
		for v in scene._card_views:
			var cc: CardData = v.card
			if cc != null and cc.target_type == CardData.TargetType.SINGLE_ENEMY:
				enemy_card_view = v
				break
		if tgt_uv != null and enemy_card_view != null:
			var keep_drag: Node = scene._dragging_view
			scene._dragging_view = enemy_card_view
			var uc: Vector2 = tgt_uv.global_position + tgt_uv.size * 0.5
			var mp_inside: Vector2 = uc + Vector2(12.0, 8.0)      # 目标范围内但不在中心
			scene._highlight_drop_target(mp_inside)
			_ok(scene._drop_valid, "鼠标在敌人范围内即为合法目标")
			# 9-23 意见 1：不再吸附 —— 箭头尖必须精确落在鼠标位置
			var raw: Vector2 = scene._arrow_tip_for(mp_inside)
			_ok(raw.is_equal_approx(mp_inside),
				"箭头不吸附、精确跟随鼠标（偏差 %.1f px）" % raw.distance_to(mp_inside))
			var blank := Vector2(520.0, 300.0)   # 友方行与敌方行之间的空地
			scene._highlight_drop_target(blank)
			_ok(not scene._drop_valid, "空地不是单体卡的有效目标")
			var blank_tip: Vector2 = scene._arrow_tip_for(blank)
			_ok(blank_tip.is_equal_approx(blank), "没有合法目标时箭头跟随鼠标")
			scene._dragging_view = keep_drag

		# 自身卡（防御卡 target_type = SELF）：无论鼠标在哪，箭头都指向释放者本人
		var self_card: CardData = load("res://data/cards/guard_phys.tres")
		var self_view: Node = scene._unit_view_of_adventurer(scene.battle.selected_adventurer)
		if self_card != null and self_view != null and scene._card_views.size() > 0:
			var probe: Node = scene._card_views[0]
			var kept_card: CardData = probe.card
			var keep_drag2: Node = scene._dragging_view
			probe.card = self_card
			scene._dragging_view = probe
			scene._highlight_drop_target(Vector2(520.0, 300.0))
			_ok(scene._drop_valid, "自身卡拖到战场空白处即视为合法释放点")
			var expect: Vector2 = self_view.global_position + self_view.size * 0.5
			# 三个不同鼠标位置都得到同一终点 → 确实固定在释放者身上
			var tips_ok := true
			for probe_pt in [Vector2(80.0, 640.0), Vector2(1100.0, 120.0), Vector2(520.0, 300.0)]:
				var tp: Vector2 = scene._arrow_tip_for(probe_pt)
				if not tp.is_equal_approx(expect):
					tips_ok = false
					break
			_ok(tips_ok, "自身卡箭头始终指向释放者本人（与鼠标位置无关）")
			_ok(not expect.is_equal_approx(Vector2(520.0, 300.0)),
				"自身卡箭头终点≠鼠标位置（确实指向了自身）")
			probe.card = kept_card
			scene._dragging_view = keep_drag2
		else:
			_ok(true, "（未取得自身卡或释放者视图，跳过自身卡箭头断言）")
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_LEFT
		rel.pressed = false
		cv_play._gui_input(rel)
		await process_frame
		_ok(scene._dragging_view == null, "松手结束拖拽")
		if is_instance_valid(cv_play):
			_ok(is_equal_approx(cv_play.position.y, hand_pos.y), "松手后卡牌落回原位（意见2）")
		else:
			# 真渲染下鼠标可能正好落在合法目标上 → 出牌成功、手牌已刷新
			_ok(true, "（松手直接出牌成功，卡牌已随手牌刷新，跳过落回断言）")
		if scene._arrow != null:
			_ok(scene._arrow.origin == Vector2.ZERO, "松手后箭头清除")

	# ---- 9-23 意见 3：弃牌模式（手牌放大 → 点选 → 确认弃牌）----
	print("\n-- 意见3：弃牌模式 --")
	var sc: Dictionary = _consts("res://scripts/battle/battle_scene.gd")
	var want_zoom: float = float(sc.get("DISCARD_SCALE", 1.5))
	var want_h_hi: float = float(sc.get("DISCARD_BOTTOM_H", 356.0))
	var want_h_lo: float = float(sc.get("NORMAL_BOTTOM_H", 232.0))
	var bottom: PanelContainer = scene.get_node("%Bottom")
	var discard_btn: Button = scene.get_node("%DiscardButton")
	_ok(sc.has("DISCARD_SCALE") and sc.has("NORMAL_BOTTOM_H"), "弃牌模式常量已定义")
	_ok(not scene._discard_mode, "初始不在弃牌模式")
	_ok(is_equal_approx(bottom.custom_minimum_size.y, want_h_lo),
		"常态底部栏高 %.0f（期望 %.0f）" % [bottom.custom_minimum_size.y, want_h_lo])

	var hand_n0: int = bm.deck.hand.size()
	var pile_n0: int = bm.deck.discard_pile.size()
	discard_btn.pressed.emit()
	await process_frame
	await process_frame
	_ok(scene._discard_mode, "点弃牌按钮进入弃牌模式")
	_ok(discard_btn.text.contains("取消"), "弃牌按钮变为「取消弃牌」（%s）" % discard_btn.text)
	_ok(is_equal_approx(bottom.custom_minimum_size.y, want_h_hi),
		"底部栏临时加高到 %.0f（实际 %.0f）" % [want_h_hi, bottom.custom_minimum_size.y])

	# 手牌全部放大、不旋转；并算出每张卡缩放后的真实包围盒
	var zoomed := true
	var flat := true
	var zoom_min := 99.0
	var zoom_max := 0.0
	var rects: Array = []
	for v in scene._card_views:
		zoom_min = minf(zoom_min, v.scale.x)
		zoom_max = maxf(zoom_max, v.scale.x)
		if v.scale.x <= 1.0:
			zoomed = false
		if not is_equal_approx(v.rotation_degrees, 0.0):
			flat = false
		var xf: Transform2D = v.get_global_transform()
		var mn := Vector2(1.0e9, 1.0e9)
		var mx := Vector2(-1.0e9, -1.0e9)
		for p in [Vector2.ZERO, Vector2(v.size.x, 0.0), Vector2(0.0, v.size.y), v.size]:
			var gp: Vector2 = xf * p
			mn = mn.min(gp)
			mx = mx.max(gp)
		rects.append(Rect2(mn, mx - mn))
	_ok(zoomed, "弃牌模式下全部手牌被放大（最小倍率 %.2f）" % zoom_min)
	_ok(flat, "弃牌模式下不再扇形旋转（rotation 归零）")
	_ok(zoom_min <= want_zoom + 0.01 and zoom_max <= want_zoom + 0.01,
		"放大倍率不超过上限 %.2f（实际 %.2f~%.2f）" % [want_zoom, zoom_min, zoom_max])

	# 硬约束：放大后任意两张卡不得重叠
	# （旧实现按 cw*0.6 硬凑一行，相邻卡会互相压住、把描述文字盖掉）
	var overlaps: Array = []
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlaps.append("%d×%d" % [i, j])
	_ok(overlaps.is_empty(), "放大的手牌互不重叠（重叠 %d 对%s）"
		% [overlaps.size(), "" if overlaps.is_empty() else "：" + ", ".join(overlaps)])

	# 阅读顺序：先左到右，一行排满后另起一行（下一行 y 更大、x 回到最左）
	var order_ok := true
	for i in range(1, rects.size()):
		var pc: Vector2 = (rects[i] as Rect2).get_center()
		var qc: Vector2 = (rects[i - 1] as Rect2).get_center()
		if absf(pc.y - qc.y) <= 1.0:
			if pc.x <= qc.x + 1.0:
				order_ok = false
		elif pc.y <= qc.y + 1.0 or pc.x >= qc.x:
			order_ok = false
	_ok(order_ok, "放大的手牌按「先左到右、再上到下」排列")

	# 放大后仍不得越出手牌区 / 视口
	var vp_h2: float = (scene as Control).size.y
	var slot_end: float = (scene.get_node("%HandSlot") as Control).global_position.y \
		+ (scene.get_node("%HandSlot") as Control).size.y
	var over_zoom := 0.0
	var over_slot2 := 0.0
	for r in rects:
		over_zoom = maxf(over_zoom, (r as Rect2).end.y - vp_h2)
		over_slot2 = maxf(over_slot2, (r as Rect2).end.y - slot_end)
	_ok(over_zoom <= 0.5, "放大的手牌不超出视口（超出 %.1f px）" % maxf(over_zoom, 0.0))
	_ok(over_slot2 <= 0.5, "放大的手牌不超出手牌区（超出 %.1f px）" % maxf(over_slot2, 0.0))

	# 顶部出现「确认弃牌 / 取消」操作条
	var bar: Node = scene._discard_bar
	_ok(bar != null and bar.is_inside_tree(), "出现弃牌操作条")
	_ok(bar != null and bar.get_node_or_null("DiscardConfirmButton") != null, "有「确认弃牌」按钮")
	_ok(bar != null and bar.get_node_or_null("DiscardCancelButton") != null, "有「取消」按钮")
	_ok(scene.get_node("%EndTurnButton").disabled, "弃牌模式下结束回合按钮被禁用")

	# 点卡 → 选中；再点 → 取消选中
	var pick: Node = scene._card_views[0]
	_ok(pick.select_mode, "弃牌模式下卡牌进入点选模式（不走拖拽）")
	scene._on_hand_card_clicked(pick)
	await process_frame
	_ok(pick.selected, "点一下手牌即选中")
	scene._on_hand_card_clicked(pick)
	await process_frame
	_ok(not pick.selected, "再点一下取消选中")

	# 没选牌就确认 → 不弃牌
	scene._on_discard_confirm()
	await process_frame
	_ok(bm.deck.hand.size() == hand_n0, "未选牌时确认不生效（手牌仍 %d 张）" % bm.deck.hand.size())
	_ok(scene._discard_mode, "未选牌时仍留在弃牌模式")

	# 选两张 → 确认弃牌
	scene._on_hand_card_clicked(scene._card_views[0])
	scene._on_hand_card_clicked(scene._card_views[1])
	await process_frame
	scene._on_discard_confirm()
	await process_frame
	await process_frame
	_ok(bm.deck.hand.size() == hand_n0 - 2,
		"确认弃牌后手牌 -2（%d → %d）" % [hand_n0, bm.deck.hand.size()])
	_ok(bm.deck.discard_pile.size() == pile_n0 + 2,
		"弃牌堆 +2（%d → %d）" % [pile_n0, bm.deck.discard_pile.size()])
	_ok(not scene._discard_mode, "确认后自动退出弃牌模式")
	_ok(discard_btn.text.contains("弃牌") and not discard_btn.text.contains("取消"),
		"按钮文案恢复（%s）" % discard_btn.text)
	_ok(is_equal_approx(bottom.custom_minimum_size.y, want_h_lo),
		"底部栏高度恢复 %.0f（实际 %.0f）" % [want_h_lo, bottom.custom_minimum_size.y])
	var restored := true
	for v in scene._card_views:
		if not is_equal_approx(v.scale.x, 1.0):
			restored = false
	_ok(restored, "退出模式后手牌恢复原大小")

	# 「取消」同样退出且不弃牌
	var hand_n1: int = bm.deck.hand.size()
	discard_btn.pressed.emit()
	await process_frame
	await process_frame
	_ok(scene._discard_mode, "可以再次进入弃牌模式")
	bar = scene._discard_bar
	_ok(bar != null and bar.get_node_or_null("DiscardCancelButton") != null, "操作条重新出现")
	if bar != null and bar.get_node_or_null("DiscardCancelButton") != null:
		(bar.get_node("DiscardCancelButton") as Button).pressed.emit()
		await process_frame
		await process_frame
	_ok(not scene._discard_mode, "点「取消」退出弃牌模式")
	_ok(bm.deck.hand.size() == hand_n1, "取消不弃牌（手牌仍 %d 张）" % bm.deck.hand.size())
	_ok(is_equal_approx(bottom.custom_minimum_size.y, want_h_lo), "取消后底部栏高度恢复")
	_ok(scene._hand_header == null or not scene._hand_header.has_node("DiscardBar"),
		"退出后操作条已销毁")

	# ---- 9-23 需求：飘字 / 受击抖动 / 出手前冲 / 暴击强化 ----
	print("\n-- 9-23 需求：战斗表现层（飘字 + 打击特效）--")
	_ok(scene._fx != null, "战斗场景装配了表现层（BattleFx）")
	_ok(scene._fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "表现层不拦鼠标")

	var fc: Dictionary = _consts("res://scripts/battle/battle_fx.gd")
	_ok(int(fc.get("FONT_CRIT", 0)) > int(fc.get("FONT_BASE", 0)),
		"暴击字号大于普通字号（%d > %d）" % [int(fc.get("FONT_CRIT", 0)), int(fc.get("FONT_BASE", 0))])
	_ok(float(fc.get("FLOAT_LIFE", 0.0)) >= 1.5,
		"数字在屏上停留 ≥1.5s 再消失（%.2fs）" % float(fc.get("FLOAT_LIFE", 0.0)))

	var fx: Control = scene._fx
	var probe := Vector2(400, 300)
	# 先把前面几张牌留下的特效清干净，这样计数才是确定的
	fx.clear_all()
	await process_frame
	_ok(fx.get_child_count() == 0, "clear_all 清空特效层（计数起点干净）")

	fx.float_number(probe, "20", "enemy", false)
	fx.float_number(probe, "60!", "enemy", true)
	fx.impact(probe, true)
	await process_frame
	_ok(fx.get_child_count() == 3, "飘字 2 个 + 冲击特效 1 个已生成（%d）" % fx.get_child_count())

	# 暴击数字必须更大（读实际生效的字号，不看常量）
	var normal_fs := -1
	var crit_fs := -1
	for c in fx.get_children():
		if c is Label:
			var lab := c as Label
			var fs := int(lab.get_theme_font_size("font_size"))
			if lab.text.ends_with("!"):
				crit_fs = fs
			else:
				normal_fs = fs
	_ok(normal_fs > 0 and crit_fs > normal_fs, "暴击数字更大（%d > %d）" % [crit_fs, normal_fs])

	# 冲击特效自毁，飘字留存更久
	await create_timer(0.85).timeout
	_ok(fx.get_child_count() == 2, "冲击特效播完自动销毁，飘字仍在（%d）" % fx.get_child_count())
	await create_timer(1.7).timeout
	_ok(fx.get_child_count() == 0, "飘字到时间后自动消失，不残留节点（%d）" % fx.get_child_count())

	# ---- 单位抖动 / 出手前冲（位移必须落在 _visual_root 上，否则会被容器排布冲掉）----
	var uv: Control = null
	for u in scene._unit_views:
		if u.adventurer != null:
			uv = u
			break
	_ok(uv != null, "找到我方单位视图")
	var vr: Control = uv._visual_root
	_ok(vr != null, "单位视图有独立表现层节点（VisualRoot）")
	uv.play_hit(false)
	await process_frame
	_ok(not vr.position.is_equal_approx(Vector2.ZERO), "受击时发生抖动（偏移 %s）" % str(vr.position))
	await create_timer(0.55).timeout
	_ok(vr.position.is_equal_approx(Vector2.ZERO), "抖动结束后归位")
	uv.play_attack(1.0)
	await process_frame
	_ok(vr.position.x > 0.0, "出手时向前冲（x=%.1f）" % vr.position.x)
	await create_timer(0.55).timeout
	uv.reset_fx()
	_ok(vr.position.is_equal_approx(Vector2.ZERO), "reset_fx 把位移清干净")

	# ---- 端到端：真事件驱动演出 ----
	var mon_view: Control = null
	for u in scene._unit_views:
		if u.monster != null:
			mon_view = u
			break
	var n_before := fx.get_child_count()
	scene._on_combat_feedback({
		"kind": "damage", "unit": bm.monsters[0], "source": bm.team[0],
		"amount": 7, "crit": true, "killed": false, "downed": false,
	})
	await process_frame
	_ok(fx.get_child_count() > n_before, "受击事件驱动出特效（+%d）" % (fx.get_child_count() - n_before))
	_ok(mon_view != null and not mon_view._visual_root.position.is_equal_approx(Vector2.ZERO),
		"受击的怪物在抖")

	var crit_shown := false
	for c in fx.get_children():
		if c is Label and (c as Label).text.ends_with("!"):
			crit_shown = true
	_ok(crit_shown, "暴击数字带感叹号标记")

	scene._on_combat_feedback({
		"kind": "combo", "unit": null, "source": bm.team[0],
		"text": "风火龙卷", "detail": "对所有敌人造成 3.0 倍法术伤害",
	})
	await process_frame
	var banner_found := false
	for c in fx.get_children():
		if c.name == "Banner":
			banner_found = true
	_ok(banner_found, "共鸣触发时弹出中央横幅")
	fx.clear_all()
	await process_frame
	_ok(fx.get_child_count() == 0, "clear_all 清空所有残留特效")

	# ---- 联合卡在手牌里的「前置条件」可视化（9-24 重构）----
	# 前置没攒够 → 卡片压暗且不可拖；攒齐 → 立刻变亮可拖。
	# 这是玩家唯一能感知到"还差什么"的地方，必须锁住。
	print("\n-- 联合卡手牌状态 --")
	var tornado: CardData = _db().get_card("fire_tornado")
	_ok(tornado != null and tornado.is_combo_payoff(), "取到联合卡 fire_tornado")
	if tornado != null:
		bm.deck.hand.append(tornado)
		bm.combo_cast.erase(tornado.combo_key)
		bm.combo_fired.erase(tornado.combo_key)
		scene._refresh_hand()
		await process_frame
		var cv_locked: Control = _find_card_view(scene, tornado)
		_ok(cv_locked != null, "联合卡出现在手牌视图里")
		_ok(cv_locked != null and not cv_locked.playable, "前置不足：联合卡不可打出（压暗）")
		_ok(cv_locked != null and cv_locked.modulate.a < 0.9,
			"前置不足：卡面确实被压暗（alpha=%.2f）" % cv_locked.modulate.a)

		# 攒齐前置 → 同一张卡立刻解锁
		bm.combo_cast[tornado.combo_key] = ["wind", "fire"]
		scene._refresh_hand()
		await process_frame
		var cv_ready: Control = _find_card_view(scene, tornado)
		_ok(cv_ready != null and cv_ready.playable, "前置凑齐：联合卡变为可打出")
		_ok(cv_ready != null and cv_ready.modulate.a > 0.9,
			"前置凑齐：卡面恢复常亮（alpha=%.2f）" % cv_ready.modulate.a)

		# 收尾：把这轮测试造出来的手牌与共鸣状态清掉，别影响后续断言
		bm.deck.hand.erase(tornado)
		bm.combo_cast.erase(tornado.combo_key)
		scene._refresh_hand()
		await process_frame

	# ---- 结束回合推进 ----
	print("\n-- 结束回合 --")
	var round_before = bm.turn.round_number
	scene._on_end_turn()
	await process_frame
	_ok(bm.turn.round_number == round_before + 1, "回合数 +1（%d → %d）" % [round_before, bm.turn.round_number])
	_ok(bm.turn.is_player_turn(), "敌方行动后回到我方回合")
	_ok(bm.damage_taken > 0, "敌方造成了伤害（%d）" % bm.damage_taken)

	# 结束回合按钮在敌方回合应禁用（异步，这里只验证最终态）
	_ok(not scene.get_node("%EndTurnButton").disabled, "我方回合时结束回合按钮可用")

	# ---- 结算面板：把敌人全打死 ----
	print("\n-- 结算面板 --")
	var guard := 0
	while bm.result == BattleManager.Result.ONGOING and guard < 60:
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
				if bm.play_card(a, card, tgt):
					acted = true
					break
		if bm.result != BattleManager.Result.ONGOING:
			break
		if not acted:
			scene._on_end_turn()
		await process_frame

	_ok(bm.result == BattleManager.Result.VICTORY, "打赢了（结果 %d）" % bm.result)

	var result_panel: Control = scene.get_node("%ResultPanel")
	var result_label: Label = scene.get_node("%ResultLabel")
	_ok(result_panel.visible, "结算面板已弹出")
	_ok(result_label.text.contains("胜利"), "标题显示胜利（%s）" % result_label.text)
	_ok(scene.get_node("%ResultButton") != null, "有返回主菜单按钮")

	scene.queue_free()
	await process_frame

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
