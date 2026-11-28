extends RefCounted
## 冷战钢笔讽刺漫画视觉基元（纯黑白墨线 + 唯一朱红印章点缀）

const PAPER := Color("f3f0e8")
const PAPER_CARD := Color("faf8f2")
const PAPER_TINT := Color("eae5d8")
const INK := Color("161514")
const INK_SOFT := Color("56524b")
const RULE := Color("bcb5a7")
const CRIMSON := Color("c42437")
const CRIMSON_DARK := Color("911726")

static func _hash(n: int) -> float:
	var x := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0

static func draw_pen_line(canvas: CanvasItem, from: Vector2, to: Vector2,
		color: Color = INK, width: float = 1.8, seed_val: int = 1,
		wobble: float = 1.15, overshoot: float = 1.6) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 1.0:
		return
	var dir := delta / length
	var normal := dir.orthogonal()
	var p0 := from - dir * overshoot
	var p1 := to + dir * overshoot
	var steps := clampi(int(length / 34.0), 3, 18)
	var pts := PackedVector2Array()
	pts.resize(steps + 1)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var envelope := sin(t * PI)
		var jitter := _hash(seed_val * 97 + i * 31) * wobble * (0.28 + 0.72 * envelope)
		pts[i] = p0.lerp(p1, t) + normal * jitter
	canvas.draw_polyline(pts, color, width, true)

static func draw_pen_rect(canvas: CanvasItem, rect: Rect2, fill: Color,
		stroke_color: Color = INK, width: float = 2.0, seed_val: int = 7,
		wobble: float = 1.1, overshoot: float = 2.4, double_ink: bool = false) -> void:
	if fill.a > 0.001:
		canvas.draw_rect(rect, fill, true)
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	draw_pen_line(canvas, tl, tr, stroke_color, width, seed_val + 1, wobble, overshoot)
	draw_pen_line(canvas, tr, br, stroke_color, width, seed_val + 2, wobble, overshoot)
	draw_pen_line(canvas, br, bl, stroke_color, width, seed_val + 3, wobble, overshoot)
	draw_pen_line(canvas, bl, tl, stroke_color, width, seed_val + 4, wobble, overshoot)
	if double_ink:
		var inner := rect.grow(-3.5)
		var itl := inner.position
		var itr := Vector2(inner.end.x, inner.position.y)
		var ibr := inner.end
		var ibl := Vector2(inner.position.x, inner.end.y)
		var faint := Color(stroke_color, stroke_color.a * 0.42)
		draw_pen_line(canvas, itl, itr, faint, 0.9, seed_val + 11, wobble * 0.7, 0.8)
		draw_pen_line(canvas, itr, ibr, faint, 0.9, seed_val + 12, wobble * 0.7, 0.8)
		draw_pen_line(canvas, ibr, ibl, faint, 0.9, seed_val + 13, wobble * 0.7, 0.8)
		draw_pen_line(canvas, ibl, itl, faint, 0.9, seed_val + 14, wobble * 0.7, 0.8)

static func draw_hatch_shadow(canvas: CanvasItem, rect: Rect2, offset: Vector2 = Vector2(7, 8),
		color: Color = Color(INK, 0.28), spacing: float = 5.5) -> void:
	# 只在卡片右侧和底侧画出漫画排线投影（L 型带）
	var right_strip := Rect2(Vector2(rect.end.x, rect.position.y + offset.y), Vector2(offset.x, rect.size.y))
	var bottom_strip := Rect2(Vector2(rect.position.x + offset.x, rect.end.y), Vector2(rect.size.x - offset.x, offset.y))
	var strips: Array[Rect2] = [right_strip, bottom_strip]
	for strip: Rect2 in strips:
		if strip.size.x <= 0.5 or strip.size.y <= 0.5:
			continue
		var total: float = strip.size.x + strip.size.y
		var d: float = spacing * 0.5
		while d < total:
			var x1: float = strip.position.x + maxf(0.0, d - strip.size.y)
			var y1: float = strip.position.y + minf(strip.size.y, d)
			var x2: float = strip.position.x + minf(strip.size.x, d)
			var y2: float = strip.position.y + maxf(0.0, d - strip.size.x)
			canvas.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, 1.15, true)
			d += spacing

static func draw_diamond(canvas: CanvasItem, center: Vector2, rx: float, ry: float,
		color: Color = CRIMSON, filled: bool = true, width: float = 1.6) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0.0, -ry),
		center + Vector2(rx, 0.0),
		center + Vector2(0.0, ry),
		center + Vector2(-rx, 0.0)
	])
	if filled:
		canvas.draw_colored_polygon(pts, color)
	else:
		var loop := pts.duplicate()
		loop.append(pts[0])
		canvas.draw_polyline(loop, color, width, true)

static func draw_centered_text(canvas: CanvasItem, font: Font, text: String,
		center: Vector2, font_size: int, color: Color = INK) -> void:
	if font == null or text.is_empty():
		return
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	canvas.draw_string(font, center + Vector2(-text_w * 0.5, baseline),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

static func draw_rubber_stamp(canvas: CanvasItem, center: Vector2, text: String,
		font: Font, font_size: int, color: Color = CRIMSON, angle_deg: float = -5.0,
		seed_val: int = 33, filled_bg: Color = Color(0, 0, 0, 0)) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box_size := Vector2(text_size.x + 20.0, float(font_size) + 12.0)
	var rect := Rect2(-box_size * 0.5, box_size)
	canvas.draw_set_transform(center, deg_to_rad(angle_deg), Vector2.ONE)
	if filled_bg.a > 0.001:
		canvas.draw_rect(rect, filled_bg, true)
	draw_pen_rect(canvas, rect, Color(0, 0, 0, 0), color, 2.0, seed_val, 0.7, 1.2, true)
	draw_centered_text(canvas, font, text, Vector2.ZERO, font_size, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_bureaucrat_avatar(canvas: CanvasItem, center: Vector2, radius: float,
		seed_id: int, is_owner: bool = false, is_offline: bool = false) -> void:
	var ink := Color(INK, 0.38) if is_offline else INK
	var accent := Color(CRIMSON, 0.45) if is_offline else CRIMSON
	var s := radius / 18.0
	# 圆形钢笔头像框
	var ring := PackedVector2Array()
	for i in range(33):
		var a := TAU * float(i) / 32.0
		var r := radius * (1.0 + _hash(seed_id * 53 + i) * 0.025)
		ring.append(center + Vector2.from_angle(a) * r)
	canvas.draw_colored_polygon(ring.slice(0, 32), PAPER_CARD)
	# 黑色西装剪影（呼应参考图的实心墨水西装 + 留白领口）
	var shoulders := PackedVector2Array([
		center + Vector2(-13.5, 13.5) * s,
		center + Vector2(-11.5, 4.0) * s,
		center + Vector2(-5.0, 1.5) * s,
		center + Vector2(5.0, 1.5) * s,
		center + Vector2(11.5, 4.0) * s,
		center + Vector2(13.5, 13.5) * s,
		center + Vector2(0.0, 16.5) * s
	])
	canvas.draw_colored_polygon(shoulders, ink)
	# 白色衬衫领口 V 字负空间
	var collar := PackedVector2Array([
		center + Vector2(-3.6, 1.8) * s,
		center + Vector2(3.6, 1.8) * s,
		center + Vector2(0.0, 9.2) * s
	])
	canvas.draw_colored_polygon(collar, PAPER_CARD)
	# 领带（房主用朱红领带，其余黑墨领带）
	var tie := PackedVector2Array([
		center + Vector2(-1.1, 3.0) * s,
		center + Vector2(1.1, 3.0) * s,
		center + Vector2(1.4, 8.6) * s,
		center + Vector2(0.0, 10.6) * s,
		center + Vector2(-1.4, 8.6) * s
	])
	canvas.draw_colored_polygon(tie, accent if is_owner else ink)
	# 钢笔简笔头颅
	var head_c := center + Vector2(0.0, -5.2) * s
	canvas.draw_circle(head_c, 6.2 * s, PAPER_CARD)
	canvas.draw_arc(head_c, 6.2 * s, 0.0, TAU, 24, ink, 1.7, true)
	# 按 id 区分冷战官僚小特征（帽子 / 眼镜 / 八字胡 / 分头）
	var variant := posmod(seed_id, 4)
	if variant == 0 or is_owner:
		# 礼帽（Fedora）
		canvas.draw_line(head_c + Vector2(-9.5, -4.0) * s, head_c + Vector2(9.5, -4.0) * s, ink, 2.0 * s, true)
		var hat := PackedVector2Array([
			head_c + Vector2(-6.0, -4.0) * s,
			head_c + Vector2(-4.8, -10.5) * s,
			head_c + Vector2(4.8, -10.5) * s,
			head_c + Vector2(6.0, -4.0) * s
		])
		canvas.draw_colored_polygon(hat, ink)
		if is_owner:
			canvas.draw_line(head_c + Vector2(-5.4, -5.5) * s, head_c + Vector2(5.4, -5.5) * s, accent, 1.8 * s, true)
	elif variant == 1:
		# 圆框眼镜
		canvas.draw_arc(head_c + Vector2(-2.4, -0.5) * s, 2.0 * s, 0.0, TAU, 12, ink, 1.3 * s, true)
		canvas.draw_arc(head_c + Vector2(2.4, -0.5) * s, 2.0 * s, 0.0, TAU, 12, ink, 1.3 * s, true)
		canvas.draw_line(head_c + Vector2(-0.4, -0.5) * s, head_c + Vector2(0.4, -0.5) * s, ink, 1.2 * s, true)
	elif variant == 2:
		# 小胡子 + 两点眼
		canvas.draw_circle(head_c + Vector2(-2.2, -1.2) * s, 1.0 * s, ink)
		canvas.draw_circle(head_c + Vector2(2.2, -1.2) * s, 1.0 * s, ink)
		canvas.draw_line(head_c + Vector2(-3.0, 2.2) * s, head_c + Vector2(3.0, 2.2) * s, ink, 1.8 * s, true)
	else:
		# 偏分黑发 + 眯眼
		var hair := PackedVector2Array([
			head_c + Vector2(-6.0, -2.5) * s,
			head_c + Vector2(-3.5, -6.8) * s,
			head_c + Vector2(3.8, -6.5) * s,
			head_c + Vector2(6.2, -2.5) * s,
			head_c + Vector2(1.0, -4.2) * s
		])
		canvas.draw_colored_polygon(hair, ink)
		canvas.draw_line(head_c + Vector2(-3.2, -0.5) * s, head_c + Vector2(-1.2, -0.5) * s, ink, 1.4 * s, true)
		canvas.draw_line(head_c + Vector2(1.2, -0.5) * s, head_c + Vector2(3.2, -0.5) * s, ink, 1.4 * s, true)
	# 外圈手绘圆边框
	canvas.draw_polyline(ring, accent if is_owner else ink, 1.8, true)
