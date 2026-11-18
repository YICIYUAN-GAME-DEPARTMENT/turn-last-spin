@tool
extends Button

const SPECIAL_NAMES := {"defense": "防御卡", "change": "变化卡", "super": "超级卡"}
const SPECIAL_HINTS := {
	"defense": "出牌阶段使用，保住最后 1 点生命",
	"change": "出牌阶段使用，先选点数，再选加或减",
	"super": "结算阶段使用"
}

@export var card_id: int = -1
@export var value: int = 1:
	set(number):
		value = number
		_update_face()
@export_enum("play", "defense", "change", "super") var kind: String = "play":
	set(card_kind):
		kind = card_kind
		_update_face()
@export var quantity: int = 1:
	set(amount):
		quantity = amount
		_update_face()

func _ready() -> void:
	_update_face()

func _update_face() -> void:
	if SPECIAL_NAMES.has(kind):
		theme_type_variation = &"SpecialHandCard"
		text = "%s\n×%d" % [SPECIAL_NAMES[kind], quantity]
		tooltip_text = SPECIAL_HINTS[kind]
	else:
		theme_type_variation = &"HandCard"
		text = str(value)
		tooltip_text = ""
