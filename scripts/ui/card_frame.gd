## 通用卡牌模板控件（两种版式）
##
## 版式 person（人物 / 物品 / 任务卡）：
##   上：纯色 / 图片区（**不放大任何文字**）/ 中下：属性·描述框 / 下：金色名字条
##   → assets/images/card/person_card_border.png（人物卡牌边框模型_白边透明_无文字）
##
## 版式 battle（战斗卡，9-23 修改意见 2）：
##   左上 = 消耗行动点 / 右上 = 消耗蓝量 / 最上方 = 名字 /
##   上半框 = 图片 / 下半框 = 描述（中间小胶囊 = 六分类）
##   → assets/images/card/battle_card_border.png（战斗卡牌边框模型_白边透明）
##
## 所有卡牌（战斗卡 / 人物卡 / 物品卡 / 任务卡）统一走本控件。
## 支持左键点击（clicked）、右键详情（right_clicked）、原生拖拽（drag_payload 非空时）。
class_name CardFrame
extends Control


signal clicked(frame: CardFrame)
## 9-22 修改意见 4：右键查看详情（左键留给选中 / 拖拽）
signal right_clicked(frame: CardFrame)


const STYLE_PERSON := "person"
const STYLE_BATTLE := "battle"

const BORDER_PERSON := "res://assets/images/card/person_pixel_frame.svg"
const BORDER_BATTLE := "res://assets/images/card/battle_card_border.png"

## 战斗卡边框分区（比例）—— 素材 750×1050。
## 9-23 修改意见 1 换用新素材后由 PIL 逐像素重测（不是目测）：
##   名字牌（尖角横幅，深棕描边 #7b5928）外框 x 0.109–0.896 / y 0.081–0.166；
##     横幅是六边形，上下沿最窄处只到 x 0.175–0.819，故文字区收窄到 x 0.168–0.832，
##     否则长卡名会从横幅的斜角处"漏"出去（这就是"文字超出框"的成因）
##   图片框内部 x 0.126–0.874 / y 0.180–0.601（灰紫框线 #877373 位于 x 0.105–0.124 / 0.876–0.896）
##   分类胶囊**外**框 x 0.305–0.701 / y 0.5648–0.6510，描边同 #877373、粗 5px，
##     白底区 y 0.5695–0.6448 —— 胶囊是"骑"在图片框底边上的（上半在图片区内）。
##     ⚠️ 所以图片色块**不能一路填到 0.600**：那样会把胶囊上半连同文字一起盖住
##        （实测渲染里"法术进攻"四个字上半被橙色吃掉）。
##        做法：主图片区止于胶囊顶 0.565，胶囊两侧余下的窄带用 art_wing_l/r 补齐。
##   描述区 x 0.125–0.879 / y 0.618–0.910（卡内亮区在 y 0.92 处收口）
##   绿六边形(行动点) x 0.011–0.157 y 0.007–0.097
##   蓝五边形(蓝量)   x 0.863–0.991 y 0.007–0.096
## 注意：素材四周有透明外边距（卡体 x 0.003–0.999 y 0.001–0.966），
##       徽章略超出卡体——这是设计如此（徽章骑在边框上）。
const BATTLE_ZONE := {
	"name": [0.168, 0.076, 0.832, 0.170],
	"art": [0.126, 0.182, 0.874, 0.565],
	"art_wing_l": [0.126, 0.565, 0.305, 0.600],
	"art_wing_r": [0.701, 0.565, 0.874, 0.600],
	"tag": [0.312, 0.570, 0.698, 0.645],
	"desc": [0.125, 0.618, 0.879, 0.910],
	"badge_l": [0.011, 0.007, 0.157, 0.097],
	"badge_r": [0.863, 0.007, 0.991, 0.096],
}

## 人物 / 物品卡边框分区（比例）—— 素材 745×1040（约 1:1.396）。
## 同样由逐像素实测：上下两块区域之间有一条 y≈0.51 的分隔线。
##   上半区（纯色 / 图片）内部 x 0.107–0.891 / y 0.130–0.508 —— 区域内不放任何文字
##   下半区（属性 / 描述）内部 x 0.150–0.848 / y 0.520–0.870
##   底部金名条 x 0.150–0.850 / y 0.878–0.946
## 稀有度 / 状态角标改贴在属性框顶部一条窄带（原先贴在图片区顶部，与"上半区不要文字"冲突）
const PERSON_ZONE := {
	"name": [0.150, 0.878, 0.850, 0.946],
	"art": [0.107, 0.130, 0.891, 0.508],
	"desc": [0.152, 0.524, 0.846, 0.868],
	"badge_l": [0.152, 0.524, 0.499, 0.562],
	"badge_r": [0.501, 0.524, 0.846, 0.562],
}

## 名字条底色（盖住模板图里烙死的「双击编辑文本」占位字）
const NAME_BAR_COLOR := Color("#d9ab5f")
const NAME_TEXT_COLOR := Color("#3a2c14")
const BATTLE_NAME_COLOR := Color("#5a3a12")   ## 米色卷轴条上的深棕字
const BATTLE_BADGE_COLOR := Color("#FFFFFF")   ## 绿 / 蓝徽章上的白字
const DESC_TEXT_COLOR := Color("#4a4841")

## 字号自适应下限：再挤也不低于这个值（低于 8px 中文已不可读）
const MIN_FONT_NAME := 9
const MIN_FONT_DESC := 8
const MIN_FONT_TAG := 8
const MIN_FONT_BADGE := 9

static var _tex_cache := {}


var drag_payload: Variant = null          ## 非空时整卡可作为拖拽源
var highlight: bool = false               ## 选中高亮描边
var style: String = STYLE_PERSON          ## person / battle


var _frame: TextureRect
var _art_clip: Control
var _art_color: ColorRect
var _art_image: TextureRect
var _art_wing_l: ColorRect                 ## 分类胶囊左侧的图片区补角（仅 battle）
var _art_wing_r: ColorRect                 ## 分类胶囊右侧的图片区补角（仅 battle）
var _art_tag: Label                       ## 类型字（**仅 battle 版式**放在中间胶囊里）
var _tag_bg: Panel                        ## 类型字后面的实底药丸（只在有插画时需要）
var _desc_label: Label
var _name_panel: Panel
var _name_label: Label
var _badge_l: Label
var _badge_r: Label
var _highlight_panel: Panel


func _init() -> void:
	custom_minimum_size = Vector2(120, 162)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_build()
	_refresh_fonts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_refresh_fonts()


## 一句话建卡：title / desc / 图片区占位色 / 可选参数
## opts: style(person|battle)、image(Texture2D)、tag(类型字)、badge_l、badge_r(String)
func setup(title: String, desc: String, art_color: Color, opts: Dictionary = {}) -> void:
	if not is_node_ready():
		ready.connect(_apply_setup.bind(title, desc, art_color, opts), CONNECT_ONE_SHOT)
		return
	_apply_setup(title, desc, art_color, opts)


func _apply_setup(title: String, desc: String, art_color: Color, opts: Dictionary) -> void:
	if _frame == null:
		_build()
	var want_style: String = opts.get("style", STYLE_PERSON)
	if want_style != style:
		set_style(want_style)
	_name_label.text = title
	_desc_label.text = desc
	_art_color.color = art_color
	if _art_wing_l != null:
		_art_wing_l.color = art_color
	if _art_wing_r != null:
		_art_wing_r.color = art_color
	var img: Texture2D = opts.get("image", null)
	if img != null:
		_art_image.texture = img
		_art_image.visible = true
		_art_color.visible = false
	else:
		_art_image.visible = false
		_art_color.visible = true
	var tag: String = opts.get("tag", "")
	_art_tag.text = tag
	_badge_l.text = opts.get("badge_l", "")
	_badge_r.text = opts.get("badge_r", "")
	_apply_zones()
	_refresh_fonts()


## 切换版式（人物卡 / 战斗卡）
func set_style(s: String) -> void:
	if s != STYLE_PERSON and s != STYLE_BATTLE:
		return
	style = s
	if _frame == null:
		return
	_frame.texture = _get_tex(BORDER_BATTLE if style == STYLE_BATTLE else BORDER_PERSON)
	_apply_zones()
	_refresh_fonts()


## 按版式摆放各分区。
##
## 名字：始终放在 zone["name"]。
##   battle —— 直接写在边框自带的米色名字牌上（不铺金条）；
##   person —— 铺一层金条盖住模板占位字，名字叠在金条上。
## 两者都必须让 _name_label 挂在 CardFrame 下（而不能挂在 _name_panel 里），
## 否则 battle 版式把面板隐藏时会连名字一起隐藏。
##
## 类型字：人物卡的图片区**不允许出现任何文字**（9-23 修改意见 5），
## 所以 person 版式一律隐藏 _art_tag；只有 battle 版式把它放进中间胶囊。
func _apply_zones() -> void:
	if _frame == null:
		return
	var zone: Dictionary = BATTLE_ZONE if style == STYLE_BATTLE else PERSON_ZONE

	# 图片区：battle 版式止于分类胶囊顶（否则色块会盖住胶囊里的分类文字）；
	# 有真实卡面图时整块铺满图片框（到 0.600，即胶囊底），胶囊由**代码**画在插画之上。
	# 分工：插画一律**不含任何文字**（AI 生成图里的中文不可控），
	#       六分类文字与它的实底药丸由代码负责，见下面的 _tag_bg。
	var art_rect: Array = zone["art"]
	var art_image_on: bool = _art_image != null and _art_image.visible
	if style == STYLE_BATTLE and art_image_on:
		art_rect = [0.126, 0.182, 0.874, 0.600]
	_anchor(_art_clip, art_rect)

	# 胶囊两侧的补角：只在 battle 且用色块占位时出现
	var wings_on: bool = style == STYLE_BATTLE and not art_image_on
	for w in [_art_wing_l, _art_wing_r]:
		if w != null:
			w.visible = wings_on
	if wings_on:
		_anchor(_art_wing_l, zone["art_wing_l"])
		_anchor(_art_wing_r, zone["art_wing_r"])

	var tag_on: bool = style == STYLE_BATTLE and _art_tag != null and _art_tag.text != ""
	if _tag_bg != null:
		# 只在"有插画 + 有类型字"时才补实底：没插画时边框贴图自带的药丸就够用，
		# 再补一块会叠出双层描边。
		_tag_bg.visible = tag_on and art_image_on
		# person 版式没有 "tag" 分区，锚到图片区即可（反正那时它不可见）
		_anchor(_tag_bg, zone["tag"] if style == STYLE_BATTLE else zone["art"])

	_anchor(_art_tag, zone["tag"] if style == STYLE_BATTLE else zone["art"])
	_art_tag.visible = tag_on

	var badges_on: bool = style == STYLE_PERSON and (_badge_l.text != "" or _badge_r.text != "")
	_badge_l.visible = _badge_l.text != ""
	_badge_r.visible = _badge_r.text != ""
	_anchor(_desc_label, _desc_rect(zone, badges_on))
	_anchor(_badge_l, zone["badge_l"])
	_anchor(_badge_r, zone["badge_r"])

	_anchor(_name_panel, zone["name"])
	_anchor(_name_label, zone["name"])
	_name_panel.visible = style != STYLE_BATTLE

	# 角标只在 person 版式的窄带里出现；battle 版式的角标是六边形上的数字
	_badge_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## 描述区实际用的矩形：属性框里若有角标窄带，描述就从窄带下面开始
func _desc_rect(zone: Dictionary, badges_on: bool) -> Array:
	if not badges_on:
		return zone["desc"]
	return [zone["desc"][0], zone["badge_l"][3], zone["desc"][2], zone["desc"][3]]


func set_highlight(v: bool) -> void:
	highlight = v
	if _highlight_panel != null:
		_highlight_panel.visible = v


func set_dim(v: bool) -> void:
	modulate = Color(1, 1, 1, 0.5) if v else Color(1, 1, 1, 1)


static func _get_tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	_frame = TextureRect.new()
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# 图片区（裁剪）
	_art_clip = Control.new()
	_art_clip.clip_contents = true
	_art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_clip)

	_art_color = ColorRect.new()
	_art_color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_clip.add_child(_art_color)

	_art_image = TextureRect.new()
	_art_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# 卡面插画是像素画：必须最近邻，线性插值会把像素块糊掉
	_art_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_image.visible = false
	_art_clip.add_child(_art_image)

	# 图片区下沿补角（battle 专用）：分类胶囊骑在图片框底边上，
	# 主图片区只能到胶囊顶，两侧各留一条窄带由这两块补齐
	_art_wing_l = ColorRect.new()
	_art_wing_r = ColorRect.new()
	for wing in [_art_wing_l, _art_wing_r]:
		wing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wing.visible = false
		add_child(wing)

	# 类型字（只有 battle 版式会显示，放在中间胶囊里）
	#
	# 实底药丸：边框贴图里本来就画了一个白色药丸，但它在 **图片层下面**；
	# 一旦卡面有了插画（会铺到 0.600，即胶囊顶 0.570 以下），白色药丸就被插画盖住，
	# 只剩深灰字 `#5c5a52` 直接压在插画上 —— 深色插画上完全读不出来。
	# 所以有插画时自己补一块同样的实底，垫在文字下面、插画上面。
	_tag_bg = Panel.new()
	_tag_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_bg.visible = false
	var tag_sb := StyleBoxFlat.new()
	tag_sb.bg_color = Color("#F6F3EA")
	tag_sb.border_color = Color("#877373")
	tag_sb.set_border_width_all(2)
	tag_sb.set_corner_radius_all(8)
	_tag_bg.add_theme_stylebox_override("panel", tag_sb)
	add_child(_tag_bg)

	_art_tag = Label.new()
	_art_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_art_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_art_tag.clip_text = true
	_art_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_tag.visible = false
	add_child(_art_tag)

	# 描述区
	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc_label.clip_text = true
	_desc_label.add_theme_color_override("font_color", DESC_TEXT_COLOR)
	# 行距收 1px：手牌尺寸（112×157）描述框只有 45.8px，而 4 行 8px 字（行高 12）需要 48px，
	# 结果末行被 clip_text 静默吃掉（guard_phys 的"束。"、static_bolt 的"倍。"都看不见）。
	# 描述框的下边界已经贴着卡内亮区收口线，不便再加高，所以从行距里挤：
	# 4 行省 3px、3 行省 2px，正好补上缺口，且对所有卡面尺寸都只是轻微收紧。
	_desc_label.add_theme_constant_override("line_spacing", -1)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc_label)

	# 金色名字条（仅 person 版式需要，用来盖住模板占位字）
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAME_BAR_COLOR
	sb.set_corner_radius_all(3)
	_name_panel = Panel.new()
	_name_panel.add_theme_stylebox_override("panel", sb)
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_panel)

	# 名字文字：必须是 CardFrame 的直接子节点（金色名字条只是它的一层底），
	# 这样 battle 版式隐藏金条时名字依然显示在边框自带的米色名字牌上。
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.add_theme_color_override("font_color", NAME_TEXT_COLOR)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	# 左上 / 右上角标（battle：行动点 / 蓝量；person：稀有度 / 状态）
	_badge_l = _make_badge()
	add_child(_badge_l)
	_badge_r = _make_badge()
	add_child(_badge_r)

	# 高亮描边
	_highlight_panel = Panel.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0)
	hsb.border_color = Color("#EF9F27")
	hsb.set_border_width_all(3)
	hsb.set_corner_radius_all(6)
	_highlight_panel.add_theme_stylebox_override("panel", hsb)
	_highlight_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_panel.visible = false
	add_child(_highlight_panel)

	set_style(style)


## 只改锚点（节点已在树上时用）
func _anchor(c: Control, r: Array) -> void:
	c.anchor_left = r[0]
	c.anchor_top = r[1]
	c.anchor_right = r[2]
	c.anchor_bottom = r[3]
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func _make_badge() -> Label:
	var l := Label.new()
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color("#2c2a24"))
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _refresh_fonts() -> void:
	if _name_label == null:
		return
	var h := size.y
	if h <= 0:
		h = custom_minimum_size.y
	var w := size.x
	if w <= 0:
		w = custom_minimum_size.x
	var zone: Dictionary = BATTLE_ZONE if style == STYLE_BATTLE else PERSON_ZONE
	var badges_on: bool = style == STYLE_PERSON and (_badge_l.text != "" or _badge_r.text != "")
	var desc_rect: Array = _desc_rect(zone, badges_on)

	if style == STYLE_BATTLE:
		# 战斗卡：名字在顶部卷轴条上，行动/蓝量在两侧六边形里，胶囊放分类。
		# 9-23 修改意见 2（手牌文字模糊）：字号下限整体抬高，再加上下面的分区自适应。
		_set_font(_name_label, int(clampf(h * 0.078, 12, 22)), BATTLE_NAME_COLOR)
		_set_font(_desc_label, int(clampf(h * 0.064, 10, 15)), DESC_TEXT_COLOR)
		_set_font(_art_tag, int(clampf(h * 0.058, 9, 14)), Color("#5c5a52"))
		_set_font(_badge_l, int(clampf(h * 0.078, 12, 20)), BATTLE_BADGE_COLOR)
		_set_font(_badge_r, int(clampf(h * 0.078, 12, 20)), BATTLE_BADGE_COLOR)
		_badge_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		_badge_r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	else:
		# 小卡（战斗手牌 100×140）也要能看清：下限抬高，字号随高度缩放
		_set_font(_name_label, int(clampf(h * 0.072, 11, 24)), NAME_TEXT_COLOR)
		_set_font(_desc_label, int(clampf(h * 0.058, 9, 16)), DESC_TEXT_COLOR)
		_set_font(_art_tag, int(clampf(h * 0.13, 12, 44)), Color(1, 1, 1, 0.85))
		_set_font(_badge_l, int(clampf(h * 0.046, 8, 15)), Color("#2c2a24"))
		_set_font(_badge_r, int(clampf(h * 0.046, 8, 15)), Color("#2c2a24"))
		_badge_l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))
		_badge_r.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))

	# 分区内字号自适应（9-23 修改意见 1）：字太长 / 行太多就往下降，直到塞进框里。
	# 内置边框的可用区是固定比例，只有字号能动——这是"文字不超出框"的唯一可靠做法。
	_autofit(_name_label, _zone_w(zone["name"], w), _zone_h(zone["name"], h), MIN_FONT_NAME, false)
	_autofit(_desc_label, _zone_w(desc_rect, w), _zone_h(desc_rect, h), MIN_FONT_DESC, true)
	_autofit(_badge_l, _zone_w(zone["badge_l"], w), _zone_h(zone["badge_l"], h), MIN_FONT_BADGE, false)
	_autofit(_badge_r, _zone_w(zone["badge_r"], w), _zone_h(zone["badge_r"], h), MIN_FONT_BADGE, false)
	if style == STYLE_BATTLE:
		_autofit(_art_tag, _zone_w(zone["tag"], w), _zone_h(zone["tag"], h), MIN_FONT_TAG, false)


func _set_font(l: Label, sz: int, col: Color) -> void:
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)


func _zone_w(r: Array, w: float) -> float:
	return maxf((r[2] - r[0]) * w, 6.0)


func _zone_h(r: Array, h: float) -> float:
	return maxf((r[3] - r[1]) * h, 6.0)


## 把 label 的字号从当前值往下调，直到文本量得下（wrap=false 时按单行宽度量）
func _autofit(l: Label, max_w: float, max_h: float, min_size: int, wrap: bool) -> void:
	if l == null or l.text == "":
		return
	var font: Font = l.get_theme_font("font")
	var base: int = l.get_theme_font_size("font_size")
	if font == null or base <= 0:
		return
	var fs := base
	while fs > min_size:
		var probe_w := max_w if wrap else -1.0
		var sz: Vector2 = font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, probe_w, fs)
		if sz.y <= max_h + 0.5 and sz.x <= max_w + 0.5:
			break
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


# ---------------------------------------------------------------------------
# 输入：点击 / 原生拖拽
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		# 9-22 修改意见 4：右键查看卡牌详情
		right_clicked.emit(self)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if drag_payload == null:
		return null
	var pv := TextureRect.new()
	pv.texture = _frame.texture
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.size = size * 0.85
	pv.modulate = Color(1, 1, 1, 0.9)
	pv.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_drag_preview(pv)
	return drag_payload
