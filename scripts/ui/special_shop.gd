extends PanelContainer
const Rules = preload("res://scripts/core/game_rules.gd")
## 商店处理购买，买到的暗牌由手牌区显示。

@onready var super_effect: Label = $Rows/Super/Details/Effect
@onready var notice: Label = $Rows/Notice
@onready var buy_buttons: Dictionary = {
	"defense": $Rows/Defense/Buy,
	"change": $Rows/Change/Buy,
	"super": $Rows/Super/Buy
}

var game: Node

func _ready() -> void:
	for kind in buy_buttons:
		buy_buttons[kind].pressed.connect(_buy.bind(kind))

func present() -> void:
	$Rows/Defense/Details/Effect.text = "被命中时保住金币" if game.game_mode == Rules.Mode.GREED else "保住最后 1 点生命"
	super_effect.text = "结算位移 +%d" % game.super_steps
	for kind in buy_buttons:
		var price: int = int(game.card_prices.get(kind, 0))
		buy_buttons[kind].text = "购买 %dr" % price
		buy_buttons[kind].disabled = not game.can_buy_cards() or not game.card_prices.has(kind) or game.balance < price
	notice.text = game.economy_notice
	notice.visible = not notice.text.is_empty()

func _buy(kind: String) -> void:
	if game != null:
		game.buy_special_card(kind)
