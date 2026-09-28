## 主菜单
##
## 布局：菜单整体居中，金币显示在右上角，不展示小队人数 / 总战力等状态信息。
##
## 9-28 需求：
##   ① 新增「游玩指南」（可滚动的规则说明面板）
##   ② 「存档」改成 **10 个栏位**：点空栏位保存、点已有栏位先确认再覆盖
##   ③ 「读档」改成点已有存档直接载入
##   ④ 每个栏位下面显示这个档的**游玩时长**与最后保存时间
##
## 浮层（设置 / 存档 / 读档 / 指南）统一由 `_open_overlay()` 搭，
## 只允许同时存在一层；覆盖确认另起一层盖在上面。
extends Control


const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"
const RUN_SCENE := "res://scenes/dungeon/run_scene.tscn"
const TOWN_SCENE := "res://scenes/town/town_scene.tscn"

## 菜单项：标题 -> [是否已实现, 说明]
##
## 9-28 需求：**地下城探索放到第二位、紧挨着「快速战斗」** ——
## 这两条都是"进战斗"的入口，放一起才顺手（原先夹在卡牌大全和存档之间）。
const MENU_ITEMS := [
	["地下城探索", true, "逐层推进，打完 Boss 选择撤离或继续"],
	["冒险者工会", true, "接任务 / 招募 / 组队 / 提升"],
	["作战整备", true, "加点 / 穿脱装备 / 编辑卡组"],
	["商店", true, "买卖物品与卡牌"],
	["仓库", true, "长期存储"],
	["卡牌大全", true, "查看全部卡牌"],
	["游玩指南", true, "规则说明：战斗 / 卡牌 / 地牢 / 养成"],
	["存档", true, "10 个栏位，选一个写入"],
	["读档", true, "点已有存档即可载入"],
	["游戏设置", true, "音量 / 静音"],
	["退出游戏", true, ""],
]

## 阶段 2 的验证入口，单独放在最上方
const QUICK_BATTLE_TEXT := "⚡ 快速战斗（新手地穴 · 第 1 层）"

## 设置面板里三个音量滑杆的配置：显示名 → AudioManager 的读写方法名
const VOLUME_ROWS := [
	["主音量", "get_master_volume", "set_master_volume"],
	["音乐", "get_music_volume", "set_music_volume"],
	["音效", "get_sfx_volume", "set_sfx_volume"],
]

## 浮层种类（`_overlay_kind`）。测试靠这些值判断"现在开的是哪一层"。
const OVERLAY_SETTINGS := "settings"
const OVERLAY_SLOTS_SAVE := "slots_save"
const OVERLAY_SLOTS_LOAD := "slots_load"
const OVERLAY_GUIDE := "guide"

## 栏位数（跟随 SaveManager，改一处即可）
const SLOT_COUNT := SaveManager.SLOT_COUNT

## 游玩指南正文：[小节标题, 内容]
##
## 🔴 内容必须**与当前代码里的实际规则一致**（不是 v2.0 设计稿）。
## 改了规则就要回来改这里 —— 指南写错比没有指南更糟。
const GUIDE_SECTIONS := [
	["目标",
		"带着你的小队深入 5 层地牢。招募人手、分配属性、穿好装备、构筑卡组，\n"
		+ "一路推进到「深渊之底」。每层的终点是层 Boss —— 打赢它才能选择撤离或继续向下。"],
	["战斗：一回合怎么打",
		"· 每回合开始时，每个角色恢复 1 点行动点、5 点蓝量（都不会超过各自上限）。\n"
		+ "· 打出一张卡要消耗它的行动点与蓝量；行动点用光就只能结束回合。\n"
		+ "· 出牌方式：把卡从手牌拖到目标身上。只能对自己用的卡会直接指向释放者。\n"
		+ "· 每个角色有独立的血量、蓝量与护盾。护盾先扣、回合结束时清空。\n"
		+ "· 敌方每回合最多有 3 只怪攻击同一个人 —— 别把脆皮单独丢在前面。\n"
		+ "· 使用道具消耗 1 点行动点。"],
	["卡牌：六分类与费用",
		"· 卡牌分 进攻 / 防御 / 特殊 三大类，每类再分物理与法术，共六分类。\n"
		+ "· 物理卡不耗蓝，法术卡耗蓝 —— 这是两套资源，别只盯着行动点。\n"
		+ "· 手牌上限 12 张。进入新节点时重新抽 8 张起手；之后每回合抽 2 张；\n"
		+ "  牌库抽空会把弃牌堆洗回来，所以卡组越紧凑越容易关键牌上手。\n"
		+ "· 卡的描述里写着倍率（如「物攻 ×1.8」），倍率越高越吃对应属性。"],
	["联合卡（共鸣）",
		"有些卡是组件卡（风之符文、火之符文…），单独打出没有任何效果，\n"
		+ "只会在本回合内「就位」。\n"
		+ "在同一回合内把一组组件全部打出，对应的联合卡本体才按得下去。\n"
		+ "前置没凑齐时，手牌里的联合卡会变暗、拖不动。\n"
		+ "部件槽以我方回合为界，回合结束清空 —— 不能跨回合攒。"],
	["地牢：五层推进",
		"1 新手地穴 · 2 幽暗回廊 · 3 深渊裂口 · 4 巫王墓庭 · 5 深渊之底\n"
		+ "越深怪越强、奖励也越丰厚。\n"
		+ "每层是一张分叉的小地图（3 列）：点高亮的相邻节点前进，节点可能是战斗、\n"
		+ "宝箱或事件；终点是层 Boss 房。\n"
		+ "打赢层 Boss 后可以撤离（带走战利品，结束本轮）或继续向下。\n"
		+ "通关过某层 Boss 之后，下次出征可以付金币直接从那一层开始（第 1 层免费）。"],
	["失败与代价",
		"全队濒死即本轮失败：金币、经验、等级会回滚到本轮开始之前，\n"
		+ "背包里的随身物品清空。\n"
		+ "仓库里的东西不受影响 —— 贵重物品记得先存进仓库。"],
	["城镇：五个去处",
		"· 冒险者工会 —— 接任务、招募、组队、提升\n"
		+ "· 作战整备 —— 分配属性点、穿脱装备、编辑卡组\n"
		+ "· 商店 —— 买卡与物品\n"
		+ "· 仓库 —— 长期存放，死亡不清空\n"
		+ "· 卡牌大全 —— 查全部卡牌与装备物品"],
	["人物养成：四属性与战力",
		"四属性：体质（血量 + 双抗）、力量（物攻）、智力（法攻与治疗）、精力（行动点）。\n"
		+ "主要派生关系：\n"
		+ "  血量 = 体质×6 + 精力×2 + 力量×1\n"
		+ "  蓝量 = 智力×4 + 精力×2 + 体质×1\n"
		+ "  物攻 = 力量×2 + 精力×0.5　　法攻 = 智力×2 + 精力×0.5\n"
		+ "  物抗 = 体质×1 + 力量×0.5　　法抗 = 体质×1 + 智力×0.5\n"
		+ "  技巧 = (智力 + 力量) × 0.5（影响暴击）\n"
		+ "战力 = 血量×0.5 + (物攻+法攻)×1.5 + (物抗+法抗)×1.0 + 技巧×2.0。\n"
		+ "队伍总战力 = 成员战力合计 × 人数系数（1 人 1.00 / 2 人 1.05 / 3 人 1.10 / 4 人以上 1.15）。\n"
		+ "升级会获得属性点，去「作战整备」分配。"],
	["存档与读档",
		"共 10 个栏位。点「存档」再点一个栏位写入；栏位下方显示这个档的游玩时长\n"
		+ "与最后保存时间。点「读档」再点一个已有存档即可载入。\n"
		+ "覆盖已有存档前会先确认一次。游玩时长跟着档走，不会因为你换了栏位而混在一起。"],
]

@onready var _menu_box: VBoxContainer = %MenuBox
@onready var _gold_label: Label = %GoldLabel
@onready var _toast: Label = %ToastLabel

## 当前浮层（设置 / 存档 / 读档 / 指南）。同一时刻只存在一层。
var _overlay: Control = null
var _overlay_kind: String = ""
## 覆盖确认层（盖在存档面板之上）
var _confirm: Control = null
## 存档面板当前模式，覆盖确认后用来重建面板
var _slot_mode: String = OVERLAY_SLOTS_SAVE
var _backdrop: SceneBackdrop = null


func _ready() -> void:
	# 主菜单 BGM（与开屏同一首 → 不重启，听感连贯）
	AudioManager.play_bgm("title")
	# 背景：城镇远景（9-28 需求「主页面是城镇」）
	_backdrop = SceneBackdrop.attach(self, "menu_town", SceneBackdrop.SCRIM_MENU)
	_outline_over_scenery()
	_build_menu()
	_refresh_status()


## 压在背景图上、又没有面板垫底的那几条文字加描边（9-28）。
## 菜单按钮本身是不透明的，按钮文字不用管。
func _outline_over_scenery() -> void:
	var targets: Array[Node] = [
		_gold_label,
		_toast,
		get_node_or_null("CenterBox/VBox/Title"),
		get_node_or_null("CenterBox/VBox/Subtitle"),
	]
	for n in targets:
		var l := n as Label
		if l != null:
			l.add_theme_color_override("font_outline_color", Color("#fbfaf6"))
			l.add_theme_constant_override("outline_size", 4)


func _build_menu() -> void:
	for child in _menu_box.get_children():
		child.queue_free()

	# 快速战斗入口
	var quick := Button.new()
	quick.text = QUICK_BATTLE_TEXT
	quick.custom_minimum_size = Vector2(320, 46)
	quick.pressed.connect(_on_quick_battle)
	_menu_box.add_child(quick)

	_menu_box.add_child(HSeparator.new())

	for entry in MENU_ITEMS:
		var title: String = entry[0]
		var implemented: bool = entry[1]
		var btn := Button.new()
		btn.text = title
		btn.custom_minimum_size = Vector2(320, 40)
		btn.disabled = not implemented
		if not implemented:
			btn.tooltip_text = "尚未实现 —— %s" % entry[2]
		if title == "退出游戏":
			btn.pressed.connect(_on_quit)
		elif title == "地下城探索":
			btn.pressed.connect(_on_dungeon)
		elif title == "游玩指南":
			btn.pressed.connect(open_guide)
		elif title == "存档":
			btn.pressed.connect(open_save_slots)
		elif title == "读档":
			btn.pressed.connect(open_load_slots)
		elif title == "游戏设置":
			btn.pressed.connect(open_audio_settings)
		else:
			btn.pressed.connect(_on_town.bind(title))
		_menu_box.add_child(btn)


## 修改意见 2：只刷新右上角金币；状态信息不再展示（校验失败改走底部提示）
func _refresh_status() -> void:
	_gold_label.text = "金币：%d" % GameData.gold
	if not GameData.validator_ok:
		print("[主菜单] 数据校验失败，共 %d 条错误（详见控制台）" % GameData.validator_errors.size())
		_flash_menu("数据校验失败，共 %d 条错误" % GameData.validator_errors.size())


func _on_quick_battle() -> void:
	print("[主菜单] 进入快速战斗")
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_dungeon() -> void:
	print("[主菜单] 进入地下城探索")
	# 清掉可能残留的战斗上下文，从准备界面开始
	GameData.last_battle_result = {}
	GameData.pending_encounter = {}
	GameData.return_scene = ""
	# 意见 1：上一轮已结束的 run 直接丢弃，避免重进时卡在旧地图
	if GameData.run != null and GameData.run.status != RunManager.Status.EXPLORING:
		GameData.run = null
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_town(tab_title: String) -> void:
	print("[主菜单] 进入城镇：%s" % tab_title)
	GameData.pending_initial_tab = tab_title
	get_tree().change_scene_to_file(TOWN_SCENE)


## 底部临时提示（存档 / 读档 / 校验告警），1.6 秒后淡出
func _flash_menu(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _on_quit() -> void:
	get_tree().quit()


# ---------------------------------------------------------------------------
# 通用浮层
#
# 设置 / 存档 / 读档 / 指南 四层长得一样（半透明底 + 居中面板 + 标题 + 内容 + 关闭），
# 只是内容不同，所以只搭一次。同一时刻只允许一层。
# ---------------------------------------------------------------------------

func is_overlay_open() -> bool:
	return _overlay != null and is_instance_valid(_overlay) and _overlay.visible


func current_overlay_kind() -> String:
	return _overlay_kind if is_overlay_open() else ""


## 打开一层浮层，返回可以往里塞控件的 VBox。
##
## `scrollable` 为真时内容放进 ScrollContainer（游玩指南、10 个栏位都用得上）。
func _open_overlay(kind: String, layer_name: String, title: String,
		min_size: Vector2, scrollable: bool = false,
		scroll_height: float = 0.0) -> VBoxContainer:
	close_confirm()
	close_overlay()
	_overlay_kind = kind

	var layer := Control.new()
	layer.name = layer_name
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = layer

	# 半透明底：同时负责拦住背后的菜单点击
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = "OverlayPanel"
	panel.custom_minimum_size = min_size
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.name = "OverlayBox"
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var head := Label.new()
	head.name = "OverlayTitle"
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 24)
	outer.add_child(head)
	outer.add_child(HSeparator.new())

	var content := VBoxContainer.new()
	content.name = "OverlayContent"
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scrollable:
		var scroll := ScrollContainer.new()
		scroll.name = "OverlayScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if scroll_height > 0.0:
			scroll.custom_minimum_size = Vector2(0, scroll_height)
		outer.add_child(scroll)
		scroll.add_child(content)
	else:
		outer.add_child(content)
	return content


func close_overlay() -> void:
	close_confirm()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_overlay_kind = ""


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close_overlay()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.keycode != KEY_ESCAPE:
		return
	# ESC 先关最上面那层
	if _confirm != null and is_instance_valid(_confirm):
		close_confirm()
	else:
		close_overlay()


## 面板底部统一的「返回 / 关闭」按钮
func _add_close_button(parent: VBoxContainer, text: String = "返回") -> Button:
	parent.add_child(HSeparator.new())
	var btn := Button.new()
	btn.name = "CloseButton"
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(close_overlay)
	parent.add_child(btn)
	return btn


# ---------------------------------------------------------------------------
# 存档 / 读档：10 个栏位（9-28 需求）
# ---------------------------------------------------------------------------

func open_save_slots() -> void:
	_open_slots(OVERLAY_SLOTS_SAVE)


func open_load_slots() -> void:
	_open_slots(OVERLAY_SLOTS_LOAD)


func _open_slots(kind: String, flash: String = "") -> void:
	var is_save := kind == OVERLAY_SLOTS_SAVE
	_slot_mode = kind
	var content := _open_overlay(
		kind,
		"SaveLayer" if is_save else "LoadLayer",
		"存档" if is_save else "读档",
		Vector2(720, 0), true, 430.0)

	var tip := Label.new()
	tip.name = "SlotsTip"
	tip.text = flash if flash != "" else (
		"点击一个空栏位保存进度；已有存档会先确认再覆盖。" if is_save
		else "点击一个已有存档读取进度。空栏位不可选。")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color",
		Color("#185FA5") if flash != "" else Color("#6B6960"))
	content.add_child(tip)

	var slots := VBoxContainer.new()
	slots.name = "SlotList"
	slots.add_theme_constant_override("separation", 8)
	content.add_child(slots)

	var sm := SaveManager.new()
	for info in sm.list_slots():
		slots.add_child(_build_slot_row(info, is_save))

	_add_close_button(content)


## 一个栏位 = 一行按钮，里面三行字：
##   标题行（栏位 N + 状态标签）/ 摘要行 / **游玩时长 + 最后保存**（需求要求附在每个档下面）
func _build_slot_row(info: Dictionary, is_save: bool) -> Button:
	var slot := int(info["slot"])
	var empty := bool(info["empty"])

	var btn := Button.new()
	btn.name = "Slot_%d" % slot
	btn.custom_minimum_size = Vector2(0, 74)
	# 读档模式下空栏位不可点（需求：点"有的"存档才读档）
	btn.disabled = (not is_save) and empty

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_top = 8
	box.offset_right = -14
	box.offset_bottom = -8
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	btn.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)

	var name_label := Label.new()
	name_label.name = "SlotName_%d" % slot
	name_label.text = "栏位 %d" % (slot + 1)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	var tag := Label.new()
	tag.name = "SlotTag_%d" % slot
	tag.add_theme_font_size_override("font_size", 14)
	head.add_child(tag)

	var summary := Label.new()
	summary.name = "SlotSummary_%d" % slot
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color("#5C5A52"))
	box.add_child(summary)

	var when := Label.new()
	when.name = "SlotTime_%d" % slot
	when.add_theme_font_size_override("font_size", 13)
	when.add_theme_color_override("font_color", Color("#185FA5"))
	box.add_child(when)

	if empty:
		tag.text = "空栏位"
		tag.add_theme_color_override("font_color", Color("#8A8880"))
		summary.text = "还没有存档"
		when.text = "点击此栏位写入当前进度" if is_save else "——"
	else:
		tag.text = "有存档"
		tag.add_theme_color_override("font_color", Color("#3B6D11"))
		summary.text = "金币 %d · 小队 %d 人（Lv%d）· 卡组 %d 张 · 已通关 %d 层" % [
			int(info["gold"]), int(info["team_size"]), int(info["team_level"]),
			int(info["deck_size"]), int(info["cleared_max"])]
		if bool(info.get("legacy", false)):
			# v1 旧存档没有记时长 → 别假装是 0 分钟
			when.text = "旧版存档：未记录游玩时长与保存时间（下次保存后补上）"
		else:
			when.text = "游玩 %s · 最后保存 %s" % [
				SaveManager.format_playtime(int(info["playtime"])),
				SaveManager.format_saved_at(int(info["saved_at"]))]

	btn.pressed.connect(_on_slot_pressed.bind(slot, empty, is_save))
	return btn


## 信号 `pressed` 没有参数 → handler 收到的就是 bind 进去的三个
func _on_slot_pressed(slot: int, empty: bool, is_save: bool) -> void:
	if not is_save:
		_do_load(slot)
		return
	if empty:
		_do_save(slot)
		return
	# 已有存档 → 先确认再覆盖（误点一下就丢进度太痛）
	var sm := SaveManager.new()
	var info := sm.slot_info(slot)
	_open_confirm(
		"覆盖栏位 %d？" % (slot + 1),
		"这个栏位里已经有一份存档：\n"
		+ "金币 %d · 小队 %d 人 · 游玩 %s · 最后保存 %s\n\n"
		% [int(info["gold"]), int(info["team_size"]),
		   SaveManager.format_playtime(int(info["playtime"])),
		   SaveManager.format_saved_at(int(info["saved_at"]))]
		+ "覆盖后原来的进度将无法恢复。",
		"覆盖存档",
		func() -> void: _do_save(slot))


func _do_save(slot: int) -> void:
	var sm := SaveManager.new()
	if sm.save(slot):
		_open_slots(_slot_mode, "已保存到栏位 %d。" % (slot + 1))
	else:
		_open_slots(_slot_mode, "栏位 %d 保存失败。" % (slot + 1))


func _do_load(slot: int) -> void:
	var sm := SaveManager.new()
	if sm.load(slot):
		_refresh_status()
		close_overlay()
		_flash_menu("已读取栏位 %d" % (slot + 1))
	else:
		_open_slots(_slot_mode, "栏位 %d 读取失败。" % (slot + 1))


# ---------------------------------------------------------------------------
# 覆盖确认（盖在存档面板之上的一层）
# ---------------------------------------------------------------------------

func is_confirm_open() -> bool:
	return _confirm != null and is_instance_valid(_confirm)


func _open_confirm(title: String, body: String, ok_text: String, on_ok: Callable) -> void:
	close_confirm()

	var layer := Control.new()
	layer.name = "ConfirmLayer"
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm = layer

	# 这一层只负责挡住点击，不接 gui_input —— 点空白处不关闭，必须明确选一个
	var dim := ColorRect.new()
	dim.name = "ConfirmDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 20)
	box.add_child(head)

	var text := Label.new()
	text.name = "ConfirmBody"
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", Color("#3A3A34"))
	box.add_child(text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	var ok := Button.new()
	ok.name = "ConfirmOk"
	ok.text = ok_text
	ok.custom_minimum_size = Vector2(140, 38)
	row.add_child(ok)

	var cancel := Button.new()
	cancel.name = "ConfirmCancel"
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(140, 38)
	row.add_child(cancel)

	ok.pressed.connect(func() -> void:
		close_confirm()
		on_ok.call())
	cancel.pressed.connect(close_confirm)


func close_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null


# ---------------------------------------------------------------------------
# 游玩指南（9-28 需求）
# ---------------------------------------------------------------------------

func open_guide() -> void:
	var content := _open_overlay(OVERLAY_GUIDE, "GuideLayer", "游玩指南",
		Vector2(780, 0), true, 470.0)

	for section in GUIDE_SECTIONS:
		var head := Label.new()
		head.text = "▍%s" % String(section[0])
		head.add_theme_font_size_override("font_size", 18)
		head.add_theme_color_override("font_color", Color("#2B4C7E"))
		content.add_child(head)

		var body := Label.new()
		body.text = String(section[1])
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 14)
		body.add_theme_color_override("font_color", Color("#3A3A34"))
		body.add_theme_constant_override("line_spacing", 2)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.custom_minimum_size = Vector2(680, 0)
		content.add_child(body)

	_add_close_button(content, "关闭")


# ---------------------------------------------------------------------------
# 游戏设置（9-25 需求：有声音之后必须能调音量 / 静音）
# ---------------------------------------------------------------------------

func open_audio_settings() -> void:
	if is_settings_open():
		return

	var content := _open_overlay(OVERLAY_SETTINGS, "SettingsLayer", "游戏设置",
		Vector2(460, 0))

	for row in VOLUME_ROWS:
		_add_volume_row(content, String(row[0]), String(row[1]), String(row[2]))

	var mute := CheckBox.new()
	mute.name = "MuteCheck"
	mute.text = "静音（全部音频）"
	mute.button_pressed = AudioManager.muted
	mute.toggled.connect(_on_mute_toggled)
	content.add_child(mute)

	_add_close_button(content)


func close_audio_settings() -> void:
	if is_settings_open():
		close_overlay()


func is_settings_open() -> bool:
	return is_overlay_open() and _overlay_kind == OVERLAY_SETTINGS


func is_guide_open() -> bool:
	return is_overlay_open() and _overlay_kind == OVERLAY_GUIDE


func is_slots_open() -> bool:
	return is_overlay_open() \
		and (_overlay_kind == OVERLAY_SLOTS_SAVE or _overlay_kind == OVERLAY_SLOTS_LOAD)


## 一行 = 「名称 + 滑杆 + 百分比」。取值/写值都走 AudioManager 的同名方法，
## 所以面板、总线、存档三者永远一致。
func _add_volume_row(parent: VBoxContainer, label_text: String,
		getter: String, setter: String) -> HSlider:
	var row := HBoxContainer.new()
	row.name = "Row_" + label_text
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = label_text
	lb.custom_minimum_size = Vector2(76, 0)
	row.add_child(lb)

	var slider := HSlider.new()
	slider.name = "Slider_" + label_text
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(AudioManager.call(getter))
	slider.custom_minimum_size = Vector2(230, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var pct := Label.new()
	pct.name = "Pct_" + label_text
	pct.custom_minimum_size = Vector2(54, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % int(round(slider.value * 100.0))
	row.add_child(pct)

	var setter_callable := Callable(AudioManager, setter)
	slider.value_changed.connect(_on_volume_changed.bind(setter_callable, pct))
	return slider


func _on_volume_changed(value: float, setter: Callable, pct: Label) -> void:
	pct.text = "%d%%" % int(round(value * 100.0))
	setter.call(value)


func _on_mute_toggled(on: bool) -> void:
	AudioManager.set_muted(on)
