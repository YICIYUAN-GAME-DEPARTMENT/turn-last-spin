extends RefCounted

const PAPER = Color("f6f2e8")
const CARD = Color("fdf9ef")
const INK = Color("282521")
const MUTED = Color("625b52")
const LINE = Color("a69a89")
const ACCENT = Color("983f30")
const WASH = Color("ebd8ca")

static func centered(canvas: CanvasItem, font: Font, value: String, at: Vector2, height: int, color: Color) -> void:
	var width = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, height).x
	var baseline = (font.get_ascent(height) - font.get_descent(height)) / 2.0
	canvas.draw_string(font, at + Vector2(-width / 2.0, baseline), value, HORIZONTAL_ALIGNMENT_LEFT, -1, height, color)

static func stroke(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float = 1.4) -> void:
	canvas.draw_polyline(points, color, width, true)
	var trace := PackedVector2Array()
	for i in range(points.size()):
		trace.append(points[i] + Vector2(1.25 + sin(i * 2.1), 1.6 + cos(i * 1.6)))
	canvas.draw_polyline(trace, Color(color, color.a * 0.26), maxf(0.7, width * 0.58), true)

static func edge(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float = 1.3) -> void:
	var normal = (to - from).normalized().orthogonal()
	stroke(canvas, PackedVector2Array([from, from.lerp(to, 0.31) + normal * 0.8,
		from.lerp(to, 0.72) - normal * 0.9, to]), color, width)

static func plane(canvas: CanvasItem, points: PackedVector2Array, fill: Color, outline: Color = INK, width: float = 1.5) -> void:
	canvas.draw_colored_polygon(points, fill)
	for i in range(points.size()):
		edge(canvas, points[i], points[(i + 1) % points.size()], outline, width)

static func hatch(canvas: CanvasItem, points: PackedVector2Array, color: Color, spacing: float, width: float = 1.0) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var slant = bounds.size.x * 0.68
	var line_y = bounds.position.y - slant
	while line_y <= bounds.end.y:
		var from = Vector2(bounds.position.x - 1.0, line_y + slant)
		var to = Vector2(bounds.end.x + 1.0, line_y)
		var hits := PackedFloat32Array()
		for i in range(points.size()):
			var hit = Geometry2D.segment_intersects_segment(from, to, points[i], points[(i + 1) % points.size()])
			if hit != null:
				hits.append(hit.x)
		hits.sort()
		for i in range(0, hits.size() - 1, 2):
			var first = from.lerp(to, (hits[i] - from.x) / (to.x - from.x))
			var last = from.lerp(to, (hits[i + 1] - from.x) / (to.x - from.x))
			canvas.draw_line(first, last, color, width, true)
		line_y += spacing

static func chip(canvas: CanvasItem, at: Vector2, radius: float, color: Color, tilt: float = 1.0) -> void:
	var points := PackedVector2Array()
	for i in range(41):
		var direction = Vector2.from_angle(TAU * i / 40.0)
		points.append(at + direction * Vector2(radius, radius * tilt))
	canvas.draw_colored_polygon(points.slice(0, 40), color)
	canvas.draw_polyline(points, INK, maxf(0.9, radius / 15.0), true)
	for index in range(8):
		var direction = Vector2.from_angle(TAU * index / 8.0)
		var ray = direction * Vector2(radius, radius * tilt)
		canvas.draw_line(at + ray * 0.67, at + ray * 0.88, CARD, maxf(0.8, radius / 11.0), true)
	var rim := PackedVector2Array()
	for point in points:
		rim.append(at.lerp(point, 0.55))
	canvas.draw_polyline(rim, CARD, maxf(0.7, radius / 17.0), true)

static func card_face(canvas: CanvasItem, font: Font, rect: Rect2, number: String, active: bool = false) -> void:
	var color = ACCENT if active else INK
	var tl = rect.position
	var br = rect.end
	var points = PackedVector2Array([tl + Vector2(0, 2), Vector2(br.x - 1, tl.y),
		br - Vector2(0, 2), Vector2(tl.x + 1, br.y)])
	canvas.draw_colored_polygon(points, CARD)
	stroke(canvas, PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), color, 1.25)
	if rect.size.x >= 45:
		canvas.draw_rect(rect.grow(-6), Color(color, 0.30), false, 0.8)
		var corner_size = clampi(roundi(rect.size.x * 0.18), 10, 22)
		centered(canvas, font, number, tl + Vector2(8 + corner_size * 0.55, 8 + corner_size * 0.55), corner_size, color)
		centered(canvas, font, number, br - Vector2(8 + corner_size * 0.55, 8 + corner_size * 0.55), corner_size, color)
	centered(canvas, font, number, rect.get_center(), maxi(10, roundi(rect.size.x * 0.47)), color)
