## 数据加载器
##
## 负责扫描 res://data/ 下所有 .tres 资源并建立索引。
## 战斗、城镇、UI 都通过这里取数据，不要各自去 load()。
##
## 典型用法：
##     var db := GameDatabase.new()
##     db.load_all()
##     var card: CardData = db.get_card("fireball")
class_name GameDatabase
extends RefCounted


const CARD_DIR := "res://data/cards/"
const MONSTER_DIR := "res://data/monsters/"
const ITEM_DIR := "res://data/items/"
const DUNGEON_DIR := "res://data/dungeons/"


var cards: Dictionary = {}      ## id -> CardData
var monsters: Dictionary = {}   ## id -> MonsterData
var items: Dictionary = {}      ## id -> ItemData
var dungeons: Dictionary = {}   ## id -> DungeonData


var _loaded: bool = false


## 加载全部数据。重复调用只生效一次。
func load_all() -> void:
	if _loaded:
		return
	cards = _load_dir(CARD_DIR)
	monsters = _load_dir(MONSTER_DIR)
	items = _load_dir(ITEM_DIR)
	dungeons = _load_dir(DUNGEON_DIR)
	_loaded = true


# ---------------------------------------------------------------------------
# 目录扫描（导出后必须走这里，不要自己写 DirAccess + ends_with(".tres")）
# ---------------------------------------------------------------------------

## 把目录条目名还原成**逻辑文件名**：剥掉导出留下的 `.remap` / `.import` 后缀。
##
## * 编辑器里：`aegis.tres`   → `aegis.tres`
## * 导出版：  `aegis.tres.remap` → `aegis.tres`
## * 贴图：    `aegis.png.import` → `aegis.png`（导出版贴图只留 `.import`）
static func normalize_entry(entry: String) -> String:
	var n := entry
	for suffix in [".remap", ".import"]:
		if n.ends_with(suffix):
			n = n.substr(0, n.length() - suffix.length())
	return n


## 列出目录下所有数据资源的**逻辑路径**（`res://data/xxx/<id>.tres`）。
##
## 🔴 **不要自己写 `DirAccess.get_next()` + `ends_with(".tres")`。**
## 导出时 Godot 默认把文本资源转成二进制
## （`editor/export/convert_text_resources_to_binary`，默认开），
## 并在原路径留一个 `.remap` 存根 —— 于是目录里的条目名是 `aegis.tres.remap`，
## **不以 `.tres` 结尾**。只按 `.tres` 过滤的话导出版一个文件都匹配不到：
## 实测「卡牌 0 / 怪物 0 / 物品 0 / 关卡 0」，整个游戏没有任何卡牌，
## 而且**不报任何错**（被过滤掉的文件连 `load()` 都不会被调用）。
##
## 返回的路径可以直接 `load()` —— 引擎会自己跟随 remap 找到真正的二进制资源。
static func list_data_files(dir_path: String, suffix: String = ".tres") -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var logical := normalize_entry(entry)
			if logical.ends_with(suffix):
				out.append(dir_path + logical)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()          # 目录列举顺序不保证稳定，排序让结果可复现
	return out


## 扫描目录下所有 .tres，返回 id -> Resource
func _load_dir(dir_path: String) -> Dictionary:
	var result := {}
	var files := list_data_files(dir_path)
	if files.is_empty():
		push_warning("GameDatabase: 目录下没有数据资源（不存在 / 空 / 后缀不匹配）-> %s" % dir_path)
		return result
	for full_path in files:
		var res := load(full_path)
		if res == null:
			push_error("GameDatabase: 加载失败 -> %s" % full_path)
		elif not ("id" in res) or res.id == "":
			push_error("GameDatabase: 资源缺少 id 字段 -> %s" % full_path)
		else:
			if result.has(res.id):
				push_error("GameDatabase: id 重复 '%s' -> %s" % [res.id, full_path])
			result[res.id] = res
	return result


# ---------------------------------------------------------------------------
# 查询接口
# ---------------------------------------------------------------------------

func get_card(id: String) -> CardData:
	return cards.get(id) as CardData


func get_monster(id: String) -> MonsterData:
	return monsters.get(id) as MonsterData


func get_item(id: String) -> ItemData:
	return items.get(id) as ItemData


func get_dungeon(id: String) -> DungeonData:
	return dungeons.get(id) as DungeonData


## 按层级序号取关卡（1 起）
func get_dungeon_by_level(level_index: int) -> DungeonData:
	for d in dungeons.values():
		if (d as DungeonData).level_index == level_index:
			return d
	return null


## 清点数量，可用于启动日志
func summary() -> String:
	return "卡牌 %d / 怪物 %d / 物品 %d / 关卡 %d" % [
		cards.size(), monsters.size(), items.size(), dungeons.size()
	]


# ---------------------------------------------------------------------------
# 筛选接口
# ---------------------------------------------------------------------------

## 按大类筛选战斗卡
func get_cards_by_class(card_class: CardData.CardClass) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in cards.values():
		if (c as CardData).card_class == card_class:
			out.append(c)
	return out


## 按大类筛选物品
func get_items_by_class(item_class: ItemData.ItemClass) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for it in items.values():
		if (it as ItemData).item_class == item_class:
			out.append(it)
	return out


## 取某层级可出现的普通怪
func get_monsters_in_dungeon(dungeon_id: String) -> Array[MonsterData]:
	var out: Array[MonsterData] = []
	var d := get_dungeon(dungeon_id)
	if d == null:
		return out
	for mid in d.monster_pool:
		var m := get_monster(mid)
		if m != null:
			out.append(m)
	return out


## 取某层级的精英怪
func get_elites_in_dungeon(dungeon_id: String) -> Array[MonsterData]:
	var out: Array[MonsterData] = []
	var d := get_dungeon(dungeon_id)
	if d == null:
		return out
	for mid in d.elite_pool:
		var m := get_monster(mid)
		if m != null:
			out.append(m)
	return out
