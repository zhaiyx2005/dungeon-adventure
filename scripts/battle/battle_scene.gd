## 战斗场景控制器
##
## 布局（设计草案 §4.3）：
##   正下方   手牌区，扇形分布
##   左下角   背包按钮
##   右侧     抽牌堆 / 弃牌堆 + 手动弃牌键
##   中间左   小队成员卡
##   中间右   怪物卡
##   中间     剑与盾分隔
##
## 操作（设计草案 §4.4）：
##   1. 点人物卡 → 选由谁释放
##   2. 拖卡释放：单体卡拖到目标身上；全场卡拖到战场空白处
extends Control


const MAIN_MENU := "res://scenes/main_menu.tscn"
const CARD_VIEW := preload("res://scripts/battle/card_view.gd")
const UNIT_VIEW := preload("res://scripts/battle/unit_view.gd")
const BATTLE_FX := preload("res://scripts/battle/battle_fx.gd")

## 敌人编成：普通战斗（阶段 3 由地牢节点经 GameData.pending_encounter 传入）
const DEFAULT_ENEMY_POOL := ["boar", "boar", "cave_bat"]

## 手牌扇形参数
const HAND_FAN_ANGLE := 8.0      ## 最大总张角（度）
const HAND_ARC_LIFT := 14.0      ## 两端相对中心的下沉量
const HAND_OVERLAP_MIN := 0.34   ## 手牌多时允许的最大重叠比
const DRAG_LIFT := 18.0          ## 拖拽时卡牌抬起高度（9-22 修改意见 2：卡牌不跟手）

## 9-23 修改意见 3：弃牌模式
##   点「弃牌」→ 手牌全部放大平铺 → 点卡切换选中 →「确认弃牌」弃掉选中的牌
const DISCARD_SCALE := 1.50      ## 弃牌模式下卡牌放大倍率上限
const DISCARD_MIN_SCALE := 0.60  ## 兜底下限（手牌极多时不会再小过这个）
const DISCARD_GAP := 10.0        ## 放大后卡与卡之间的间距（保证不重叠）
const DISCARD_BOTTOM_H := 430.0  ## 弃牌模式下底部栏临时加高，容纳两行放大的卡
## 普通状态下底部栏高度（与 battle_scene.tscn 的 Bottom.custom_minimum_size.y 一致）
const NORMAL_BOTTOM_H := 232.0

## 战斗事件 kind → 音效 id（9-25 需求）。
## 攻击/受击的音效还要看 damage_type 与暴击，在 _play_feedback_audio 里分支。
## 映射表放在场景层（而不是 AudioManager 里）：AudioManager 不需要知道战斗事件长什么样。
const FEEDBACK_SFX := {
	"shield": "shield",
	"heal": "heal",
	"mana": "mana",
	"combo": "combo",
}

## 拖拽指示箭头（9-22 修改意见 4/5）
## 用三次贝塞尔曲线 + 箭头三角，从卡牌起始位置指向当前鼠标位置：
##   合法目标 → 绿色；无合法目标 → 灰色
class DragArrow extends Control:
	const VALID_COLOR := Color("#2E7D32")
	const IDLE_COLOR := Color("#8D8B83")

	var origin := Vector2.ZERO
	var tip := Vector2.ZERO
	var valid := false

	func set_line(p_origin: Vector2, p_tip: Vector2, p_valid: bool) -> void:
		origin = p_origin
		tip = p_tip
		valid = p_valid
		queue_redraw()

	func clear_line() -> void:
		origin = Vector2.ZERO
		tip = Vector2.ZERO
		queue_redraw()

	## 三次贝塞尔求值
	static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
		var u := 1.0 - t
		return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3

	## 控制点：沿 a→b 方向外推 + 垂直弓起（弓起量随"水平度"缩放）
	## 关键：控制点必须跟着拖拽方向走，否则横拖会先往回勾、竖拖会扭成 S 形
	static func control_points(a: Vector2, b: Vector2) -> PackedVector2Array:
		var d := b - a
		var dist := d.length()
		if dist < 0.001:
			return PackedVector2Array([a, b])
		var dir := d / dist
		var perp := Vector2(-dir.y, dir.x)
		if perp.y > 0.0:
			perp = -perp            # 统一朝"上"弓起
		# 竖直方向不做侧向弓起（正上/正下拖拽时画直线最清楚）
		var bow := clampf(dist * 0.26, 18.0, 96.0) * absf(dir.x)
		return PackedVector2Array([
			a + dir * (dist * 0.30) + perp * bow,
			b - dir * (dist * 0.30) + perp * bow,
		])

	func _draw() -> void:
		var dist := origin.distance_to(tip)
		if dist < 24.0:
			return                  # 太近不画，避免抖动的小团块
		var col := VALID_COLOR if valid else IDLE_COLOR
		var a := origin
		var b := tip
		var cps := control_points(a, b)
		var c1 := cps[0]
		var c2 := cps[1]
		var pts := PackedVector2Array()
		var steps := 28
		for i in range(steps + 1):
			pts.append(bezier(a, c1, c2, b, float(i) / float(steps)))
		draw_polyline(pts, col, 4.0, true)
		# 箭头三角：沿末端切线方向
		var d := (b - bezier(a, c1, c2, b, 0.9)).normalized()
		if d == Vector2.ZERO:
			return
		var n := Vector2(-d.y, d.x)
		var s := 16.0
		draw_colored_polygon(PackedVector2Array([
			b, b - d * s + n * s * 0.5, b - d * s - n * s * 0.5,
		]), col)

var battle: BattleManager

var _card_views: Array = []          ## CardView（手牌）
var _hand_slot: Control
var _ally_row: HBoxContainer
var _enemy_row: HBoxContainer
var _unit_views: Array = []          ## UnitView（全部单位）
var _dragging_view: Node = null
var _arrow: DragArrow = null         ## 拖拽贝塞尔指示箭头
var _fx: BattleFx = null             ## 飘字 / 打击特效层（9-23 需求）
var _drag_origin := Vector2.ZERO     ## 拖拽起点（卡牌原位中心，全局坐标）
var _drop_valid := false             ## 当前悬停位置是否为合法释放目标
## 9-23 修改意见 1：取消箭头吸附后不再需要「悬停目标」缓存，
## 箭头终点只由「自身卡→释放者本人 / 其余→鼠标」决定。

## 9-23 修改意见 3：弃牌模式状态
var _discard_mode: bool = false
var _discard_bar: HBoxContainer = null
var _bottom_panel: PanelContainer

# UI 引用
@onready var _round_label: Label = %RoundLabel
@onready var _phase_label: Label = %PhaseLabel
@onready var _deck_label: Label = %DeckLabel
@onready var _discard_label: Label = %DiscardLabel
@onready var _hand_label: Label = %HandLabel
@onready var _hand_header: HBoxContainer = %HandHeader
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _end_turn_btn: Button = %EndTurnButton
@onready var _discard_btn: Button = %DiscardButton
@onready var _bag_btn: Button = %BagButton
@onready var _battlefield: Control = %Battlefield
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result_label: Label = %ResultLabel
@onready var _result_detail: Label = %ResultDetail
@onready var _result_button: Button = %ResultButton
@onready var _hint_label: Label = %HintLabel


func _ready() -> void:
	# 战斗 BGM（9-25 需求）。离开战斗回城镇 / 地牢时会自动切回 title
	AudioManager.play_bgm("battle")
	# 背景：地下城石室（9-28 需求）。战场面板同时调成半透明，否则背景全被它盖住
	SceneBackdrop.attach(self, "dungeon_battle", SceneBackdrop.SCRIM_BATTLE)
	_soften_battlefield()
	_hand_slot = %HandSlot
	_ally_row = %AllyRow
	_enemy_row = %EnemyRow
	_bottom_panel = %Bottom

	# 拖拽指示箭头覆盖层（放在最上层，不拦鼠标）
	_arrow = DragArrow.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.z_index = 90
	add_child(_arrow)
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 飘字 / 打击特效层（9-23 需求）：盖在单位之上，但不拦鼠标
	_fx = BATTLE_FX.new()
	_fx.name = "BattleFx"
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.z_index = 120
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_setup_battle()
	_wire_ui()

	# 布局跑完后再排一次手牌，避免首次布局时 HandSlot 尺寸还是 0
	call_deferred("_deferred_relayout")
	get_viewport().size_changed.connect(_on_viewport_resized)
	# HandSlot 尺寸一旦定下来（容器把它从 0 撑到实际高度）就重排一次，
	# 否则首帧算出来的扇形位置会一直沿用，卡牌底部被视口裁掉。
	_hand_slot.resized.connect(_layout_hand)


## 把战场面板调成半透明，让地牢背景透出来（9-28 需求）。
##
## 战场面板原本是不透明的浅米色，会把整块背景压死 —— 那样加背景等于白加。
## 这里**复制**一份 StyleBoxFlat 再改 alpha：直接改原对象会污染场景文件里的
## 共享 SubResource（同一场景的多个实例共用它，改一次全场变色）。
const BATTLEFIELD_ALPHA := 0.35


func _soften_battlefield() -> void:
	var bf := get_node_or_null("Root/Middle/Battlefield") as Panel
	if bf == null:
		return
	var sb := bf.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		var copy := sb.duplicate() as StyleBoxFlat
		copy.bg_color.a = BATTLEFIELD_ALPHA
		bf.add_theme_stylebox_override("panel", copy)

	# 面板变半透明后，「我方小队 / 敌方」这两条标题就直接压在背景图上了。
	# 只给这两条加描边 —— **不要**笼统遍历战场里的 Label：
	# 单位卡上的名字是白字压在深色条上，加了浅色描边反而更糊。
	for path in ["Root/Middle/Battlefield/FieldMargin/FieldRow/AllyBox/AllyTitle",
			"Root/Middle/Battlefield/FieldMargin/FieldRow/EnemyBox/EnemyTitle"]:
		var l := get_node_or_null(path) as Label
		if l != null:
			l.add_theme_color_override("font_outline_color", Color("#fbfaf6"))
			l.add_theme_constant_override("outline_size", 4)


func _deferred_relayout() -> void:
	_layout_hand()

func _setup_battle() -> void:
	battle = BattleManager.new()

	# 敌人来源：优先读地牢节点写入的待战斗遭遇，否则用默认编成（快速战斗）
	var enemy_ids: Array = DEFAULT_ENEMY_POOL
	if not GameData.pending_encounter.is_empty() and GameData.pending_encounter.has("monster_ids"):
		var ids: Array = GameData.pending_encounter["monster_ids"]
		if not ids.is_empty():
			enemy_ids = ids

	var monsters: Array[MonsterData] = []
	for id in enemy_ids:
		var m := GameData.db.get_monster(id)
		if m != null:
			monsters.append(m)
	if monsters.is_empty():
		push_error("战斗场景：找不到任何敌人数据")

	# 先连信号再 setup/start，否则 setup 里的「—— 战斗开始 ——」进不了日志面板
	battle.log_added.connect(_on_log)
	battle.state_changed.connect(_on_state_changed)
	battle.battle_finished.connect(_on_battle_finished)
	battle.combat_feedback.connect(_on_combat_feedback)
	battle.setup(GameData.team, monsters, GameData.deck)

	_build_unit_views()
	battle.start()
	_on_state_changed()


func _wire_ui() -> void:
	_end_turn_btn.pressed.connect(_on_end_turn)
	_discard_btn.pressed.connect(_on_discard_mode)
	_bag_btn.pressed.connect(_on_bag)
	_result_button.pressed.connect(_on_result_button)
	_result_panel.visible = false

	# 战场空白处点击 = 取消拖拽中的高亮
	_battlefield.gui_input.connect(_on_battlefield_input)


func _build_unit_views() -> void:
	for child in _ally_row.get_children():
		child.queue_free()
	for child in _enemy_row.get_children():
		child.queue_free()
	_unit_views.clear()

	for a in battle.team:
		var uv := UNIT_VIEW.new()
		uv.name = "Ally_" + a.id
		_ally_row.add_child(uv)
		uv.setup_adventurer(a)
		uv.clicked.connect(_on_unit_clicked)
		_unit_views.append(uv)

	for m in battle.monsters:
		var uv := UNIT_VIEW.new()
		uv.name = "Enemy_" + m.data.id
		_enemy_row.add_child(uv)
		uv.setup_monster(m)
		uv.clicked.connect(_on_unit_clicked)
		_unit_views.append(uv)


# ---------------------------------------------------------------------------
# 状态刷新
# ---------------------------------------------------------------------------

func _on_state_changed() -> void:
	# 回合结束 / 战斗结束时必须退出弃牌模式，否则会停在被放大的手牌上
	if _discard_mode and (not battle.turn.is_player_turn() or battle.turn.is_finished()):
		_set_discard_mode(false)
	_refresh_units()
	_refresh_hand()
	_refresh_labels()
	_refresh_buttons()


func _refresh_units() -> void:
	for uv in _unit_views:
		uv.refresh()


func _refresh_labels() -> void:
	_round_label.text = "第 %d 回合" % maxi(battle.turn.round_number, 1)
	if battle.turn.is_finished():
		_phase_label.text = "战斗结束"
	elif battle.turn.is_player_turn():
		_phase_label.text = "我方回合"
	else:
		_phase_label.text = "敌方回合"

	_deck_label.text = "抽牌堆\n%d" % battle.deck.draw_pile.size()
	_discard_label.text = "弃牌堆\n%d" % battle.deck.discard_pile.size()
	_hand_label.text = "手牌 %d / %d" % [battle.deck.hand.size(), DeckManager.HAND_LIMIT]

	var sel := battle.selected_adventurer
	if sel != null:
		_hint_label.text = "当前释放者：%s（行动 %d，蓝 %d）" % [
			sel.display_name, sel.current_action, sel.current_mana
		]
	else:
		_hint_label.text = "点下方的成员卡选择释放者"


func _refresh_buttons() -> void:
	var acting := battle.turn.is_player_turn() and battle.result == BattleManager.Result.ONGOING
	_end_turn_btn.disabled = not acting or _discard_mode
	# 弃牌按钮在弃牌模式下变成「取消弃牌」，必须保持可点
	_discard_btn.disabled = (not acting and not _discard_mode) or battle.deck.hand.is_empty()
	_bag_btn.disabled = false


func _refresh_hand() -> void:
	for cv in _card_views:
		cv.queue_free()
	_card_views.clear()

	var hand := battle.deck.hand
	var count := hand.size()
	if count == 0:
		return

	# 意见 6：手牌按行动点数从小到大排列（同点数按卡牌 id 稳定排）
	var ordered: Array = hand.duplicate()
	ordered.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.action_cost == b.action_cost:
			return a.id < b.id
		return a.action_cost < b.action_cost)

	for i in range(count):
		var card: CardData = ordered[i]
		var cv := CARD_VIEW.new()
		cv.name = "Card_%d" % i
		_hand_slot.add_child(cv)
		cv.setup(card)
		# 只有"当前释放者"付得起且目标合法，才算可打
		var playable := battle.can_play(battle.selected_adventurer, card)
		cv.set_playable(playable)
		cv.drag_started.connect(_on_card_drag_started)
		cv.drag_released.connect(_on_card_drag_released)
		cv.clicked.connect(_on_hand_card_clicked)
		# 弃牌模式下重建手牌（例如弃掉一张后）仍要保持选择态
		cv.set_select_mode(_discard_mode)
		_card_views.append(cv)

	_layout_hand()


## 手牌扇形排布
##
## 约束：整排卡牌必须在 HandSlot 内完整可见，不能溢出屏幕。
## 做法：先按"完全展开"算步进，若超出可用宽度就压缩到刚好放下；
##       两端下沉形成扇形弧度，但下沉量受控，保证不越过下边界。
func _layout_hand() -> void:
	var n := _card_views.size()
	if n == 0:
		return

	# 9-23 修改意见 3：弃牌模式下用"放大平铺"而不是扇形
	if _discard_mode:
		_layout_hand_discard(n)
		return

	var card_w := CARD_VIEW.CARD_SIZE.x
	var card_h := CARD_VIEW.CARD_SIZE.y

	# 容器尺寸可能在布局跑完前为 0，此时用兜底值，等延迟重排修正
	var area := _hand_slot.size
	if area.x < card_w + 8.0 or area.y < card_h:
		area = Vector2(maxf(size.x - 340.0, 900.0), card_h + 30.0)

	var half := card_w * 0.5
	# 可用宽度：左右各留出半张卡宽，避免两端旋转后越界
	var usable_w := maxf(area.x - card_w, card_w)

	var step := card_w + 6.0
	if n > 1:
		step = minf(step, usable_w / float(n - 1))
		step = maxf(step, card_w * HAND_OVERLAP_MIN)
	else:
		step = 0.0

	var total_w := step * float(n - 1)
	var center_x := area.x * 0.5

	# 扇形下沉量：确保 卡高 + 最大下移 + 旋转余量 不超出可用高度
	# 旋转后包围盒下沿会比未旋转时再低一点（最外侧卡最大），必须一起预留，
	# 否则两端旋转的卡牌底部会被视口切掉。
	var half_fan := deg_to_rad(HAND_FAN_ANGLE * 0.5)
	var rot_pad := (card_w * sin(half_fan) + card_h * cos(half_fan) - card_h) * 0.5
	var max_lift := clampf(area.y - card_h - 6.0 - rot_pad, 0.0, HAND_ARC_LIFT)

	for i in range(n):
		var cv: Node = _card_views[i]
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var x := center_x + (t - 0.5) * total_w
		# 弧度：中间 0，两端最大
		var edge := pow(absf(t - 0.5) * 2.0, 2.0)
		var y := 3.0 + edge * max_lift
		var angle := (t - 0.5) * HAND_FAN_ANGLE

		cv.refresh_pivot()
		cv.position = Vector2(x - half, y)
		cv.rotation_degrees = angle


## 窗口尺寸变化后重排（相机/分辨率调整时手牌仍要完整可见）
func _on_viewport_resized() -> void:
	if _hand_slot != null:
		_layout_hand()


## 弃牌模式排布（9-23 修改意见 3）：手牌全部放大、平铺不扇形，方便点选。
##
## 唯一硬约束是**不重叠**。一行塞不下就自动折成两行：
## 早先版本按 cw*0.6 收窄步长硬凑一行，结果相邻卡互相压住、
## 把描述文字整段盖掉（"文字超出框"的观感来源）。
func _layout_hand_discard(n: int) -> void:
	if n <= 0:
		return
	var base := CARD_VIEW.CARD_SIZE
	var area := _hand_slot.size
	var usable_w := maxf(area.x - 8.0, base.x)
	var usable_h := maxf(area.y - 6.0, base.y)

	# 逐档试 1/2/3 行，取"能放到的最大倍率"；同倍率优先行数少的
	var best_rows := 1
	var best_scale := 0.0
	for rows in [1, 2, 3]:
		if rows > n:
			break
		var pr := int(ceil(float(n) / float(rows)))
		var by_w := (usable_w - DISCARD_GAP * float(pr - 1)) / (base.x * float(pr))
		var by_h := (usable_h - DISCARD_GAP * float(rows - 1)) / (base.y * float(rows))
		var s := minf(DISCARD_SCALE, minf(by_w, by_h))
		if s > best_scale + 0.001:
			best_scale = s
			best_rows = rows

	var scale: float = clampf(best_scale, DISCARD_MIN_SCALE, DISCARD_SCALE)
	var per_row := int(ceil(float(n) / float(best_rows)))
	var cw := base.x * scale
	var ch := base.y * scale
	var step := cw + DISCARD_GAP
	var row_step := ch + DISCARD_GAP
	var total_h := row_step * float(best_rows - 1) + ch
	var block_top := maxf((area.y - total_h) * 0.5, 0.0) + ch * 0.5
	var area_cx := maxf(area.x, cw) * 0.5

	for i in range(n):
		var r: int = i / per_row
		var col: int = i % per_row
		var in_row: int = mini(per_row, n - r * per_row)
		var row_w := step * float(in_row - 1) + cw
		var cv: Node = _card_views[i]
		# 缩放以卡牌中心为轴 → 卡中心不动，position 仍按未缩放尺寸反推
		cv.pivot_offset = base * 0.5
		cv.scale = Vector2(scale, scale)
		cv.rotation_degrees = 0.0
		cv.position = Vector2(
			area_cx - row_w * 0.5 + step * float(col) + cw * 0.5 - base.x * 0.5,
			block_top + row_step * float(r) - base.y * 0.5)


# ---------------------------------------------------------------------------
# 拖拽出牌
# ---------------------------------------------------------------------------

func _on_card_drag_started(view: Node) -> void:
	_dragging_view = view
	view.z_index = 100
	# 拿起卡牌的手感音（音高比按钮点击略高，区分"选中"与"点按钮"）
	AudioManager.play_sfx("ui_click", 1.18)
	# 箭头起点 = 卡牌原位中心（此时卡还没抬起）
	_drag_origin = view.get_global_rect().get_center()
	# 9-22 修改意见 2：拖拽时卡牌不跟随鼠标，只在原位轻微抬起作视觉反馈
	var cv := view as Control
	if cv != null:
		cv.position.y -= DRAG_LIFT
	_drop_valid = false


func _on_card_drag_released(view: Node, global_pos: Vector2) -> void:
	_dragging_view = null
	view.z_index = 0
	view.clear_hover()
	if _arrow != null:
		_arrow.clear_line()
	_drop_valid = false
	# 恢复抬起前的排布
	_layout_hand()

	var card: CardData = view.card
	var caster := battle.selected_adventurer
	if caster == null:
		_flash("先点一个成员卡，选择由谁释放")
		_layout_hand()
		return

	if not battle.can_play(caster, card):
		# 打不出去 → 用"拒绝"音把失败说清楚，不用只靠文字提示
		AudioManager.play_sfx("ui_deny")
		_flash("「%s」当前无法打出（资源不足或目标无效）" % card.display_name)
		_layout_hand()
		return

	# 单体卡 → 需要落在某个单位身上
	if card.needs_target_card():
		var uv := _unit_view_at(global_pos)
		if uv == null:
			_flash("「%s」需要拖到目标身上" % card.display_name)
			_layout_hand()
			return

		if card.target_type == CardData.TargetType.SINGLE_ENEMY:
			if uv.monster == null or not uv.monster.is_alive():
				_flash("目标必须是存活的敌人")
				_layout_hand()
				return
			battle.play_card(caster, card, uv.monster)
		else:
			if uv.adventurer == null:
				_flash("目标必须是友方成员")
				_layout_hand()
				return
			battle.play_card(caster, card, uv.adventurer)
		return

	# 自身卡（防御 / 自增益）→ 箭头已指向释放者本人，落在战场任意处即生效
	if card.target_type == CardData.TargetType.SELF:
		if _battlefield_hit(global_pos) or _unit_view_at(global_pos) != null:
			battle.play_card(caster, card, null)
		else:
			_flash("「%s」是自身效果卡，拖到战场任意处释放" % card.display_name)
			_layout_hand()
		return

	# 全场卡 → 落在战场上即生效
	if _battlefield_hit(global_pos) or _unit_view_at(global_pos) != null:
		battle.play_card(caster, card, null)
	else:
		_flash("「%s」是全場效果卡，拖到战场任意处释放" % card.display_name)
		_layout_hand()


## 找落在某屏幕坐标上的单位
func _unit_view_at(global_pos: Vector2) -> Node:
	for uv in _unit_views:
		if uv.contains_global_point(global_pos):
			return uv
	return null


## 点是否落在战场区域内
func _battlefield_hit(global_pos: Vector2) -> bool:
	return Rect2(_battlefield.global_position, _battlefield.size).has_point(global_pos)


func _on_battlefield_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_clear_highlights()


func _process(_delta: float) -> void:
	# 9-22 修改意见 2：拖拽时卡牌留在原位，只更新指向箭头与目标高亮
	if _dragging_view != null and _dragging_view.is_inside_tree():
		var mp := get_global_mouse_position()
		_highlight_drop_target(mp)
		if _arrow != null:
			# 终点吸附到目标（没有目标时跟随鼠标）
			var tip := _arrow_tip_for(mp)
			# Control 没有 to_local，用全局变换的逆矩阵换算到覆盖层局部坐标
			var inv := _arrow.get_global_transform().affine_inverse()
			_arrow.set_line(inv * _drag_origin, inv * tip, _drop_valid)


func _highlight_drop_target(mp: Vector2) -> void:
	var hovering := _unit_view_at(mp)
	for uv in _unit_views:
		uv.set_drop_highlight(false)
	_drop_valid = false
	if _dragging_view == null:
		return
	var card: CardData = _dragging_view.card
	if card == null:
		return
	# 9-23 修改意见 1：自身卡（防御类）高亮的是「释放者本人」——
	# 这类效果一定作用在自己身上，高亮别人会误导。
	if card.target_type == CardData.TargetType.SELF:
		var self_view := _unit_view_of_adventurer(battle.selected_adventurer)
		if self_view != null:
			self_view.set_drop_highlight(true)
		_drop_valid = _battlefield_hit(mp) or hovering != null
		return
	if hovering == null:
		# 全场效果卡：拖到战场任意空白处也是合法释放点
		if not card.needs_target_card() and _battlefield_hit(mp):
			_drop_valid = true
		return
	# 只有类型匹配才高亮
	if card.target_type == CardData.TargetType.SINGLE_ENEMY and hovering.monster != null and hovering.monster.is_alive():
		hovering.set_drop_highlight(true)
		_drop_valid = true
	elif card.target_type == CardData.TargetType.SINGLE_ALLY and hovering.adventurer != null:
		hovering.set_drop_highlight(true)
		_drop_valid = true
	elif not card.needs_target_card():
		hovering.set_drop_highlight(true)
		_drop_valid = true


## 找某个冒险者对应的单位视图
func _unit_view_of_adventurer(a: Adventurer) -> Node:
	if a == null:
		return null
	for uv in _unit_views:
		if uv.adventurer == a:
			return uv
	return null


## 找某个战斗单位（冒险者或怪物）对应的单位视图
func _unit_view_of(u) -> Node:
	if u == null:
		return null
	for uv in _unit_views:
		if uv.adventurer == u or uv.monster == u:
			return uv
	return null


# ---------------------------------------------------------------------------
# 战斗表现层（9-23 需求）
#
# 数值结算全在 BattleManager 里完成，这里只负责"演"：
#   出手 → 前冲 + 轨迹线
#   命中 → 抖动 + 冲击环 + 飘字（暴击更大更亮）
#   共鸣 → 中央横幅
# ---------------------------------------------------------------------------

func _on_combat_feedback(p: Dictionary) -> void:
	# 先出声音再画特效：音频不依赖 _fx 层（两者是独立的演出通道）
	_play_feedback_audio(p)
	if _fx == null:
		return
	var kind := String(p.get("kind", ""))
	var src_uv := _unit_view_of(p.get("source", null))
	var uv := _unit_view_of(p.get("unit", null))

	match kind:
		"attack_start":
			if src_uv != null:
				# 我方在左、怪物在右：我方往右冲，怪物往左冲
				src_uv.play_attack(1.0 if src_uv.is_ally else -1.0)
		"damage":
			if uv != null:
				var crit := bool(p.get("crit", false))
				var amount := int(p.get("amount", 0))
				var ctr: Vector2 = uv.global_position + uv.size * 0.5
				# 数字落在单位上方，避免压住血条与属性文字
				var fpos: Vector2 = ctr + Vector2(0.0, -uv.size.y * 0.55)
				uv.play_hit(crit)
				if src_uv != null:
					_fx.streak(src_uv.global_position + src_uv.size * 0.5, ctr, crit)
				_fx.impact(ctr, crit)
				# 我方受伤用红字、敌人受伤用橙字；暴击一律金色放大
				_fx.float_number(fpos, "%d%s" % [amount, "!" if crit else ""],
					"ally" if uv.is_ally else "enemy", crit)
				if bool(p.get("killed", false)):
					uv.play_death()
		"heal":
			if uv != null:
				var hp: Vector2 = uv.global_position + uv.size * 0.5 + Vector2(0.0, -uv.size.y * 0.4)
				_fx.float_number(hp, "+%d" % int(p.get("amount", 0)), "heal", false)
		"mana":
			if uv != null:
				var mp: Vector2 = uv.global_position + uv.size * 0.5 + Vector2(0.0, -uv.size.y * 0.4)
				_fx.float_number(mp, "+%d 蓝" % int(p.get("amount", 0)), "mana", false)
		"shield":
			if uv != null:
				var sp: Vector2 = uv.global_position + uv.size * 0.5 + Vector2(0.0, -uv.size.y * 0.4)
				_fx.float_number(sp, "盾 +%d" % int(p.get("amount", 0)), "shield", false)
		"combo":
			_fx.banner("★ %s ★" % String(p.get("text", "共鸣")),
				String(p.get("detail", "")), BattleFx.COL_CRIT)


## 表现层事件 → 音效（9-25 需求：攻击 / 受击 / 防御 / 法术 都要有声音）
##
## 分层：battle_manager 只负责 emit 事件，声音在场景层解读 ——
## 这样模拟器（不加载场景）依然是零成本的。
func _play_feedback_audio(p: Dictionary) -> void:
	var kind := String(p.get("kind", ""))
	var magical := String(p.get("damage_type", "PHYSICAL")) == "MAGICAL"

	match kind:
		"attack_start":
			# 起手音：物理是破空声，法术是咏唱声
			AudioManager.play_sfx("attack_magic" if magical else "attack_phys")
		"damage":
			# 命中音按伤害类型分：闷响 / 噼啪；暴击再叠一层金属重击
			AudioManager.play_sfx("hit_magic" if magical else "hit_phys")
			if bool(p.get("crit", false)):
				AudioManager.play_sfx("crit")
		_:
			if FEEDBACK_SFX.has(kind):
				AudioManager.play_sfx(String(FEEDBACK_SFX[kind]))


## 箭头终点（9-23 修改意见 1）：
##   默认跟随鼠标、不做吸附（吸附会让"指向"跳来跳去）；
##   只有「自身卡」把箭头指向释放者自己，明确表示"作用在自己身上"。
func _arrow_tip_for(mp: Vector2) -> Vector2:
	if _dragging_view != null:
		var card: CardData = _dragging_view.card
		if card != null and card.target_type == CardData.TargetType.SELF:
			var self_view := _unit_view_of_adventurer(battle.selected_adventurer)
			if self_view != null:
				return self_view.global_position + self_view.size * 0.5
	return mp


func _clear_highlights() -> void:
	for uv in _unit_views:
		uv.set_drop_highlight(false)


# ---------------------------------------------------------------------------
# 单位点击（选释放者）
# ---------------------------------------------------------------------------

func _on_unit_clicked(uv: Node) -> void:
	if uv.adventurer == null:
		return
	if uv.adventurer.is_downed:
		_flash("%s 处于濒死，无法行动" % uv.adventurer.display_name)
		return
	battle.select_adventurer(uv.adventurer)
	for v in _unit_views:
		v.set_selected(v.adventurer == uv.adventurer)
	_refresh_hand()
	_refresh_labels()


# ---------------------------------------------------------------------------
# 按钮
# ---------------------------------------------------------------------------

func _on_end_turn() -> void:
	if not battle.turn.is_player_turn():
		return
	for v in _unit_views:
		v.set_selected(false)
	_clear_highlights()
	_flash("—— 结束回合，敌方行动 ——")
	battle.end_player_turn()
	_update_selection_visual()


func _update_selection_visual() -> void:
	for v in _unit_views:
		v.set_selected(v.adventurer != null and v.adventurer == battle.selected_adventurer)


# ---------------------------------------------------------------------------
# 弃牌模式（9-23 修改意见 3）
# ---------------------------------------------------------------------------

func _on_discard_mode() -> void:
	# 已经是弃牌模式 → 再点一次当"取消"
	if _discard_mode:
		_set_discard_mode(false)
		return
	if battle.deck.hand.is_empty():
		_flash("手牌为空，无需弃牌")
		return
	_set_discard_mode(true)


## 切换弃牌模式：手牌放大平铺 + 顶部出现「确认弃牌 / 取消」
func _set_discard_mode(v: bool) -> void:
	if _discard_mode == v:
		return
	_discard_mode = v
	for cv in _card_views:
		cv.set_select_mode(v)
		if not v:
			cv.set_selected(false)

	if v:
		_build_discard_bar()
		_discard_btn.text = "取消弃牌"
		_flash("点选要弃掉的手牌（可多选），再点「确认弃牌」")
		_resize_bottom_for_discard(true)
		_layout_hand()
	else:
		if _discard_bar != null and _discard_bar.is_inside_tree():
			_discard_bar.queue_free()
		_discard_bar = null
		_discard_btn.text = "弃牌"
		_resize_bottom_for_discard(false)
		_refresh_hand()
	# 弃牌模式下「结束回合」必须禁用、弃牌键保持可点（可当"取消"用）
	_refresh_buttons()


## 弃牌时把底部栏临时加高，放大的手牌才有地方摆
func _resize_bottom_for_discard(on: bool) -> void:
	if _bottom_panel == null:
		return
	_bottom_panel.custom_minimum_size = Vector2(0, DISCARD_BOTTOM_H if on else NORMAL_BOTTOM_H)


func _build_discard_bar() -> void:
	if _discard_bar != null and _discard_bar.is_inside_tree():
		return
	if _hand_header == null:
		# 场景里 HandHeader 必须有 unique_name_in_owner=true，否则操作条无处安放
		push_error("battle_scene: 找不到 %HandHeader，弃牌操作条无法创建")
		return
	var bar := HBoxContainer.new()
	bar.name = "DiscardBar"
	bar.add_theme_constant_override("separation", 8)

	var confirm := Button.new()
	confirm.name = "DiscardConfirmButton"
	confirm.text = "确认弃牌"
	confirm.custom_minimum_size = Vector2(110, 34)
	confirm.add_theme_color_override("font_color", Color("#A32B1E"))
	confirm.pressed.connect(_on_discard_confirm)
	bar.add_child(confirm)

	var cancel := Button.new()
	cancel.name = "DiscardCancelButton"
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(80, 34)
	cancel.pressed.connect(_set_discard_mode.bind(false))
	bar.add_child(cancel)

	# 插在「结束回合」之前，让「确认弃牌 / 取消」贴着弃牌键一侧，视觉上成组
	var idx := _hand_header.get_children().size()
	if _end_turn_btn != null and _end_turn_btn.get_parent() == _hand_header:
		idx = _end_turn_btn.get_index()
	_hand_header.add_child(bar)
	_hand_header.move_child(bar, idx)
	_discard_bar = bar


## 手牌点击（只有弃牌模式下会连到这个回调）
func _on_hand_card_clicked(view: Node) -> void:
	if not _discard_mode:
		return
	var cv := view as CardView
	if cv == null:
		return
	cv.set_selected(not cv.selected)


func _on_discard_confirm() -> void:
	var chosen: Array = []
	for cv in _card_views:
		if cv.selected and cv.card != null:
			chosen.append(cv.card)
	if chosen.is_empty():
		_flash("还没有选中任何手牌")
		return
	# 先退出模式再逐张弃，避免每次 state_changed 都在弃牌布局下重排
	_set_discard_mode(false)
	for card in chosen:
		battle.discard_card(card)
	_flash("弃掉 %d 张手牌" % chosen.size())


func _on_bag() -> void:
	_show_bag_popup()


## 背包弹窗：列出战斗内可用的消耗品，点使用
var _bag_popup: PanelContainer = null


func _show_bag_popup() -> void:
	if battle.turn.is_finished() or not battle.turn.is_player_turn():
		_flash("当前无法使用背包")
		return
	if _bag_popup != null and _bag_popup.is_inside_tree():
		_bag_popup.queue_free()
		_bag_popup = null

	var usables: Array[ItemData] = []
	for it in GameData.inventory:
		if it.usable_in_battle:
			usables.append(it)

	var popup := PanelContainer.new()
	popup.z_index = 200
	popup.anchor_left = 0.5
	popup.anchor_top = 0.5
	popup.anchor_right = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -220
	popup.offset_top = -160
	popup.offset_right = 220
	popup.offset_bottom = 160
	add_child(popup)
	_bag_popup = popup

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "背包（消耗 1 行动值）"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	if usables.is_empty():
		var empty := Label.new()
		empty.text = "背包里没有可在战斗中使用的东西"
		empty.add_theme_color_override("font_color", Color("#9A978E"))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(empty)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 180)
		box.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)

		for it in usables:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var label := Label.new()
			label.text = "%s" % it.display_name
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var btn := Button.new()
			btn.text = "使用"
			btn.disabled = not battle.can_use_item(battle.selected_adventurer, it)
			btn.pressed.connect(_on_use_item.bind(it))
			row.add_child(btn)
			list.add_child(row)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 36)
	close.pressed.connect(_close_bag_popup)
	box.add_child(close)


func _on_use_item(item: ItemData) -> void:
	var user := battle.selected_adventurer
	if user == null:
		_flash("先点一个成员卡，选择由谁使用")
		return
	if battle.use_item(user, item):
		_flash("使用了「%s」" % item.display_name)
		_close_bag_popup()
	else:
		_flash("无法使用「%s」" % item.display_name)


func _close_bag_popup() -> void:
	if _bag_popup != null and _bag_popup.is_inside_tree():
		_bag_popup.queue_free()
		_bag_popup = null


func _on_log(text: String) -> void:
	if _log_label == null:
		return
	_log_label.append_text(text + "\n")


func _clear_log() -> void:
	if _log_label != null:
		_log_label.clear()


func _flash(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


# ---------------------------------------------------------------------------
# 结算
# ---------------------------------------------------------------------------

## 结算只跑一次（防止信号重复触发导致奖励重复发放）
var _rewards_granted: bool = false


func _on_battle_finished(result: BattleManager.Result) -> void:
	_refresh_units()
	_refresh_buttons()

	var victory := result == BattleManager.Result.VICTORY
	# 结算音：淡出战斗 BGM，放一段胜负小段（音乐让位给结算提示）
	AudioManager.stop_bgm(0.5)
	AudioManager.play_sfx("victory" if victory else "defeat")
	_result_label.text = "战斗胜利" if victory else "任务失败"
	_result_label.add_theme_color_override(
		"font_color",
		Color("#3B6D11") if victory else Color("#C0392B")
	)

	var lines: PackedStringArray = []
	lines.append("回合数：%d" % battle.turn.round_number)
	if victory:
		lines.append("击杀：%d" % battle.kills)
		lines.append("造成伤害：%d" % battle.damage_dealt)
		lines.append("承受伤害：%d" % battle.damage_taken)
		lines.append("")
		lines.append("获得经验：%d" % battle.reward_exp)
		lines.append("获得金币：%d" % battle.reward_gold)
		if not _rewards_granted:
			_rewards_granted = true
			var msgs := battle.grant_rewards()
			GameData.gold += battle.reward_gold
			if msgs.size() > 0:
				lines.append("")
				lines.append_array(msgs)
	else:
		lines.append("")
		lines.append("全队濒死 —— 失去背包物品与本次探索的金钱经验")
		lines.append("（保留卡组与已穿装备）")

	# 写入结算结果供 run_scene 读取
	GameData.last_battle_result = {
		"victory": victory,
		"reward_exp": battle.reward_exp,
		"reward_gold": battle.reward_gold,
	}

	# 通知地牢 run 管理器（若当前战斗来自地牢节点）
	if GameData.run != null:
		if victory:
			GameData.run.on_battle_victory(battle.reward_exp, battle.reward_gold)
			if GameData.run.at_boss():
				lines.append("")
				lines.append_array(GameData.run.last_event_lines)
		else:
			GameData.run.on_battle_defeat()

	_result_detail.text = "\n".join(lines)
	_result_panel.visible = true


func _on_result_button() -> void:
	# 战斗结束清掉待处理遭遇，避免下一场战斗读到旧敌人
	GameData.pending_encounter = {}
	var target := GameData.return_scene if GameData.return_scene != "" else MAIN_MENU
	get_tree().change_scene_to_file(target)
