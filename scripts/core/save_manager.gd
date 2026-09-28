## 存档系统（9-28 需求：**10 个栏位**）
##
## 序列化 GameData 的持久态到 user://save_00.json … save_09.json，读档恢复。
## 持久态包括：金币、小队（含装备/等级/经验/属性点）、卡组、背包、仓库、人物卡池、刷新次数、任务进度、
##            已通关的地牢层级（金币直达用）、**累计游玩时长**、**最后保存时间**。
## 不持久化：局内战斗状态、地牢 run 进行中的临时状态、pending_encounter 等。
##
## 遵循 class_name 脚本不引用 autoload 全局名的模式。
class_name SaveManager
extends RefCounted


## 栏位数（需求：点击后有 10 个栏位）
const SLOT_COUNT := 10

## 当前存档格式版本。v1 = 单文件单存档（无栏位、无游玩时长）；v2 = 多栏位 + 元信息
const SAVE_VERSION := 2

## 栏位文件名的前缀。测试可以改成别的值来**完全隔离**，
## 避免自动化测试把玩家真实存档覆盖掉（以前只用默认路径，跑一次测试就擦掉玩家进度）。
const DEFAULT_PREFIX := "user://save_"
const LEGACY_PATH := "user://save.json"

## 全局默认前缀。自动化测试开头把它改成 `user://_test_save_`，
## 之后**任何地方** new 出来的 SaveManager（包括主菜单面板里那个）都走隔离存储 ——
## 否则 UI 测试会去读/写玩家真实栏位，断言也就跟着玩家进度飘。
static var active_prefix: String = DEFAULT_PREFIX


## 实例前缀。构造时若未显式指定就跟随 `active_prefix`。
var path_prefix: String = ""

## 旧版单文件存档路径。同样是**可覆盖**的：测试要能在隔离空间里演练迁移逻辑，
## 否则"迁移"这段代码永远测不到（只在真实默认路径下才允许动手）。
var legacy_path: String = LEGACY_PATH


func _init() -> void:
	if path_prefix == "":
		path_prefix = active_prefix


var _gdata: Node = null


## 栏位 → 存档文件路径
func slot_path(slot: int) -> String:
	return "%s%02d.json" % [path_prefix, slot]


func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


func _g() -> Node:
	if _gdata == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			_gdata = tree.root.get_node_or_null("/root/GameData")
	return _gdata


func _db() -> GameDatabase:
	return _g().db as GameDatabase


# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------

## 存档到指定栏位。返回是否成功。
##
## `created_at` 保留该栏位**第一次**写入的时间（覆盖存档时不刷新），
## 这样"这个档是什么时候开的"和"最后什么时候存的"能分开看。
func save(slot: int = 0) -> bool:
	if not is_valid_slot(slot):
		push_error("存档失败：栏位号越界 %d（应在 0–%d）" % [slot, SLOT_COUNT - 1])
		return false

	var g := _g()
	var now := int(Time.get_unix_time_from_system())
	var data := {
		"version": SAVE_VERSION,
		"slot": slot,
		"created_at": _created_at_of(slot, now),
		"saved_at": now,
		# 累计游玩时长（秒）。读档时恢复，存回去时带上 —— 这样"玩多久了"是跟着档走的
		"playtime": int(round(float(g.playtime_seconds))),
		"gold": g.gold,
		"team": _serialize_team(g.team),
		"roster": _serialize_team(g.roster),
		"deck": _serialize_cards(g.deck),
		"owned_cards": _serialize_cards(g.owned_cards),
		"inventory": _serialize_items(g.inventory),
		"storage": _serialize_items(g.storage),
		"refresh_store": g.refresh_store,
		"refresh_recruit": g.refresh_recruit,
		"refresh_quest": g.refresh_quest,
		"quests": _serialize_quests(g.quests),
		# 9-24 修改意见 3：已通关过的地牢层级（决定哪些层可以金币直达）
		"cleared_levels": g.cleared_levels.duplicate(),
	}

	var path := slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("存档失败：无法打开 %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[存档] 已保存到栏位 %d（%s）：金币 %d，游玩 %s"
		% [slot + 1, path, g.gold, format_playtime(int(data["playtime"]))])
	return true


## 该栏位是否已有存档
func has_save(slot: int = 0) -> bool:
	if not is_valid_slot(slot):
		return false
	return FileAccess.file_exists(slot_path(slot))


## 删除指定栏位的存档
func erase(slot: int = 0) -> void:
	if not is_valid_slot(slot):
		return
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 覆盖存档时沿用原来的创建时间；新栏位才记当前时间
func _created_at_of(slot: int, fallback: int) -> int:
	var info := slot_info(slot)
	if bool(info["empty"]):
		return fallback
	var created := int(info.get("created_at", 0))
	return created if created > 0 else fallback


# ---------------------------------------------------------------------------
# 栏位概览（给"存档 / 读档"面板用）
# ---------------------------------------------------------------------------

## 读一个栏位的**摘要**。
##
## 🔴 这里刻意**只解析 JSON 顶层字段**，不做 `_deserialize_*`：
## 面板一次要列 10 个栏位，若每个都去查 db、new 出一堆 Adventurer/ItemData，
## 光是打开面板就要构造上千个对象 —— 列表只需要几个数字。
func slot_info(slot: int) -> Dictionary:
	var info := {
		"slot": slot, "empty": true, "gold": 0, "playtime": 0,
		"created_at": 0, "saved_at": 0, "legacy": false,
		"team_size": 0, "team_level": 0, "deck_size": 0, "cleared_max": 0,
	}
	if not is_valid_slot(slot):
		return info
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return info
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return info
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return info

	var d: Dictionary = parsed
	info["empty"] = false
	info["gold"] = int(d.get("gold", 0))
	info["playtime"] = int(d.get("playtime", 0))
	info["created_at"] = int(d.get("created_at", 0))
	info["saved_at"] = int(d.get("saved_at", 0))
	# v1 时代（单文件存档）没有游玩时长/保存时间这两个字段。
	# 直接按 0 显示会变成"游玩 0 分钟"，那是假的 —— 面板要能区分"真的是 0"和"没记录"。
	info["legacy"] = not (d.has("playtime") or d.has("saved_at"))

	var team: Array = d.get("team", [])
	info["team_size"] = team.size()
	var top_level := 0
	for entry in team:
		if entry is Dictionary:
			top_level = maxi(top_level, int((entry as Dictionary).get("level", 1)))
	info["team_level"] = top_level
	info["deck_size"] = (d.get("deck", []) as Array).size()
	var deepest := 0
	for lv in d.get("cleared_levels", []):
		deepest = maxi(deepest, int(lv))
	info["cleared_max"] = deepest
	return info


## 全部栏位的摘要，按栏位号升序
func list_slots() -> Array:
	var out: Array = []
	for i in range(SLOT_COUNT):
		out.append(slot_info(i))
	return out


## 是否任何一个栏位有存档（读档面板用于判断"全空"）
func has_any_save() -> bool:
	for i in range(SLOT_COUNT):
		if has_save(i):
			return true
	return false


# ---------------------------------------------------------------------------
# 显示格式化
# ---------------------------------------------------------------------------

## 时长 → 「2 小时 13 分」。需求：附在每个档下面说明这个档的游玩时间。
static func format_playtime(seconds: int) -> String:
	if seconds <= 0:
		return "0 分钟"
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	if h > 0:
		return "%d 小时 %d 分" % [h, m]
	if m > 0:
		return "%d 分钟" % m
	return "不足 1 分钟"


## unix 秒 → 「09-28 19:20」（**本地时间**）
##
## `Time.get_datetime_dict_from_unix_time()` 给的是 UTC，
## 直接用会显示成 8 小时前 —— 必须自己加时区偏移。
static func format_saved_at(unix: int) -> String:
	if unix <= 0:
		return "—"
	var bias := 0
	var tz := Time.get_time_zone_from_system()
	if tz.has("bias"):
		bias = int(tz["bias"])
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d-%02d %02d:%02d" % [int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"])]


# ---------------------------------------------------------------------------
# 旧存档迁移（单文件 → 栏位 1）
# ---------------------------------------------------------------------------

## v1 时代只有 `user://save.json` 一个文件。第一次跑新版本时把它搬到栏位 1，
## 免得玩家的进度"看起来丢了"。
##
## 只在目标栏位为空时才搬（不去猜、不覆盖已有栏位）。
## 迁移用「读出→写入→删原文件」而不是 rename：`DirAccess.rename_absolute`
## 对 `user://` 虚拟路径的行为在各平台上不完全一致，这样写最稳。
##
## 🔴 安全闸：`path_prefix` 与 `legacy_path` 必须**同为真实**或**同为沙箱**。
## 混搭（例：真实旧存档路径 + 测试栏位前缀）直接拒绝 —— 那种组合会
## 把玩家真实的 save.json 搬进测试栏位、并删掉原文件。
func migrate_legacy_save() -> bool:
	var real_pair: bool = path_prefix == DEFAULT_PREFIX and legacy_path == LEGACY_PATH
	var sandbox_pair: bool = path_prefix != DEFAULT_PREFIX and legacy_path != LEGACY_PATH
	if not (real_pair or sandbox_pair):
		return false
	if not FileAccess.file_exists(legacy_path):
		return false
	if has_save(0):
		return false

	var text := FileAccess.get_file_as_string(legacy_path)
	if text == "":
		return false
	var file := FileAccess.open(slot_path(0), FileAccess.WRITE)
	if file == null:
		push_warning("[存档] 旧存档迁移失败：无法写入 %s" % slot_path(0))
		return false
	file.store_string(text)
	file.close()
	DirAccess.remove_absolute(legacy_path)
	print("[存档] 旧存档 save.json 已迁移到栏位 1")
	return true


# ---------------------------------------------------------------------------
# 读档
# ---------------------------------------------------------------------------

## 读指定栏位。返回是否成功。
func load(slot: int = 0) -> bool:
	if not is_valid_slot(slot) or not has_save(slot):
		return false
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("读档失败：存档格式错误（栏位 %d）" % (slot + 1))
		return false
	var data: Dictionary = parsed

	var g := _g()
	# 游玩时长跟着档走：读档后从该档记录的秒数继续累加
	g.playtime_seconds = float(int(data.get("playtime", 0)))
	g.gold = int(data.get("gold", 200))
	g.team = _deserialize_team(data.get("team", []))
	g.roster = _deserialize_team(data.get("roster", []))
	g.deck = _deserialize_cards(data.get("deck", []))
	# 旧存档没有持有卡池字段 → 用卡组内容兜底，保证可编入数不为 0
	var owned_raw: Array = data.get("owned_cards", [])
	if owned_raw.is_empty():
		g.owned_cards = _deserialize_cards(data.get("deck", []))
	else:
		g.owned_cards = _deserialize_cards(owned_raw)
	g.inventory = _deserialize_items(data.get("inventory", []))
	g.storage = _deserialize_items(data.get("storage", []))
	g.refresh_store = int(data.get("refresh_store", 1))
	g.refresh_recruit = int(data.get("refresh_recruit", 1))
	g.refresh_quest = int(data.get("refresh_quest", 1))
	g.quests = _deserialize_quests(data.get("quests", {}))
	# 旧存档没有通关层记录 → 空数组；玩家重新打一遍即可解锁（不猜测进度）
	g.cleared_levels.clear()
	for lv in data.get("cleared_levels", []):
		g.mark_level_cleared(int(lv))

	print("[存档] 已读取栏位 %d：金币 %d，小队 %d 人，卡组 %d 张，游玩 %s"
		% [slot + 1, g.gold, g.team.size(), g.deck.size(),
		   format_playtime(int(g.playtime_seconds))])
	return true


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------

func _serialize_team(members: Array) -> Array:
	var out: Array = []
	for a in members:
		out.append(_serialize_adventurer(a))
	return out


func _serialize_adventurer(a: Adventurer) -> Dictionary:
	var equip: Dictionary = {}
	for slot in a.equipment:
		var it: ItemData = a.equipment[slot]
		equip[str(int(slot))] = it.id
	return {
		"id": a.id,
		"display_name": a.display_name,
		"constitution": a.constitution,
		"strength": a.strength,
		"intelligence": a.intelligence,
		"vitality": a.vitality,
		"level": a.level,
		"exp": a.exp,
		"unspent_points": a.unspent_points,
		"base_luck": a.base_luck,
		"equipment": equip,
	}


func _serialize_cards(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.id)
	return out


func _serialize_items(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(it.id)
	return out


func _serialize_quests(quests: QuestManager) -> Dictionary:
	if quests == null:
		return {"available": [], "active": []}
	var out := {"available": [], "active": []}
	for q in quests.available:
		out["available"].append(_serialize_quest(q))
	for q in quests.active:
		out["active"].append(_serialize_quest(q))
	return out


func _serialize_quest(q: QuestManager.Quest) -> Dictionary:
	return {
		"id": q.id, "title": q.title, "description": q.description,
		"monster_id": q.monster_id, "target_count": q.target_count,
		"progress": q.progress, "recommend_power": q.recommend_power,
		"reward_gold": q.reward_gold, "reward_item_id": q.reward_item_id,
		"reward_item_count": q.reward_item_count,
		"accepted": q.accepted, "completed": q.completed,
	}


# ---------------------------------------------------------------------------
# 反序列化
# ---------------------------------------------------------------------------

func _deserialize_team(arr: Array) -> Array[Adventurer]:
	var out: Array[Adventurer] = []
	for entry in arr:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var a := Adventurer.new()
		a.id = str(d.get("id", ""))
		a.display_name = str(d.get("display_name", "冒险者"))
		a.constitution = int(d.get("constitution", 5))
		a.strength = int(d.get("strength", 5))
		a.intelligence = int(d.get("intelligence", 5))
		a.vitality = int(d.get("vitality", 5))
		a.level = int(d.get("level", 1))
		a.exp = int(d.get("exp", 0))
		a.unspent_points = int(d.get("unspent_points", 0))
		a.base_luck = int(d.get("base_luck", 3))
		var equip: Dictionary = d.get("equipment", {})
		for slot_key in equip.keys():
			var item := _db().get_item(str(equip[slot_key]))
			if item != null:
				a.equipment[_migrate_slot(int(slot_key))] = item
		out.append(a)
	return out


## 旧存档槽位迁移（9-22 修改意见 5：武器三个槽位合并为一个）
## 旧枚举：… 6=单手 7=双手 8=远程 9=非装备；新枚举：6=武器 7=非装备
func _migrate_slot(slot: int) -> int:
	if slot == 6 or slot == 7 or slot == 8:
		return ItemData.Slot.WEAPON
	if slot >= 9:
		return ItemData.Slot.NONE
	return slot


func _deserialize_cards(arr: Array) -> Array[CardData]:
	var out: Array[CardData] = []
	for id in arr:
		var card := _db().get_card(str(id))
		if card != null:
			out.append(card)
	return out


func _deserialize_items(arr: Array) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for id in arr:
		var item := _db().get_item(str(id))
		if item != null:
			out.append(item)
	return out


## 反序列化任务管理器。
##
## 🔴 两边都空时返回 **null**，而不是一个空的 QuestManager。
## 原因：存档时 `GameData.quests` 可能还是 null（没进过城镇），写出来就是两个空数组。
## 读回来若造一个"非空但空"的管理器，城镇 `_ready` 里的 `if gd.quests == null` 就不成立，
## **任务木板会永远空着**（实测踩到过）。返回 null 就等于回到"还没初始化"的状态，
## 城镇会照常 roll 一批任务。
func _deserialize_quests(data: Dictionary) -> QuestManager:
	var avail: Array = data.get("available", [])
	var act: Array = data.get("active", [])
	if avail.is_empty() and act.is_empty():
		return null
	var qm := QuestManager.new()
	for entry in avail:
		var q := _deserialize_quest(entry)
		if q != null:
			qm.available.append(q)
	for entry in act:
		var q := _deserialize_quest(entry)
		if q != null:
			qm.active.append(q)
	return qm


func _deserialize_quest(entry: Variant) -> QuestManager.Quest:
	if not (entry is Dictionary):
		return null
	var d: Dictionary = entry
	var q := QuestManager.Quest.new()
	q.id = str(d.get("id", ""))
	q.title = str(d.get("title", ""))
	q.description = str(d.get("description", ""))
	q.monster_id = str(d.get("monster_id", ""))
	q.target_count = int(d.get("target_count", 1))
	q.progress = int(d.get("progress", 0))
	q.recommend_power = int(d.get("recommend_power", 0))
	q.reward_gold = int(d.get("reward_gold", 0))
	q.reward_item_id = str(d.get("reward_item_id", ""))
	q.reward_item_count = int(d.get("reward_item_count", 1))
	q.accepted = bool(d.get("accepted", false))
	q.completed = bool(d.get("completed", false))
	return q
