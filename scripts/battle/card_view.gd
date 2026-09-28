## 战斗卡牌显示控件
##
## 视觉统一使用 CardFrame（卡牌边框模板：上图片 / 中描述 / 下名字）。
## 行为：
##   - 悬停：以底边中点为轴放大突显（意见 4）
##   - 拖拽：按住并移动即开始拖拽，松手在目标上释放（意见 4）
##   - 只有「可打出」（作用范围 / 资源合法）的卡牌才允许拖拽（意见 4）
class_name CardView
extends Control


signal drag_started(view: CardView)
signal drag_released(view: CardView, global_pos: Vector2)
signal clicked(view: CardView)


## 与战斗卡边框比例一致（750×1050 → 1:1.4）
## 9-23 修改意见 2（手牌文字模糊）：100×140 下手牌里的中文字号只能压到 9px，
## 必然发糊；放大到 112×157 后同一套排版可以把字号提到 11–12px。
const CARD_SIZE := Vector2(112, 157)
const HOVER_SCALE := 1.30            ## 悬停放大倍率
const RARITY_COLORS := {
	CardData.Rarity.COMMON: Color("#D3D1C7"),
	CardData.Rarity.RARE: Color("#97C459"),
	CardData.Rarity.EPIC: Color("#AFA9EC"),
	CardData.Rarity.LEGENDARY: Color("#EF9F27"),
}

var card: CardData
var playable: bool = true
var selected: bool = false
var hovered: bool = false
## 9-23 修改意见 3：弃牌模式下点卡 = 选中（不拖拽、也不受 playable 限制）
var select_mode: bool = false

var _dragging: bool = false

var _frame: CardFrame
var _border: Panel


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func setup(p_card: CardData) -> void:
	card = p_card
	if is_node_ready():
		_refresh()


func _build() -> void:
	_frame = CardFrame.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 0
	_frame.offset_top = 0
	_frame.offset_right = 0
	_frame.offset_bottom = 0
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.custom_minimum_size = Vector2.ZERO
	add_child(_frame)

	_border = Panel.new()
	_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border)


func _refresh() -> void:
	if card == null or _frame == null:
		return

	# 9-23 修改意见 2：战斗卡使用新边框版式 ——
	#   左上 = 行动点，右上 = 蓝量，最上方 = 名字，上框 = 图片，下框 = 描述
	var badge_r := "%d" % card.mana_cost if card.mana_cost > 0 else ""
	# 9-22 修改意见 6：卡面显示六分类（物理进攻 / 法术防御 …），放在中间胶囊
	var cat := card.get_category_name_cn()
	# 9-23 需求（共鸣）：组件卡胶囊显示「共鸣」、联合卡本体显示「联合」，
	# 首行改用前置条件提示（普通卡才显示「六分类 · 稀有度」）。
	var tag_text := cat
	if card.is_combo_component():
		tag_text = "共鸣"
	elif card.is_combo_payoff():
		tag_text = "联合"
	var head := "%s · %s" % [cat, card.get_rarity_name_cn()]
	if card.has_combo():
		head = card.get_combo_hint_cn()
	_frame.setup(
		card.display_name,
		"%s\n%s" % [head, card.description],
		Color(card.art_placeholder),
		{
			"style": CardFrame.STYLE_BATTLE,
			"image": ArtRegistry.card(card.id),
			"tag": tag_text,
			"badge_l": "%d" % card.action_cost,
			"badge_r": badge_r,
		}
	)
	_apply_visual_state()


func set_playable(v: bool) -> void:
	if playable == v:
		return
	playable = v
	if not playable:
		_set_hover(false)
	if is_node_ready():
		_apply_visual_state()


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	if is_node_ready():
		_apply_visual_state()


## 进入 / 退出「弃牌选择」模式：点一下切换选中，不走拖拽
func set_select_mode(v: bool) -> void:
	if select_mode == v:
		return
	select_mode = v
	if not v:
		selected = false
		_dragging = false
	if is_node_ready():
		_apply_visual_state()


## 悬停放大：以底边中点为轴向上升起，不越出手牌区下边界
func refresh_pivot() -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y if hovered else size.y * 0.5)


func clear_hover() -> void:
	_set_hover(false)


func _on_mouse_entered() -> void:
	_set_hover(true)


func _on_mouse_exited() -> void:
	_set_hover(false)


func _set_hover(v: bool) -> void:
	if hovered == v:
		return
	hovered = v
	z_index = 60 if v else 0
	scale = Vector2(HOVER_SCALE, HOVER_SCALE) if v else Vector2.ONE
	refresh_pivot()
	_apply_visual_state()


func _apply_visual_state() -> void:
	var rarity_color: Color = RARITY_COLORS.get(card.rarity, Color("#D3D1C7")) if card != null else Color("#D3D1C7")
	var border_color := rarity_color
	var border_width := 2

	if select_mode:
		# 弃牌模式：可选中，不再因为"打不出"而变灰
		modulate = Color(1.08, 1.08, 1.08, 1) if selected else Color(1, 1, 1, 1)
	elif not playable:
		modulate = Color(1, 1, 1, 0.55)
	elif hovered:
		modulate = Color(1.06, 1.06, 1.06, 1)
	else:
		modulate = Color(1, 1, 1, 1)

	if selected:
		border_color = Color("#C0392B") if select_mode else Color("#3B6D11")
		border_width = 4 if select_mode else 3
	# 悬停突显：金色描边 + 加粗
	if hovered and playable and not select_mode:
		border_color = Color("#EF9F27")
		border_width = 3

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(7)
	_border.add_theme_stylebox_override("panel", sb)


# ---------------------------------------------------------------------------
# 拖拽
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# 意见 3（9-23）：弃牌模式下左键点击 = 切换选中，不进入拖拽
	if select_mode:
		var mbs := event as InputEventMouseButton
		if mbs != null and mbs.pressed and mbs.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(self)
			accept_event()
		return

	# 意见 4：只有作用范围 / 资源合法的卡牌才可拖拽
	if not playable:
		if event is InputEventMouseButton:
			var mb0 := event as InputEventMouseButton
			if mb0.pressed and mb0.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit(self)
				accept_event()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				drag_started.emit(self)
				accept_event()
			else:
				if _dragging:
					_dragging = false
					drag_released.emit(self, get_global_mouse_position())
					accept_event()
