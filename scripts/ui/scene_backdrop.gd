## 场景背景板（全屏底图 + 压光层）
##
## 用法（场景脚本 `_ready()` 里一行）：
##     _backdrop = SceneBackdrop.attach(self, "menu_town", 0.50)
##     _backdrop.show_image("guild_hall")      # 换图（城镇切标签用）
##
## 素材在 `assets/images/bg/<id>.png`（1280×720，由 `tools/process_art.py` 的 `bg` 类产出）。
##
## 三个设计要点：
##
## 1. **插在场景根的第一个子节点**，所以已有的 UI 全部自动在它上面 ——
##    不需要逐节点调 `z_index`（同一 canvas 内 z_index 是全局排序，很容易踩坑）。
##    原来那个不透明的 `Background` Panel 直接隐藏，由本组件取代。
##
## 2. **必须带压光层**。界面是浅色主题 + 深色文字（`theme_main.tres`），
##    底图直接铺上去会让表单/描述文字读不出来。压光层用场景原本的米色，
##    把底图压到"看得出氛围、但抢不走注意力"的程度。
##    alpha 越大越干净、越小越有画面感 —— 各场景按需调。
##
## 3. 滤镜用 **LINEAR_WITH_MIPMAPS**（跟开屏图一致），不用 NEAREST。
##    背景是 1280 宽的大图、显示时还要被窗口缩放（1280×720 逻辑 → 1600×900 实际，
##    即 1.25×），最近邻会出现"有的像素 1px、有的 2px"的错位感；
##    而它本来就**不是** 1:1 显示的像素素材（不像 96×75 的卡面），线性过滤才是对的。
class_name SceneBackdrop
extends Control


const DIR := "res://assets/images/bg/"

## 压光底色：与城镇/主菜单原本的浅米色底一致（#F1EFE8）
const SCRIM_BASE := Color("#f1efe8")

## 各场景的默认压光强度（越大越干净）。
##
## 这组数是**渲出来比过**的，不是拍的：在同一张背景上跑 0.45/0.55/0.65/0.75/0.85 五档
## （`_probe_scrim.gd`），看灰色提示文字（`#66635C`，13–14px）压在书架上还读不读得出来。
## 结论：**浅色主题 + 小号灰字至少要 0.65**；0.45/0.55 时提示文字糊在背景里。
## 界面里没多少文字的场景（战斗：面板本身还叠了一层半透明）可以低一些，画面感更好。
const SCRIM_MENU := 0.60
const SCRIM_TOWN := 0.70
const SCRIM_DUNGEON := 0.62
const SCRIM_BATTLE := 0.50

var _tex: TextureRect
var _scrim: ColorRect


## 给 `host` 挂一块背景板，返回它供后续换图。
static func attach(host: Control, image_id: String, scrim_alpha: float) -> SceneBackdrop:
	var b := SceneBackdrop.new()
	b.name = "SceneBackdrop"
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b._build()
	b.set_scrim(scrim_alpha)
	b.show_image(image_id)
	host.add_child(b)
	host.move_child(b, 0)          # 垫到底下，已有 UI 全部盖在它上面
	# 场景里原本的不透明 Background Panel 由本组件取代
	var old := host.get_node_or_null("Background")
	if old is CanvasItem:
		(old as CanvasItem).visible = false
	return b


func _build() -> void:
	_tex = TextureRect.new()
	_tex.name = "Image"
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(SCRIM_BASE, 1.0)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)


## 换底图。素材缺失时只是这张图不显示（露出压光底色），不会崩。
func show_image(image_id: String) -> void:
	if _tex == null:
		return
	_tex.texture = ArtRegistry.bg(image_id)


func current_id() -> String:
	if _tex == null or _tex.texture == null:
		return ""
	return _tex.texture.resource_path.get_file().get_basename()


func set_scrim(alpha: float) -> void:
	if _scrim != null:
		_scrim.color = Color(SCRIM_BASE, clampf(alpha, 0.0, 1.0))


## 有没有真的挂上底图（探针/测试用）
func has_image() -> bool:
	return _tex != null and _tex.texture != null
