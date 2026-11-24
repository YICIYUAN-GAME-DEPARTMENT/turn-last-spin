@tool
extends Container
## 保存发牌顺序。将悬停牌移到绘制和鼠标命中顺序的最前面。
const ROW_HEIGHT := 160.0
const HOVER_SCALE := Vector2(1.09, 1.09)
var _order: Array[Button] = []
var _front: Button
var _pinned: Button

func _ready() -> void:
	child_entered_tree.connect(_add_card)
	child_exiting_tree.connect(_remove_card)
	for card in get_children():
		_add_card(card)

func _add_card(card: Node) -> void:
	if card is Button:
		_order.append(card)
		card.mouse_entered.connect(_hover.bind(card))
		card.mouse_exited.connect(_leave.bind(card))
		queue_sort()

func _remove_card(card: Node) -> void:
	_order.erase(card)
	if _pinned == card:
		_pinned = null
	if _front == card:
		_front = null
	queue_sort()

func pin(card: Button) -> void:
	_pinned = card
	_raise_card(card)

func _hover(card: Button) -> void:
	if _pinned == null:
		_raise_card(card)

func _leave(card: Button) -> void:
	if _pinned == null and _front == card:
		_raise_card(null)

func _raise_card(card: Button) -> void:
	if _front == card:
		return
	if is_instance_valid(_front):
		_front.scale = Vector2.ONE
		move_child(_front, _order.find(_front))
	_front = card
	if card != null:
		move_child(card, -1)
		card.scale = HOVER_SCALE

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or not is_node_ready():
		return
	var per_row := maxi(2, floori((size.x - 114.0) / 26.0) + 1)
	var rows := ceili(float(_order.size()) / per_row)
	custom_minimum_size.y = rows * ROW_HEIGHT
	var top := maxf(0.0, (size.y - custom_minimum_size.y) * 0.5)
	for i in _order.size():
		var card := _order[i]
		var column := i % per_row
		var row_start := i - column
		var count := mini(per_row, _order.size() - row_start)
		card.show_corner = count > 1
		card.size = card.get_combined_minimum_size()
		var spacing := minf(card.size.x * 0.84, (size.x - card.size.x - 38.0) / maxi(1, count - 1))
		var offset := column - (count - 1) * 0.5
		var angle := clampf(offset * 12.0, -17.0, 17.0)
		card.pivot_offset = card.size * 0.5
		card.rotation = deg_to_rad(angle)
		var center := Vector2(size.x * 0.5 + offset * spacing,
			top + (floori(float(i) / per_row) + 0.5) * ROW_HEIGHT + 9.0 * pow(angle / 17.0, 2))
		card.position = center - card.pivot_offset
