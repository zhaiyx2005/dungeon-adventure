## 音频系统测试（9-25 需求）
##
## 覆盖六层：
##   1. 素材层 —— 全部 wav 可加载、规格正确、BGM 带循环标记、登记表与磁盘一一对应
##   2. 总线层 —— Music / SFX 总线存在，音量与静音真实写进 AudioServer
##   3. 播放层 —— play_sfx 入池发声、未知 id 安全失败、play_bgm 幂等与交叉切换
##   4. 按钮层 —— 任何新入树的 BaseButton 自动挂点击音（含真实场景里的按钮）
##   5. 战斗层 —— 表现层事件 → 音效映射（物理/法术/暴击各自选对素材）
##   6. 场景层 —— 开屏/主菜单/城镇/地牢=标题曲，战斗=战斗曲，结算切换
##   7. 设置层 —— 设置面板滑杆 / 静音 / 持久化
extends SceneTree

const AM_PATH := "res://scripts/core/audio_manager.gd"
const AUDIO_DIR := "res://assets/audio/"
const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TOWN_SCENE := "res://scenes/town/town_scene.tscn"
const RUN_SCENE := "res://scenes/dungeon/run_scene.tscn"
const SPLASH_SCENE := "res://scenes/splash_scene.tscn"

var _pass := 0
var _fail := 0
var _am: Node = null
var _db: GameDatabase = null
var _orig_master := 1.0
var _orig_music := 0.8
var _orig_sfx := 1.0
var _orig_muted := false


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(120.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


## --script 模式下 autoload 的全局标识符在编译期不可解析，只能走节点路径取
func _am_node() -> Node:
	return root.get_node_or_null("/root/AudioManager")


func _consts(path: String) -> Dictionary:
	var s: GDScript = load(path)
	if s == null:
		return {}
	return s.get_script_constant_map()


func _find_by_name(node: Node, nm: String) -> Node:
	if node == null:
		return null
	if node.name == nm:
		return node
	for ch in node.get_children():
		var hit := _find_by_name(ch, nm)
		if hit != null:
			return hit
	return null


func _count_buttons(node: Node, out: Array) -> void:
	if node is BaseButton:
		out.append(node)
	for ch in node.get_children():
		_count_buttons(ch, out)


func _frames(n: int = 2) -> void:
	for i in range(n):
		await process_frame


func _run() -> void:
	_watchdog()
	print("\n===== 音频系统（9-25：攻击/受击/防御/法术音效 + 开屏音乐 + 按钮点击音）=====\n")

	_am = _am_node()
	_ok(_am != null, "AudioManager autoload 已加载")
	if _am == null:
		_finish()
		return

	var gd: Node = root.get_node_or_null("/root/GameData")
	_db = gd.db if gd != null else null

	_orig_master = float(_am.get_master_volume())
	_orig_music = float(_am.get_music_volume())
	_orig_sfx = float(_am.get_sfx_volume())
	_orig_muted = bool(_am.muted)

	var consts := _consts(AM_PATH)
	var sfx_files: Dictionary = consts.get("SFX_FILES", {})
	var bgm_files: Dictionary = consts.get("BGM_FILES", {})

	await _test_assets(sfx_files, bgm_files)
	await _test_buses()
	await _test_playback(sfx_files, bgm_files)
	await _test_button_autowire()
	await _test_battle_mapping()
	await _test_scene_bgm()
	await _test_settings_panel()

	# 复位（别把测试期的音量留在玩家设置里）
	_am.set_master_volume(_orig_master)
	_am.set_music_volume(_orig_music)
	_am.set_sfx_volume(_orig_sfx)
	_am.set_muted(_orig_muted)
	_am.stop_bgm(0.0)

	_finish()


func _finish() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------
# 1. 素材层
# ---------------------------------------------------------------------------

func _test_assets(sfx_files: Dictionary, bgm_files: Dictionary) -> void:
	print("-- 素材 --")
	_ok(sfx_files.size() >= 14, "音效登记表 %d 条（≥14：点击/确认/拒绝/物理攻击/法术攻击/物理受击/法术受击/暴击/护盾/治疗/回蓝/联合卡/胜利/失败）"
		% sfx_files.size())
	_ok(bgm_files.size() == 2, "BGM 登记表 %d 条（开屏标题曲 + 战斗曲）" % bgm_files.size())

	# 需求点名的四类必须有
	for need in ["attack_phys", "attack_magic", "hit_phys", "hit_magic", "shield", "ui_click"]:
		_ok(sfx_files.has(need), "登记表包含 %s" % need)

	# 登记表 ↔ 磁盘一一对应（多一个文件没登记 = 白做了；登记了没文件 = 播放失败）
	var disk: Array = []
	var dir := DirAccess.open(AUDIO_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".wav"):
				disk.append(f)
	disk.sort()
	var registered: Array = []
	for k in sfx_files.keys():
		registered.append(String(sfx_files[k]))
	for k in bgm_files.keys():
		registered.append(String(bgm_files[k]))
	registered.sort()
	_ok(disk == registered, "磁盘 wav 与登记表完全一致（磁盘 %d / 登记 %d）" % [disk.size(), registered.size()])
	if disk != registered:
		for f in disk:
			if not registered.has(f):
				print("      磁盘多出：%s" % f)
		for f in registered:
			if not disk.has(f):
				print("      登记缺文件：%s" % f)

	# 逐个音效：可加载 / 16bit PCM / 44.1k / 时长合理
	var bad_load: Array = []
	var bad_fmt: Array = []
	var bad_len: Array = []
	for id in sfx_files.keys():
		var path: String = AUDIO_DIR + String(sfx_files[id])
		if not ResourceLoader.exists(path):
			bad_load.append(String(id))
			continue
		var s: AudioStream = load(path)
		if s == null:
			bad_load.append(String(id))
			continue
		var w := s as AudioStreamWAV
		if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS or w.mix_rate != 44100:
			bad_fmt.append(String(id))
		var sec := s.get_length()
		if sec < 0.05 or sec > 2.5:
			bad_len.append(String(id) + "(%.2fs)" % sec)
	_ok(bad_load.is_empty(), "全部音效素材可加载（失败：%s）" % str(bad_load))
	_ok(bad_fmt.is_empty(), "全部音效为 16bit PCM / 44100Hz（异常：%s）" % str(bad_fmt))
	_ok(bad_len.is_empty(), "全部音效时长在 0.05–2.5s（异常：%s）" % str(bad_len))

	# BGM：循环标记 + 立体声 + 时长
	for id in bgm_files.keys():
		var path2: String = AUDIO_DIR + String(bgm_files[id])
		var s2: AudioStream = load(path2)
		var w2 := s2 as AudioStreamWAV
		_ok(s2 != null, "BGM %s 可加载" % id)
		if s2 == null:
			continue
		_ok(w2 != null and w2.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"BGM %s 带前向循环标记（.import 的 edit/loop_mode=1 生效）" % id)
		_ok(s2.get_length() >= 8.0, "BGM %s 时长 %.1fs（≥8s）" % [id, s2.get_length()])
		_ok(w2 != null and w2.stereo, "BGM %s 是立体声" % id)
		_ok(w2 != null and w2.format == AudioStreamWAV.FORMAT_16_BITS,
			"BGM %s 未被有损压缩（16bit PCM）" % id)

	# ensure_loop 幂等；帧数换算对得上
	var title: AudioStream = load(AUDIO_DIR + String(bgm_files.get("title", "")))
	var tw := title as AudioStreamWAV
	if tw != null and title != null:
		var before := tw.loop_mode
		_am.ensure_loop(title)
		_ok(tw.loop_mode == before, "ensure_loop 对已带标记的素材是幂等的")
		var frames: int = _am.wav_frame_count(tw, title)
		var expect := int(round(title.get_length() * float(tw.mix_rate)))
		_ok(absi(frames - expect) <= 1, "帧数换算与 get_length 一致（%d vs %d）" % [frames, expect])


# ---------------------------------------------------------------------------
# 2. 总线层
# ---------------------------------------------------------------------------

func _test_buses() -> void:
	print("\n-- 总线与音量 --")
	_ok(_am.has_bus("Music"), "存在 Music 总线")
	_ok(_am.has_bus("SFX"), "存在 SFX 总线")
	_ok(AudioServer.get_bus_index("Music") != AudioServer.get_bus_index("SFX"),
		"Music 与 SFX 是两条独立总线")

	_am.set_music_volume(0.5)
	var mv := float(_am.bus_volume("Music"))
	_ok(absf(mv - 0.5) < 0.02, "写 0.5 后 Music 总线实测 %.3f" % mv)

	_am.set_sfx_volume(0.25)
	var sv := float(_am.bus_volume("SFX"))
	_ok(absf(sv - 0.25) < 0.02, "写 0.25 后 SFX 总线实测 %.3f" % sv)

	_am.set_master_volume(0.0)
	_ok(float(_am.bus_volume("Master")) < 0.001, "主音量 0 时总线近乎静默")
	_am.set_master_volume(1.0)

	_am.set_muted(true)
	_ok(bool(_am.muted), "静音标记已置位")
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master 总线被静音")
	_am.set_muted(false)
	_ok(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "取消静音后 Master 恢复")


# ---------------------------------------------------------------------------
# 3. 播放层
# ---------------------------------------------------------------------------

func _test_playback(sfx_files: Dictionary, bgm_files: Dictionary) -> void:
	print("\n-- 播放 --")
	_am.clear_played_log()

	var ok: bool = _am.play_sfx("ui_click")
	_ok(ok, "play_sfx 返回成功")
	_ok(int(_am.played_count("ui_click")) == 1, "记录到 1 次 ui_click")
	_ok(int(_am.sfx_playing_count()) >= 1, "有音效播放器处于播放状态")

	# 未知 id 必须安全失败且不污染失败列表
	var before_fail: int = _am.play_failures.size()
	var bad: bool = _am.play_sfx("no_such_sfx_id")
	_ok(not bad, "未知音效 id 返回 false")
	_ok(_am.play_failures.size() == before_fail, "未知 id 不会写进 play_failures")

	# 播放池：连续塞 30 个不应崩，池大小固定
	_am.clear_played_log()
	for i in range(30):
		_am.play_sfx("hit_phys")
	_ok(int(_am.played_count("hit_phys")) == 30, "连续播 30 次全部入账")
	_ok(int(_am.sfx_playing_count()) <= 14, "同时发声数不超过池大小（%d）" % int(_am.sfx_playing_count()))

	# pitch 变奏真的写进播放器
	_am.play_sfx("ui_click", 1.5)
	var got_pitch := false
	for ch in _am.get_children():
		var p := ch as AudioStreamPlayer
		if p != null and p.playing and absf(p.pitch_scale - 1.5) < 0.001:
			got_pitch = true
			break
	_ok(got_pitch, "pitch 参数写到 AudioStreamPlayer.pitch_scale")

	# BGM：播放 / 幂等 / 切换 / 停止
	_am.stop_bgm(0.0)
	_am.play_bgm("title", 0.0)
	_ok(String(_am.current_bgm()) == "title", "play_bgm 后 current_bgm == title")
	_ok(bool(_am.is_bgm_playing()), "BGM 处于播放状态")

	var slot_before: int = int(_am._bgm_slot)
	var same: bool = _am.play_bgm("title", 0.0)
	_ok(same and _am._bgm_slot == slot_before, "重复请求同一首 → 不重启（播放器槽未切换）")

	_am.play_bgm("battle", 0.25)
	_ok(String(_am.current_bgm()) == "battle", "切到战斗曲后 current_bgm == battle")
	await create_timer(0.45).timeout
	var playing := 0
	for p in _am._bgm_players:
		if p.playing:
			playing += 1
	_ok(playing == 1, "交叉淡入完成后只剩 1 个 BGM 播放器在响（实际 %d）" % playing)

	_am.stop_bgm(0.0)
	await _frames(2)
	_ok(not bool(_am.is_bgm_playing()), "stop_bgm 后没有 BGM 在播")
	_ok(String(_am.current_bgm()) == "", "stop_bgm 后 current_bgm 清空")


# ---------------------------------------------------------------------------
# 4. 按钮点击音自动挂接
# ---------------------------------------------------------------------------

func _test_button_autowire() -> void:
	print("\n-- 按钮点击音 --")
	_am.button_sfx_enabled = true
	_am.clear_played_log()

	# 代码里 new 出来的按钮也要被接上（UI 大多是代码构建的）
	var btn := Button.new()
	btn.name = "TestButton"
	root.add_child(btn)
	await _frames(1)
	_ok(btn.has_meta("_audio_wired"), "新入树的 Button 自动挂上点击音标记")

	btn.pressed.emit()
	await _frames(1)
	_ok(int(_am.played_count("ui_click")) == 1, "按钮 pressed 触发了一次点击音")

	# 幂等：重复挂接不会重复连接
	var n_before: int = btn.pressed.get_connections().size()
	_am.wire_button(btn)
	_ok(btn.pressed.get_connections().size() == n_before, "wire_button 幂等（连接数不变）")

	# 关掉总开关后不再挂接
	_am.button_sfx_enabled = false
	var btn2 := Button.new()
	root.add_child(btn2)
	await _frames(1)
	_ok(not btn2.has_meta("_audio_wired"), "总开关关闭时新按钮不挂音")
	_am.button_sfx_enabled = true

	btn.queue_free()
	btn2.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# 5. 战斗事件 → 音效映射
# ---------------------------------------------------------------------------

func _test_battle_mapping() -> void:
	print("\n-- 战斗事件 → 音效 --")
	var ps: PackedScene = load(BATTLE_SCENE)
	_ok(ps != null, "battle_scene 可加载")
	if ps == null:
		return
	var scene: Node = ps.instantiate()
	root.add_child(scene)
	await _frames(2)
	await create_timer(0.1).timeout

	# 5a. 场景里的按钮全部被自动挂音（真实 UI，不是造出来的）
	var btns: Array = []
	_count_buttons(scene, btns)
	var wired := 0
	for b in btns:
		if b.has_meta("_audio_wired"):
			wired += 1
	_ok(btns.size() > 0, "战斗场景里有 %d 个按钮" % btns.size())
	_ok(wired == btns.size(), "战斗场景按钮全部挂上点击音（%d/%d）" % [wired, btns.size()])

	# 5b. 表现层事件 → 音效 id
	_am.clear_played_log()
	scene._play_feedback_audio({"kind": "attack_start", "damage_type": "PHYSICAL"})
	_ok(int(_am.played_count("attack_phys")) == 1, "物理起手 → attack_phys")

	_am.clear_played_log()
	scene._play_feedback_audio({"kind": "attack_start", "damage_type": "MAGICAL"})
	_ok(int(_am.played_count("attack_magic")) == 1, "法术起手 → attack_magic")

	_am.clear_played_log()
	scene._play_feedback_audio({"kind": "damage", "damage_type": "PHYSICAL", "amount": 10})
	_ok(int(_am.played_count("hit_phys")) == 1, "物理受击 → hit_phys")
	_ok(int(_am.played_count("crit")) == 0, "非暴击不播 crit")

	_am.clear_played_log()
	scene._play_feedback_audio({"kind": "damage", "damage_type": "MAGICAL", "amount": 10})
	_ok(int(_am.played_count("hit_magic")) == 1, "法术受击 → hit_magic")

	_am.clear_played_log()
	scene._play_feedback_audio({"kind": "damage", "damage_type": "PHYSICAL", "amount": 30, "crit": true})
	_ok(int(_am.played_count("hit_phys")) == 1 and int(_am.played_count("crit")) == 1,
		"暴击 → 受击音 + 额外的暴击重击层")

	for pair in [["shield", "shield"], ["heal", "heal"], ["mana", "mana"], ["combo", "combo"]]:
		_am.clear_played_log()
		scene._play_feedback_audio({"kind": String(pair[0])})
		_ok(int(_am.played_count(String(pair[1]))) == 1, "事件 %s → %s" % [pair[0], pair[1]])

	# 5c. battle_manager 的 payload 真的带 damage_type
	_am.clear_played_log()
	var bm: BattleManager = scene.battle
	if bm != null and _db != null:
		var hero := _make_adventurer("测试者", 12, 12, 12, 8)
		var monsters := _monsters_of(["boar"])
		var bm2 := BattleManager.new()
		bm2.setup([hero], monsters, _deck_of([["strike", 4], ["fireball", 4]]))
		bm2.start()
		hero.current_action = 9
		hero.current_mana = maxi(hero.get_max_mana(), 60)
		var ev: Array = []
		bm2.combat_feedback.connect(func(p: Dictionary) -> void: ev.append(p))

		var phys: CardData = _db.get_card("strike")
		bm2.play_card(hero, phys, bm2.living_monsters()[0])
		_ok(_has_dtype(ev, "attack_start", "PHYSICAL"), "物理卡 attack_start 带 damage_type=PHYSICAL")
		_ok(_has_dtype(ev, "damage", "PHYSICAL"), "物理卡 damage 带 damage_type=PHYSICAL")

		ev.clear()
		var mag: CardData = _db.get_card("fireball")
		bm2.play_card(hero, mag, bm2.living_monsters()[0])
		_ok(_has_dtype(ev, "attack_start", "MAGICAL"), "法术卡 attack_start 带 damage_type=MAGICAL")
		_ok(_has_dtype(ev, "damage", "MAGICAL"), "法术卡 damage 带 damage_type=MAGICAL")

		# 怪物攻击恒为物理
		ev.clear()
		bm2.end_player_turn()
		await create_timer(0.05).timeout
		var monster_phys := true
		for p in ev:
			if String(p.get("kind", "")) == "damage" and String(p.get("damage_type", "")) != "PHYSICAL":
				monster_phys = false
		_ok(monster_phys, "怪物攻击的 damage 一律 PHYSICAL")
	else:
		_ok(false, "取到 BattleManager 与数据库")

	# 5d. 结算：停战斗曲 + 胜负音
	_ok(String(_am.current_bgm()) == "battle", "战斗场景 _ready 后切到战斗曲")
	# 防止结算回调去碰地牢 run（这里只想验证音频分支）
	var gd_node: Node = root.get_node_or_null("/root/GameData")
	if gd_node != null:
		gd_node.run = null
	_am.clear_played_log()
	scene._on_battle_finished(BattleManager.Result.VICTORY)
	await _frames(2)
	_ok(int(_am.played_count("victory")) == 1, "胜利结算播 victory")
	_ok(String(_am.current_bgm()) == "", "结算后战斗曲已停")

	_am.clear_played_log()
	scene._on_battle_finished(BattleManager.Result.DEFEAT)
	await _frames(2)
	_ok(int(_am.played_count("defeat")) == 1, "失败结算播 defeat")

	scene.queue_free()
	await _frames(2)
	_am.stop_bgm(0.0)
	await _frames(1)


func _has_dtype(events: Array, kind: String, dtype: String) -> bool:
	for p in events:
		if String(p.get("kind", "")) == kind and String(p.get("damage_type", "")) == dtype:
			return true
	return false


# ---------------------------------------------------------------------------
# 6. 各场景 BGM
# ---------------------------------------------------------------------------

func _test_scene_bgm() -> void:
	print("\n-- 场景 BGM --")

	var cases := [
		[SPLASH_SCENE, "title", "开屏页"],
		[MENU_SCENE, "title", "主菜单"],
		[TOWN_SCENE, "title", "城镇"],
		[RUN_SCENE, "title", "地牢准备/地图"],
	]
	for c in cases:
		var ps: PackedScene = load(String(c[0]))
		if ps == null:
			_ok(false, "%s 场景可加载" % c[2])
			continue
		_am.stop_bgm(0.0)
		await _frames(1)
		var sc: Node = ps.instantiate()
		root.add_child(sc)
		await _frames(2)
		await create_timer(0.08).timeout
		_ok(String(_am.current_bgm()) == String(c[1]),
			"%s 进入后播放「%s」（实际「%s」）" % [c[2], c[1], _am.current_bgm()])
		sc.queue_free()
		await _frames(2)

	# 开屏 → 主菜单不重启（同一首曲子的连贯性）
	_am.stop_bgm(0.0)
	var sp: PackedScene = load(SPLASH_SCENE)
	var splash: Node = sp.instantiate()
	root.add_child(splash)
	await _frames(2)
	var slot_at_splash: int = int(_am._bgm_slot)
	var mp: PackedScene = load(MENU_SCENE)
	var menu: Node = mp.instantiate()
	root.add_child(menu)
	await _frames(2)
	_ok(String(_am.current_bgm()) == "title" and _am._bgm_slot == slot_at_splash,
		"开屏 → 主菜单 同一首曲子不重头播放（跨场景连贯）")
	menu.queue_free()
	splash.queue_free()
	await _frames(2)
	_am.stop_bgm(0.0)
	await _frames(1)


# ---------------------------------------------------------------------------
# 7. 设置面板
# ---------------------------------------------------------------------------

func _test_settings_panel() -> void:
	print("\n-- 游戏设置面板 --")
	var ps: PackedScene = load(MENU_SCENE)
	if ps == null:
		_ok(false, "主菜单可加载")
		return
	var menu: Node = ps.instantiate()
	root.add_child(menu)
	await _frames(2)

	# 菜单项不再是「尚未实现」
	var settings_btn := _find_button_by_text(menu, "游戏设置")
	_ok(settings_btn != null, "主菜单有「游戏设置」按钮")
	if settings_btn != null:
		_ok(not settings_btn.disabled, "「游戏设置」已启用（不再是占位）")

	_ok(not bool(menu.is_settings_open()), "初始时设置面板未打开")
	# 先把音量设成一个不等于默认值的数，才能验证"滑杆初值来自 AudioManager"
	_am.set_music_volume(0.6)
	menu.open_audio_settings()
	await _frames(1)
	_ok(bool(menu.is_settings_open()), "open_audio_settings 后面板打开")

	var layer: Node = _find_by_name(menu, "SettingsLayer")
	_ok(layer != null, "设置层存在")
	var dim := _find_by_name(menu, "Dim") as ColorRect
	_ok(dim != null and dim.mouse_filter == Control.MOUSE_FILTER_STOP,
		"半透明遮罩拦住背后菜单的点击")

	var slider := _find_by_name(menu, "Slider_音乐") as HSlider
	_ok(slider != null, "存在「音乐」滑杆")
	if slider != null:
		_ok(absf(slider.value - 0.6) < 0.001, "滑杆初值取自 AudioManager（%.2f）" % slider.value)
		slider.value = 0.35
		await _frames(1)
		_ok(absf(float(_am.get_music_volume()) - 0.35) < 0.001,
			"拖动滑杆写回 AudioManager（%.2f）" % float(_am.get_music_volume()))
		var pct := _find_by_name(menu, "Pct_音乐") as Label
		_ok(pct != null and pct.text == "35%", "百分比文字同步（%s）" % (pct.text if pct != null else "无"))

	for nm in ["Slider_主音量", "Slider_音效"]:
		_ok(_find_by_name(menu, nm) != null, "存在滑杆 %s" % nm)

	# 静音勾选框
	var mute := _find_by_name(menu, "MuteCheck") as CheckBox
	_ok(mute != null, "存在静音勾选框")
	if mute != null:
		mute.button_pressed = true
		await _frames(1)
		_ok(bool(_am.muted), "勾选静音 → AudioManager.muted = true")
		mute.button_pressed = false
		await _frames(1)
		_ok(not bool(_am.muted), "取消勾选 → 恢复有声")

	# 持久化：配置写进 user://audio_settings.cfg
	_am.set_sfx_volume(0.45)
	_am.save_settings()
	var cfg := ConfigFile.new()
	var err := cfg.load("user://audio_settings.cfg")
	_ok(err == OK, "音量配置写入 user://audio_settings.cfg")
	if err == OK:
		_ok(absf(float(cfg.get_value("audio", "sfx", -1.0)) - 0.45) < 0.001,
			"存档里的音效音量 = 0.45（实际 %s）" % str(cfg.get_value("audio", "sfx", -1.0)))

	# 关闭
	var close := _find_by_name(menu, "CloseButton") as Button
	_ok(close != null, "存在「返回」按钮")
	if close != null:
		close.pressed.emit()
		await _frames(2)
	_ok(not bool(menu.is_settings_open()), "点返回后面板关闭")

	menu.queue_free()
	await _frames(2)


func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button:
		var b := node as Button
		if b.text == text:
			return b
	for ch in node.get_children():
		var hit := _find_button_by_text(ch, text)
		if hit != null:
			return hit
	return null


# ---------------------------------------------------------------------------
# 构造帮手
# ---------------------------------------------------------------------------

func _make_adventurer(nm: String, t: int, s: int, i: int, v: int) -> Adventurer:
	var a := Adventurer.new()
	a.id = nm
	a.display_name = nm
	a.constitution = t
	a.strength = s
	a.intelligence = i
	a.vitality = v
	a.base_luck = 3
	return a


func _monsters_of(ids: Array) -> Array[MonsterData]:
	var out: Array[MonsterData] = []
	for id in ids:
		var m: MonsterData = _db.get_monster(id)
		if m != null:
			out.append(m)
	return out


func _deck_of(pairs: Array) -> Array[CardData]:
	var out: Array[CardData] = []
	for p in pairs:
		var c: CardData = _db.get_card(String(p[0]))
		if c == null:
			continue
		for i in range(int(p[1])):
			out.append(c)
	return out
