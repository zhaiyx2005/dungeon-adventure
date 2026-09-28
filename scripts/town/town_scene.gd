## 城镇界面（9-22 修改意见重构版）
##
## 主菜单各入口进入对应标签页：
##   冒险者工会：4 个选项（接取任务 / 招募成员 / 组建队伍 / 伟业升级），
##               选项下方是当前小队成员人物卡（名字/等级/战力），
##               左键点卡放大查看详情，可给有剩余属性点的同伴加点。
##               接取任务 = 任务木板（任务卡：信息/奖励/推荐战力随小队总战力浮动）
##               招募成员 = 招募木板（格子里人物卡，卡下方标招募所需：金钱或收集品卡牌）
##               组建队伍 = 上方小队 1–4 号位 + 下方卡池，拖拽加入/移出/互换（主角不可移出）
##               伟业升级 = 左放人物卡、右放战利品卡，中间按钮消耗战利品升级人物
##   作战整备：自动选队伍 1 号位；加点；装备栏多框，装备卡拖进去穿上；
##             「卡组」按钮进入整备卡组界面：战斗卡全在左侧，拖到右侧编入
##   商店：商品以卡牌形式显示；背包物品同样卡牌化
##   仓库 / 卡牌大全：同样卡牌化
##
## 所有卡牌统一使用 CardFrame（卡牌边框模板）。
## 所有数据操作走 TownManager，UI 只读状态、调方法、刷新显示。
extends Control


const MAIN_MENU := "res://scenes/main_menu.tscn"

## 标签页
const TABS := ["冒险者工会", "作战整备", "商店", "仓库", "卡牌大全"]

## 每个标签页配一张场景背景（9-28 需求）。
## 用**标签名**做键而不是下标：TABS 一旦重排，下标写死的那种写法会静默错位。
const TAB_BG := {
	"冒险者工会": "guild_hall",
	"作战整备": "armory",
	"商店": "shop",
	"仓库": "storage",
	"卡牌大全": "library",
}

## 装备槽位展示顺序
## 9-22 修改意见 5：单手 / 双手 / 远程武器合并成一个「武器」槽位
const SLOTS: Array = [
	ItemData.Slot.HEAD, ItemData.Slot.NECK, ItemData.Slot.BODY, ItemData.Slot.HAND,
	ItemData.Slot.LEG, ItemData.Slot.FOOT, ItemData.Slot.WEAPON,
]

## 属性中文名
const STAT_CN := {
	"constitution": "体质", "strength": "力量",
	"intelligence": "智力", "vitality": "精力",
}

@onready var _title: Label = %TitleLabel
@onready var _gold: Label = %GoldLabel
@onready var _tabs: HBoxContainer = %Tabs
@onready var _content: VBoxContainer = %Content
@onready var _scroll: ScrollContainer = %Scroll
@onready var _back_btn: Button = %BackButton
@onready var _hint: Label = %HintLabel


var town: TownManager
var _current_tab: int = 0
var _guild_mode: String = "home"        ## 工会子页面：home/quests/recruit/team/trophy
var _deck_view: bool = false            ## 整备页是否处于卡组子界面
var _selected_adventurer: Adventurer = null
var _recruit_candidates: Array = []     ## [{adventurer, price, collectible_id, collectible_name}]
var _backdrop: SceneBackdrop = null     ## 场景背景板（随标签页换图）
var _shop_items: Array[ItemData] = []
var _popup_layer: Control = null

## 伟业升级左右框的暂存
var _trophy_char: Adventurer = null
var _trophy_item: ItemData = null


func _ready() -> void:
	AudioManager.play_bgm("title")
	# 背景：按标签页切图（9-28 需求）。先挂第一张，_switch_tab 里会跟着换
	_backdrop = SceneBackdrop.attach(self, TAB_BG[TABS[0]], SceneBackdrop.SCRIM_TOWN)
	# 顶栏这三条文字也直接压在背景上（没有面板），一并加描边
	_outline(_title)
	_outline(_gold)
	_outline(_hint)
	town = TownManager.new()
	town.town_changed.connect(_refresh)
	_back_btn.pressed.connect(_on_back)
	_build_tabs()
	_refresh_recruits()
	_roll_shop()

	# 初始化任务系统（跨场景存活，首次进入时生成任务并挂到 GameData）
	var gd := town._g()
	if gd.quests == null:
		gd.quests = QuestManager.new()
		gd.quests.roll_quests()
	gd.quests.quest_changed.connect(_refresh)

	# 主菜单指定了初始标签页则跳转过去
	var initial := 0
	if gd.pending_initial_tab != "":
		var target: String = gd.pending_initial_tab
		gd.pending_initial_tab = ""
		for i in range(TABS.size()):
			if TABS[i] == target:
				initial = i
				break
	_switch_tab(initial)


func _build_tabs() -> void:
	for i in range(TABS.size()):
		var btn := Button.new()
		btn.text = TABS[i]
		btn.custom_minimum_size = Vector2(160, 40)
		btn.toggle_mode = true
		btn.button_pressed = i == 0
		btn.pressed.connect(_on_tab_pressed.bind(i))
		_tabs.add_child(btn)


func _on_tab_pressed(i: int) -> void:
	_current_tab = i
	_guild_mode = "home"
	_deck_view = false
	_switch_tab(i)


func _switch_tab(i: int) -> void:
	_current_tab = i
	# 背景跟着标签页换（9-28）：工会客厅 / 铁匠铺 / 商店 / 仓库 / 藏书室
	if _backdrop != null and i >= 0 and i < TABS.size():
		_backdrop.show_image(String(TAB_BG.get(TABS[i], "menu_town")))
	# 更新标签高亮
	for j in range(_tabs.get_child_count()):
		(_tabs.get_child(j) as Button).button_pressed = (j == i)
	_refresh()


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var gd := town._g()
	_gold.text = "金币：%d" % gd.gold
	# 9-24 修改意见 3：默认允许横向滚动；卡组整备页会自己关掉它（见 _build_deck_edit）
	_set_h_scroll(false)
	for child in _content.get_children():
		child.queue_free()

	match _current_tab:
		0: _build_guild()
		1: _build_prepare()
		2: _build_shop()
		3: _build_storage()
		4: _build_codex()


## 文字描边（9-28）。加了场景背景之后，这几类文字是**直接压在背景图**上的：
## 小号灰字（`#6B6960` / `#66635C`）落在背景的深色区域时对比度只剩 ~3.4:1，读不出来。
## 正确解是给文字描边，而不是把背景压得更死 —— 压到能盖住最暗区域时背景就没了。
const TEXT_OUTLINE_COLOR := Color("#fbfaf6")
const TEXT_OUTLINE_SIZE := 4


## 给压在背景上的文字加一圈浅色描边（幂等，可重复调用）
func _outline(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", TEXT_OUTLINE_COLOR)
	l.add_theme_constant_override("outline_size", TEXT_OUTLINE_SIZE)
	return l


func _section_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#3B6D11"))
	_content.add_child(l)
	return _outline(l)


func _subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("#6B6960"))
	_content.add_child(l)
	return _outline(l)


func _wood_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#c9a06a")
	sb.border_color = Color("#8a6236")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	return p


# ---------------------------------------------------------------------------
# 卡牌工厂（统一 CardFrame 模板）
# ---------------------------------------------------------------------------

## 人物卡（9-23 修改意见 5）：
##   上半区 = 纯色图片框（**框内不放任何文字**）
##   下半区 = 属性框，逐条列 等级 / 战力 / 四维 / 幸运 / 装备数
##   底部   = 金名条，放名字
func _adventurer_card(a: Adventurer, payload: Variant = null) -> CardFrame:
	var c := CardFrame.new()
	c.custom_minimum_size = Vector2(156, 218)      # 与人物卡边框 745×1040（1:1.396）等比
	c.drag_payload = payload
	var lines: PackedStringArray = []
	lines.append("等级 lv%d    战力 %d" % [a.level, int(a.get_power())])
	lines.append("体质 %d       力量 %d" % [a.constitution, a.strength])
	lines.append("智力 %d       精力 %d" % [a.intelligence, a.vitality])
	lines.append("幸运 %d       装备 %d" % [a.get_luck(), a.equipment.size()])
	# 有未分配属性点时，把提示放在属性框顶部的窄角标带里（不会占掉图片区）
	var badge_l := ""
	if a.unspent_points > 0:
		badge_l = "剩余点数 %d" % a.unspent_points
	# 有像素立绘就用立绘（9-26，取半身）；没有则回落到原来的纯色块。
	# 招募来的人没有专属立绘，会按最高属性分派一张职业原型立绘（ArtRegistry 里统一处理）。
	c.setup(a.display_name, "\n".join(lines), Color("#4A6FB5"),
		{"badge_l": badge_l, "image": ArtRegistry.adventurer_bust(a)})
	# 9-22 修改意见 4：详情改由右键触发
	c.right_clicked.connect(_on_adventurer_card_clicked.bind(a))
	return c


## 物品卡（9-23 意见 5 版式）：上半插画 / 下描述 / 下金名条
func _item_card(item: ItemData, badge_r: String = "", payload: Variant = null) -> CardFrame:
	var c := CardFrame.new()
	c.custom_minimum_size = Vector2(128, 179)     # 与卡牌素材 1:1.4 等比
	c.drag_payload = payload
	c.setup(item.display_name, item.get_card_desc_cn(), item.get_rarity_color(), {
		"badge_l": item.get_rarity_name_cn(),
		"badge_r": badge_r,
		# 物品插画（9-26）。缺素材返回 null，CardFrame 自动回落到珍贵度色块，
		# 所以"还没出图的物品"不会渲染成空白。
		"image": ArtRegistry.item(item.id),
	})
	c.right_clicked.connect(_on_item_card_clicked.bind(item))
	return c


## 战斗卡（9-23 意见 2 版式）：左上 = 行动点 / 右上 = 蓝量 / 最上方 = 名字 /
## 上半框 = 图片 / 下半框 = 描述（中间胶囊 = 六分类）
func _battle_card(card: CardData, badge_override := "") -> CardFrame:
	var c := CardFrame.new()
	c.custom_minimum_size = Vector2(128, 179)
	var badge_r := "%d" % card.mana_cost if card.mana_cost > 0 else ""
	# 9-22 修改意见 6：卡面类型显示物理/法术 × 进攻/防御/特殊 六分类
	# 9-24：共鸣体系的卡改显示「共鸣」（组件）/「联合」（本体），首行给前置提示，
	#       与战斗手牌（card_view.gd）保持同一套视觉语言。
	var cat := card.get_category_name_cn()
	var tag_text := cat
	var head := "%s · %s" % [cat, card.get_rarity_name_cn()]
	if card.is_combo_component():
		tag_text = "共鸣"
	elif card.is_combo_payoff():
		tag_text = "联合"
	if card.has_combo():
		head = card.get_combo_hint_cn()
	c.setup(card.display_name, "%s\n%s" % [head, card.description],
		Color(card.art_placeholder), {
			"style": CardFrame.STYLE_BATTLE,
			"image": ArtRegistry.card(card.id),
			"tag": tag_text,
			"badge_l": badge_override if badge_override != "" else "%d" % card.action_cost,
			"badge_r": badge_r,
		})
	c.right_clicked.connect(_on_battle_card_clicked.bind(card))
	return c


## 任务木板上的任务（9-23 修改意见 4）：
## 木板上不再使用卡牌边框素材，改为**纯色圆角块 + 文字**：
##   标题 / 任务内容 / 推荐战力 / 奖励
func _quest_block(q: QuestManager.Quest) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(232, 158)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#4A6FB5")            ## 示意图里的蓝色块
	sb.border_color = Color("#2F4C86")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = q.title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#FFFFFF"))
	box.add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color("#E8EDF8"))
	body.text = "任务内容：%s\n战力参考：%d（%s）\n奖励：%s" % [
		q.description, q.recommend_power, _quest_diff_text(q), _quest_reward_text(q),
	]
	box.add_child(body)

	var state := Label.new()
	state.add_theme_font_size_override("font_size", 12)
	state.add_theme_color_override("font_color", Color("#C9D6EE"))
	if q.accepted:
		state.text = "进行中 %d / %d" % [q.progress, q.target_count]
	else:
		state.text = "未接取"
	box.add_child(state)
	return panel


## 推荐战力与小队战力的对比描述
func _quest_diff_text(q: QuestManager.Quest) -> String:
	var squad_power: int = town._g().team_power()
	if q.recommend_power <= int(squad_power * 0.85):
		return "较为轻松"
	if q.recommend_power > int(squad_power * 1.15):
		return "颇为危险"
	return "势均力敌"


## 任务奖励文案（金币 + 可选物品 + 可选卡牌）
func _quest_reward_text(q: QuestManager.Quest) -> String:
	var reward := "%d 金币" % q.reward_gold
	if q.reward_item_id != "":
		var it: ItemData = town._g().db.get_item(q.reward_item_id)
		if it != null:
			reward += " + %s" % it.display_name
	# 意见 8：任务也可能奖励战斗卡
	if q.reward_card_id != "":
		var rc: CardData = town._g().db.get_card(q.reward_card_id)
		if rc != null:
			reward += " + 卡牌「%s」" % rc.display_name
	return reward


func _card_grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	return g


## 是否禁止整页横向滚动（9-24 修改意见 3）。
## 关掉横向滚动 = 内容被钳到视口宽度内，配合 HFlowContainer 就会自动换行，
## 玩家再也不用左右拖着看卡。
func _set_h_scroll(disable: bool) -> void:
	if _scroll == null:
		return
	_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED if disable else ScrollContainer.SCROLL_MODE_AUTO
	)


func _empty_label(text: String) -> Label:
	var l := Label.new()
	l.text = "  " + text
	l.add_theme_color_override("font_color", Color("#9A978E"))
	return l


# ---------------------------------------------------------------------------
# 详情弹窗（放大单张卡牌 + 详细信息 + 可选加点）
# ---------------------------------------------------------------------------

func _show_detail_popup(frame: CardFrame, info: String, stat_target: Adventurer = null) -> void:
	_close_popup()
	_popup_layer = Control.new()
	_popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_layer.z_index = 200
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_layer.add_child(dim)
	dim.gui_input.connect(_on_popup_dim_input)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#F4F2EC")
	sb.border_color = Color("#8a6236")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	box.add_child(cards)

	frame.custom_minimum_size = Vector2(200, 280)
	frame.drag_payload = null
	_strip_card_signals(frame)
	cards.add_child(frame)

	var info_label := Label.new()
	info_label.text = info
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.custom_minimum_size = Vector2(280, 0)
	cards.add_child(info_label)

	if stat_target != null and stat_target.unspent_points > 0:
		box.add_child(_subtitle_wrap("剩余属性点 %d：点击分配" % stat_target.unspent_points))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for key in ["constitution", "strength", "intelligence", "vitality"]:
			var val: int = stat_target.get(key)
			var btn := Button.new()
			btn.text = "%s %d +" % [STAT_CN[key], val]
			btn.pressed.connect(_on_popup_spend.bind(stat_target, key))
			row.add_child(btn)
		box.add_child(row)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 36)
	close.pressed.connect(_close_popup)
	box.add_child(close)

	add_child(_popup_layer)


func _subtitle_wrap(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#6B6960"))
	return l


func _on_popup_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		_close_popup()


func _on_popup_spend(a: Adventurer, key: String) -> void:
	town.spend_point(a, key)
	_close_popup()


func _close_popup() -> void:
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null


func _adventurer_info(a: Adventurer) -> String:
	var lines: PackedStringArray = []
	lines.append("%s   Lv.%d   经验 %d" % [a.display_name, a.level, a.exp])
	var s := a.get_stats()
	lines.append("血量 %d  蓝量 %d  行动 %d" % [int(s["hp"]), int(s["mana"]), int(s["action"])])
	lines.append("物攻 %d  法攻 %d  物抗 %d  法抗 %d" % [
		int(s["phys_atk"]), int(s["mag_atk"]), int(s["phys_res"]), int(s["mag_res"])])
	lines.append("技巧 %d  幸运 %d  战力 %d" % [int(s["technique"]), a.get_luck(), int(a.get_power())])
	lines.append("体质 %d  力量 %d  智力 %d  精力 %d" % [a.constitution, a.strength, a.intelligence, a.vitality])
	if a.unspent_points > 0:
		lines.append("剩余属性点：%d" % a.unspent_points)
	if not a.equipment.is_empty():
		var names: PackedStringArray = []
		for slot in a.equipment:
			var it: ItemData = a.equipment[slot]
			names.append("[%s]%s" % [it.get_slot_name_cn(), it.display_name])
		lines.append("装备：%s" % "  ".join(names))
	return "\n".join(lines)


## 去掉卡牌上的点击/右键连接（弹窗里的放大卡不需要再触发弹窗）
func _strip_card_signals(frame: CardFrame) -> void:
	for conn in frame.clicked.get_connections():
		frame.clicked.disconnect(conn["callable"])
	for conn in frame.right_clicked.get_connections():
		frame.right_clicked.disconnect(conn["callable"])


## 注意：CardFrame.clicked / right_clicked 会先传 frame，再拼 bind 的参数，
## 所以这里必须显式接收（但不用）第一个参数，否则实参数量不匹配、点击无反应。
func _on_adventurer_card_clicked(_frame: CardFrame, a: Adventurer) -> void:
	var frame := _adventurer_card(a)
	# 弹窗里重新接点击：放大卡不需要再弹
	_strip_card_signals(frame)
	_show_detail_popup(frame, _adventurer_info(a), a)


func _on_item_card_clicked(_frame: CardFrame, item: ItemData) -> void:
	var frame := _item_card(item)
	_strip_card_signals(frame)
	var lines: PackedStringArray = []
	lines.append("[%s]" % item.get_rarity_name_cn())
	if item.is_equipment():
		lines.append("装备槽位：%s" % item.get_slot_name_cn())
	var bonus := item.get_bonus_text_cn()
	if bonus != "":
		lines.append("加成：%s" % bonus)
	if item.description != "":
		lines.append("")
		lines.append(item.description)
	lines.append("")
	lines.append("售价 %d 金" % item.sell_price)
	_show_detail_popup(frame, "\n".join(lines))


func _on_battle_card_clicked(_frame: CardFrame, card: CardData) -> void:
	var frame := _battle_card(card)
	_strip_card_signals(frame)
	var lines: PackedStringArray = []
	lines.append("%s · %s" % [card.get_category_name_cn(), card.get_rarity_name_cn()])
	lines.append("行动 %d   蓝耗 %d" % [card.action_cost, card.mana_cost])
	# 9-24：共鸣体系卡把前置条件说清楚（弹窗空间够，不用像卡面那样省字）
	if card.is_combo_component():
		lines.append("共鸣组件：本回合内凑齐「%s」全部组件后，才能打出该联合卡" % card.combo_name)
	elif card.is_combo_payoff():
		lines.append("联合卡：前置条件 %s（本回合内先打出该组组件）" % card.combo_desc)
		# 只有联合卡没有组件 = 一张永远打不出去的废牌，这里必须提醒
		var comp_names: PackedStringArray = []
		var all_owned := true
		# gd2 来自跨 autoload 的动态取节点，返回值无静态类型 → 显式标注，不能靠 := 推导
		var gd2: Node = town._g()
		for comp: CardData in _combo_component_cards(card):
			var n: int = gd2.owned_card_count(comp.id)
			comp_names.append("%s×%d" % [comp.display_name, n])
			if n <= 0:
				all_owned = false
		if not comp_names.is_empty():
			lines.append("需要组件：%s%s" % [
				"、".join(comp_names),
				"" if all_owned else "　← 尚未全部持有，先去商人处补齐",
			])
	lines.append("")
	lines.append(card.description)
	_show_detail_popup(frame, "\n".join(lines))


# ---------------------------------------------------------------------------
# 拖拽目标（内部类）
# ---------------------------------------------------------------------------

class DropTarget extends PanelContainer:
	var accepts: Callable
	var on_drop: Callable

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return accepts.is_valid() and accepts.call(data)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if on_drop.is_valid():
			on_drop.call(data)


func _empty_slot_style(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.06)
	sb.border_color = Color("#B5B3AB")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)


# ---------------------------------------------------------------------------
# 标签 0：冒险者工会
# ---------------------------------------------------------------------------

func _build_guild() -> void:
	match _guild_mode:
		"home": _build_guild_home()
		"quests": _build_quests()
		"recruit": _build_recruit()
		"team": _build_team()
		"trophy": _build_trophy()


func _build_guild_home() -> void:
	var gd := town._g()
	_section_title("冒险者工会")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_content.add_child(row)
	for entry in [["接取任务", "quests"], ["招募成员", "recruit"], ["组建队伍", "team"], ["伟业升级", "trophy"]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(220, 64)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_guild_mode.bind(entry[1]))
		row.add_child(btn)

	_content.add_child(HSeparator.new())
	_subtitle("当前的小队成员（%d 人，总战力 %d）—— 左键选中加点，右键查看详情" % [gd.team.size(), gd.team_power()])
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	_content.add_child(cards)
	for a in gd.team:
		cards.add_child(_adventurer_card(a))

	_content.add_child(HSeparator.new())
	_subtitle("人物卡池（%d 人，右键查看详情）" % gd.roster.size())
	if gd.roster.is_empty():
		_content.add_child(_empty_label("卡池为空，可在「招募成员」木板获取新成员"))
	else:
		var pool := HBoxContainer.new()
		pool.add_theme_constant_override("separation", 12)
		_content.add_child(pool)
		for a in gd.roster:
			pool.add_child(_adventurer_card(a))


func _on_guild_mode(mode: String) -> void:
	_guild_mode = mode
	_trophy_char = null
	_trophy_item = null
	_refresh()


func _back_home_btn() -> void:
	var btn := Button.new()
	btn.text = "← 返回工会"
	btn.custom_minimum_size = Vector2(140, 36)
	btn.pressed.connect(_on_guild_mode.bind("home"))
	_content.add_child(btn)


# ---- 接取任务（任务木板） ----

func _build_quests() -> void:
	var gd := town._g()
	_back_home_btn()
	_section_title("任务木板")

	_subtitle("可接任务（刷新次数 %d）" % gd.refresh_quest)
	if gd.quests.available.is_empty():
		_content.add_child(_empty_label("暂无任务，可点击「刷新任务」"))
	else:
		var board := _wood_panel()
		_content.add_child(board)
		var grid := _card_grid(3)
		board.add_child(grid)
		for q in gd.quests.available:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(_quest_block(q))
			var accept := Button.new()
			accept.text = "接取"
			accept.pressed.connect(_on_accept_quest.bind(q))
			cell.add_child(accept)
			grid.add_child(cell)

	var refresh := Button.new()
	refresh.text = "刷新任务"
	refresh.custom_minimum_size = Vector2(140, 36)
	refresh.pressed.connect(_on_refresh_quests)
	_content.add_child(refresh)

	_content.add_child(HSeparator.new())
	_subtitle("进行中的任务（%d 个，最多 3 个）" % gd.quests.active.size())
	if gd.quests.active.is_empty():
		_content.add_child(_empty_label("没有进行中的任务"))
	else:
		var grid2 := _card_grid(3)
		_content.add_child(grid2)
		for q in gd.quests.active:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(_quest_block(q))
			var complete: bool = town._g().quests.is_complete(q)
			var btn := Button.new()
			btn.text = "提交领奖" if complete else "进行中…"
			btn.disabled = not complete
			btn.pressed.connect(_on_claim_quest.bind(q))
			cell.add_child(btn)
			grid2.add_child(cell)


func _on_accept_quest(q: QuestManager.Quest) -> void:
	town._g().quests.accept(q)


func _on_claim_quest(q: QuestManager.Quest) -> void:
	var msgs: Array[String] = town._g().quests.claim(q)
	if not msgs.is_empty():
		_hint.text = "任务完成：" + "；".join(msgs)


func _on_refresh_quests() -> void:
	if town._g().quests.try_refresh_quests():
		_refresh()


# ---- 招募成员（招募木板） ----

func _build_recruit() -> void:
	var gd := town._g()
	_back_home_btn()
	_section_title("招募木板")

	_subtitle("招募候选（刷新次数 %d）—— 右键查看详情，满足条件点击招募" % gd.refresh_recruit)
	var board := _wood_panel()
	_content.add_child(board)
	var grid := _card_grid(3)
	board.add_child(grid)
	for cand in _recruit_candidates:
		grid.add_child(_recruit_cell(cand))

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新招募"
	refresh_btn.custom_minimum_size = Vector2(140, 36)
	refresh_btn.pressed.connect(_on_refresh_recruit)
	_content.add_child(refresh_btn)


func _recruit_cell(cand: Dictionary) -> Control:
	var a: Adventurer = cand["adventurer"]
	var price: int = cand["price"]
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)
	# 意见 9：单元格宽度固定为卡牌宽度，避免文案把整列 / 卡牌撑宽
	cell.custom_minimum_size = Vector2(128, 0)
	cell.add_child(_adventurer_card(a))

	var cost := Label.new()
	if cand.get("collectible_id", "") != "":
		cost.text = "招募：收集品「%s」+ %d 金" % [cand["collectible_name"], price]
		cost.add_theme_color_override("font_color", Color("#185FA5"))
	else:
		cost.text = "招募：金钱 %d" % price
		cost.add_theme_color_override("font_color", Color("#6B6960"))
	# 意见 9：条件文案允许 2–3 行换行，卡牌长宽保持不变
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.max_lines_visible = 3
	cost.custom_minimum_size = Vector2(128, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(cost)

	var btn := Button.new()
	btn.text = "招募"
	var can := town.can_afford_candidate(cand)
	btn.disabled = not can
	btn.tooltip_text = "" if can else "金币或收集品不足"
	btn.pressed.connect(_on_recruit_candidate.bind(cand))
	cell.add_child(btn)
	return cell


func _on_recruit_candidate(cand: Dictionary) -> void:
	if town.recruit_candidate(cand):
		_refresh_recruits()
		_refresh()


func _on_refresh_recruit() -> void:
	if town.try_refresh_recruit():
		_refresh_recruits()
		_refresh()


func _refresh_recruits() -> void:
	_recruit_candidates.clear()
	for _i in range(3):
		_recruit_candidates.append(town.roll_recruit_candidate())


# ---- 组建队伍（拖拽） ----

func _build_team() -> void:
	var gd := town._g()
	_back_home_btn()
	_section_title("组建队伍")
	_subtitle("把下方卡池的人物拖入小队空位，或在小队内拖动换位；把小队成员拖回卡池即移出（主角不可移出）")

	# 上：小队 1–4 号位
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	_content.add_child(slots)
	for i in range(TownManager.MAX_TEAM_SIZE):
		slots.add_child(_team_slot(i, gd))

	_content.add_child(HSeparator.new())

	# 下：卡池（也是「移出小队」的拖放目标）
	var pool_label := Label.new()
	pool_label.text = "人物卡池（拖入上方空位加入；拖到这里移出小队）"
	pool_label.add_theme_font_size_override("font_size", 14)
	pool_label.add_theme_color_override("font_color", Color("#6B6960"))
	var pool := DropTarget.new()
	pool.custom_minimum_size = Vector2(0, 200)
	pool.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_slot_style(pool)
	pool.accepts = func(data: Variant) -> bool:
		return data is Dictionary and data.get("kind", "") == "adventurer" \
			and data.get("from", "") == "team" and not town.is_protagonist(data.get("adventurer"))
	pool.on_drop = func(data: Variant) -> void:
		town.remove_from_team(data["adventurer"])
	_content.add_child(pool)
	pool.add_child(pool_label)
	var pool_cards := _card_grid(6)
	pool.add_child(pool_cards)
	if gd.roster.is_empty():
		pool.add_child(_empty_label("卡池为空，先去「招募成员」"))
	for a in gd.roster:
		pool_cards.add_child(_adventurer_card(a, {"kind": "adventurer", "adventurer": a, "from": "roster"}))


func _team_slot(i: int, gd: Node) -> Control:
	var slot := DropTarget.new()
	slot.custom_minimum_size = Vector2(150, 230)
	_empty_slot_style(slot)
	slot.accepts = func(data: Variant) -> bool:
		return data is Dictionary and data.get("kind", "") == "adventurer"
	slot.on_drop = func(data: Variant) -> void:
		var a: Adventurer = data["adventurer"]
		if data.get("from", "") == "team":
			town.reorder_to(a, i)
		else:
			town.insert_into_team(a, i)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	slot.add_child(box)

	var head := Label.new()
	head.text = "%d 号位" % (i + 1)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", Color("#6B6960"))
	box.add_child(head)

	if i < gd.team.size():
		var a: Adventurer = gd.team[i]
		var card := _adventurer_card(a, {"kind": "adventurer", "adventurer": a, "from": "team", "index": i})
		box.add_child(card)
		if town.is_protagonist(a):
			var lock := Label.new()
			lock.text = "主角（不可移出）"
			lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lock.add_theme_font_size_override("font_size", 12)
			lock.add_theme_color_override("font_color", Color("#B58121"))
			box.add_child(lock)
	else:
		var empty := Label.new()
		empty.text = "空位\n（拖入人物卡）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color("#9A978E"))
		box.add_child(empty)
	return slot


# ---- 伟业升级 ----

func _build_trophy() -> void:
	var gd := town._g()
	_back_home_btn()
	_section_title("伟业升级")
	_subtitle("左侧框放入人物卡，右侧框放入战利品卡，点击「伟业升级」消耗战利品提升人物等级")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(row)

	row.add_child(_trophy_slot("放入人物卡", _trophy_char, true))
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 8)
	var up := Button.new()
	up.text = "伟业升级"
	up.custom_minimum_size = Vector2(160, 56)
	up.add_theme_font_size_override("font_size", 18)
	up.disabled = _trophy_char == null or _trophy_item == null
	up.pressed.connect(_on_trophy_upgrade)
	mid.add_child(up)
	var clear := Button.new()
	clear.text = "清空"
	clear.pressed.connect(_on_trophy_clear)
	mid.add_child(clear)
	row.add_child(mid)
	row.add_child(_trophy_slot("放入战利品卡", _trophy_item, false))

	_content.add_child(HSeparator.new())
	_subtitle("小队与卡池人物（拖到左侧框）")
	var chars := HBoxContainer.new()
	chars.add_theme_constant_override("separation", 12)
	_content.add_child(chars)
	for a in gd.team:
		chars.add_child(_adventurer_card(a, {"kind": "adventurer", "adventurer": a, "from": "team", "index": gd.team.find(a)}))
	for a in gd.roster:
		chars.add_child(_adventurer_card(a, {"kind": "adventurer", "adventurer": a, "from": "roster"}))

	_content.add_child(HSeparator.new())
	var trophies := _bag_trophies()
	_subtitle("背包战利品（拖到右侧框）")
	if trophies.is_empty():
		_content.add_child(_empty_label("背包里没有战利品"))
	else:
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 12)
		_content.add_child(cards)
		for t in trophies:
			cards.add_child(_item_card(t, "战利品", {"kind": "item", "item": t}))


func _trophy_slot(caption: String, held: Variant, is_char: bool) -> Control:
	var slot := DropTarget.new()
	slot.custom_minimum_size = Vector2(200, 250)
	_empty_slot_style(slot)
	if is_char:
		slot.accepts = func(data: Variant) -> bool:
			return data is Dictionary and data.get("kind", "") == "adventurer"
		slot.on_drop = func(data: Variant) -> void:
			_trophy_char = data["adventurer"]
			_refresh()
	else:
		slot.accepts = func(data: Variant) -> bool:
			return data is Dictionary and data.get("kind", "") == "item" \
				and data.get("item") != null and data["item"].item_class == ItemData.ItemClass.TROPHY
		slot.on_drop = func(data: Variant) -> void:
			_trophy_item = data["item"]
			_refresh()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	slot.add_child(box)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", Color("#6B6960"))
	box.add_child(cap)
	if held != null:
		if is_char:
			box.add_child(_adventurer_card(held))
			var name_l := Label.new()
			name_l.text = "已放入：%s" % held.display_name
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(name_l)
		else:
			box.add_child(_item_card(held, "战利品"))
	else:
		var empty := Label.new()
		empty.text = "（拖入这里）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color("#9A978E"))
		box.add_child(empty)
	return slot


func _on_trophy_upgrade() -> void:
	if _trophy_char == null or _trophy_item == null:
		return
	if town.level_up_with_trophy(_trophy_char, _trophy_item):
		_trophy_char = null
		_trophy_item = null
		_hint.text = "伟业升级成功！"
		_refresh()


func _on_trophy_clear() -> void:
	_trophy_char = null
	_trophy_item = null
	_refresh()


# ---------------------------------------------------------------------------
# 标签 1：作战整备
# ---------------------------------------------------------------------------

func _build_prepare() -> void:
	var gd := town._g()
	if _deck_view:
		_build_deck_edit()
		return

	_section_title("作战整备")
	_subtitle("已自动选择队伍 1 号位，点击其他成员卡可切换；装备卡拖进装备栏即可穿上")

	# ---- 选择成员（默认 1 号位） ----
	if _selected_adventurer == null or not gd.team.has(_selected_adventurer):
		_selected_adventurer = gd.team[0] if not gd.team.is_empty() else null

	var sel_row := _card_grid(6)
	_content.add_child(sel_row)
	for a in gd.team:
		var holder := VBoxContainer.new()
		var card := _adventurer_card(a)
		for conn in card.clicked.get_connections():
			card.clicked.disconnect(conn["callable"])
		card.clicked.connect(_on_select_adventurer.bind(a))
		card.set_highlight(a == _selected_adventurer)
		holder.add_child(card)
		var tag := Label.new()
		tag.text = "1 号位" if gd.team.find(a) == 0 else "%d 号位" % (gd.team.find(a) + 1)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", Color("#6B6960"))
		holder.add_child(tag)
		sel_row.add_child(holder)

	if _selected_adventurer == null:
		return

	var a := _selected_adventurer
	_content.add_child(HSeparator.new())

	# ---- 加点 ----
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 8)
	_content.add_child(stat_row)
	for key in ["constitution", "strength", "intelligence", "vitality"]:
		var val: int = a.get(key)
		var btn := Button.new()
		btn.text = "%s %d +" % [STAT_CN[key], val]
		btn.disabled = a.unspent_points <= 0
		btn.pressed.connect(_on_spend_point.bind(a, key))
		stat_row.add_child(btn)
	var points_label := Label.new()
	points_label.text = "  剩余属性点 %d" % a.unspent_points
	points_label.add_theme_color_override("font_color", Color("#B58121"))
	stat_row.add_child(points_label)

	var stats := a.get_stats()
	var derived := Label.new()
	derived.text = "  %s  Lv.%d  血量 %d  蓝量 %d  物攻 %d  法攻 %d  物抗 %d  法抗 %d  技巧 %d  战力 %d" % [
		a.display_name, a.level, int(stats["hp"]), int(stats["mana"]), int(stats["phys_atk"]),
		int(stats["mag_atk"]), int(stats["phys_res"]), int(stats["mag_res"]), int(stats["technique"]), int(a.get_power()),
	]
	derived.add_theme_color_override("font_color", Color("#6B6960"))
	_content.add_child(derived)

	_content.add_child(HSeparator.new())

	# ---- 装备栏（多框，拖入即装备） ----
	_subtitle("装备栏（把背包装备卡拖进对应框）")
	var equip_grid := _card_grid(5)
	_content.add_child(equip_grid)
	for slot in SLOTS:
		equip_grid.add_child(_equip_slot(a, slot))

	# ---- 背包装备（拖拽源） ----
	var equippable := _bag_equipment()
	_subtitle("背包装备（%d 件，拖到上方装备栏）" % equippable.size())
	if equippable.is_empty():
		_content.add_child(_empty_label("背包里没有可穿的装备"))
	else:
		var bag := HBoxContainer.new()
		bag.add_theme_constant_override("separation", 12)
		_content.add_child(bag)
		for item in equippable:
			bag.add_child(_item_card(item, item.get_slot_name_cn(), {"kind": "item", "item": item}))

	_content.add_child(HSeparator.new())

	# ---- 卡组入口 ----
	var deck_info := Label.new()
	deck_info.text = "当前卡组 %d / %d 张（%s）" % [
		gd.deck.size(), TownManager.MAX_DECK, "合法" if town.is_deck_valid() else "不合法（需 20–40）",
	]
	_content.add_child(deck_info)
	var deck_btn := Button.new()
	deck_btn.text = "卡组整备"
	deck_btn.custom_minimum_size = Vector2(160, 44)
	deck_btn.pressed.connect(_on_open_deck)
	_content.add_child(deck_btn)


func _equip_slot(a: Adventurer, slot: ItemData.Slot) -> Control:
	var box := DropTarget.new()
	box.custom_minimum_size = Vector2(150, 210)
	_empty_slot_style(box)
	box.accepts = func(data: Variant) -> bool:
		return data is Dictionary and data.get("kind", "") == "item" \
			and data.get("item") != null and data["item"].is_equipment() and data["item"].slot == slot
	box.on_drop = func(data: Variant) -> void:
		town.equip(a, data["item"])

	var inner := VBoxContainer.new()
	box.add_child(inner)
	var cap := Label.new()
	cap.text = _slot_cn(slot)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", Color("#6B6960"))
	inner.add_child(cap)

	var item: ItemData = a.equipment.get(slot)
	if item != null:
		var card := _item_card(item, "已穿")
		card.custom_minimum_size = Vector2(120, 162)
		inner.add_child(card)
		var off := Button.new()
		off.text = "脱下"
		off.pressed.connect(_on_unequip.bind(a, slot))
		inner.add_child(off)
	else:
		var empty := Label.new()
		empty.text = "（空）\n拖入装备卡"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color("#9A978E"))
		inner.add_child(empty)
	return box


func _slot_cn(slot: ItemData.Slot) -> String:
	var probe := ItemData.new()
	probe.slot = slot
	return probe.get_slot_name_cn()


func _on_select_adventurer(_frame: CardFrame, a: Adventurer) -> void:
	_selected_adventurer = a
	_refresh()


func _on_spend_point(a: Adventurer, key: String) -> void:
	town.spend_point(a, key)


func _on_unequip(a: Adventurer, slot: ItemData.Slot) -> void:
	town.unequip(a, slot)


func _bag_equipment() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for it in town._g().inventory:
		if it.is_equipment():
			out.append(it)
	return out


func _bag_trophies() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for it in town._g().inventory:
		if it.item_class == ItemData.ItemClass.TROPHY:
			out.append(it)
	return out


# ---- 卡组整备子界面（左：全部战斗卡；右：卡组；拖拽编入/移出） ----

func _on_open_deck() -> void:
	_deck_view = true
	_refresh()


func _build_deck_edit() -> void:
	var gd := town._g()
	_section_title("整备卡组")
	_subtitle("左侧是你持有的战斗卡（编入数不能超过持有数），拖到右侧编入；从右侧拖回左侧即移出")

	var info := Label.new()
	info.text = "卡组 %d / %d 张（%s）" % [
		gd.deck.size(), TownManager.MAX_DECK, "合法" if town.is_deck_valid() else "不合法（需 20–40）",
	]
	info.add_theme_color_override("font_color", Color("#B58121"))
	_content.add_child(info)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)

	# 左：卡池（全部战斗卡，按分类）
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var left_title := Label.new()
	left_title.text = "持有卡牌（拖到右侧编入）"
	left_title.add_theme_color_override("font_color", Color("#185FA5"))
	left.add_child(left_title)

	# 左侧也是「移出卡组」的拖放目标
	var left_drop := DropTarget.new()
	left_drop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_slot_style(left_drop)
	left_drop.accepts = func(data: Variant) -> bool:
		return data is Dictionary and data.get("kind", "") == "deck_card"
	left_drop.on_drop = func(data: Variant) -> void:
		town.remove_card_from_deck(data["card"])
	left.add_child(left_drop)
	# 9-24 修改意见 3：卡池不再需要左右拖动。
	#   关掉横向滚动条 → 内容被钳到视口宽度内 → 配合 HFlowContainer 自动换行，
	#   卡池永远一屏排得下，只上下滚动。
	_set_h_scroll(true)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(0, 380)
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_drop.add_child(left_scroll)

	var left_pool := VBoxContainer.new()
	left_pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_pool.add_theme_constant_override("separation", 10)
	left_scroll.add_child(left_pool)

	# 意见 6：按物理/法术 × 进攻/防御/特殊 六分类分组；
	# 每组 = 一行标题 + 一个自动折行的卡片流（HFlowContainer 按可视宽度决定每行几张）
	var groups := town.cards_by_category(true)
	for grp in groups:
		var cards: Array[CardData] = grp["cards"]
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation", 6)
		left_pool.add_child(block)

		var cls_label := Label.new()
		cls_label.name = "PoolGroup_" + str(grp["name"])
		cls_label.text = "%s卡（%d 种）" % [grp["name"], cards.size()]
		cls_label.add_theme_color_override("font_color", Color("#3B6D11"))
		block.add_child(cls_label)

		var flow := HFlowContainer.new()
		flow.name = "PoolFlow_" + str(grp["name"])
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		block.add_child(flow)

		for card in cards:
			var in_deck := _count_in_deck(card)
			var owned: int = gd.owned_card_count(card.id)
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 2)
			cell.custom_minimum_size = Vector2(128, 0)
			var frame := _battle_card(card)
			frame.drag_payload = {"kind": "card", "card": card}
			cell.add_child(frame)
			var cnt := Label.new()
			cnt.text = "持有 %d · 编入 %d" % [owned, in_deck]
			cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cnt.add_theme_font_size_override("font_size", 12)
			# autowrap 的 Label 最小宽度为 0，放进流式容器会被压成一列一个字 → 关掉换行
			cnt.autowrap_mode = TextServer.AUTOWRAP_OFF
			cnt.custom_minimum_size = Vector2(128, 0)
			if in_deck >= owned:
				cnt.add_theme_color_override("font_color", Color("#B58121"))
			elif in_deck > 0:
				cnt.add_theme_color_override("font_color", Color("#3B6D11"))
			else:
				cnt.add_theme_color_override("font_color", Color("#6B6960"))
			cell.add_child(cnt)
			flow.add_child(cell)

	# 右：卡组（拖出即移除）
	var right := DropTarget.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_slot_style(right)
	right.accepts = func(data: Variant) -> bool:
		return data is Dictionary and data.get("kind", "") == "card"
	right.on_drop = func(data: Variant) -> void:
		town.add_card_to_deck(data["card"])
	cols.add_child(right)
	var right_box := VBoxContainer.new()
	right.add_child(right_box)
	var right_title := Label.new()
	right_title.text = "当前卡组（拖回左侧移出）"
	right_title.add_theme_color_override("font_color", Color("#185FA5"))
	right_box.add_child(right_title)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box.add_child(right_scroll)
	var right_grid := _card_grid(3)
	right_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_grid)
	if gd.deck.is_empty():
		right_grid.add_child(_empty_label("卡组为空，从左侧拖入战斗卡"))
	for card in gd.deck:
		var frame := _battle_card(card)
		frame.drag_payload = {"kind": "deck_card", "card": card}
		right_grid.add_child(frame)

	var back := Button.new()
	back.text = "← 返回整备"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(_on_close_deck)
	_content.add_child(back)


func _on_close_deck() -> void:
	_deck_view = false
	_refresh()


func _count_in_deck(card: CardData) -> int:
	var n := 0
	for c in town._g().deck:
		if c == card:
			n += 1
	return n


## 某张联合卡本体的前置组件卡（按 combo_complete 里声明的部件顺序）。
## 用于卡牌详情里提示"这张卡还需要哪些组件才打得出去"。
func _combo_component_cards(card: CardData) -> Array[CardData]:
	var out: Array[CardData] = []
	if card == null or not card.is_combo_payoff():
		return out
	for part in card.combo_complete:
		for c in town._g().db.cards.values():
			var cd := c as CardData
			if cd.is_combo_component() and cd.combo_key == card.combo_key \
				and cd.combo_part == String(part):
				out.append(cd)
				break
	return out


# ---------------------------------------------------------------------------
# 标签 2：商店（商品与背包全部卡牌化）
# ---------------------------------------------------------------------------

func _build_shop() -> void:
	var gd := town._g()
	_section_title("商店")

	# 9-22 修改意见 8：刷新按钮放到最上面
	var refresh := Button.new()
	refresh.text = "刷新商品"
	refresh.custom_minimum_size = Vector2(180, 40)
	refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	refresh.pressed.connect(_on_refresh_shop)
	_content.add_child(refresh)

	_subtitle("购买（刷新次数 %d）—— 右键查看卡牌详情" % gd.refresh_store)

	if _shop_items.is_empty():
		_roll_shop()
	var grid := _card_grid(4)
	_content.add_child(grid)
	for item in _shop_items:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(_item_card(item, "%d 金" % item.sell_price))
		var btn := Button.new()
		btn.text = "购买 %d 金" % item.sell_price
		btn.disabled = gd.gold < item.sell_price
		btn.pressed.connect(_on_buy.bind(item))
		cell.add_child(btn)
		grid.add_child(cell)

	# 意见 8：商人卖战斗卡牌（买到即入库，可在「整备」里编入卡组）
	_content.add_child(HSeparator.new())
	_subtitle("卡牌（持有 %d 张 · 售价按稀有度）—— 右键查看详情" % gd.owned_cards.size())
	if town.shop_cards.is_empty():
		_content.add_child(_empty_label("本店卡牌已售罄，刷新商品可补货"))
	else:
		var card_grid := _card_grid(4)
		_content.add_child(card_grid)
		for entry in town.shop_cards:
			var card: CardData = entry["card"]
			var price: int = entry["price"]
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(_battle_card(card))
			var btn := Button.new()
			btn.text = "买卡 %d 金" % price
			btn.disabled = gd.gold < price
			btn.pressed.connect(_on_buy_card.bind(card))
			cell.add_child(btn)
			card_grid.add_child(cell)

	_content.add_child(HSeparator.new())
	_subtitle("售卖（背包 %d 件，售价为原价一半）—— 右键查看卡牌详情" % gd.inventory.size())
	if gd.inventory.is_empty():
		_content.add_child(_empty_label("背包为空"))
	else:
		var grid2 := _card_grid(4)
		_content.add_child(grid2)
		for item in gd.inventory.duplicate():
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(_item_card(item, "卖 %d 金" % maxi(item.sell_price / 2, 1)))
			var btn := Button.new()
			btn.text = "出售"
			btn.pressed.connect(_on_sell.bind(item))
			cell.add_child(btn)
			grid2.add_child(cell)


func _on_buy(item: ItemData) -> void:
	town.buy(item)


func _on_sell(item: ItemData) -> void:
	town.sell(item)


func _on_refresh_shop() -> void:
	if town.try_refresh_store():
		_roll_shop()
		_refresh()


func _on_buy_card(card: CardData) -> void:
	town.buy_card(card)


func _roll_shop() -> void:
	_shop_items = town.roll_shop()
	# 意见 8：刷新商品时同时补货卡牌
	town.roll_shop_cards()


# ---------------------------------------------------------------------------
# 标签 3：仓库（卡牌化）
# ---------------------------------------------------------------------------

func _build_storage() -> void:
	var gd := town._g()
	_section_title("仓库")

	_subtitle("背包 → 仓库（右键查看卡牌详情）")
	if gd.inventory.is_empty():
		_content.add_child(_empty_label("背包为空"))
	else:
		var grid := _card_grid(4)
		_content.add_child(grid)
		for item in gd.inventory.duplicate():
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(_item_card(item, item.get_rarity_name_cn()))
			var btn := Button.new()
			btn.text = "存入"
			btn.pressed.connect(_on_store.bind(item))
			cell.add_child(btn)
			grid.add_child(cell)

	_content.add_child(HSeparator.new())
	_subtitle("仓库 → 背包（%d 件）" % gd.storage.size())
	if gd.storage.is_empty():
		_content.add_child(_empty_label("仓库为空"))
	else:
		var grid2 := _card_grid(4)
		_content.add_child(grid2)
		for item in gd.storage.duplicate():
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.add_child(_item_card(item, item.get_rarity_name_cn()))
			var btn := Button.new()
			btn.text = "取回"
			btn.pressed.connect(_on_retrieve.bind(item))
			cell.add_child(btn)
			grid2.add_child(cell)


func _on_store(item: ItemData) -> void:
	town.store(item)


func _on_retrieve(item: ItemData) -> void:
	town.retrieve(item)


# ---------------------------------------------------------------------------
# 标签 4：卡牌大全（卡牌化）
# ---------------------------------------------------------------------------

## 卡牌大全的"大节"标题（战斗卡牌 / 装备 / 道具与杂物）。
##
## 页面上有三层标题，必须让它一眼分得开：
##   大节（17px 深蓝 + 左侧竖条） → 分组（14px 蓝） → 卡面（自带卡名）
## 所以大节用"▍"前缀做视觉锚点。
func _codex_chapter(text: String) -> Label:
	var l := Label.new()
	l.text = "▍%s" % text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("#2B4C7E"))
	_content.add_child(l)
	return _outline(l)


## 卡牌大全的分组标题（物理进攻卡 / 装备 · 武器 / 道具 …）
func _codex_group(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("#185FA5"))
	_content.add_child(l)
	return _outline(l)


## 往 _content 里铺一组卡：分组标题 + 6 列网格 + 已建好的卡面
func _codex_grid(title: String, cards: Array) -> void:
	_codex_group(title)
	var grid := _card_grid(6)
	_content.add_child(grid)
	for c in cards:
		grid.add_child(c as Control)


## 标签 4：卡牌大全（9-26 起同时收录**战斗卡牌 + 装备 + 物品**）
func _build_codex() -> void:
	var n_card: int = town._g().db.cards.size()

	var equip_groups: Array = []
	var other_groups: Array = []
	var n_equip := 0
	var n_other := 0
	for grp in town.items_by_group():
		var n: int = (grp["items"] as Array).size()
		if String(grp["chapter"]) == "equip":
			equip_groups.append(grp)
			n_equip += n
		else:
			other_groups.append(grp)
			n_other += n

	_section_title("卡牌大全")
	_subtitle("共 %d 张战斗卡牌 + %d 件装备与物品 —— 右键查看详情" % [n_card, n_equip + n_other])

	# ---- 大节一：战斗卡牌（物理/法术 × 进攻/防御/特殊 六分类）----
	_codex_chapter("战斗卡牌（%d 张）" % n_card)
	for grp in town.cards_by_category(false):
		var cards: Array = grp["cards"]
		var views: Array = []
		for c in cards:
			views.append(_battle_card(c as CardData))
		_codex_grid("%s卡（%d 张）" % [grp["name"], cards.size()], views)

	# ---- 大节二：装备（按可穿戴部位细分）----
	if not equip_groups.is_empty():
		_codex_chapter("装备（%d 件）" % n_equip)
		for grp in equip_groups:
			_add_item_grid(String(grp["name"]), grp["items"] as Array)

	# ---- 大节三：道具与杂物（消耗品 / 收集品 / 战利品 / 杂物）----
	if not other_groups.is_empty():
		_codex_chapter("道具与杂物（%d 件）" % n_other)
		for grp in other_groups:
			_add_item_grid(String(grp["name"]), grp["items"] as Array)


func _add_item_grid(group_name: String, items: Array) -> void:
	var views: Array = []
	for it in items:
		views.append(_item_card(it as ItemData))
	_codex_grid("%s（%d 件）" % [group_name, items.size()], views)
