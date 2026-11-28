@tool
extends Container
## 扇形手牌排布容器：保持发牌顺序，悬停或选中时抬升并置顶

const ROW_HEIGHT := 136.0
const HOVER_SCALE := Vector2(1.10, 1.10)
const HOVER_LIFT := 14.0

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
		var btn: Button = card
		_order.append(btn)
		btn.mouse_entered.connect(_hover.bind(btn))
		btn.mouse_exited.connect(_leave.bind(btn))
		queue_sort()

func _remove_card(card: Node) -> void:
	if card is Button:
		_order.erase(card)
	if _pinned == card:
		_pinned = null
	if _front == card:
		_front = null
	queue_sort()

func pin(card: Button) -> void:
	if is_instance_valid(_pinned) and _pinned.has_method("set"):
		_pinned.set("is_pinned", false)
	_pinned = card
	if is_instance_valid(_pinned) and _pinned.has_method("set"):
		_pinned.set("is_pinned", true)
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
		var orig_idx := _order.find(_front)
		if orig_idx >= 0:
			move_child(_front, orig_idx)
	_front = card
	if is_instance_valid(card):
		move_child(card, -1)
		card.scale = HOVER_SCALE
	queue_sort()

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or not is_node_ready():
		return
	var per_row := maxi(2, floori((size.x - 104.0) / 34.0) + 1)
	var rows := maxi(1, ceili(float(_order.size()) / float(per_row)))
	custom_minimum_size.y = float(rows) * ROW_HEIGHT
	var top := maxf(0.0, (size.y - custom_minimum_size.y) * 0.5)
	for i in range(_order.size()):
		var card: Button = _order[i]
		var column := i % per_row
		var row_start := i - column
		var count := mini(per_row, _order.size() - row_start)
		if card.has_method("set"):
			card.set("show_corner", true)
		card.size = card.get_combined_minimum_size()
		var spacing := minf(card.size.x * 0.92, (size.x - card.size.x - 32.0) / float(maxi(1, count - 1)))
		var offset := float(column) - float(count - 1) * 0.5
		var angle := clampf(offset * 7.5, -13.0, 13.0)
		card.pivot_offset = card.size * 0.5
		card.rotation = deg_to_rad(angle)
		var lift := HOVER_LIFT if card == _front else 0.0
		@warning_ignore("integer_division")
		var row_idx := i / per_row
		var center := Vector2(
			size.x * 0.5 + offset * spacing,
			top + (float(row_idx) + 0.55) * ROW_HEIGHT + 7.0 * pow(angle / 13.0, 2.0) - lift
		)
		card.position = center - card.pivot_offset
