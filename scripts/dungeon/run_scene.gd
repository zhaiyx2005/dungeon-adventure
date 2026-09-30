## 地牢探索界面
##
## 阶段 3 的地牢入口与推进界面：
##   - 无进行中的 run → 显示「选层」面板（5 层，准入判定）
##   - 探索中 → 显示 3×7 地图，点可达节点前进
##   - 战斗节点 → 写入 GameData.pending_encounter 后切到 battle_scene
##   - 宝箱 / 事件 → 弹窗结算
##   - Boss 胜利 → 弹「撤离 / 继续向下」选择
##   - 撤离 / 死亡 / 通关 → 结束面板回主菜单
extends Control


const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"

## 属性中文名（加点面板用）
const STAT_CN := {
	"constitution": "体质", "strength": "力量",
	"intelligence": "智力", "vitality": "精力",
}

## 装备槽位展示顺序（与 ItemData.Slot 一致，武器已合并为单一槽位）
const PREP_SLOTS: Array = [
	ItemData.Slot.HEAD, ItemData.Slot.NECK, ItemData.Slot.BODY, ItemData.Slot.HAND,
	ItemData.Slot.LEG, ItemData.Slot.FOOT, ItemData.Slot.WEAPON,
]

## 节点类型 → 图标 + 名称
const NODE_ICON := {
	MapGenerator.NodeType.BATTLE: "⚔",
	MapGenerator.NodeType.TREASURE: "💰",
	MapGenerator.NodeType.EVENT: "❓",
	MapGenerator.NodeType.BOSS: "👑",
	MapGenerator.NodeType.START: "🚪",
}
const NODE_NAME := {
	MapGenerator.NodeType.BATTLE: "战斗",
	MapGenerator.NodeType.TREASURE: "宝箱",
	MapGenerator.NodeType.EVENT: "事件",
	MapGenerator.NodeType.BOSS: "层 Boss",
	MapGenerator.NodeType.START: "入口",
}


@onready var _header_label: Label = %HeaderLabel
@onready var _map_area: VBoxContainer = %MapArea
@onready var _hint_label: Label = %HintLabel
@onready var _status_label: Label = %StatusLabel
@onready var _info_label: Label = %InfoLabel
@onready var _select_panel: PanelContainer = %SelectPanel
@onready var _select_tabs: HBoxContainer = %SelectTabs
@onready var _select_list: VBoxContainer = %SelectList
@onready var _select_close: Button = %SelectClose
@onready var _overlay: PanelContainer = %Overlay
@onready var _overlay_title: Label = %OverlayTitle
@onready var _overlay_text: Label = %OverlayText
@onready var _overlay_button: Button = %OverlayButton
@onready var _overlay_btn2: Button = %OverlayButton2


## 覆盖面板主/次按钮各自的动作
var _overlay_action: String = "none"
var _overlay_action2: String = "none"


func _ready() -> void:
	AudioManager.play_bgm("dungeon")
	# 背景：地下城入口大厅（9-28 需求）
	SceneBackdrop.attach(self, "dungeon_gate", SceneBackdrop.SCRIM_DUNGEON)
	# 左/右两栏标题直接压在背景上（没有面板垫底）→ 加描边
	var outlines: Array[Label] = [_header_label, _hint_label, _status_label, _info_label]
	for l in outlines:
		l.add_theme_color_override("font_outline_color", Color("#fbfaf6"))
		l.add_theme_constant_override("outline_size", 4)
	# 9-22 修改意见 1：上一轮已结束（撤离 / 全队濒死）的 run 必须丢弃，
	# 否则再次点击「地下城探索」会渲染那张已通关的旧地图并且无法继续前进。
	if GameData.run != null and GameData.run.status != RunManager.Status.EXPLORING:
		GameData.run = null
		GameData.last_battle_result = {}
	_wire_ui()
	# 刚从战斗回来（地牢 run 的结算）→ 显示过渡面板
	if GameData.run != null and GameData.last_battle_result.has("victory"):
		_show_battle_result()
	else:
		_refresh()


func _wire_ui() -> void:
	# 9-22 修改意见 7：右侧面板不再放「撤离 / 返回主菜单」按钮，
	# 撤离改为打完层 Boss 后在弹出面板里选择
	_select_close.pressed.connect(_on_back)
	_overlay_button.pressed.connect(_on_overlay_confirm)
	_overlay_btn2.pressed.connect(_on_overlay_btn2)
	_overlay.visible = false
	_select_panel.visible = false


# ---------------------------------------------------------------------------
# 状态刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var run := GameData.run
	# 没有 run，或上一轮已结束（撤离/失败）→ 回到准备面板重新开始
	if run == null or run.status != RunManager.Status.EXPLORING:
		GameData.run = null
		_show_select_panel()
		return

	_select_panel.visible = false
	_header_label.text = "%s（危险 %s · 第 %d 层）" % [
		run.dungeon.display_name, run.dungeon.get_danger_name(), run.dungeon.level_index,
	]
	_refresh_status()
	_refresh_map()
	_refresh_actions()


func _refresh_status() -> void:
	var run := GameData.run
	var lines: PackedStringArray = []
	lines.append("小队总战力：%d" % GameData.team_power())
	lines.append("金币：%d" % GameData.gold)
	lines.append("背包：%d 件" % GameData.inventory.size())
	lines.append("")
	lines.append("本次探索：金币 +%d   经验 +%d   物品 %d 件" % [
		run.gold_earned, run.exp_earned, run.items_found.size(),
	])
	_status_label.text = "\n".join(lines)


func _refresh_map() -> void:
	for child in _map_area.get_children():
		child.queue_free()

	var run := GameData.run
	var reachable := run.reachable_nodes()

	# 自上而下 row 0（Boss）→ row 6（入口）
	for row in range(0, 7):
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 10)
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		_map_area.add_child(row_box)

		for col in range(3):
			var node := MapGenerator.find(run.map, row, col)
			if node == null:
				row_box.add_child(_placeholder())
				continue
			row_box.add_child(_node_button(node, reachable))


func _placeholder() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(96, 54)
	return c


func _node_button(node: MapGenerator.MapNode, reachable: Array) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(96, 54)

	var is_current := node == GameData.run.current
	var is_reachable := reachable.has(node)
	var is_boss_done := node.type == MapGenerator.NodeType.BOSS and GameData.run.boss_defeated

	var label: String = NODE_ICON.get(node.type, "?")
	if is_current:
		label = "📍" + label
	elif is_reachable:
		label = "▶ " + label
	btn.text = label
	btn.tooltip_text = NODE_NAME.get(node.type, "?") + ("（已击败）" if is_boss_done else "")

	if is_current or is_boss_done or not is_reachable:
		btn.disabled = true
	else:
		btn.pressed.connect(_on_node_pressed.bind(node))

	if is_current:
		btn.add_theme_color_override("font_color", Color("#185FA5"))
	elif is_reachable:
		btn.add_theme_color_override("font_color", Color("#3B6D11"))
	else:
		btn.add_theme_color_override("font_color", Color("#9A978E"))
	return btn


func _refresh_actions() -> void:
	var run := GameData.run
	# 9-22 修改意见 7：撤离按层级 —— 只有击败本层 Boss 后才可选择撤离
	if run.at_boss() and run.boss_defeated:
		_hint_label.text = "层 Boss 已击败 —— 选择撤离返回城镇，或继续向下。"
	else:
		_hint_label.text = "点击 ▶ 高亮的节点前进。一层多条路线，终点是 👑 层 Boss 房；打完 Boss 才能撤离。"
	_info_label.text = _describe_current()


func _describe_current() -> String:
	var run := GameData.run
	if run == null or run.current == null:
		return ""
	var n := run.current
	var s := "当前位置：第 %d 行 · %s" % [n.row, NODE_NAME.get(n.type, "?")]
	if run.at_boss() and run.boss_defeated:
		s += "（已击败）"
	return s


# ---------------------------------------------------------------------------
# 选层
# ---------------------------------------------------------------------------

func _show_select_panel() -> void:
	_header_label.text = "地下城探索 · 准备"
	_hint_label.text = ""

	# 清掉遗留占位文字，右侧显示队伍与资源概要
	_status_label.text = "小队总战力：%d\n金币：%d\n背包：%d 件\n卡组：%d 张" % [
		GameData.team_power(), GameData.gold, GameData.inventory.size(), GameData.deck.size(),
	]
	_info_label.text = ""

	_select_panel.visible = true
	_build_prep_tabs()
	_refresh_prep()


# ---------------------------------------------------------------------------
# 准备面板（9-23 修改意见 6）
##
## 进入地牢前也能做完整整备：编成 / 加点（提升队友）/ 装备 / 背包 / 道具。
## 原先这里只有一段说明文字 + 一个「进入地牢」按钮，出门前想换装备必须回城镇。
# ---------------------------------------------------------------------------

## 准备面板的标签页：key → 显示名
const PREP_TABS := [
	["overview", "出征概要"],
	["team", "队伍加点"],
	["equip", "装备"],
	["bag", "背包道具"],
]

var _prep_tab: String = "overview"
var _prep_member: Adventurer = null


func _build_prep_tabs() -> void:
	for child in _select_tabs.get_children():
		child.queue_free()
	for entry in PREP_TABS:
		var key: String = entry[0]
		var btn := Button.new()
		btn.name = "PrepTab_" + key
		btn.text = entry[1]
		btn.toggle_mode = true
		btn.button_pressed = key == _prep_tab
		btn.custom_minimum_size = Vector2(130, 36)
		btn.pressed.connect(_on_prep_tab.bind(key))
		_select_tabs.add_child(btn)


func _on_prep_tab(key: String) -> void:
	_prep_tab = key
	_build_prep_tabs()
	_refresh_prep()


func _refresh_prep() -> void:
	for child in _select_list.get_children():
		child.queue_free()
	match _prep_tab:
		"team":
			_build_prep_team()
		"equip":
			_build_prep_equip()
		"bag":
			_build_prep_bag()
		_:
			_build_prep_overview()


## ---- 概要 ----

func _build_prep_overview() -> void:
	var lines: PackedStringArray = []
	lines.append("小队 %d 人 · 总战力 %d" % [GameData.team.size(), GameData.team_power()])
	var names: PackedStringArray = []
	for a in GameData.team:
		names.append("%s Lv.%d" % [a.display_name, a.level])
	lines.append("成员：" + "、".join(names))
	lines.append("卡组 %d 张 · 背包 %d 件 · 金币 %d" % [
		GameData.deck.size(), GameData.inventory.size(), GameData.gold,
	])
	_select_list.add_child(_prep_label(lines[0] + "  /  " + lines[2], 15))

	var desc := _prep_label("击败层 Boss 后可撤离或深入下一层。全队濒死会损失本轮收益与背包物品。", 13)
	desc.add_theme_color_override("font_color", Color(0.4, 0.39, 0.36, 1))
	_select_list.add_child(desc)

	# 9-24 修改意见 3：通关过某层 Boss 后，就能付金币直接进入该层。
	# 这里把 1–5 层的阶梯全列出来，每层写清"为什么能进 / 为什么不能进"。
	_select_list.add_child(HSeparator.new())
	_select_list.add_child(_prep_label("关卡直达（通关过的层可付金币直接进入）", 16))
	_build_floors()


## 层级阶梯：每层一行，显示名称 / 危险度 / 战力要求 / 入场费 / 准入状态 + 进入按钮
func _build_floors() -> void:
	var probe := RunManager.new()
	var colors := [Color("#577e75"), Color("#657c9d"), Color("#8b6d99"), Color("#a47d48"), Color("#ad5657")]
	for level in range(1, 6):
		var d := GameData.db.get_dungeon_by_level(level)
		if d == null:
			continue
		var reason: String = probe.direct_entry_block_reason(d)
		var panel := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#e5dcc5") if reason == "" else Color("#d2cebd")
		box.border_color = colors[level - 1]
		box.border_width_left = 5
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", box)
		_select_list.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		panel.add_child(row)
		var art := TextureRect.new()
		art.custom_minimum_size = Vector2(80, 48)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.texture = ArtRegistry.bg("dungeon_gate" if level == 1 else "dungeon_battle")
		art.modulate = colors[level - 1].lightened(0.35)
		row.add_child(art)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)
		var status := "已通关" if GameData.is_level_cleared(level) else "尚未通关"
		text_box.add_child(_prep_label("%02d  /  %s  ·  %s" % [level, d.display_name, status], 17))
		var cost := "免费" if d.entry_cost <= 0 else "%d 金" % d.entry_cost
		text_box.add_child(_prep_label("危险 %s  ·  战力 ≥ %d  ·  入场 %s" % [d.get_danger_name(), d.recommend_power_min, cost], 13))
		var btn := Button.new()
		btn.name = "EnterDungeonButton" if level == 1 else "EnterFloorButton%d" % level
		btn.custom_minimum_size = Vector2(300, 44)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.text = "进入第 %d 层  →" % level if reason == "" else reason
		btn.tooltip_text = "入场：%s" % cost if reason == "" else reason
		btn.disabled = reason != ""
		btn.pressed.connect(_on_select_level.bind(level))
		row.add_child(btn)


## ---- 队伍：加点 + 卡池换人 ----

func _build_prep_team() -> void:
	var gd := GameData
	_select_list.add_child(_prep_label("小队成员（剩余属性点可随时分配）", 16))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_select_list.add_child(box)
	for a in gd.team:
		box.add_child(_prep_member_row(a))

	_select_list.add_child(HSeparator.new())
	_select_list.add_child(_prep_label("人物卡池（%d 人）" % gd.roster.size(), 16))
	if gd.roster.is_empty():
		_select_list.add_child(_prep_label("卡池为空", 13))
		return
	var pool := HBoxContainer.new()
	pool.add_theme_constant_override("separation", 10)
	_select_list.add_child(pool)
	for a in gd.roster:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(_prep_label("%s Lv.%d" % [a.display_name, a.level], 13))
		cell.add_child(_prep_label("战力 %d" % int(a.get_power()), 12))
		var add := Button.new()
		add.text = "加入小队"
		add.disabled = gd.team.size() >= TownManager.MAX_TEAM_SIZE
		add.pressed.connect(_on_prep_add_member.bind(a))
		cell.add_child(add)
		pool.add_child(cell)


func _prep_member_row(a: Adventurer) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#EFEDE6")
	sb.border_color = Color("#C6C3BA")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var head := VBoxContainer.new()
	head.custom_minimum_size = Vector2(190, 0)
	head.add_theme_constant_override("separation", 2)
	head.add_child(_prep_label("%s  Lv.%d" % [a.display_name, a.level], 15))
	head.add_child(_prep_label("战力 %d · 剩余点数 %d" % [int(a.get_power()), a.unspent_points], 12))
	row.add_child(head)

	for key in ["constitution", "strength", "intelligence", "vitality"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var val: int = a.get(key)
		col.add_child(_prep_label("%s %d" % [STAT_CN.get(key, key), val], 13))
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(40, 26)
		plus.disabled = a.unspent_points <= 0
		plus.pressed.connect(_on_prep_spend.bind(a, key))
		col.add_child(plus)
		row.add_child(col)

	# 换下 / 移出小队（主角锁定）
	if not _is_protagonist(a):
		var out := Button.new()
		out.text = "移出小队"
		out.custom_minimum_size = Vector2(90, 26)
		out.pressed.connect(_on_prep_remove_member.bind(a))
		row.add_child(out)
	return panel


func _is_protagonist(a: Adventurer) -> bool:
	return a != null and a.id == "hero"


func _on_prep_spend(a: Adventurer, key: String) -> void:
	var tm := TownManager.new()
	tm.spend_point(a, key)
	_refresh_prep()


func _on_prep_add_member(a: Adventurer) -> void:
	var tm := TownManager.new()
	tm.add_to_team(a)
	_refresh_prep()


func _on_prep_remove_member(a: Adventurer) -> void:
	var tm := TownManager.new()
	tm.remove_from_team(a)
	_refresh_prep()


## ---- 装备 ----

func _build_prep_equip() -> void:
	var gd := GameData
	if _prep_member == null or not gd.team.has(_prep_member):
		_prep_member = gd.team[0] if not gd.team.is_empty() else null

	# 成员选择
	var sel := HBoxContainer.new()
	sel.add_theme_constant_override("separation", 8)
	_select_list.add_child(sel)
	for a in gd.team:
		var btn := Button.new()
		btn.name = "PrepMember_" + a.id
		btn.text = "%s Lv.%d" % [a.display_name, a.level]
		btn.toggle_mode = true
		btn.button_pressed = a == _prep_member
		btn.custom_minimum_size = Vector2(130, 34)
		btn.pressed.connect(_on_prep_pick_member.bind(a))
		sel.add_child(btn)

	if _prep_member == null:
		_select_list.add_child(_prep_label("小队里没有人", 13))
		return

	# 已装备槽位
	_select_list.add_child(_prep_label("%s 的装备（点「卸下」放回背包）" % _prep_member.display_name, 16))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	_select_list.add_child(slots)
	for slot in PREP_SLOTS:
		slots.add_child(_prep_equip_slot(_prep_member, slot))

	# 背包里可穿的装备
	var equippable: Array[ItemData] = []
	for it in gd.inventory:
		if it.is_equipment():
			equippable.append(it)
	_select_list.add_child(HSeparator.new())
	_select_list.add_child(_prep_label("背包装备（%d 件，点「装备」穿到 %s 身上）"
		% [equippable.size(), _prep_member.display_name], 16))
	if equippable.is_empty():
		_select_list.add_child(_prep_label("背包里没有装备", 13))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_select_list.add_child(grid)
	for it in equippable:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _prep_label("%s（%s）" % [it.display_name, it.get_slot_name_cn()], 13)
		info.custom_minimum_size = Vector2(200, 0)
		row.add_child(info)
		var btn := Button.new()
		btn.text = "装备"
		btn.custom_minimum_size = Vector2(76, 30)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_on_prep_equip.bind(_prep_member, it))
		row.add_child(btn)
		grid.add_child(row)


func _prep_equip_slot(a: Adventurer, slot: ItemData.Slot) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(104, 0)
	box.add_theme_constant_override("separation", 3)
	var item: ItemData = a.equipment.get(slot)
	box.add_child(_prep_label(ItemData.slot_name_cn(slot), 12))
	if item == null:
		box.add_child(_prep_label("空", 12))
	else:
		box.add_child(_prep_label(item.display_name, 12))
		var off := Button.new()
		off.text = "卸下"
		off.custom_minimum_size = Vector2(0, 24)
		off.pressed.connect(_on_prep_unequip.bind(a, slot))
		box.add_child(off)
	return box


func _on_prep_pick_member(a: Adventurer) -> void:
	_prep_member = a
	_refresh_prep()


func _on_prep_equip(a: Adventurer, item: ItemData) -> void:
	var tm := TownManager.new()
	tm.equip(a, item)
	_refresh_prep()


func _on_prep_unequip(a: Adventurer, slot: ItemData.Slot) -> void:
	var tm := TownManager.new()
	tm.unequip(a, slot)
	_refresh_prep()


## ---- 背包 / 道具 ----

func _build_prep_bag() -> void:
	var gd := GameData
	_select_list.add_child(_prep_label("背包（%d 件）" % gd.inventory.size(), 16))
	if gd.inventory.is_empty():
		_select_list.add_child(_prep_label("背包为空", 13))
		return

	# 使用道具的目标成员
	var target := _prep_member if _prep_member != null and gd.team.has(_prep_member) else null
	if target == null and not gd.team.is_empty():
		target = gd.team[0]
		_prep_member = target

	var sel := HBoxContainer.new()
	sel.add_theme_constant_override("separation", 8)
	_select_list.add_child(sel)
	sel.add_child(_prep_label("道具使用对象：", 13, 110))
	sel.alignment = BoxContainer.ALIGNMENT_BEGIN
	for a in gd.team:
		var btn := Button.new()
		btn.text = "%s（血 %d/%d）" % [a.display_name, a.current_hp, a.get_max_hp()]
		btn.toggle_mode = true
		btn.button_pressed = a == target
		btn.custom_minimum_size = Vector2(170, 32)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_on_prep_pick_member.bind(a))
		sel.add_child(btn)

	var hint := _prep_label("血量 / 蓝量在每场战斗开始时都会回满，所以恢复类道具主要用在战斗内" \
		+ "（战斗界面右侧「背包」按钮）。这里给的是出征前的兜底补给。", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.43, 0.40, 1))
	_select_list.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_select_list.add_child(grid)
	for it in gd.inventory:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _prep_label("%s · %s" % [it.display_name, it.get_rarity_name_cn()], 13)
		info.custom_minimum_size = Vector2(240, 0)
		row.add_child(info)
		if it.is_equipment():
			var eq := Button.new()
			eq.text = "装备"
			eq.custom_minimum_size = Vector2(76, 30)
			eq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			eq.pressed.connect(_on_prep_equip.bind(target, it))
			row.add_child(eq)
		elif it.is_consumable():
			var use := Button.new()
			use.name = "PrepUse_" + it.id
			use.text = "使用"
			use.custom_minimum_size = Vector2(76, 30)
			use.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			use.disabled = target == null
			use.pressed.connect(_on_prep_use_item.bind(target, it))
			row.add_child(use)
		else:
			row.add_child(_prep_label("—", 12))
		grid.add_child(row)


func _on_prep_use_item(target: Adventurer, item: ItemData) -> void:
	if _use_item_out_of_battle(target, item):
		_hint_label.text = "对 %s 使用了「%s」" % [target.display_name, item.display_name]
	else:
		_hint_label.text = "「%s」现在用不上（目标已满或该道具只能战斗内使用）" % item.display_name
	_refresh_prep()


## 出征前使用消耗品（9-23 修改意见 6）。
## 与战斗内 battle_manager.use_item 的效果一致，避免两处数值漂移。
func _use_item_out_of_battle(target: Adventurer, item: ItemData) -> bool:
	if target == null or item == null or not item.is_consumable():
		return false
	if not GameData.inventory.has(item):
		return false
	var ok := false
	match item.id:
		"health_potion":
			if target.is_alive() and target.current_hp < target.get_max_hp():
				target.heal(20)
				ok = true
		"greater_health_potion":
			if target.is_alive() and target.current_hp < target.get_max_hp():
				target.heal(50)
				ok = true
		"mana_potion":
			if target.current_mana < target.get_max_mana():
				target.current_mana = mini(target.current_mana + 20, target.get_max_mana())
				ok = true
		"greater_mana_potion":
			if target.current_mana < target.get_max_mana():
				target.current_mana = mini(target.current_mana + 50, target.get_max_mana())
				ok = true
	if ok:
		GameData.inventory.erase(item)
	return ok


## 准备面板里的普通文字标签。
## min_width > 0 时关掉自动换行并钉死最小宽度——放在水平排列里时，
## 自动换行的 Label 最小宽度为 0，会被压成"一列一个字"（背包页踩过）。
func _prep_label(text: String, font_size: int = 14, min_width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	if min_width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2(min_width, 0)
		l.size_flags_horizontal = Control.SIZE_FILL
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _on_select_level(level_index: int) -> void:
	var run := RunManager.new()
	GameData.run = run
	run.log_added.connect(_on_run_log)
	if run.start_at_level(level_index):
		_select_panel.visible = false
		_refresh()
	else:
		_show_select_panel()


func _on_run_log(_text: String) -> void:
	pass  # 地牢日志暂不单独展示，控制台可见


# ---------------------------------------------------------------------------
# 节点交互
# ---------------------------------------------------------------------------

func _on_node_pressed(node: MapGenerator.MapNode) -> void:
	var run := GameData.run
	if run == null or not run.move_to(node):
		AudioManager.play_sfx("ui_deny")
		return
	AudioManager.play_sfx("map_step", 0.96 + float(node.row % 3) * 0.04)

	match node.type:
		MapGenerator.NodeType.BATTLE, MapGenerator.NodeType.BOSS:
			_start_battle(node)
		MapGenerator.NodeType.TREASURE:
			run.open_treasure()
			AudioManager.play_sfx("reward")
			_show_overlay(run.last_event_title, run.last_event_lines, "继续探索", "", "continue", "none")
			_refresh()
		MapGenerator.NodeType.EVENT:
			run.resolve_event()
			AudioManager.play_sfx("reward", 0.92)
			_show_overlay(run.last_event_title, run.last_event_lines, "继续探索", "", "continue", "none")
			_refresh()
		_:
			_refresh()


## 进入战斗：写入待处理遭遇 + 返回场景，切到战斗界面
func _start_battle(node: MapGenerator.MapNode) -> void:
	var run := GameData.run
	var monster_ids: Array = node.monster_ids if not node.monster_ids.is_empty() else run.build_encounter()
	GameData.pending_encounter = {
		"monster_ids": monster_ids,
		"node_type": "boss" if node.type == MapGenerator.NodeType.BOSS else "battle",
	}
	GameData.return_scene = "res://scenes/dungeon/run_scene.tscn"
	GameData.last_battle_result = {}
	get_tree().change_scene_to_file(BATTLE_SCENE)


# ---------------------------------------------------------------------------
# 战斗结果过渡
# ---------------------------------------------------------------------------

func _show_battle_result() -> void:
	var run := GameData.run
	var res: Dictionary = GameData.last_battle_result
	var victory: bool = res.get("victory", false)
	GameData.last_battle_result = {}

	if victory:
		var lines: PackedStringArray = []
		lines.append("获得经验 %d、金币 %d" % [res.get("reward_exp", 0), res.get("reward_gold", 0)])
		if run.boss_defeated:
			lines.append("")
			lines.append("Boss 宝箱已收入背包。")
		_show_overlay("战斗胜利", lines, "继续探索", "", "continue", "none")
		_refresh()
	else:
		var lines: PackedStringArray = []
		lines.append("全队濒死。")
		lines.append("已失去背包内所有物品与本次探索的金币、经验。")
		lines.append("（保留卡组与已穿装备）")
		_show_overlay("任务失败", lines, "返回主菜单", "", "menu", "none")


# ---------------------------------------------------------------------------
# 撤离 / 结束
# ---------------------------------------------------------------------------

func _on_retreat() -> void:
	var run := GameData.run
	if run == null or not run.can_retreat():
		return
	run.retreat()
	_show_overlay(
		"撤离",
		[
			"你带着战利品安全返回了城镇。",
			"",
			"本次探索：金币 +%d  经验 +%d  物品 %d 件" % [run.gold_earned, run.exp_earned, run.items_found.size()],
		],
		"返回主菜单", "", "menu", "none"
	)


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


# ---------------------------------------------------------------------------
# 覆盖面板
# ---------------------------------------------------------------------------

func _show_overlay(title: String, lines: Array, btn_text: String, btn2_text: String, action: String, action2: String) -> void:
	_overlay_title.text = title
	_overlay_text.text = "\n".join(lines)
	_overlay_button.text = btn_text
	_overlay_btn2.text = btn2_text
	_overlay_btn2.visible = btn2_text != ""
	_overlay_action = action
	_overlay_action2 = action2
	_overlay.visible = true


func _on_overlay_confirm() -> void:
	_overlay.visible = false
	match _overlay_action:
		"menu":
			get_tree().change_scene_to_file(MAIN_MENU)
		"retreat":
			_on_retreat()
		"continue":
			if _at_boss_done():
				_show_boss_choice()
			else:
				_refresh()
		_:
			_refresh()


func _on_overlay_btn2() -> void:
	match _overlay_action2:
		"continue_down":
			_overlay.visible = false
			_do_continue_down()
		_:
			pass


func _at_boss_done() -> bool:
	return GameData.run != null and GameData.run.at_boss() and GameData.run.boss_defeated


func _show_boss_choice() -> void:
	_show_overlay(
		"Boss 已击败",
		[
			"你击败了「%s」的层 Boss。" % GameData.run.dungeon.display_name,
			"",
			"选择：撤离（带走战利品）或继续向下（更深层、更强怪、更丰厚奖励）。",
		],
		"撤离（结束本轮）", "继续向下", "retreat", "continue_down"
	)


func _do_continue_down() -> void:
	var run := GameData.run
	if run == null:
		_refresh()
		return
	if run.continue_down():
		_refresh()
	else:
		_show_overlay(
			"通关",
			[
				"你已抵达最深处并击败了所有层的 Boss。",
				"",
				"本次探索：金币 +%d  经验 +%d  物品 %d 件" % [run.gold_earned, run.exp_earned, run.items_found.size()],
			],
			"返回主菜单", "", "menu", "none"
		)
