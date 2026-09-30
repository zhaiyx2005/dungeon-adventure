## 战斗单位显示控件
##
## 同时用于「小队成员」与「怪物」。顶部一条像素立绘（有素材时）+ 下方状态文字。
## 承担两个职责：
##   1. 显示血量 / 护盾 / 资源
##   2. 作为拖拽目标（把卡拖到它身上 = 对该目标施放）与点击选择（选释放者）
class_name UnitView
extends Control


signal clicked(view: UnitView)          ## 点了自己（用于选释放者）
signal card_dropped(view: UnitView, card_view: Node)  ## 有卡被拖到这上面

## 单位卡尺寸。9-26 起加高：顶部要留一条 92px 的立绘带。
## 战场纵向本来就有富余（`AllyBox`/`EnemyBox` 里是两个 spacer 吸收余量），
## 所以加高只是吃掉 spacer，不影响其它布局。
const UNIT_SIZE := Vector2(132, 242)
## 顶部立绘带高度
const ART_H := 108.0

# --- 打击感参数（9-23 需求）---
const SHAKE_DUR := 0.28         ## 受击抖动时长
const SHAKE_AMP := 9.0          ## 普通受击振幅（像素）
const SHAKE_AMP_CRIT := 17.0    ## 暴击受击振幅
const LUNGE_DIST := 22.0        ## 出手前冲距离
const LUNGE_UP := 7.0           ## 出手时略微上抬

var adventurer: Adventurer = null
var monster: MonsterInstance = null
var is_ally: bool = true
var selected: bool = false
var drop_highlight: bool = false

var _visual_root: Control        ## 所有可见部件的父节点（抖动/前冲都动它，不动控件本身）
var _bg: ColorRect
var _art_bg: ColorRect           ## 立绘带的深色底（透明立绘直接压在浅色卡面上会看不清）
var _art: TextureRect            ## 顶部像素立绘（无素材时隐藏）
var _art_frame: Control          ## 立绘带的裁剪容器
var _vbox: VBoxContainer         ## 文字区（有/无立绘时上边距不同）
var _border: Panel
var _name_label: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _shield_label: Label
var _detail_label: Label
var _status_label: Label
var _flash_rect: ColorRect
var _pos_tween: Tween


func _init() -> void:
	custom_minimum_size = UNIT_SIZE
	size = UNIT_SIZE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## 绑定一个冒险者
func setup_adventurer(a: Adventurer) -> void:
	adventurer = a
	monster = null
	is_ally = true
	if is_node_ready():
		refresh()


## 绑定一个怪物
func setup_monster(m: MonsterInstance) -> void:
	monster = m
	adventurer = null
	is_ally = false
	if is_node_ready():
		refresh()


func _build() -> void:
	# 全部可见部件挂在这一层之下：容器只管 UnitView 本身的位置，
	# 所以对 _visual_root 做位移/缩放不会被 HBoxContainer 的重新排布冲掉。
	_visual_root = Control.new()
	_visual_root.name = "VisualRoot"
	_visual_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual_root)

	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_root.add_child(_bg)

	# 顶部立绘带：裁剪容器 + 像素立绘（NEAREST，保持整身比例不裁切）
	_art_frame = Control.new()
	_art_frame.name = "ArtFrame"
	_art_frame.clip_contents = true
	_art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_root.add_child(_art_frame)
	_art_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_art_frame.offset_left = 2
	_art_frame.offset_right = -2
	_art_frame.offset_top = 2
	_art_frame.offset_bottom = ART_H

	_art_bg = ColorRect.new()
	_art_bg.name = "ArtBg"
	_art_bg.color = Color("#33323C")
	_art_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_frame.add_child(_art_bg)
	_art_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_art = TextureRect.new()
	_art.name = "Art"
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	_art_frame.add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_border = Panel.new()
	_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_root.add_child(_border)

	var vbox := VBoxContainer.new()
	_vbox = vbox
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = ART_H + 5
	vbox.offset_right = -8
	vbox.offset_bottom = -7
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	_visual_root.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 14)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hp_label)

	_shield_label = Label.new()
	_shield_label.add_theme_font_size_override("font_size", 12)
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_shield_label)

	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", 11)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_detail_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_status_label)

	# 受击白闪层：盖在所有内容之上，平时完全透明
	_flash_rect = ColorRect.new()
	_flash_rect.name = "FlashRect"
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	_visual_root.add_child(_flash_rect)


func refresh() -> void:
	if not is_node_ready():
		return
	if adventurer != null:
		_apply_art(ArtRegistry.adventurer_bust(adventurer))
		_refresh_adventurer()
	elif monster != null:
		_apply_art(ArtRegistry.monster_battle(monster))
		_refresh_monster()
	_apply_visual_state()


## 顶部立绘。没有素材的单位（尚未生成 / 招募池没有原型匹配）要把整条立绘带收起来，
## 否则文字上方会白白空出 97px。
func _apply_art(tex: Texture2D) -> void:
	_art.texture = tex
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if is_ally else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var has_art := tex != null
	_art.visible = has_art
	_art_bg.visible = has_art
	_art_frame.visible = has_art
	if _vbox != null:
		_vbox.offset_top = (ART_H + 5.0) if has_art else 7.0


func _refresh_adventurer() -> void:
	var a := adventurer
	var maxhp := a.get_max_hp()
	var ratio := 0.0 if maxhp <= 0 else float(a.current_hp) / float(maxhp)
	_hp_bar.max_value = 100.0
	_hp_bar.value = ratio * 100.0

	_name_label.text = "%s  Lv.%d" % [a.display_name, a.level]
	_hp_label.text = "%d / %d" % [a.current_hp, maxhp]

	var sb := StyleBoxFlat.new()
	sb.bg_color = _hp_color_for(ratio, a.is_downed)
	sb.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color("#D8D6CE")
	bg_sb.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", bg_sb)

	if a.shield > 0:
		_shield_label.text = "护盾 %d" % a.shield
		_shield_label.add_theme_color_override("font_color", Color("#287e88"))
	else:
		_shield_label.text = ""

	var stats := a.get_stats()
	_detail_label.text = "行动 %d/%d  蓝 %d/%d" % [
		a.current_action, a.get_max_action(), a.current_mana, a.get_max_mana()
	]

	if a.is_downed:
		_status_label.text = "濒死"
		_status_label.add_theme_color_override("font_color", Color("#C0392B"))
	else:
		_status_label.text = "物攻 %d  法攻 %d" % [int(stats["phys_atk"]), int(stats["mag_atk"])]
		_status_label.add_theme_color_override("font_color", Color("#6B6960"))


func _hp_color_for(ratio: float, downed: bool) -> Color:
	if downed:
		return Color("#8B3A3A")
	if ratio > 0.6:
		return Color("#5FA85F")
	elif ratio > 0.3:
		return Color("#D9A441")
	else:
		return Color("#C0392B")


func _refresh_monster() -> void:
	var m := monster
	var maxhp := m.data.hp
	var ratio := 0.0 if maxhp <= 0 else float(m.current_hp) / float(maxhp)
	_hp_bar.max_value = 100.0
	_hp_bar.value = ratio * 100.0

	var tier := ""
	match m.data.monster_tier:
		MonsterData.MonsterTier.ELITE: tier = "精英 "
		MonsterData.MonsterTier.BOSS: tier = "首领 "
	_name_label.text = tier + m.get_display_name()
	_hp_label.text = "%d / %d" % [m.current_hp, maxhp]

	var sb := StyleBoxFlat.new()
	sb.bg_color = _hp_color_for(ratio, m.is_dead)
	sb.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color("#D8D6CE")
	bg_sb.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", bg_sb)

	if m.shield > 0:
		_shield_label.text = "护盾 %d" % m.shield
		_shield_label.add_theme_color_override("font_color", Color("#287e88"))
	else:
		_shield_label.text = ""

	_detail_label.text = "战力 %d" % int(m.get_power())

	if m.is_dead:
		_status_label.text = "已击杀"
		_status_label.add_theme_color_override("font_color", Color("#8B3A3A"))
	else:
		_status_label.text = "物攻 %d  法攻 %d" % [m.data.phys_atk, m.data.mag_atk]
		_status_label.add_theme_color_override("font_color", Color("#6B6960"))


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	refresh()


func set_drop_highlight(v: bool) -> void:
	if drop_highlight == v:
		return
	drop_highlight = v
	_apply_visual_state()


func _apply_visual_state() -> void:
	var base: Color
	if adventurer != null:
		base = Color("#EFEDE4") if not adventurer.is_downed else Color("#E0D5D3")
	else:
		base = Color("#F3EFE6") if (monster != null and not monster.is_dead) else Color("#DEDCD4")

	var dead := false
	if monster != null and monster.is_dead:
		dead = true
	_bg.color = base
	modulate = Color(1, 1, 1, 0.45) if dead else Color(1, 1, 1, 1)

	var border_color := Color("#aa8146")
	var border_width := 2

	if drop_highlight:
		border_color = Color("#3B6D11")
		border_width = 4
	elif selected:
		border_color = Color("#287e88")
		border_width = 3

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(0)
	_border.add_theme_stylebox_override("panel", sb)


# ---------------------------------------------------------------------------
# 打击感（9-23 需求）：受击抖动 / 出手前冲 / 白闪
#
# 关键实现点：一切位移都作用在 _visual_root 上，而不是 UnitView 自己。
# 因为 UnitView 是 HBoxContainer 的子节点，容器重新排布时会覆盖 position；
# _visual_root 的父节点是普通 Control，位置由我们自己说了算。
# ---------------------------------------------------------------------------

## 受击抖动。crit = 暴击（振幅更大、多抖一轮）
func play_hit(crit: bool = false) -> void:
	if not is_inside_tree():
		return
	var amp := SHAKE_AMP_CRIT if crit else SHAKE_AMP
	var steps := 5 if crit else 4
	_kill_pos_tween()
	_pos_tween = create_tween()
	var step_t := SHAKE_DUR / float(steps + 1)
	for i in range(steps):
		var k := 1.0 - float(i) / float(steps)          # 振幅衰减
		var sx := amp * k * (1.0 if i % 2 == 0 else -1.0)
		var sy := amp * 0.42 * k * (-1.0 if i % 2 == 0 else 1.0)
		_pos_tween.tween_property(_visual_root, "position", Vector2(sx, sy), step_t) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pos_tween.tween_property(_visual_root, "position", Vector2.ZERO, step_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	play_flash(Color("#FF6B5A") if crit else Color("#FFFFFF"))


## 出手前冲：dir = +1 向右（我方）/ −1 向左（敌方）
func play_attack(dir: float = 1.0) -> void:
	if not is_inside_tree():
		return
	_kill_pos_tween()
	_pos_tween = create_tween()
	_pos_tween.tween_property(_visual_root, "position",
		Vector2(LUNGE_DIST * dir, -LUNGE_UP), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pos_tween.tween_property(_visual_root, "position", Vector2.ZERO, 0.20) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 快速白闪（受击反馈）。传 alpha=0 表示关闭
func play_flash(c: Color) -> void:
	if _flash_rect == null or not is_inside_tree():
		return
	var peak := clampf((c.a if c.a > 0.0 else 0.45) * 0.45, 0.0, 1.0)
	var col := Color(c.r, c.g, c.b, 0.0)
	_flash_rect.color = col
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", peak, 0.05)
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.22)


## 倒下：整体缩一下并压暗（复用 _visual_root，不与 refresh() 的 modulate 冲突）
func play_death() -> void:
	if not is_inside_tree():
		return
	_visual_root.pivot_offset = size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_visual_root, "scale", Vector2(0.85, 0.85), 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual_root, "modulate:a", 0.38, 0.30)


## 复位（新战斗 / 复活 / 重开时用），把抖动残留清干净
func reset_fx() -> void:
	_kill_pos_tween()
	if _visual_root != null:
		_visual_root.position = Vector2.ZERO
		_visual_root.scale = Vector2.ONE
		_visual_root.modulate = Color(1, 1, 1, 1)
	if _flash_rect != null:
		_flash_rect.color = Color(1, 1, 1, 0)


func _kill_pos_tween() -> void:
	if _pos_tween != null and _pos_tween.is_valid():
		_pos_tween.kill()
	_pos_tween = null


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()


## 由战斗场景调用：判断一个屏幕坐标是否落在自己身上
func contains_global_point(p: Vector2) -> bool:
	return Rect2(global_position, size).has_point(p)


## 取显示名，日志用
func display_name() -> String:
	if adventurer != null:
		return adventurer.display_name
	if monster != null:
		return monster.get_display_name()
	return "?"
