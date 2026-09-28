## 开屏页（游戏启动首屏）
## - 开屏图片按时间顺序（上午 → 中午 → 下午 → 傍晚）每 5 秒切换一次，循环播放
## - 游戏名「地牢冒险记」在画面中间偏上逐渐显现（不遮挡主画面）
## - 画面下方出现「任意点击开始游戏」，缓慢呼吸闪烁
## - 鼠标左键点击进入游戏主菜单
extends Control

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SWITCH_INTERVAL := 5.0      ## 开屏图切换间隔（秒）
const CROSSFADE_TIME := 0.6       ## 图片切换淡入时长（秒）
const TITLE_DELAY := 0.3          ## 游戏名开始渐显前的停顿（秒）
const TITLE_FADE_TIME := 2.0      ## 游戏名渐显时长（秒）
const HINT_DELAY := 1.5           ## 点击提示出现延迟（秒）
const CLICK_GUARD := 0.4          ## 防误触：开屏最初一小段时间忽略点击（秒）

const SPLASH_PATHS: Array[String] = [
	"res://assets/images/splash/splash_morning.png",
	"res://assets/images/splash/splash_noon.png",
	"res://assets/images/splash/splash_afternoon.png",
	"res://assets/images/splash/splash_evening.png",
]

var _textures: Array[Texture2D] = []
var _index := 0
var _front: TextureRect
var _back: TextureRect
var _elapsed := 0.0
var _switch_clock := 0.0
var _leaving := false

@onready var _title: Label = %GameTitle
@onready var _hint: Label = %ClickHint


func _ready() -> void:
	# 开屏音乐（9-25 需求）。play_bgm 对"同一首正在播"是幂等的，
	# 所以从开屏 → 主菜单 → 城镇一路都是同一首，不会从头重放。
	AudioManager.play_bgm("title")
	for path in SPLASH_PATHS:
		var tex: Texture2D = load(path)
		if tex != null:
			_textures.append(tex)
	_front = %ImageFront
	_back = %ImageBack
	if not _textures.is_empty():
		_front.texture = _textures[0]
	_front.modulate.a = 1.0
	_back.modulate.a = 0.0
	_title.modulate.a = 0.0
	_hint.modulate.a = 0.0
	_play_title_fade()
	_play_hint_intro()


func _process(delta: float) -> void:
	_elapsed += delta
	_switch_clock += delta
	if _switch_clock >= SWITCH_INTERVAL:
		_switch_clock -= SWITCH_INTERVAL
		_crossfade_to_next()


## 开屏图按时间顺序轮换：淡入新图覆盖在当前图上，完成后交换两层
func _crossfade_to_next() -> void:
	if _textures.is_empty():
		return
	_index = (_index + 1) % _textures.size()
	_back.texture = _textures[_index]
	var tw := create_tween()
	tw.tween_property(_back, "modulate:a", 1.0, CROSSFADE_TIME)
	tw.tween_callback(_swap_layers)


func _swap_layers() -> void:
	_front.texture = _back.texture
	_front.modulate.a = 1.0
	_back.modulate.a = 0.0


## 游戏名在最上方逐渐显现
func _play_title_fade() -> void:
	var tw := create_tween()
	tw.tween_interval(TITLE_DELAY)
	tw.tween_property(_title, "modulate:a", 1.0, TITLE_FADE_TIME)


## 点击提示先淡入，之后循环呼吸闪烁
func _play_hint_intro() -> void:
	var tw := create_tween()
	tw.tween_interval(HINT_DELAY)
	tw.tween_property(_hint, "modulate:a", 1.0, 0.8)
	tw.tween_callback(_play_hint_pulse)


func _play_hint_pulse() -> void:
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_hint, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_hint, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _input(event: InputEvent) -> void:
	if _leaving or _elapsed < CLICK_GUARD:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_start_game()


func _start_game() -> void:
	_leaving = true
	# 进场确认音（点击音由 AudioManager 自动挂在按钮上，开屏是整屏点击，所以手动补一个）
	AudioManager.play_sfx("ui_confirm")
	get_tree().change_scene_to_file(MENU_SCENE)
