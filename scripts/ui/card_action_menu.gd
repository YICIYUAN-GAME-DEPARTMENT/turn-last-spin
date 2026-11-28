extends PanelContainer

signal direction_selected(direction: int, points: int)
signal special_confirmed
signal cancelled

@onready var title: Label = %Title
@onready var point_row: HBoxContainer = %PointRow
@onready var points: OptionButton = %Points
@onready var choices: HBoxContainer = %Choices
@onready var plus_button: Button = %Plus
@onready var minus_button: Button = %Minus
@onready var effect: Label = %Effect
@onready var confirm_button: Button = %Confirm

var _fixed_value: int = 1

func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

func set_card_value(value: int) -> void:
	_fixed_value = value
	_set_mode("出牌  %d" % value, false, false)
	_update_directions()

func set_change_range(maximum: int) -> void:
	_set_mode("♦  变化卡", true, false)
	points.clear()
	for value in range(1, maximum + 1):
		points.add_item(str(value), value)
	points.select(0)
	_update_directions()

func set_special_card(card_name: String, description: String) -> void:
	_set_mode("♦  %s" % card_name, false, true)
	effect.text = description
	confirm_button.text = "♦  使用%s" % card_name

func close_point_picker() -> void:
	points.get_popup().hide()

func _set_mode(heading: String, choose_points: bool, confirm_special: bool) -> void:
	title.text = heading
	point_row.visible = choose_points
	choices.visible = not confirm_special
	effect.visible = confirm_special
	confirm_button.visible = confirm_special

func _selected_value() -> int:
	return points.get_selected_id() if point_row.visible else _fixed_value

func _update_directions() -> void:
	var value: int = _selected_value()
	plus_button.text = "＋%d 打出" % value
	minus_button.text = "−%d 打出" % value

func _on_points_selected(_index: int) -> void:
	_update_directions()

func _on_plus_pressed() -> void:
	direction_selected.emit(1, _selected_value())

func _on_minus_pressed() -> void:
	direction_selected.emit(-1, _selected_value())

func _on_special_pressed() -> void:
	special_confirmed.emit()

func _on_cancel_pressed() -> void:
	cancelled.emit()
