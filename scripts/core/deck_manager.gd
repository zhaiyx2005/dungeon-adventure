## 战斗卡组管理
##
## 负责抽牌堆 / 手牌 / 弃牌堆的运作。
## 规则（docs/设计草案 v0.3 §4.1.1）：
##   - 进入新战斗节点：一次性抽 8 张，手牌清空重抽
##   - 之后每个回合开始：基础抽 2 张，手牌保留
##   - 手牌上限 12 张，超出则【禁止抽牌】（抽牌效果直接失效）
##   - 牌库抽空：弃牌堆立即洗回抽牌堆
##   - 回合间手牌保留
class_name DeckManager
extends RefCounted


const HAND_LIMIT := 12
const FIRST_DRAW := 8      ## 进入节点时的首抽
const TURN_DRAW := 2       ## 每回合基础抽牌


var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var _rng := RandomNumberGenerator.new()


func _init(deck: Array[CardData] = []) -> void:
	_rng.randomize()
	draw_pile = deck.duplicate()
	shuffle_draw_pile()


# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func shuffle_draw_pile() -> void:
	# Fisher-Yates，用自带 RNG 保证可复现
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp


## 设置卡组（进入地牢前调用）
func set_deck(deck: Array[CardData]) -> void:
	draw_pile = deck.duplicate()
	hand.clear()
	discard_pile.clear()
	shuffle_draw_pile()


## 进入新的战斗节点：手牌清空，重抽 8 张
func on_enter_battle() -> void:
	hand.clear()
	draw_cards(FIRST_DRAW)


## 回合开始：抽 2 张，手牌保留
func on_turn_start() -> int:
	return draw_cards(TURN_DRAW)


# ---------------------------------------------------------------------------
# 抽牌
# ---------------------------------------------------------------------------

## 抽 n 张。返回实际抽到的张数。
## 手牌达到上限后不再抽牌（不销毁牌，直接停手）。
func draw_cards(n: int) -> int:
	var drawn := 0
	for _i in range(n):
		if hand.size() >= HAND_LIMIT:
			break  # 手牌已满，禁止抽牌
		var card := _draw_one()
		if card == null:
			break  # 牌库与弃牌堆都空了
		hand.append(card)
		drawn += 1
	return drawn


## 抽一张，牌库空则洗回弃牌堆
func _draw_one() -> CardData:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return null
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		shuffle_draw_pile()
	var card: CardData = draw_pile.pop_back()
	return card


# ---------------------------------------------------------------------------
# 出牌与弃牌
# ---------------------------------------------------------------------------

## 打出一张手牌
func play_card(card: CardData) -> bool:
	var idx := hand.find(card)
	if idx < 0:
		return false
	hand.remove_at(idx)
	discard_pile.append(card)
	return true


## 手动弃牌（右侧弃牌键）
func discard_card(card: CardData) -> bool:
	var idx := hand.find(card)
	if idx < 0:
		return false
	hand.remove_at(idx)
	discard_pile.append(card)
	return true


## 弃掉整手牌
func discard_hand() -> void:
	for c in hand:
		discard_pile.append(c)
	hand.clear()


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func hand_size() -> int:
	return hand.size()


func is_hand_full() -> bool:
	return hand.size() >= HAND_LIMIT


func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()


## 卡组容量是否合法（20–40 张）
static func is_valid_deck_size(size: int) -> bool:
	return size >= 20 and size <= 40
