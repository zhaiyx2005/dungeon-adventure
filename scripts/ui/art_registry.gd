## 像素插画注册表
##
## 约定：`assets/images/art/card/<卡牌id>.png`、`assets/images/art/unit/<怪物或人物id>.png`、
## `assets/images/art/item/<物品id>.png`。
## 素材由 `tools/process_art.py` 从 AI 生成的原图处理而来（裁水印 → 抠底 → 像素化 → 限色板），
## 不是手绘的，所以**允许缺失**：没生成的 id 返回 null，卡面回落到占位色块，
## 这样"先出一部分素材"和"全量出完"两种情况都能正常跑。
##
## 插画节点一律用 NEAREST 过滤（`TextureRect.texture_filter`），
## 否则线性插值会把像素块糊掉 —— 像素画的显示方式必须是"最近邻放大"。
class_name ArtRegistry
extends RefCounted


const CARD_DIR := "res://assets/images/art/card/"
const UNIT_DIR := "res://assets/images/art/unit/"
const ITEM_DIR := "res://assets/images/art/item/"
## 场景背景与卡面/立绘不同层：它是铺满全屏的 1280×720 大图，
## 所以放 `assets/images/bg/`（与 `splash/` 平级），不进 `art/`。
const BG_DIR := "res://assets/images/bg/"

## 已解析过的纹理缓存（load 本身有缓存，这里只是省掉一次 ResourceLoader.exists 探测）
static var _cache: Dictionary = {}


## 卡面插画（法术/攻击/防御/特殊 通用）
static func card(card_id: String) -> Texture2D:
	return _load_tex(CARD_DIR + card_id + ".png")


## 单位立绘（怪物 / 冒险者），透明底
static func unit(unit_id: String) -> Texture2D:
	return _load_tex(UNIT_DIR + unit_id + ".png")


## 物品图标（装备 / 道具 / 收集品 / 战利品 / 杂物），透明底。
##
## 原生网格 100×68，**与人物卡的图片区尺寸 1:1 一致**（归一化 0.107–0.891 × 0.130–0.508
## 落在 128×179 的卡体上正好是 100×68）。尺寸对齐是刻意的：
## CardFrame 的插画是 KEEP_ASPECT_COVERED，原生网格比例对不上就会把物体边角裁掉，
## 而剑/弓/甲被裁掉一头一尾就废了。
static func item(item_id: String) -> Texture2D:
	return _load_tex(ITEM_DIR + item_id + ".png")


## 场景背景（1280×720，带画面）。
## 由 `SceneBackdrop` 使用，不要在场景里直接 load —— 那会绕过缺失保护与缓存。
static func bg(bg_id: String) -> Texture2D:
	return _load_tex(BG_DIR + bg_id + ".png")


## 半身像（胸像）：取立绘上部的横向切片。
##
## 只对**人形**用（人物卡）。人形立绘的头在上部，取"头 + 上身"这一条
## 塞进横向的卡面图片区，主体更大。
##
## ⚠️ 不要给四足怪用！野猪、狼这类身体横在画面中部，
## 取上部切片只会剩下一片后背（实测过）。四足/形状不定的单位用 `unit_trimmed`。
##
## 返回 AtlasTexture（不复制像素，零额外显存）。
static func unit_bust(unit_id: String, top_ratio: float = 0.64) -> Texture2D:
	var tex := unit(unit_id)
	if tex == null:
		return null
	var key := UNIT_DIR + unit_id + "#bust%.2f" % top_ratio
	if _cache.has(key):
		return _cache[key]
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0.0, 0.0, float(tex.get_width()),
		float(tex.get_height()) * top_ratio)
	_cache[key] = at
	return at


## 战斗立绘：优先 `<id>_battle.png`（侧身朝右 —— 我方在左、敌人在右，朝向正对对手），
## 没有就退回普通立绘。
##
## 命名约定而非新字段：同一角色的多张立绘用"主 id + 用途后缀"区分，
## 这样数据表（Adventurer/MonsterData）不用为一个纯美术需求加字段。
static func unit_battle(unit_id: String) -> Texture2D:
	var key := UNIT_DIR + unit_id + "#battletrim"
	if _cache.has(key):
		return _cache[key]
	var tex := unit(unit_id + "_battle")
	var res: Texture2D = _trimmed_atlas(tex) if tex != null else unit_trimmed(unit_id)
	_cache[key] = res
	return res


## 裁掉透明边后的立绘，配合 `STRETCH_KEEP_ASPECT_CENTERED` 使用。
##
## 立绘源是固定 96×96 的方形，主体在框里的占比和位置**因素材而异**：
## 人形几乎占满高度，四足怪只占中间一横条、上下都是透明。
## 所以单位立绘带不能固定"取上部 64%"或"铺满裁切"，而要
## **先按 alpha 求出主体包围盒、再整身等比塞进立绘带** —— 每个单位都能拿满可用空间，
## 而且不会被裁掉头或脚。
static func unit_trimmed(unit_id: String) -> Texture2D:
	var tex := unit(unit_id)
	if tex == null:
		return null
	var key := UNIT_DIR + unit_id + "#trim"
	if _cache.has(key):
		return _cache[key]
	var at := _trimmed_atlas(tex)
	_cache[key] = at
	return at


static func _trimmed_atlas(tex: Texture2D) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	var img := tex.get_image()
	if img == null:
		return at
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return at
	at.region = Rect2(used)
	return at


static func has_card(card_id: String) -> bool:
	return card(card_id) != null


static func has_unit(unit_id: String) -> bool:
	return unit(unit_id) != null


# ---------------------------------------------------------------------------
# 冒险者立绘：专属立绘 → 职业原型立绘 的两级回退
#
# 招募池里的冒险者是"随机属性 + 随机名"生成的（`TownManager.roll_recruit`），
# **没有固定身份**，不可能给每个 id 都出一张立绘。所以：
#   1. 先找该 id 自己的立绘（主角 / 固定成员有）
#   2. 没有再按"最高属性"分派一张职业原型立绘
# 这样招募到的人不会是一块纯色占位。
# ---------------------------------------------------------------------------

## 四属性 → 职业原型立绘 id
const ARCHETYPES := {
	"strength": "warrior",
	"intelligence": "arch_scholar",
	"vitality": "arch_rogue",
	"constitution": "arch_priest",
}
## 四属性都很平均时的原型（没有明显长项 = 万金油游侠）
const ARCHETYPE_BALANCED := "arch_ranger"

const ARCHETYPE_NAMES_CN := {
	"warrior": "战士",
	"arch_scholar": "法师",
	"arch_rogue": "盗贼",
	"arch_priest": "牧师",
	"arch_ranger": "游侠",
}

## 按最高属性判定职业原型 id。
##
## "万金油游侠"的判据：**最高值并列 + 四属性极差 ≤1**。
## 只写"极差 ≤1"是不够的 —— 5/5/6/5 这种极差也是 1，但智力**唯一最高**，
## 应该判学者而不是游侠（实测踩过这个 case）。
## 比较用固定顺序遍历 + 严格大于，保证同一个人每次算出来一样。
static func archetype_of(a: Adventurer) -> String:
	if a == null:
		return ARCHETYPE_BALANCED
	var vals := [a.constitution, a.strength, a.intelligence, a.vitality]
	var lo: int = vals.min()
	var hi: int = vals.max()
	var tied := 0
	for v in vals:
		if int(v) == hi:
			tied += 1
	if tied >= 2 and hi - lo <= 1:
		return ARCHETYPE_BALANCED
	var best_key := "constitution"
	var best := -9999
	for k in ["strength", "intelligence", "vitality", "constitution"]:
		var v := 0
		match k:
			"strength": v = a.strength
			"intelligence": v = a.intelligence
			"vitality": v = a.vitality
			_ : v = a.constitution
		if v > best:
			best = v
			best_key = k
	return String(ARCHETYPES.get(best_key, ARCHETYPE_BALANCED))


static func archetype_name_cn(a: Adventurer) -> String:
	return String(ARCHETYPE_NAMES_CN.get(archetype_of(a), "冒险者"))


## 冒险者的人物卡立绘（半身）：先自己的，再原型
static func adventurer_bust(a: Adventurer) -> Texture2D:
	if a == null:
		return null
	var atlas := _load_tex(UNIT_DIR + "portraits_pixel_v2.png")
	if atlas != null:
		var portraits := {"hero": 0, "warrior": 1, "mage": 2, "arch_scholar": 2,
			"arch_rogue": 3, "arch_priest": 4, "arch_ranger": 5}
		var portrait_id: String = a.id if portraits.has(a.id) else archetype_of(a)
		var key := "pixel_portrait/" + portrait_id
		if not _cache.has(key):
			var index: int = portraits.get(portrait_id, 0)
			var region := AtlasTexture.new()
			region.atlas = atlas
			var cell := Vector2(atlas.get_width() / 3.0, atlas.get_height() / 2.0)
			region.region = Rect2(Vector2(index % 3, index / 3) * cell, cell)
			region.filter_clip = true
			_cache[key] = region
		return _cache[key]
	var own := unit_bust(a.id)
	if own != null:
		return own
	return unit_bust(archetype_of(a))


## 冒险者的战斗立绘（整身裁边）：先自己的（含 `<id>_battle`），再原型
static func adventurer_battle(a: Adventurer) -> Texture2D:
	if a == null:
		return null
	for candidate in [a.id, archetype_of(a)]:
		var t := unit_battle(String(candidate))
		if t != null:
			return t
	return null


## 怪物战斗立绘：怪物都有固定 id，直接走 unit_battle
static func monster_battle(m: MonsterInstance) -> Texture2D:
	if m == null or m.data == null:
		return null
	return unit_battle(m.data.id)


static func has_item(item_id: String) -> bool:
	return item(item_id) != null


static func has_bg(bg_id: String) -> bool:
	return bg(bg_id) != null


## 是否已经有任何素材（给测试与"素材进度"提示用）
##
## ⚠️ 目录列举要归一化条目名并去重：编辑器里贴图是 `.png` + `.png.import` 两个条目，
## 而导出版**只有 `.png.import`**（贴图靠 `.import` 里的 remap 段解析到 `.ctex`）。
## 不归一化的话：编辑器里数成 2 倍，导出版数成 0 —— 两头都不对。
static func available_count() -> int:
	var seen := {}
	for dir_path in [CARD_DIR, UNIT_DIR, ITEM_DIR, BG_DIR]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			var logical := GameDatabase.normalize_entry(f)
			if logical.ends_with(".png"):
				seen[dir_path + logical] = true
	return seen.size()


static func clear_cache() -> void:
	_cache.clear()


static func _load_tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[path] = tex
	return tex


## 给插画节点套上像素画该有的显示设置。
##
## 两个都必须设置：
##   * `texture_filter = TEXTURE_FILTER_NEAREST` —— 否则线性插值糊掉像素块
##   * `stretch_mode` / `expand_mode` 由调用方决定（卡面铺满、立绘保持比例）
static func apply_pixel_filter(node: CanvasItem) -> void:
	if node == null:
		return
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
