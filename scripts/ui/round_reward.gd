extends Control
## 先在桌面中央报出本轮收益，再把金币送到本人的钱包。
signal delivered(gain: int)
@onready var panel: Panel = $Panel
@onready var rate_label: Label = $Panel/Formula/Rate
@onready var times: Label = $Panel/Formula/Times
@onready var slot: Control = $Panel/Formula/Slot
@onready var current: Label = $Panel/Formula/Slot/Current
@onready var following: Label = $Panel/Formula/Slot/Following
@onready var receipt: Control = $Panel/Window
@onready var share: Label = $Panel/Window/Share
@onready var reels = $Panel/Window/Reels
var _sequence: Tween
var _destination: Control
var _flight: float = -1.0:
	set(value):
		_flight = value
		queue_redraw()

func play(gain: int, result: Dictionary, destination: Control) -> void:
	cancel()
	_destination = destination
	panel.modulate.a = 1.0
	var steps: int = result.reward_steps
	var seats: int = result.actions.size()
	# 主机已按本局配置结算出牌奖励，分得的余额单列。
	@warning_ignore("integer_division")
	var rate: int = int(result.play_reward) / steps
	var extra: int = gain - int(result.play_reward)
	rate_label.text = "%dr" % rate
	times.hide()
	slot.hide()
	receipt.hide()
	share.text = "另分得 %dr" % extra if extra > 0 else "本轮合计"
	reels.set_amount(0, false)
	show()

	_sequence = create_tween()
	_sequence.tween_interval(0.38)
	_sequence.tween_callback(func():
		times.show()
		slot.scale = Vector2.ONE
		slot.show())
	var stop := seats * ceili(6.0 / seats) + steps - 1
	_sequence.tween_method(_roll_multiplier.bind(seats), 0.0, float(stop), 0.76).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sequence.tween_callback(func(): slot.pivot_offset = slot.size * 0.5)
	_sequence.tween_property(slot, "scale", Vector2(1.16, 1.16), 0.08)
	_sequence.tween_property(slot, "scale", Vector2.ONE, 0.12)
	_sequence.tween_callback(func():
		receipt.show()
		reels.set_amount(gain, true, 0.28))
	_sequence.tween_interval(0.66)
	_sequence.tween_property(self, "_flight", 1.0, 0.48).from(0.0)
	_sequence.parallel().tween_property(panel, "modulate:a", 0.0, 0.19)
	_sequence.tween_callback(func():
		hide()
		delivered.emit(gain))

func _roll_multiplier(value: float, seats: int) -> void:
	var index := floori(value)
	var y := -(value - index) * slot.size.y
	current.text = str(posmod(index, seats) + 1)
	current.position.y = y
	following.text = str(posmod(index + 1, seats) + 1)
	following.position.y = y + slot.size.y

func cancel() -> void:
	if _sequence:
		_sequence.kill()
	_flight = -1.0
	hide()

func _draw() -> void:
	if _flight < 0.0 or not is_instance_valid(_destination):
		return
	var start := size * 0.5
	var end := get_global_transform().affine_inverse() * _destination.get_global_rect().get_center()
	for i in 5:
		var t := (_flight - i * 0.055) / 0.78
		if t < 0.0 or t > 1.0:
			continue
		var pos := start.lerp(end, t)
		pos.y -= sin(t * PI) * (45.0 + i * 7.0)
		var radius := lerpf(10.0, 5.0, t)
		draw_circle(pos, radius, Color("ffd978"), true, -1.0, true)
		draw_arc(pos, radius * 0.73, 0, TAU, 24, Color("b7782f"), 1.5, true)
		draw_line(pos - Vector2(0, radius * 0.36), pos + Vector2(0, radius * 0.36), Color("a36728"), 2.0, true)
