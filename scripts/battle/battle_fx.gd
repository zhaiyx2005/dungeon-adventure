## 战斗表现层（9-23 需求）：飘字 + 打击特效
##
## 覆盖在整个战斗场景之上的全屏层，只负责"看起来怎么样"，不参与任何数值结算。
## 承担三件事：
##   1. 飘字——伤害 / 治疗 / 护盾数字，在受击者身上弹出、停留约 2 秒后上浮淡出
##   2. 命中冲击——扩散环 + 斩击十字；暴击时更大、更亮、金色
##   3. 出手轨迹——从出手者指向目标的一道残影
##
## 全部特效都是**程序绘制的纯色图形**，与当前"占位色块"美术风格一致，不需要任何素材。
## 用法：加到场景根节点下（全屏锚点、mouse_filter=IGNORE、z_index 抬高），
##       然后调 float_number() / impact() / streak() / banner()。
class_name BattleFx
extends Control


# --- 飘字时序（"数字在屏上几秒再消失"）---
const FLOAT_HOLD := 1.10        ## 停留时长（此期间原地上浮很慢）
const FLOAT_FADE := 0.90        ## 上浮淡出时长
const FLOAT_LIFE := FLOAT_HOLD + FLOAT_FADE   ## 合计 2.0s
const FLOAT_RISE := 54.0        ## 淡出期间的上浮距离
const STACK_STEP := 34.0        ## 连续冒数字时每层向上错位的距离

# --- 字号 ---
const FONT_BASE := 26
const FONT_CRIT := 46           ## 暴击更大
const BOX_W := 260.0            ## 文字盒宽（居中摆放用，不影响文字实际宽度）
const BOX_H := 64.0

# --- 配色 ---
const COL_ENEMY_HIT := Color("#F08A24")   ## 敌人受伤
const COL_ALLY_HIT := Color("#D64545")    ## 我方受伤
const COL_HEAL := Color("#3E9E52")        ## 治疗
const COL_SHIELD := Color("#2E7BB5")      ## 护盾
const COL_CRIT := Color("#FFD24A")        ## 暴击（更亮）
const COL_OUTLINE := Color("#241503")     ## 描边（保证浅底也看得清）

# --- 特效 ---
const IMPACT_DUR := 0.46
const STREAK_DUR := 0.30
const BANNER_LIFE := 2.20

var _streaks: Array = []        ## [{from, to, t, dur, color, crit}]
var _live_floats: Array = []    ## [{pos, node}] 用于连续冒数字时向上错位

## 对外接口
## ---------------------------------------------------------------------------

## 飘一个数字。kind: "enemy" | "ally" | "heal" | "shield"；crit = 暴击（更大更亮）
func float_number(global_pos: Vector2, text: String, kind: String, crit: bool = false) -> void:
	var l := Label.new()
	l.name = "Float"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	l.add_theme_font_size_override("font_size", FONT_CRIT if crit else FONT_BASE)
	l.add_theme_color_override("font_color", COL_CRIT if crit else _color_for(kind))
	l.add_theme_constant_override("outline_size", 9 if crit else 5)
	l.add_theme_color_override("font_outline_color", COL_OUTLINE)
	l.size = Vector2(BOX_W, BOX_H)
	l.pivot_offset = l.size * 0.5

	# 同一处短时间内连着冒数字时逐层上移，避免几个数字叠成一团看不清
	var fpos := to_local_p(global_pos)
	for _i in range(6):
		var clash := false
		for f in _live_floats:
			var n = f["node"]
			if n == null or not is_instance_valid(n):
				continue
			if absf(float(f["pos"].x) - fpos.x) < 46.0 \
					and absf(float(f["pos"].y) - fpos.y) < 34.0:
				clash = true
				break
		if not clash:
			break
		fpos.y -= STACK_STEP
	_prune_floats()
	_live_floats.append({"pos": fpos, "node": l})

	l.position = fpos - l.size * 0.5
	l.z_index = 200
	add_child(l)

	var tw := create_tween()
	tw.set_parallel(true)
	if crit:
		# 暴击：从很小弹到略大再回落，前端停顿一下更有"重击感"
		l.scale = Vector2(0.35, 0.35)
		tw.tween_property(l, "scale", Vector2(1.20, 1.20), 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(l, "scale", Vector2.ONE, 0.14).set_delay(0.20)
	else:
		l.scale = Vector2(0.55, 0.55)
		tw.tween_property(l, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 先原地停留，再上浮淡出
	tw.tween_property(l, "position:y", l.position.y - FLOAT_RISE, FLOAT_LIFE).set_delay(0.16)
	tw.tween_property(l, "modulate:a", 0.0, FLOAT_FADE).set_delay(0.16 + FLOAT_HOLD)
	tw.finished.connect(l.queue_free)


## 命中冲击：扩散环 + 斩击十字，画在受击者中心
func impact(global_pos: Vector2, crit: bool = false) -> void:
	var fx := Impact.new()
	add_child(fx)
	fx.setup(to_local_p(global_pos),
		COL_CRIT if crit else Color("#FFFFFF"),
		crit, IMPACT_DUR)


## 出手轨迹：从出手者中心划向目标中心
func streak(from_global: Vector2, to_global: Vector2, crit: bool = false) -> void:
	_streaks.append({
		"from": to_local_p(from_global),
		"to": to_local_p(to_global),
		"t": 0.0,
		"dur": STREAK_DUR,
		"color": COL_CRIT if crit else Color("#F3EFE6"),
		"crit": crit,
	})
	queue_redraw()


## 中央横幅（共鸣触发等大事件）
func banner(main_text: String, sub_text: String = "", color: Color = COL_CRIT) -> void:
	var box := VBoxContainer.new()
	box.name = "Banner"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 92.0
	box.offset_bottom = 186.0
	add_child(box)

	var t := Label.new()
	t.text = main_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", color)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", COL_OUTLINE)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)

	if sub_text != "":
		var s := Label.new()
		s.text = sub_text
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_font_size_override("font_size", 18)
		s.add_theme_color_override("font_color", Color("#4A4436"))
		s.add_theme_constant_override("outline_size", 5)
		s.add_theme_color_override("font_outline_color", Color("#F3EFE6"))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(s)

	box.modulate.a = 0.0
	box.scale = Vector2(0.82, 0.82)
	box.pivot_offset = Vector2(get_viewport_rect().size.x * 0.5, 50.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.18)
	tw.tween_property(box, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 0.0, 0.55).set_delay(BANNER_LIFE - 0.55)
	tw.finished.connect(box.queue_free)


## 清掉所有残留特效（战斗重开 / 场景切换时调用）
func clear_all() -> void:
	_streaks.clear()
	_live_floats.clear()
	for c in get_children():
		c.queue_free()
	queue_redraw()


## 丢掉已经失效的飘字记录（节点被释放 / 已被 tween 收走）
func _prune_floats() -> void:
	var alive: Array = []
	for f in _live_floats:
		var n = f["node"]
		if n != null and is_instance_valid(n) and (n as Node).is_inside_tree():
			alive.append(f)
	_live_floats = alive


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

## 全局坐标 → 本层局部坐标
## 注意：Control 没有 Node2D 的 to_local()，只能用全局变换求逆
func to_local_p(global_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_pos


func _color_for(kind: String) -> Color:
	match kind:
		"heal": return COL_HEAL
		"shield", "mana": return COL_SHIELD
		"ally": return COL_ALLY_HIT
		_: return COL_ENEMY_HIT


func _process(delta: float) -> void:
	if _streaks.is_empty():
		return
	var alive: Array = []
	for s in _streaks:
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) < float(s["dur"]):
			alive.append(s)
	_streaks = alive
	queue_redraw()


func _draw() -> void:
	for s in _streaks:
		_draw_streak(s)


func _draw_streak(s: Dictionary) -> void:
	var p: float = clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
	var a: Vector2 = s["from"]
	var b: Vector2 = s["to"]
	var d := b - a
	var dist := d.length()
	if dist < 1.0:
		return
	var dir := d / dist
	var n := Vector2(-dir.y, dir.x)
	var crit: bool = s["crit"]

	# 头部沿直线推进（easeOut），尾部拖着一段尾巴
	var e := 1.0 - pow(1.0 - p, 3.0)
	var head := a.lerp(b, e)
	var tail := a.lerp(head, 0.52)

	var col: Color = s["color"]
	col.a = (1.0 - p) * 0.85
	var w0 := 15.0 if crit else 10.0
	var w1 := 2.5
	draw_colored_polygon(PackedVector2Array([
		tail + n * w0, head + n * w1, head - n * w1, tail - n * w0,
	]), col)

	var head_col := Color(1, 1, 1, (1.0 - p) * 0.9)
	draw_circle(head, 7.0 if crit else 5.0, head_col)


# ---------------------------------------------------------------------------
# 命中冲击（内部类：自己管生命周期，播完自毁）
# ---------------------------------------------------------------------------
class Impact extends Control:
	const SEGMENTS := 48

	var fx_color := Color.WHITE
	var crit := false
	var radius := 62.0
	var dur := 0.46
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 190

	## p_local: BattleFx 局部坐标下的落点
	func setup(p_local: Vector2, p_color: Color, p_crit: bool, p_dur: float) -> void:
		fx_color = p_color
		crit = p_crit
		dur = p_dur
		radius = 62.0 * (1.45 if crit else 1.0)
		size = Vector2(radius * 2.0, radius * 2.0)
		pivot_offset = size * 0.5
		position = p_local - size * 0.5

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var p: float = clampf(_t / dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - p, 3.0)
		var ctr := size * 0.5
		var max_r := size.x * 0.5 - 2.0
		var r := lerpf(max_r * 0.16, max_r, e)

		var c := fx_color
		c.a = (1.0 - p) * (1.0 - p)
		draw_arc(ctr, r, 0.0, TAU, SEGMENTS, c, 3.0, true)
		if crit:
			var c2 := c
			c2.a *= 0.6
			draw_arc(ctr, r * 0.6, 0.0, TAU, SEGMENTS, c2, 2.0, true)

		# 斩击十字
		var sl := c
		sl.a *= 0.9
		var l := max_r * (0.5 + 0.8 * e)
		var w := 4.5 if crit else 3.0
		var d := Vector2(0.7071, 0.7071) * l
		draw_line(ctr - d, ctr + d, sl, w, true)
		draw_line(ctr + Vector2(-d.x, d.y), ctr + Vector2(d.x, -d.y), sl, w, true)
