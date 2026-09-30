## 全局音频管理器（autoload）
##
## 覆盖 9-25 需求：
##   ① 攻击 / 受击 / 防御 / 法术 音效
##   ② 开屏（以及城镇、主菜单）BGM
##   ③ 按钮点击音
##
## 设计要点
##   * 素材全部由 tools/generate_audio.py 程序化合成 → assets/audio/*.wav
##     （项目当前所有美术都是程序绘制占位图，音频走同一路线：可确定性重跑、不依赖外部素材）
##   * 总线在运行时创建（Master → Music / SFX），不需要额外的 default_bus_layout.tres
##   * 音效用固定大小的播放器池轮转，避免同一帧多段音效互相打断
##   * BGM 双播放器交叉淡入淡出；WAV 在运行时打上 LOOP_FORWARD 标记（素材无 smpl 块）
##   * 按钮点击音用 get_tree().node_added 自动挂接 —— 任何**新加入场景树**的 BaseButton
##     都会被自动接上，不需要逐场景写接线代码（UI 大多是代码里 new 出来的）
##   * 音量 / 静音写 user://audio_settings.cfg，与存档解耦（没存档也该记得设置）
##
## 注意：本脚本是 autoload，**不要**加 class_name（会与 autoload 名冲突）。
##       场景脚本可以直接写 AudioManager.xxx；--script 测试里要用
##       root.get_node_or_null("/root/AudioManager") 取。
extends Node


const AUDIO_DIR := "res://assets/audio/"
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const SETTINGS_PATH := "user://audio_settings.cfg"

## 音效播放器池大小（同时发声的上限；超了就轮转抢用最久没播的那个）
const SFX_POOL_SIZE := 14
## 最近播放记录长度（给测试与调试面板看）
const PLAYED_LOG_MAX := 64
## BGM 相对音效的整体衰减（dB）：音乐是背景，不能盖住打击感
const BGM_HEADROOM_DB := -4.0

## 音效 id → 文件名。id 就是代码里唯一的引用方式，改素材只改这张表。
const SFX_FILES := {
	"ui_click": "sfx_ui_click.wav",
	"ui_confirm": "sfx_ui_confirm.wav",
	"ui_deny": "sfx_ui_deny.wav",
	"attack_phys": "sfx_atk_slash.wav",
	"attack_magic": "sfx_atk_cast.wav",
	"hit_phys": "sfx_hit_phys.wav",
	"hit_magic": "sfx_hit_magic.wav",
	"crit": "sfx_crit.wav",
	"shield": "sfx_shield.wav",
	"heal": "sfx_heal.wav",
	"mana": "sfx_mana.wav",
	"combo": "sfx_combo.wav",
	"victory": "sfx_victory.wav",
	"defeat": "sfx_defeat.wav",
	"card_draw": "sfx_card_draw.wav",
	"card_play": "sfx_card_play.wav",
	"map_step": "sfx_map_step.wav",
	"reward": "sfx_reward.wav",
}

const BGM_FILES := {
	"title": "bgm_title.wav",
	"battle": "bgm_battle.wav",
	"town": "bgm_town.wav",
	"dungeon": "bgm_dungeon.wav",
}

## 战斗表现层事件 kind → 起手音效 id
const FEEDBACK_SFX := {
	"shield": "shield",
	"heal": "heal",
	"mana": "mana",
	"combo": "combo",
}

# ---------------------------------------------------------------------------

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0

var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_slot := 0
var _bgm_current := ""
var _bgm_tween: Tween = null

## 当前音量（线性 0–1），供 UI 与存档读写
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 1.0
var muted := false

## 按钮点击音总开关（个别场景可临时关掉）
var button_sfx_enabled := true

## 最近播放的音效 id（测试与调试用；只保留最后 PLAYED_LOG_MAX 条）
var played_log: Array[String] = []
## 播放失败次数（素材缺失等），方便一次性断言
var play_failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时音效照常（BGM 也不断）
	_ensure_buses()
	_build_sfx_pool()
	_build_bgm_players()
	_load_settings()
	_apply_volumes()

	# 自动给所有按钮挂点击音。
	# autoload 的 _ready 早于主场景实例化，所以只要监听 node_added 就够了；
	# 主场景里已有的按钮会在节点入树时逐条触发。
	var tree := get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


# ---------------------------------------------------------------------------
# 总线
# ---------------------------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_MASTER)


func has_bus(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) != -1


func _apply_volumes() -> void:
	_set_bus_volume(BUS_MASTER, master_volume)
	_set_bus_volume(BUS_MUSIC, music_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), muted)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if linear <= 0.0001:
		AudioServer.set_bus_volume_db(idx, -80.0)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


# ---------------------------------------------------------------------------
# 播放器池
# ---------------------------------------------------------------------------

func _build_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_sfx_players.append(p)


func _build_bgm_players() -> void:
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.name = "Bgm%d" % i
		p.bus = BUS_MUSIC
		p.volume_db = -80.0
		add_child(p)
		_bgm_players.append(p)


## 取一个空闲播放器；全忙就按游标轮转抢用（宁可打断最老的，也不要丢音）
func _take_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		return null
	for i in range(_sfx_players.size()):
		var idx := (_sfx_cursor + i) % _sfx_players.size()
		if not _sfx_players[idx].playing:
			_sfx_cursor = (idx + 1) % _sfx_players.size()
			return _sfx_players[idx]
	var p := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return p


# ---------------------------------------------------------------------------
# 素材
# ---------------------------------------------------------------------------

func sfx_path(id: String) -> String:
	if not SFX_FILES.has(id):
		return ""
	return AUDIO_DIR + String(SFX_FILES[id])


func bgm_path(id: String) -> String:
	if not BGM_FILES.has(id):
		return ""
	return AUDIO_DIR + String(BGM_FILES[id])


func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		if not play_failures.has(path):
			play_failures.append(path)
			push_warning("[Audio] 找不到音频素材：%s" % path)
		return null
	var s: AudioStream = load(path)
	if s == null and not play_failures.has(path):
		play_failures.append(path)
		push_warning("[Audio] 音频素材加载失败：%s" % path)
	return s


## 给 WAV 打上循环标记。
##
## 素材的循环标记**已经在 tools/patch_audio_import.py 里写进 .import**，
## 正常情况下这里什么都不用做。留这一段是兜底：素材重生成后如果忘了跑
## 「patch_audio_import + --import」两步，BGM 会变成"放一遍就停"，
## 兜底能让它至少还能循环（只是代价是导入参数没生效）。
func ensure_loop(s: AudioStream) -> AudioStream:
	var w := s as AudioStreamWAV
	if w == null:
		return s
	if w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = wav_frame_count(w, s)
	return w


## WAV 的帧数（帧 = 每声道一个采样点）。
##
## 不能用 `data.size()` 硬算：导入参数一旦是 IMA-ADPCM / QOA，
## data 就是压缩数据，字节数 ≠ 采样数。统一用 `get_length() × 采样率` 反推，
## 这对任何编码格式都成立。
func wav_frame_count(w: AudioStreamWAV, s: AudioStream) -> int:
	if w == null or s == null or w.mix_rate <= 0:
		return 0
	return int(round(s.get_length() * float(w.mix_rate)))


# ---------------------------------------------------------------------------
# 音效
# ---------------------------------------------------------------------------

## 播一个音效。pitch 用来做同素材的变奏（连击时音高递增很有效）
##
## 未知 id 属于**调用方的 bug**，不是素材缺失：直接返回 false，
## 不写进 play_failures（否则拼错一个 id 就会污染"素材缺失"的诊断）。
func play_sfx(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> bool:
	if not SFX_FILES.has(id):
		push_warning("[Audio] 未登记的音效 id：%s" % id)
		return false
	var s := _load_stream(sfx_path(id))
	if s == null:
		return false
	var p := _take_sfx_player()
	if p == null:
		return false
	p.stream = s
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.volume_db = volume_db
	p.play()
	_note_played(id)
	return true


func _note_played(id: String) -> void:
	played_log.append(id)
	if played_log.size() > PLAYED_LOG_MAX:
		played_log = played_log.slice(played_log.size() - PLAYED_LOG_MAX)


func clear_played_log() -> void:
	played_log.clear()


func played_count(id: String) -> int:
	var n := 0
	for e in played_log:
		if e == id:
			n += 1
	return n


## 一帧里播了几种音效（给"一次攻击应同时有挥击 + 命中"这类断言用）
func sfx_playing_count() -> int:
	var n := 0
	for p in _sfx_players:
		if p.playing:
			n += 1
	return n


# ---------------------------------------------------------------------------
# BGM
# ---------------------------------------------------------------------------

func current_bgm() -> String:
	return _bgm_current


func is_bgm_playing() -> bool:
	for p in _bgm_players:
		if p.playing:
			return true
	return false


## 切 BGM。同一首正在播 → 直接返回 true（不重启，跨场景连贯）
func play_bgm(id: String, fade: float = 0.8) -> bool:
	if not BGM_FILES.has(id):
		push_warning("[Audio] 未登记的 BGM id：%s" % id)
		return false
	if id == _bgm_current and is_bgm_playing():
		return true
	var s := _load_stream(bgm_path(id))
	if s == null:
		return false
	ensure_loop(s)

	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()

	var from := _bgm_players[_bgm_slot]
	_bgm_slot = 1 - _bgm_slot
	var to := _bgm_players[_bgm_slot]
	to.stream = s
	to.volume_db = -80.0
	to.play()

	_bgm_current = id
	if fade <= 0.0 or not from.playing:
		to.volume_db = BGM_HEADROOM_DB
		from.stop()
		return true

	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	_bgm_tween.tween_property(to, "volume_db", BGM_HEADROOM_DB, fade)
	_bgm_tween.tween_property(from, "volume_db", -80.0, fade)
	_bgm_tween.chain().tween_callback(from.stop)
	return true


func stop_bgm(fade: float = 0.6) -> void:
	_bgm_current = ""
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	for p in _bgm_players:
		if not p.playing:
			p.volume_db = -80.0
			continue
		if fade <= 0.0:
			p.stop()
			p.volume_db = -80.0
		else:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -80.0, fade)
			tw.tween_callback(p.stop)


# ---------------------------------------------------------------------------
# 音量 / 静音
# ---------------------------------------------------------------------------

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_set_bus_volume(BUS_MASTER, master_volume)
	save_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_set_bus_volume(BUS_MUSIC, music_volume)
	save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_set_bus_volume(BUS_SFX, sfx_volume)
	save_settings()


# 与 set_* 成对的读取接口。设置面板用「方法名」配置滑杆（见 main_menu.VOLUME_ROWS），
# 所以读写都统一走方法，不做属性直读，避免两条路径分叉。
func get_master_volume() -> float:
	return master_volume


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


func set_muted(v: bool) -> void:
	muted = v
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), muted)
	save_settings()


func bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 0.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", muted))


# ---------------------------------------------------------------------------
# 按钮点击音自动挂接
# ---------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if not button_sfx_enabled:
		return
	var b := node as BaseButton
	if b != null:
		wire_button(b)


## 给单个按钮挂点击音（幂等；测试里也可以直接调）
func wire_button(b: BaseButton) -> void:
	if b == null or b.has_meta("_audio_wired"):
		return
	b.set_meta("_audio_wired", true)
	b.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play_sfx("ui_click")
