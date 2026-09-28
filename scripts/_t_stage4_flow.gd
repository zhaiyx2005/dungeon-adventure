## 阶段 4d 城镇链路测试（9-22 修改意见重构版）
##
## 覆盖：主菜单（右侧小队详情已删）→ 城镇各标签 → 工会 4 选项
## （任务木板 / 招募木板 / 组建队伍 / 伟业升级）→ 卡组子界面 → 返回。
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


func _wait_scene(timeout: float = 3.0) -> Node:
	var t := 0.0
	while t < timeout:
		var cur := current_scene
		if cur != null:
			return cur
		await process_frame
		t += 0.016
	return null


func _find_btn(root: Node, text: String, exact: bool = true) -> Button:
	if root is Button:
		var b := root as Button
		if (exact and b.text == text) or (not exact and b.text.contains(text)):
			return b
	for ch in root.get_children():
		var found := _find_btn(ch, text, exact)
		if found != null:
			return found
	return null


func _count_frames(root: Node) -> int:
	var n := 0
	if root is CardFrame:
		n += 1
	for ch in root.get_children():
		n += _count_frames(ch)
	return n


## 取控件由锚点换算的归一化矩形（不依赖实际像素布局）
func _norm_rect(c: Control) -> Rect2:
	if c == null:
		return Rect2()
	return Rect2(c.anchor_left, c.anchor_top,
		c.anchor_right - c.anchor_left, c.anchor_bottom - c.anchor_top)


## 收集落在某一区域内的**可见且有文字**的 Label（用来硬断言"这块区域不许有字"）
func _labels_in(root: Control, zone: Rect2, out: Array) -> void:
	for ch in root.get_children():
		if ch is Label:
			var lb := ch as Label
			if lb.visible and lb.text.strip_edges() != "" and _norm_rect(lb).intersects(zone):
				out.append(lb.text.replace("\n", " "))
		if ch is Control:
			_labels_in(ch as Control, zone, out)


## 9-23 修改意见 4：任务木板改用纯色圆角块（不再是卡牌边框），按底色统计块数
func _count_color_blocks(root: Node, color: Color) -> int:
	var n := 0
	if root is PanelContainer:
		var sb: StyleBox = (root as PanelContainer).get_theme_stylebox("panel")
		var flat := sb as StyleBoxFlat
		if flat != null and flat.bg_color.is_equal_approx(color):
			n += 1
	for ch in root.get_children():
		n += _count_color_blocks(ch, color)
	return n


func _run() -> void:
	_watchdog()
	print("\n===== 阶段4d 城镇链路测试（重构版） =====\n")

	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		_quit()
		return

	# ---- 主菜单：右侧小队详情已删，5 个城镇入口仍在 ----
	change_scene_to_file("res://scenes/main_menu.tscn")
	var menu: Node = await _wait_scene()
	await process_frame
	var menu_box: Node = menu.get_node_or_null("%MenuBox")
	var town_btns: Array = []
	if menu_box != null:
		for ch in menu_box.get_children():
			if ch is Button and (ch.text == "冒险者工会" or ch.text == "作战整备" or ch.text == "商店" or ch.text == "仓库" or ch.text == "卡牌大全"):
				town_btns.append(ch)
	_ok(town_btns.size() == 5, "主菜单 5 个城镇入口按钮已启用")
	_ok(menu.get_node_or_null("%ToastLabel") != null, "主菜单保留底部提示标签（状态栏已按意见2移除）")
	_ok(menu.get_node_or_null("%GoldLabel") != null, "主菜单保留金币显示")
	# 意见2：金币应在右上角、菜单应居中
	var gl: Label = menu.get_node_or_null("%GoldLabel")
	if gl != null:
		_ok(gl.global_position.x > 640.0, "金币显示位于画面右半边（右上角）")
	var menu_vbox: Node = menu.get_node_or_null("%MenuBox")
	if menu_vbox != null:
		var c: float = menu_vbox.global_position.x + menu_vbox.size.x * 0.5
		_ok(absf(c - 640.0) < 80.0, "菜单横向居中（中心 x=%.0f）" % c)

	# 点「商店」进城镇
	var shop_btn: Button = null
	for b in town_btns:
		if b.text == "商店":
			shop_btn = b
	_ok(shop_btn != null and not shop_btn.disabled, "商店按钮可用")
	shop_btn.pressed.emit()
	await process_frame
	var town: Node = await _wait_scene()
	await process_frame
	await process_frame
	_ok(town != null and town.get_node_or_null("%Tabs") != null, "进入城镇场景")
	_ok(gd.pending_initial_tab == "", "初始标签页参数已消费")

	# 商店标签应已选中（新 TABS：工会0/整备1/商店2/仓库3/大全4）
	_ok(town._current_tab == 2, "初始落在商店标签（实际 %d）" % town._current_tab)
	_ok(town.get_node("%GoldLabel").text.contains(str(gd.gold)), "金币显示一致")
	var shop_frames := _count_frames(town.get_node("%Content"))
	_ok(shop_frames >= 4, "商店商品以卡牌显示（%d 张）" % shop_frames)
	# 意见 8：商店同时卖战斗卡
	_ok(town.town.shop_cards.size() >= 1, "商店有在售卡牌（%d 张）" % town.town.shop_cards.size())
	_ok(_find_btn(town.get_node("%Content"), "买卡", false) != null, "商店有「买卡」按钮（意见8）")
	_ok(_find_btn(town.get_node("%Content"), "刷新商品", false) != null, "商店有「刷新商品」按钮")
	# 意见 8：刷新按钮必须在商品列表之前
	var refresh_idx := -1
	var first_card_idx := -1
	var kids: Array = town.get_node("%Content").get_children()
	for i in range(kids.size()):
		if refresh_idx < 0 and _find_btn(kids[i], "刷新商品", false) != null:
			refresh_idx = i
		if first_card_idx < 0 and _count_frames(kids[i]) > 0:
			first_card_idx = i
	_ok(refresh_idx >= 0 and first_card_idx >= 0 and refresh_idx < first_card_idx,
		"商店「刷新商品」按钮位于最上面（位置 %d < 商品 %d，意见8）" % [refresh_idx, first_card_idx])

	# ---- 切换各标签 ----
	var tab_names := ["冒险者工会", "作战整备", "商店", "仓库", "卡牌大全"]
	for i in range(5):
		town._switch_tab(i)
		await process_frame
		_ok(town._current_tab == i, "切到「%s」标签" % tab_names[i])

	# ---- 工会主页：4 选项 + 小队人物卡 ----
	town._switch_tab(0)
	await process_frame
	_ok(town._guild_mode == "home", "工会默认主页")
	for opt in ["接取任务", "招募成员", "组建队伍", "伟业升级"]:
		_ok(_find_btn(town.get_node("%Content"), opt) != null, "工会选项「%s」存在" % opt)
	var squad_frames := _count_frames(town.get_node("%Content"))
	_ok(squad_frames >= gd.team.size(), "选项下方显示小队成员人物卡（%d 张）" % squad_frames)

	# ---- 招募木板：点招募 → 卡池 +1 ----
	# 先给足金币并追加一个保底金钱候选（候选 30% 概率全为收集品类型会必然无可点按钮）
	gd.gold = 10000
	var m: Dictionary = town.town.roll_recruit_candidate()
	while str(m.get("collectible_id", "")) != "":
		m = town.town.roll_recruit_candidate()
	m["price"] = 100
	town._recruit_candidates.append(m)
	town._on_guild_mode("recruit")
	await process_frame
	_ok(town._guild_mode == "recruit", "进入招募木板")
	var recruit_btn := _find_btn(town.get_node("%Content"), "招募", false)
	recruit_btn = null
	for b in _all_buttons(town.get_node("%Content")):
		if b.text == "招募" and not b.disabled:
			recruit_btn = b
			break
	_ok(recruit_btn != null, "找到可用的招募按钮")
	if recruit_btn != null:
		var roster_before: int = gd.roster.size()
		recruit_btn.pressed.emit()
		await process_frame
		_ok(gd.roster.size() == roster_before + 1, "点招募后卡池 +1")

	# ---- 组建队伍：主角锁 + 换位 ----
	town._on_guild_mode("team")
	await process_frame
	_ok(town._guild_mode == "team", "进入组建队伍")
	var hero: Adventurer = gd.team[0]
	_ok(not town.town.remove_from_team(hero), "主角无法移出队伍")
	_ok(gd.team.has(hero), "主角仍在队伍中")
	if gd.team.size() >= 2:
		var n0: String = gd.team[0].display_name
		town.town.swap_team_positions(0, 1)
		await process_frame
		_ok(gd.team[0].display_name != n0 or gd.team[1].display_name == n0, "小队换位生效")

	# ---- 伟业升级 / 任务木板 ----
	town._on_guild_mode("trophy")
	await process_frame
	_ok(town._guild_mode == "trophy", "进入伟业升级")
	_ok(_find_btn(town.get_node("%Content"), "伟业升级") != null, "伟业升级按钮存在")
	town._on_guild_mode("quests")
	await process_frame
	_ok(town._guild_mode == "quests", "进入任务木板")
	# 9-23 修改意见 4：任务木板不再用卡牌边框，改成纯色块
	var quest_frames := _count_frames(town.get_node("%Content"))
	_ok(quest_frames == 0, "任务木板不再使用卡牌边框（%d 张卡）" % quest_frames)
	var blocks := _count_color_blocks(town.get_node("%Content"), Color("#4A6FB5"))
	var want_blocks: int = gd.quests.available.size() + gd.quests.active.size()
	_ok(want_blocks > 0 and blocks == want_blocks,
		"任务以纯色块显示（%d / %d 块）" % [blocks, want_blocks])

	# ---- 意见 9 + 意见 4：点卡查看详情（已改为右键；且必须走真实信号，
	#      历史 bug：信号会先传 frame 再拼 bind 参数，处理函数少一个形参 → 点击无反应） ----
	print("\n-- 意见4/9：右键查看卡牌详情 --")
	town._on_guild_mode("home")
	await process_frame
	var probe_card: CardFrame = town._adventurer_card(gd.team[0])
	town.add_child(probe_card)
	await process_frame
	probe_card.right_clicked.emit(probe_card)
	await process_frame
	_ok(town._popup_layer != null, "右键小队成员卡弹出详情（意见4）")
	town._close_popup()
	await process_frame
	_ok(town._popup_layer == null, "详情弹窗可关闭")
	probe_card.queue_free()
	await process_frame

	# 招募候选卡同样可看详情，且长条件文案不撑宽卡牌
	town._on_guild_mode("recruit")
	await process_frame
	if town._recruit_candidates.size() > 0:
		var cell: Control = town._recruit_cell(town._recruit_candidates[0])
		town.add_child(cell)
		await process_frame
		var rcard: CardFrame = null
		var cost_label: Label = null
		for ch in cell.get_children():
			if ch is CardFrame:
				rcard = ch
			elif ch is Label:
				cost_label = ch
		if rcard != null:
			rcard.right_clicked.emit(rcard)
			await process_frame
			_ok(town._popup_layer != null, "右键招募候选卡弹出详情（意见4）")
			town._close_popup()
			await process_frame
			_ok(cell.custom_minimum_size.x <= rcard.custom_minimum_size.x + 0.5,
				"招募单元格宽度不超过卡牌宽度（意见9）")
		_ok(cost_label != null and cost_label.autowrap_mode != TextServer.AUTOWRAP_OFF,
			"招募条件文案自动换行（意见9）")
		cell.queue_free()
		await process_frame

	# ---- 9-23 意见 5：人物卡版式（上半区纯色框内不允许出现任何文字）----
	print("\n-- 意见5：人物卡版式 --")
	var pcard: CardFrame = town._adventurer_card(gd.team[0])
	town.add_child(pcard)
	await process_frame
	_ok(pcard.style == CardFrame.STYLE_PERSON, "人物卡使用 person 版式")
	_ok(pcard._frame.texture != null
			and String(pcard._frame.texture.resource_path).ends_with("person_card_border.png"),
		"边框贴图 = person_card_border.png")
	_ok(not pcard._art_tag.visible, "类型字在人物卡上被隐藏（不再出现在上半区）")
	var art_zone: Rect2 = _norm_rect(pcard._art_clip)
	var desc_zone: Rect2 = _norm_rect(pcard._desc_label)
	var name_zone: Rect2 = _norm_rect(pcard._name_label)
	_ok(art_zone.get_center().y < 0.55, "纯色框在上半区（y 中心 %.2f）" % art_zone.get_center().y)
	_ok(desc_zone.get_center().y > 0.5, "属性框在下半区（y 中心 %.2f）" % desc_zone.get_center().y)
	_ok(name_zone.get_center().y > 0.85, "名字在底部金名条内（y 中心 %.2f）" % name_zone.get_center().y)
	_ok(not art_zone.intersects(desc_zone), "纯色框与属性框不重叠")
	_ok(not art_zone.intersects(name_zone), "纯色框与金名条不重叠")
	# 硬断言：上半区纯色框内一个可见文字都不能有
	var intruders: Array = []
	_labels_in(pcard, art_zone, intruders)
	_ok(intruders.is_empty(), "上半区纯色框内无任何文字（越界文字 %d 处%s）"
		% [intruders.size(), "" if intruders.is_empty() else "：" + ", ".join(intruders)])
	# 反过来：名字 / 属性必须在自己的框里
	var in_name: Array = []
	_labels_in(pcard, name_zone, in_name)
	_ok(in_name.has(gd.team[0].display_name), "名字落在金名条内（%s）" % pcard._name_label.text)
	_ok(pcard._name_label.text == gd.team[0].display_name, "金名条内容 = 人物名")
	_ok(pcard._desc_label.text.contains("战力") and pcard._desc_label.text.contains("体质")
			and pcard._desc_label.text.contains("幸运"),
		"下半区属性框列出属性（%s）" % pcard._desc_label.text.replace("\n", " / "))
	_ok(pcard._desc_label.text.strip_edges() != "" and in_name.find(pcard._desc_label.text) == -1,
		"属性文字不在上半区")
	# 宽高比必须贴合素材 745×1040，否则边框会被拉伸变形
	var want_ratio := 745.0 / 1040.0
	var got_ratio: float = pcard.custom_minimum_size.x / pcard.custom_minimum_size.y
	_ok(absf(got_ratio - want_ratio) < 0.005,
		"人物卡宽高比贴合素材（%.4f vs %.4f）" % [got_ratio, want_ratio])
	# 有未分配点数时，提示贴在属性框顶部窄带（不能跑去上半区）
	if gd.team[0].unspent_points > 0:
		var bl: Rect2 = _norm_rect(pcard._badge_l)
		_ok(bl.position.y > art_zone.end.y, "剩余点数角标贴在属性框顶部、位于上半区之下")
	pcard.queue_free()
	await process_frame

	# 物品卡同样是 person 版式，上半区也不许有字
	var any_item: ItemData = null
	for it in gd.inventory:
		if it != null:
			any_item = it
			break
	if any_item == null:
		any_item = gd.db.get_item("chain_mail")     # 背包空时借一件装备来验版式
	if any_item != null:
		var icard: CardFrame = town._item_card(any_item)
		town.add_child(icard)
		await process_frame
		var icard_art: Rect2 = _norm_rect(icard._art_clip)
		var icard_bad: Array = []
		_labels_in(icard, icard_art, icard_bad)
		_ok(not icard._art_tag.visible, "物品卡类型字也被隐藏")
		_ok(icard_bad.is_empty(), "物品卡上半区纯色框内无任何文字（越界 %d 处）" % icard_bad.size())
		icard.queue_free()
		await process_frame
	else:
		_ok(true, "（背包为空，跳过物品卡断言）")

	# ---- 作战整备：自动选 1 号位 + 卡组子界面 ----
	# 前面换位测试可能残留旧选中（场景会在选中者仍在队时保持选中），清空以验证自动选择路径
	town._selected_adventurer = null
	town._switch_tab(1)
	await process_frame
	var prep: Node = town
	_ok(prep._selected_adventurer == gd.team[0], "整备自动选择 1 号位")
	town._on_open_deck()
	await process_frame
	_ok(town._deck_view, "进入整备卡组界面")
	var deck_frames := _count_frames(town.get_node("%Content"))
	_ok(deck_frames >= gd.deck.size(), "卡组界面显示全部战斗卡（%d 张）" % deck_frames)

	# ---- 9-24 修改意见 3：卡池不再需要左右拖动 ----
	# 只手改"看不到滚动条"不够 —— 必须数值锁住"卡片流没有超出可视宽度"。
	print("\n-- 卡组整备：卡池自动换行 --")
	var town_scroll: ScrollContainer = town.get_node("%Scroll")
	_ok(town_scroll != null and town_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"整备卡组页关闭整页横向滚动（不再需要左右拖）")
	var flows: Array = []
	_collect_by_class(town.get_node("%Content"), "HFlowContainer", flows)
	_ok(flows.size() >= 2, "卡池按分类分成 %d 个自动折行卡片流" % flows.size())
	var pool_scroll_w := 0.0
	for s in _collect_by_class(town.get_node("%Content"), "ScrollContainer", []):
		if (s as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			pool_scroll_w = (s as Control).size.x
			break
	_ok(pool_scroll_w > 0.0, "找到卡池视口（宽 %.0f）" % pool_scroll_w)
	var overflow := 0
	for f in flows:
		if (f as Control).size.x > pool_scroll_w + 1.0:
			overflow += 1
	_ok(overflow == 0, "每个卡片流都装得进可视宽度（溢出 %d 个）" % overflow)
	# 卡片流里的格子必须钉住最小宽度，否则自动换行后描述行会被压成一列一个字
	var squeezed := 0
	for f in flows:
		for cell in (f as Control).get_children():
			if (cell as Control).size.x < 100.0:
				squeezed += 1
	_ok(squeezed == 0, "卡池格子没有被压窄（异常 %d 个）" % squeezed)

	town._on_close_deck()
	await process_frame
	_ok(not town._deck_view, "返回整备主页")
	_ok(town.get_node("%Scroll").horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"离开卡组页后恢复默认横向滚动（其它页不受影响）")

	# ---- 返回主菜单 ----
	town.get_node("%BackButton").pressed.emit()
	await process_frame
	var menu2: Node = await _wait_scene()
	_ok(menu2 != null and menu2.get_node_or_null("%MenuBox") != null, "回到主菜单")

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _all_buttons(root: Node) -> Array:
	var out: Array = []
	if root is Button:
		out.append(root)
	for ch in root.get_children():
		out.append_array(_all_buttons(ch))
	return out


## 递归收集某类型（is_class）的后代节点
func _collect_by_class(root: Node, cls: String, out: Array) -> Array:
	for ch in root.get_children():
		if ch.is_class(cls):
			out.append(ch)
		_collect_by_class(ch, cls, out)
	return out


func _quit() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1)
