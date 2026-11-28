@tool
extends Control
## 主菜单右侧核心视觉：复古扑克牌框 + 冷战圆桌讽刺漫画 + 会紧张停顿的朱红转盘指针

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var illustration: Texture2D
@export var card_rank := "12"
@export var caption_en := "FIG. 1 — THE COMMITTEE REACHES A DECISION."
@export var caption_zh := "图一 · 委员会正在友好表决"

const DEFAULT_ART_PATH := "res://assets/ui/hero_roundtable.png"

var _pointer_angle := -PI * 0.5
var _target_angle := -PI * 0.5
var _velocity := 0.0
var _pause_timer := 1.4
var _paused_seat := 0
var _sweat_phase := 0.0
var _boil_timer := 0.0
var _boil_frame := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_illustration()
	_rng.seed = 196210
	_pick_next_target()

func _ensure_illustration() -> void:
	if illustration != null:
		return
	if ResourceLoader.exists(DEFAULT_ART_PATH):
		illustration = load(DEFAULT_ART_PATH)
	if illustration == null:
		var abs_path := ProjectSettings.globalize_path(DEFAULT_ART_PATH)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				illustration = ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# 极克制的漫画手绘沸腾线（约 4fps 微幅抖动，只作用于指针与汗滴，不刺眼）
	_boil_timer += delta
	if _boil_timer >= 0.26:
		_boil_timer = 0.0
		_boil_frame = (_boil_frame + 1) % 3
		queue_redraw()

	if _pause_timer > 0.0:
		_pause_timer -= delta
		_sweat_phase += delta
		# 停在某位代表面前时，指针轻微神经质微颤
		if _pause_timer <= 0.0:
			_pick_next_target()
		queue_redraw()
		return

	var diff := _target_angle - _pointer_angle
	if absf(diff) < 0.012:
		_pointer_angle = _target_angle
		_velocity = 0.0
		_pause_timer = _rng.randf_range(1.6, 2.8)
		_sweat_phase = 0.0
		queue_redraw()
		return

	var step := clampf(diff * 3.1, -3.6, 3.6)
	_velocity = lerpf(_velocity, step, minf(1.0, delta * 6.5))
	_pointer_angle += _velocity * delta
	queue_redraw()

func _pick_next_target() -> void:
	# 8 位圆桌代表均匀排布在 -PI/2 起步的 8 个方位
	var seats_jump := _rng.randi_range(2, 6)
	if _rng.randf() < 0.35:
		seats_jump = -_rng.randi_range(1, 4)
	_paused_seat = posmod(_paused_seat + seats_jump, 8)
	_target_angle = _pointer_angle + float(seats_jump) * (TAU / 8.0)

func _draw() -> void:
	if size.x < 120.0 or size.y < 160.0:
		return
	# 按扑克牌经典比例 5:7 计算居中牌面，留足呼吸空间
	var avail_w := size.x - 42.0
	var avail_h := size.y - 42.0
	var card_w := minf(avail_w, avail_h * 0.705)
	var card_h := card_w / 0.705
	var center := size * 0.5
	var rect := Rect2(-Vector2(card_w, card_h) * 0.5, Vector2(card_w, card_h))

	# 轻微自然搁置倾角（-1.4°），像一张刚扣在桌上的讽刺扑克
	var card_xform := Transform2D(deg_to_rad(-1.4), center)
	draw_set_transform_matrix(card_xform)

	# 1. 版画斜排线投影
	Ink.draw_hatch_shadow(self, rect, Vector2(10.0, 11.0), Color(Ink.INK, 0.24), 5.2)

	# 2. 暖象牙卡面 + 钢笔手绘双边框
	Ink.draw_pen_rect(self, rect, Ink.PAPER_CARD, Ink.INK, 2.3, 41, 1.25, 2.8, true)

	# 3. 左上 & 右下倒置扑克牌角标（12 ♦）
	var font := get_theme_default_font()
	var corner_inset := Vector2(28.0, 34.0)
	_draw_card_corner(card_xform, font, rect.position + corner_inset, 0.0)
	_draw_card_corner(card_xform, font, rect.end - corner_inset, PI)

	# 4. 中央冷战圆桌钢笔插画
	var art_side := minf(card_w * 0.84, card_h * 0.66)
	var art_center := Vector2(0.0, -card_h * 0.025)
	var art_rect := Rect2(art_center - Vector2(art_side, art_side) * 0.5, Vector2(art_side, art_side))
	if illustration != null:
		draw_texture_rect(illustration, art_rect, false)

	# 5. 圆桌中心活体朱红轮盘指针（与空心桌心精准对齐）
	var table_radius := art_side * 0.23
	var jitter_ang := sin(_sweat_phase * 26.0) * 0.018 * exp(-_sweat_phase * 2.4) if _pause_timer > 0.0 else 0.0
	var ang := _pointer_angle + jitter_ang
	_draw_comic_needle(art_center, table_radius, ang)

	# 当指针停在某位官僚面前时，在其身旁画两笔讽刺漫画“冷汗 / 惊叹”墨线
	if _pause_timer > 0.2 and _sweat_phase < 1.9:
		var seat_dir := Vector2.from_angle(ang)
		var panic_pos := art_center + seat_dir * (art_side * 0.435)
		var perp := seat_dir.orthogonal()
		var pop := minf(1.0, _sweat_phase / 0.14)
		var s := 6.0 * pop
		Ink.draw_pen_line(self, panic_pos + perp * 6.0, panic_pos + perp * (6.0 + s) + seat_dir * (s * 0.9),
			Ink.CRIMSON, 1.8, 100 + _boil_frame, 0.5, 0.0)
		Ink.draw_pen_line(self, panic_pos - perp * 6.0, panic_pos - perp * (6.0 + s) + seat_dir * (s * 0.9),
			Ink.CRIMSON, 1.8, 120 + _boil_frame, 0.5, 0.0)

	# 6. 底部报刊讽刺漫画图注
	if font != null:
		var cap_y := rect.end.y - 42.0
		Ink.draw_pen_line(self, Vector2(rect.position.x + 28.0, cap_y - 16.0),
			Vector2(rect.end.x - 28.0, cap_y - 16.0), Color(Ink.RULE, 0.75), 1.0, 88, 0.5, 0.0)
		Ink.draw_centered_text(self, font, caption_zh, Vector2(0.0, cap_y), 12, Ink.INK)
		Ink.draw_centered_text(self, font, caption_en, Vector2(0.0, cap_y + 16.0), 9, Ink.INK_SOFT)

	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_card_corner(card_xform: Transform2D, font: Font, pos: Vector2, rot: float) -> void:
	draw_set_transform_matrix(card_xform * Transform2D(rot, pos))
	if font != null:
		Ink.draw_centered_text(self, font, card_rank, Vector2(0.0, -3.0), 22, Ink.CRIMSON)
	Ink.draw_diamond(self, Vector2(0.0, 20.0), 6.0, 8.8, Ink.CRIMSON, true)
	draw_set_transform_matrix(card_xform)

func _draw_comic_needle(center: Vector2, radius: float, angle: float) -> void:
	var dir := Vector2.from_angle(angle)
	var perp := dir.orthogonal()
	# 细虚线刻盘圆环（像冷战战术图）
	for i in range(8):
		var a := -PI * 0.5 + TAU * float(i) / 8.0
		var d := Vector2.from_angle(a)
		draw_line(center + d * (radius * 0.86), center + d * (radius * 0.98), Color(Ink.INK, 0.32), 1.2, true)
	# 指针轻微墨影
	var tip := center + dir * (radius * 0.94)
	var tail := center - dir * (radius * 0.28)
	var shoulder_l := center + dir * (radius * 0.52) + perp * 6.5
	var shoulder_r := center + dir * (radius * 0.52) - perp * 6.5
	var poly := PackedVector2Array([tail, shoulder_l, tip, shoulder_r])
	var shadow := PackedVector2Array()
	for p in poly:
		shadow.append(p + Vector2(2.5, 3.0))
	draw_colored_polygon(shadow, Color(Ink.INK, 0.16))
	draw_colored_polygon(poly, Ink.CRIMSON)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Ink.INK, 1.5, true)
	# 中心轴铆钉
	draw_circle(center, 6.2, Ink.PAPER_CARD)
	draw_arc(center, 6.2, 0.0, TAU, 20, Ink.INK, 1.9, true)
	draw_circle(center, 2.4, Ink.INK)
