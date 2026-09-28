## 全链路真渲染冒烟测试
##   开屏页 → 主菜单 → 城镇（5 标签 / 工会 5 模式 / 详情弹窗 / 卡组子界面 / 商店 / 仓库）
##   → 地牢（选层 / 前进 / 战斗 / 返回 / 撤离门禁）→ 存档读档（10 栏位面板）
## 跑法：python godot_run.py _t_smoke.gd <log> --render
## 说明：真实渲染模式跑，能同时暴露渲染期问题（字体/主题/弹窗/拖拽预览）
extends SceneTree

## 🔴 存档隔离前缀。**必须**在开头设给 SaveManager.active_prefix：
## 否则主菜单的存档面板会去读写玩家真实栏位，断言也跟着玩家进度飘。
const TEST_PREFIX := "user://_test_save_"

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(240.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _wait_scene(timeout: float = 5.0) -> Node:
	var t := 0.0
	while t < timeout:
		var cur: Node = current_scene
		if cur != null:
			return cur
		await process_frame
		t += 0.016
	return null


func _fake_click() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(640, 360)
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(640, 360)
	Input.parse_input_event(release)


func _find_btn(node: Node, text: String, exact: bool = true) -> Button:
	if node is Button:
		var b := node as Button
		if (exact and b.text == text) or (not exact and b.text.contains(text)):
			return b
	for ch in node.get_children():
		var found := _find_btn(ch, text, exact)
		if found != null:
			return found
	return null


## 按节点名递归找（唯一名不一定配了 unique_name_in_owner，这里按普通名找）
func _find_by_name(node: Node, nm: String) -> Node:
	if node.name == nm:
		return node
	for ch in node.get_children():
		var hit := _find_by_name(ch, nm)
		if hit != null:
			return hit
	return null


## 点一个按名字找到的按钮。找不到返回 false（避免 null 崩掉整条链路）
func _press_named(node: Node, nm: String) -> bool:
	var b := _find_by_name(node, nm) as Button
	if b == null:
		return false
	b.pressed.emit()
	return true


func _count_card_frames(node: Node) -> int:
	var n := 0
	if node is CardFrame:
		n += 1
	for ch in node.get_children():
		n += _count_card_frames(ch)
	return n


func _run() -> void:
	_watchdog()
	print("\n===== 全链路真渲染冒烟测试 =====\n")

	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd != null, "GameData autoload 已注册")
	if gd == null:
		_quit()
		return

	# 存档隔离：本测试全程用独立前缀，绝不碰玩家真实栏位
	SaveManager.active_prefix = TEST_PREFIX
	var cleanup := SaveManager.new()
	for i in range(SaveManager.SLOT_COUNT):
		cleanup.erase(i)

	# ============ 1. 开屏页 ============
	print("\n-- 1. 开屏页 --")
	change_scene_to_file("res://scenes/splash_scene.tscn")
	var sp: Node = await _wait_scene()
	await create_timer(1.2).timeout
	_ok(sp != null and sp.get_script() != null, "开屏页已加载")
	_fake_click()
	await create_timer(1.0).timeout
	var menu: Node = await _wait_scene()
	_ok(menu != null and menu.get_node_or_null("%MenuBox") != null, "点击开屏 → 进入主菜单")

	# ============ 2. 主菜单 ============
	print("\n-- 2. 主菜单 --")
	var mb: Node = menu.get_node_or_null("%MenuBox")
	var labels: Array = []
	if mb != null:
		for ch in mb.get_children():
			if ch is Button:
				labels.append(ch.text)
	_ok(labels.size() >= 7, "主菜单按钮数 %d（%s）" % [labels.size(), ", ".join(labels)])
	_ok(menu.get_node_or_null("%GoldLabel") != null, "金币标签存在（右上角）")
	_ok(menu.get_node_or_null("%ToastLabel") != null, "底部提示标签存在")
	_ok(menu.get_node_or_null("%StatusLabel") == null, "小队人数/总战力等状态信息已移除（意见2）")
	_ok(menu.get_node_or_null("RightPanel") == null, "右侧小队详情已删除（修改1）")

	# ---- 9-28：菜单顺序「地下城探索」紧挨着「快速战斗」----
	# 两条都是"进战斗"的入口，放一起才顺手
	var menu_btns: Array = []
	for ch in mb.get_children():
		if ch is Button:
			menu_btns.append(ch)
	_ok(menu_btns.size() >= 2 and String(menu_btns[0].text).contains("快速战斗"),
		"第一项是「快速战斗」（实际 %s）" % (menu_btns[0].text if menu_btns.size() > 0 else "无"))
	_ok(menu_btns.size() >= 2 and String(menu_btns[1].text) == "地下城探索",
		"第二项是「地下城探索」（实际 %s）" % (menu_btns[1].text if menu_btns.size() > 1 else "无"))

	# ---- 9-28：主菜单背景 ----
	var mb_bd: Node = menu.get_node_or_null("SceneBackdrop")
	_ok(mb_bd != null, "主菜单挂了背景板")
	if mb_bd != null:
		_ok(String(mb_bd.current_id()) == "menu_town", "主菜单背景是城镇（实际 %s）" % mb_bd.current_id())
		_ok(bool(mb_bd.has_image()), "主菜单背景贴图已加载")
	# 背景必须在最底层（插在 index 0），否则会盖住 UI
	_ok(mb_bd != null and menu.get_child(0) == mb_bd, "背景板是主菜单的第一个子节点（垫在最底下）")

	# ---- 9-28：游玩指南 ----
	_ok(_find_btn(mb, "游玩指南") != null, "主菜单有「游玩指南」")
	menu.open_guide()
	await process_frame
	await process_frame
	_ok(bool(menu.is_guide_open()), "指南面板已打开")
	_ok(_find_by_name(menu, "GuideLayer") != null, "指南浮层是 GuideLayer")
	_ok(_find_by_name(menu, "OverlayScroll") != null, "指南内容放进了滚动容器")
	var guide_sections := 0
	var guide_body := 0
	var markdown_leaks := 0
	var gcontent := _find_by_name(menu, "OverlayContent")
	if gcontent != null:
		for ch in gcontent.get_children():
			if ch is Label:
				var txt := String((ch as Label).text)
				if txt.begins_with("▍"):
					guide_sections += 1
				elif txt != "":
					guide_body += 1
				if txt.contains("**") or txt.contains("##"):
					markdown_leaks += 1
	_ok(guide_sections >= 5, "指南有 %d 个小节" % guide_sections)
	_ok(guide_body == guide_sections, "每个小节都配了正文（%d/%d）" % [guide_body, guide_sections])
	# Label 不解析 Markdown，写进去的 ** / ## 会原样显示 —— 必须为 0
	_ok(markdown_leaks == 0, "指南文案没有残留 Markdown 标记（%d 处）" % markdown_leaks)
	# 正文必须换行（autowrap）而不是被压成一长条
	var gbody := _find_by_name(menu, "OverlayContent").get_child(1) as Label
	_ok(gbody != null and gbody.autowrap_mode != TextServer.AUTOWRAP_OFF, "指南正文开了自动换行")
	_ok(_press_named(menu, "CloseButton"), "点指南的关闭按钮")
	await process_frame
	await process_frame
	_ok(not bool(menu.is_overlay_open()), "关闭后浮层消失")

	# ---- 9-28：存档 = 10 个栏位面板 ----
	var sm_ui := SaveManager.new()
	_ok(not sm_ui.has_any_save(), "测试存档空间是干净的（隔离前缀生效）")

	menu.open_save_slots()
	await process_frame
	await process_frame
	_ok(String(menu.current_overlay_kind()) == "slots_save", "存档面板已打开（kind=%s）" % menu.current_overlay_kind())
	var slot_list := _find_by_name(menu, "SlotList")
	_ok(slot_list != null and slot_list.get_child_count() == SaveManager.SLOT_COUNT,
		"存档面板有 %d 个栏位（实际 %d）" % [SaveManager.SLOT_COUNT,
		slot_list.get_child_count() if slot_list != null else -1])
	var with_time := 0
	var empty_summary := 0
	for i in range(SaveManager.SLOT_COUNT):
		if _find_by_name(menu, "SlotTime_%d" % i) != null:
			with_time += 1
		var s := _find_by_name(menu, "SlotSummary_%d" % i) as Label
		if s != null and s.text == "还没有存档":
			empty_summary += 1
	_ok(with_time == SaveManager.SLOT_COUNT,
		"每个栏位都带「游玩时间」行（%d/%d）" % [with_time, SaveManager.SLOT_COUNT])
	_ok(empty_summary == SaveManager.SLOT_COUNT,
		"初始时 10 个栏位都显示为空（%d）" % empty_summary)
	var slot0 := _find_by_name(menu, "Slot_0") as Button
	_ok(slot0 != null and not slot0.disabled, "存档模式下空栏位可点")

	# 点空栏位 → 直接写入
	_ok(_press_named(menu, "Slot_0"), "点击空栏位")
	await process_frame
	await process_frame
	_ok(sm_ui.has_save(0), "点击空栏位 → 写入栏位 1")
	_ok(not bool(sm_ui.slot_info(0)["empty"]), "栏位 1 摘要已刷新为非空")
	var time0 := _find_by_name(menu, "SlotTime_0") as Label
	_ok(time0 != null and String(time0.text).begins_with("游玩 "),
		"栏位 1 下方显示游玩时间（%s）" % (time0.text if time0 != null else "无"))
	_ok(time0 != null and String(time0.text).contains("最后保存"),
		"栏位 1 同时显示最后保存时间")

	# 点已有栏位 → 先确认再覆盖
	_ok(_press_named(menu, "Slot_0"), "再次点击栏位 1")
	await process_frame
	await process_frame
	_ok(bool(menu.is_confirm_open()), "点已有存档 → 弹出覆盖确认")
	_ok(_find_by_name(menu, "ConfirmBody") != null, "确认层有说明文字")
	_ok(_press_named(menu, "ConfirmCancel"), "点「取消」")
	await process_frame
	await process_frame
	_ok(not bool(menu.is_confirm_open()), "取消后确认层关闭")
	_ok(bool(menu.is_slots_open()), "取消覆盖后仍停在存档面板")
	menu.close_overlay()
	await process_frame
	await process_frame

	# ---- 读档面板：空栏位不可点，点已有存档直接载入 ----
	gd.gold = 4242
	_ok(sm_ui.save(0), "往栏位 1 写一份可辨识的存档（金币 4242）")
	gd.gold = 0
	menu.open_load_slots()
	await process_frame
	await process_frame
	_ok(String(menu.current_overlay_kind()) == "slots_load", "读档面板已打开")
	var enabled := 0
	var disabled := 0
	for i in range(SaveManager.SLOT_COUNT):
		var b := _find_by_name(menu, "Slot_%d" % i) as Button
		if b == null:
			continue
		if b.disabled:
			disabled += 1
		else:
			enabled += 1
	_ok(enabled == 1 and disabled == SaveManager.SLOT_COUNT - 1,
		"只有已存档的栏位 1 可点（可点 %d / 置灰 %d）" % [enabled, disabled])
	_ok(_press_named(menu, "Slot_0"), "点已有存档的栏位 1")
	await process_frame
	await process_frame
	_ok(gd.gold == 4242, "读档还原金币 4242（实际 %d）" % gd.gold)
	_ok(not bool(menu.is_overlay_open()), "读档后浮层自动关闭")
	_ok(not bool(menu.is_confirm_open()), "读档不会弹覆盖确认")
	var toast := _find_by_name(menu, "ToastLabel") as Label
	_ok(toast != null and String(toast.text).contains("已读取栏位 1"),
		"读档后底部提示「已读取栏位 1」（实际 %s）" % (toast.text if toast != null else "无"))

	# ---- 旧版（v1）存档在面板上要给出诚实文案，而不是「游玩 0 分钟」----
	var v1_path := TEST_PREFIX + "07.json"
	var v1f := FileAccess.open(v1_path, FileAccess.WRITE)
	v1f.store_string('{"version":1,"gold":900,"team":[],"deck":[]}')
	v1f.close()
	menu.open_save_slots()
	await process_frame
	await process_frame
	var t7 := _find_by_name(menu, "SlotTime_7") as Label
	_ok(t7 != null and String(t7.text).contains("旧版"),
		"旧版存档栏位提示「旧版」（%s）" % (t7.text if t7 != null else "无"))
	menu.close_overlay()
	await process_frame
	DirAccess.remove_absolute(v1_path)

	# ============ 3. 城镇 ============
	print("\n-- 3. 城镇 --")
	var town_btn: Button = _find_btn(mb, "冒险者工会")
	_ok(town_btn != null, "找到「冒险者工会」入口")
	if town_btn == null:
		_quit()
		return
	town_btn.pressed.emit()
	await process_frame
	var town: Node = await _wait_scene()
	await process_frame
	await process_frame
	_ok(town != null and town.get_node_or_null("%Tabs") != null, "进入城镇场景")
	gd.gold = 50000

	# 5 标签
	for i in range(5):
		town._switch_tab(i)
		await process_frame
	_ok(town._current_tab == 4, "5 个标签全部可切换（当前 %d）" % town._current_tab)

	# ---- 9-28：城镇 5 个标签页各有自己的背景 ----
	var town_bd: Node = town.get_node_or_null("SceneBackdrop")
	_ok(town_bd != null, "城镇挂了背景板")
	if town_bd != null:
		var want := {
			0: "guild_hall", 1: "armory", 2: "shop", 3: "storage", 4: "library",
		}
		for i in range(5):
			town._switch_tab(i)
			await process_frame
			var got := String(town_bd.current_id())
			_ok(got == String(want[i]), "标签「%s」背景 = %s（实际 %s）"
				% [town.TABS[i], want[i], got])

	# 工会 5 个模式（必须先回到工会标签，否则刷新按当前标签分派）
	town._switch_tab(0)
	await process_frame
	for m in ["quests", "recruit", "team", "trophy", "home"]:
		town._on_guild_mode(m)
		await process_frame
		await process_frame
		_ok(town._guild_mode == m, "工会子页面「%s」渲染" % m)
		print("    [探针] %s：Content 子节点 %d / 卡牌 %d" % [m, town.get_node("%Content").get_child_count(), _count_card_frames(town.get_node("%Content"))])
	var guild_frames: int = _count_card_frames(town.get_node("%Content"))
	_ok(guild_frames >= 3, "工会主页人物卡 %d 张" % guild_frames)
	_ok(guild_frames <= 12, "工会主页无页面切换残留（卡牌 %d 张 ≤ 12）" % guild_frames)

	# 任务木板：接取任务
	town._on_guild_mode("quests")
	await process_frame
	var qs: Array = gd.quests.available
	var accepted := false
	if qs.size() > 0:
		town._on_accept_quest(qs[0])
		accepted = gd.quests.active.size() >= 1
	_ok(accepted, "任务木板：接取任务成功（进行中 %d）" % gd.quests.active.size())

	# 招募木板：刷新
	town._on_guild_mode("recruit")
	await process_frame
	_ok(town._recruit_candidates.size() >= 1, "招募候选 %d 个" % town._recruit_candidates.size())

	# 组队页：主角锁 + 换位
	town._on_guild_mode("team")
	await process_frame
	var hero: Adventurer = gd.team[0]
	_ok(not town.town.remove_from_team(hero), "主角不可移出小队（修改1）")
	_ok(gd.team.has(hero), "主角仍在小队中")

	# 伟业升级页
	town._on_guild_mode("trophy")
	await process_frame
	_ok(town._guild_mode == "trophy", "伟业升级页渲染")

	# 人物详情弹窗
	town._switch_tab(0)
	await process_frame
	# 意见4：详情改右键；意见9：必须走真实信号（历史上处理函数少一个形参 → 点击无反应）
	var probe_card: CardFrame = town._adventurer_card(hero)
	town.add_child(probe_card)
	await process_frame
	probe_card.right_clicked.emit(probe_card)
	await process_frame
	_ok(town._popup_layer != null, "右键小队成员卡弹出详情（意见4）")
	probe_card.queue_free()
	await process_frame
	town._close_popup()
	await process_frame
	_ok(town._popup_layer == null, "详情弹窗可关闭")

	# 作战整备：自动选 1 号位 + 卡组子界面
	town._selected_adventurer = null
	town._switch_tab(1)
	await process_frame
	_ok(town._selected_adventurer == gd.team[0], "整备自动选择 1 号位（修改2）")
	town._on_open_deck()
	await process_frame
	_ok(town._deck_view and _count_card_frames(town.get_node("%Content")) >= gd.deck.size(),
		"卡组子界面显示全部战斗卡（%d 张）" % gd.deck.size())
	town._on_close_deck()
	await process_frame
	_ok(not town._deck_view, "退出卡组子界面")

	# 商店：买 + 卖
	town._switch_tab(2)
	await process_frame
	_ok(town._shop_items.size() >= 4, "商店商品 %d 件（卡牌化）" % town._shop_items.size())
	_ok(town.town.shop_cards.size() >= 1, "商店在售卡牌 %d 张（意见8）" % town.town.shop_cards.size())
	if town._shop_items.size() > 0:
		var buy_item: ItemData = town._shop_items[0]
		var gold_before: int = gd.gold
		var owned_before: int = gd.inventory.size()
		town._on_buy(buy_item)
		await process_frame
		_ok(gd.gold < gold_before and gd.inventory.size() == owned_before + 1,
			"商店购买成功（-%d 金）" % (gold_before - gd.gold))
		if gd.inventory.size() > 0:
			var sell_item: ItemData = gd.inventory[gd.inventory.size() - 1]
			var g2: int = gd.gold
			var n2: int = gd.inventory.size()
			town._on_sell(sell_item)
			await process_frame
			_ok(gd.gold > g2 and gd.inventory.size() == n2 - 1, "商店出售成功（+%d 金）" % (gd.gold - g2))

	# 仓库：存入 + 取回
	town._switch_tab(3)
	await process_frame
	if gd.inventory.size() > 0:
		var st_item: ItemData = gd.inventory[0]
		var inv_before: int = gd.inventory.size()
		var st_before: int = gd.storage.size()
		town._on_store(st_item)
		await process_frame
		_ok(gd.inventory.size() == inv_before - 1 and gd.storage.size() == st_before + 1,
			"仓库存入成功（仓库 %d 件）" % gd.storage.size())
		town._on_retrieve(gd.storage[gd.storage.size() - 1])
		await process_frame
		_ok(gd.inventory.size() == inv_before, "仓库取回成功")

	# 卡牌大全
	town._switch_tab(4)
	await process_frame
	_ok(_count_card_frames(town.get_node("%Content")) >= 10, "卡牌大全以卡牌网格显示")

	# ============ 4. 地牢 ============
	print("\n-- 4. 地牢 --")
	town.get_node("%BackButton").pressed.emit()
	await process_frame
	var menu2: Node = await _wait_scene()
	await process_frame
	var dungeon_btn: Button = _find_btn(menu2.get_node("%MenuBox"), "地下城探索")
	_ok(dungeon_btn != null, "主菜单有「地下城探索」入口")
	if dungeon_btn == null:
		_quit()
		return
	dungeon_btn.pressed.emit()
	await process_frame
	var run_scene: Node = await _wait_scene()
	await process_frame
	await process_frame
	_ok(run_scene != null and run_scene.get_node_or_null("%SelectPanel") != null, "进入地牢准备面板（意见7）")
	# 9-28：地牢场景背景
	var run_bd: Node = run_scene.get_node_or_null("SceneBackdrop")
	_ok(run_bd != null and String(run_bd.current_id()) == "dungeon_gate",
		"地牢背景 = dungeon_gate（实际 %s）"
		% (run_bd.current_id() if run_bd != null else "无背景板"))
	run_scene._on_select_level(1)
	await process_frame
	await process_frame
	var run = gd.run
	_ok(run != null and run.status == RunManager.Status.EXPLORING, "已开始第 1 层探索")

	# 撤离门禁：未打 Boss 应被拒（意见7：右侧已无撤离/返回按钮）
	_ok(run_scene.get_node_or_null("%RetreatButton") == null, "右侧面板无「撤离」按钮（意见7）")
	_ok(run_scene.get_node_or_null("%BackButton") == null, "右侧面板无「返回主菜单」按钮（意见7）")
	_ok(not run.can_retreat(), "can_retreat() = false（Boss 前）")
	_ok(not run.retreat(), "retreat() 被拒绝（Boss 前）")
	_ok(run.status == RunManager.Status.EXPLORING, "拒绝后仍在探索中")

	# 前进到战斗节点
	var battle_node = null
	var guard := 0
	while battle_node == null and guard < 8:
		guard += 1
		for n in run.reachable_nodes():
			if n.type == MapGenerator.NodeType.BATTLE:
				battle_node = n
				break
		if battle_node == null:
			run.move_to(run.reachable_nodes()[0])
	_ok(battle_node != null, "找到战斗节点")
	if battle_node == null:
		_quit()
		return
	# 准备战斗内可用道具（验证背包/道具使用链路）
	for pid in ["health_potion", "mana_potion"]:
		var pit: ItemData = gd.db.get_item(pid)
		if pit != null:
			gd.inventory.append(pit)

	run_scene._on_node_pressed(battle_node)
	await process_frame
	var battle: Node = await _wait_scene()
	await create_timer(0.4).timeout
	_ok(battle != null and battle.battle != null, "进入战斗场景")
	var bm: BattleManager = battle.battle
	# 意见 3：开局默认指定主角
	_ok(bm.selected_adventurer != null and bm.selected_adventurer.id == "hero",
		"开局默认指定主角（意见3）")
	# 意见 6：手牌显示六分类名
	var cat_ok := true
	var cat_sample := ""
	for hc in bm.deck.hand:
		var cn: String = (hc as CardData).get_category_name_cn()
		if not (cn.contains("物理") or cn.contains("法术")):
			cat_ok = false
		cat_sample = cn
	_ok(cat_ok and bm.deck.hand.size() > 0, "手牌全部归入物理/法术分类（末张：%s）" % cat_sample)

	# ============ 5. 战斗 ============
	print("\n-- 5. 战斗 --")
	# 9-28：战斗背景 + 战场面板半透明（否则背景全被面板盖住，等于没加）
	var btl_bd: Node = battle.get_node_or_null("SceneBackdrop")
	_ok(btl_bd != null and String(btl_bd.current_id()) == "dungeon_battle",
		"战斗背景 = dungeon_battle（实际 %s）"
		% (btl_bd.current_id() if btl_bd != null else "无背景板"))
	var bf_panel := battle.get_node_or_null("Root/Middle/Battlefield") as Panel
	var bf_sb: StyleBoxFlat = null
	if bf_panel != null:
		bf_sb = bf_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_ok(bf_sb != null and bf_sb.bg_color.a < 0.9,
		"战场面板半透明，背景能透出来（alpha %.2f）"
		% (bf_sb.bg_color.a if bf_sb != null else -1.0))
	# 道具使用放在回合初（行动值满，可用条件最宽松）
	for a in bm.team:
		if a.is_alive():
			a.current_hp = maxi(1, a.current_hp / 2)
	var item_used := false
	var item_candidates := ""
	for it in gd.inventory.duplicate():
		if not it.usable_in_battle:
			continue
		item_candidates += it.id + " "
		for a in bm.team:
			if bm.can_use_item(a, it):
				if bm.use_item(a, it, a):
					item_used = true
				break
		if item_used:
			break
	print("  背包内可战斗使用道具：%s" % item_candidates)
	if not item_used:
		var st := ""
		for a in bm.team:
			st += "%s(行动%d/血%d/%d) " % [a.display_name, a.current_action, a.current_hp, a.get_max_hp()]
		print("  诊断：玩家回合=%s；%s" % [bm.turn.is_player_turn(), st])
	_ok(item_used, "战斗内使用道具（背包链路）")

	# 背包弹窗
	battle._on_bag()
	await create_timer(0.3).timeout
	_ok(true, "背包弹窗可打开（无异常）")
	if battle._bag_popup != null:
		battle._bag_popup.queue_free()
		await process_frame

	# 选中单位 + 出牌
	var uv0: Node = null
	for uv in battle._unit_views:
		if uv.adventurer != null:
			uv0 = uv
			break
	if uv0 != null:
		battle._on_unit_clicked(uv0)
		await process_frame
		_ok(bm.selected_adventurer != null, "点击单位可选中释放者")
	var played := 0
	for card in bm.deck.hand.duplicate():
		var caster: Adventurer = bm.selected_adventurer
		if caster == null or not bm.can_play(caster, card):
			continue
		var tgt: Variant = null
		if card.card_class == CardData.CardClass.ATTACK and not bm.living_monsters().is_empty():
			tgt = bm.living_monsters()[0]
		if bm.play_card(caster, card, tgt):
			played += 1
		if played >= 2:
			break
	_ok(played >= 1, "手动出牌 %d 张" % played)

	# 意见6：手牌按行动点数非递减排列
	var hand_ordered := true
	var prev_cost := -1
	var hand_costs := ""
	for v in battle._card_views:
		var c_cost: int = v.card.action_cost
		if c_cost < prev_cost:
			hand_ordered = false
		prev_cost = c_cost
		hand_costs += str(c_cost) + " "
	_ok(hand_ordered, "手牌按行动点数排列（%s）" % hand_costs.strip_edges())
	# 意见4/5：悬停放大 + 拖拽贝塞尔箭头
	var hover_card = battle._card_views[0]
	hover_card._on_mouse_entered()
	await process_frame
	_ok(hover_card.scale.x > 1.0, "手牌悬停放大（scale=%.2f，意见4）" % hover_card.scale.x)
	hover_card._on_mouse_exited()
	_ok(battle._arrow != null, "拖拽指示箭头覆盖层存在（意见5）")

	# 结束回合
	battle._on_end_turn()
	await create_timer(0.5).timeout

	# 战斗记录面板：必须有内容且字色为深色（浅色底白字＝看不见）
	var loglbl: RichTextLabel = battle.get_node_or_null("%LogLabel")
	var log_lines: int = loglbl.get_line_count() if loglbl != null else 0
	_ok(loglbl != null and log_lines >= 3, "战斗记录面板有日志（%d 行）" % log_lines)
	if loglbl != null:
		var lc: Color = loglbl.get_theme_color("default_color")
		_ok(lc.get_luminance() < 0.5, "战斗记录字色为深色（亮度 %.2f）" % lc.get_luminance())

	# 自动打完
	var g := 0
	while bm.result == BattleManager.Result.ONGOING and g < 120:
		g += 1
		var acted := false
		for a in bm.team:
			if not a.is_alive():
				continue
			for card in bm.deck.hand.duplicate():
				if not bm.can_play(a, card):
					continue
				var tgt2: Variant = null
				if card.card_class == CardData.CardClass.ATTACK and not bm.living_monsters().is_empty():
					tgt2 = bm.living_monsters()[0]
				if bm.play_card(a, card, tgt2):
					acted = true
					break
		if bm.result != BattleManager.Result.ONGOING:
			break
		if not acted:
			battle._on_end_turn()
		await process_frame
	_ok(bm.result == BattleManager.Result.VICTORY, "战斗结束：胜利（回合 %d）" % bm.turn.round_number)

	# ============ 6. 返回地牢 + 存档 ============
	print("\n-- 6. 返回地牢 / 存档 --")
	if bm.result == BattleManager.Result.VICTORY:
		battle.get_node("%ResultButton").pressed.emit()
		await process_frame
		var back: Node = await _wait_scene()
		await create_timer(0.4).timeout
		_ok(back != null and back.get_node_or_null("%MapArea") != null, "返回地牢场景")
		_ok(gd.run.status == RunManager.Status.EXPLORING, "地牢继续探索中")

	# 存档 → 改数据 → 读档（隔离前缀，栏位 5）
	var sm := SaveManager.new()
	var gold_snapshot: int = gd.gold
	gd.playtime_seconds = 4210.0          # 1 小时 10 分
	_ok(sm.save(4), "存档写入成功（栏位 5）")
	gd.gold = 123456
	gd.playtime_seconds = 0.0
	var loaded: bool = sm.load(4)
	# 存档里记的是取整秒；读回后 _process 已经在继续累加，所以判断"≥ 记录值"
	var pt_after: int = int(gd.playtime_seconds)
	await process_frame
	_ok(loaded and gd.gold == gold_snapshot, "读档还原金币（%d）" % gd.gold)
	_ok(pt_after >= 4210, "读档还原游玩时长（%d 秒，≥4210）" % pt_after)
	_ok(gd.team.size() >= 1 and gd.deck.size() >= 20, "读档后小队 %d 人 / 卡组 %d 张" % [gd.team.size(), gd.deck.size()])

	# 清掉本测试写下的全部栏位，别给下次运行留垃圾
	for i in range(SaveManager.SLOT_COUNT):
		sm.erase(i)
	_ok(not sm.has_any_save(), "测试写下的栏位已全部清理")

	_quit()


func _quit() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
