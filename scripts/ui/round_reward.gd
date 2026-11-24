extends Control
## 滚动揭晓结算公式和到账金额，再把筹码送入钱包。

const Sketch = preload("res://scripts/ui/sketch_ink.gd")
const Timing = preload("res://scripts/core/round_presentation_timing.gd")
const Reel = preload("res://scripts/ui/reward_reel.gd")

signal delivered(gain: int)

@onready var panel: Panel = $Panel
@onready var rate: Reel = $Panel/Formula/Rate
@onready var operator: Reel = $Panel/Formula/Operator
@onready var steps_reel: Reel = $Panel/Formula/Steps
@onready var share: Control = $Panel/Receipt/Share
@onready var share_reel: Reel = $Panel/Receipt/Share/Reel
@onready var total: Reel = $Panel/Receipt/Total/Reel

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
	# 使用主机结算出的奖励和实际分得的筹码。
	@warning_ignore("integer_division")
	var coefficient: int = int(result.play_reward) / steps
	var inherited: int = gain - int(result.play_reward)
	rate.prepare([_amount_track(coefficient, "r")])
	operator.prepare([PackedStringArray(["", "·", "×", "·", "×"])])
	steps_reel.prepare([_step_track(steps, seats)])
	share.visible = inherited > 0
	if share.visible:
		share_reel.prepare([_amount_track(inherited, "r", "+")])
	total.prepare(_total_tracks(gain))
	show()

	_sequence = create_tween()
	_sequence.tween_interval(Timing.REWARD_INTRO_SECONDS)
	_sequence.tween_property(rate, "progress", 1.0, Timing.REWARD_RATE_SECONDS)
	_sequence.tween_property(operator, "progress", 1.0, Timing.REWARD_OPERATOR_SECONDS)
	_sequence.tween_property(steps_reel, "progress", 1.0, Timing.REWARD_STEPS_SECONDS)
	if share.visible:
		_sequence.tween_property(share_reel, "progress", 1.0, Timing.REWARD_SHARE_SECONDS)
	_sequence.tween_property(total, "progress", 1.0, Timing.REWARD_TOTAL_SECONDS)
	_sequence.tween_interval(Timing.REWARD_READ_SECONDS)
	_sequence.tween_property(self, "_flight", 1.0, Timing.REWARD_FLIGHT_SECONDS).from(0.0)
	_sequence.parallel().tween_property(panel, "modulate:a", 0.0, 0.19)
	_sequence.tween_callback(func():
		hide()
		_sequence = null
		delivered.emit(gain))

func _amount_track(value: int, suffix: String, prefix: String = "") -> PackedStringArray:
	var track := PackedStringArray([""])
	for offset in [2, -1, 5, -3, 1, 0]:
		track.append(prefix + str(maxi(0, value + offset)) + suffix)
	return track

func _step_track(steps: int, seats: int) -> PackedStringArray:
	var track := PackedStringArray([""])
	var cycles := ceili(7.0 / seats)
	for i in range(seats * cycles + steps):
		track.append(str(i % seats + 1))
	return track

func _total_tracks(gain: int) -> Array[PackedStringArray]:
	var tracks: Array[PackedStringArray] = [PackedStringArray(["", "+", "·", "+"])]
	var number := str(gain)
	for column in range(number.length()):
		var final_digit := int(number[column])
		var track := PackedStringArray([""])
		for offset in range(9):
			track.append(str(posmod(final_digit + column * 3 + offset + 1, 10)))
		track.append(str(final_digit))
		tracks.append(track)
	tracks.append(PackedStringArray(["", "r", "", "r"]))
	return tracks

func cancel() -> void:
	if _sequence:
		_sequence.kill()
		_sequence = null
	_flight = -1.0
	hide()

func _draw() -> void:
	if _flight < 0.0 or not is_instance_valid(_destination):
		return
	var inverse := get_global_transform().affine_inverse()
	var start := inverse * total.get_global_rect().get_center()
	var end := inverse * _destination.get_global_rect().get_center()
	for i in range(5):
		var t := (_flight - i * 0.055) / 0.78
		if t < 0.0 or t > 1.0:
			continue
		var pos := start.lerp(end, t)
		pos.y -= sin(t * PI) * (45.0 + i * 7.0)
		var radius := lerpf(10.0, 5.0, t)
		Sketch.chip(self, pos, radius, Sketch.ACCENT, 0.7 + 0.3 * cos(t * TAU))
