@tool
extends Control
## 固定正俯视角的冷战讽刺漫画圆桌轮盘：
## 圆桌外围环坐钢笔官僚 + 高可读直立明牌席位卡 + 桌面盖牌/翻牌 + 中央活体朱红指针

const Ink = preload("res://scripts/ui/editorial_ink.gd")

const DECK_SIZE := Vector2(44.0, 60.0)
const TABLE_FILL_A := Color("faf8f2")
const TABLE_FILL_B := Color("f2ede1")
const TABLE_RIM := Color("e6dfd0")

var seats: Array = []
var local_player_id: int = 0
var front_index: int = 0
var start_index: int = -1
var target_index: int = -1
var center_caption: String = ""
var center_steps: String = "—"
var countdown_seconds: int = -1:
	set(value):
		if countdown_seconds != value:
			countdown_seconds = value
			queue_redraw()
var countdown_ratio: float = 0.0:
	set(value):
		if not is_equal_approx(countdown_ratio, value):
			countdown_ratio = value
			queue_redraw()
var needle_angle: float = PI * 0.5:
	set(value):
		needle_angle = value
		queue_redraw()
var deal_progress: float = 1.0:
	set(value):
		deal_progress = value
		queue_redraw()
var play_progress: float = 1.0:
	set(value):
		play_progress = value
		queue_redraw()
var number_scale: float = 1.0:
	set(value):
		number_scale = value
		queue_redraw()
var showing_actions: bool = false
var hit_defended: bool = false
var table_cards: Dictionary = {}:
	set(value):
		table_cards = value
		queue_redraw()
var self_deal: Dictionary = {}:
	set(value):
		self_deal = value
		queue_redraw()

var _placements: Dictionary = {}
var _opponent_deals: Array[Dictionary] = []
var _seat_plate_rects: Dictionary = {}
var _hovered_seat_id: int = -1
var _boil_timer: float = 0.0
var _boil_frame: int = 0
var _ui_font: Font

@export var display_font: Font
@export var mono_font: Font
@export_range(2, 12, 1) var preview_players: int = 8:
	set(number):
		preview_players = number
		if Engine.is_editor_hint() and is_node_ready():
			_editor_preview()

func _ready() -> void:
	_ui_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)
	if Engine.is_editor_hint():
		_editor_preview()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# 极克制的 3fps 漫画抖动帧，仅用于命中冷汗线/紧急倒计时提示
	if target_index >= 0 or (countdown_seconds >= 0 and countdown_seconds <= 5):
		_boil_timer += delta
		if _boil_timer >= 0.28:
			_boil_timer = 0.0
			_boil_frame = (_boil_frame + 1) % 3
			queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos: Vector2 = event.position
		var found: int = -1
		for sid in _seat_plate_rects:
			var r: Rect2 = _seat_plate_rects[sid]
			if r.has_point(pos):
				found = int(sid)
				break
		if found != _hovered_seat_id:
			_hovered_seat_id = found
			queue_redraw()

func _editor_preview() -> void:
	seats.clear()
	for i in range(preview_players):
		seats.append({
			"id": i + 1,
			"name": "你" if i == 0 else String.chr(97 + i),
			"alive": true,
			"hp": 3,
			"balance": 120 + i * 25,
			"cards": [
				{"id": i * 2 + 1, "value": (i * 3 + 1) % preview_players + 1, "face_up": true, "played": false},
				{"id": i * 2 + 2, "value": (i * 5 + 2) % preview_players + 1, "face_up": true, "played": false},
				{"face_up": false, "quantity": 1 if i % 2 == 0 else 0}
			].filter(func(c: Dictionary) -> bool: return c.get("face_up", false) or int(c.get("quantity", 0)) > 0)
		})
	local_player_id = 1
	front_index = 0
	start_index = 2 % preview_players
	target_index = -1
	center_caption = "初始"
	center_steps = str(start_index + 1)
	countdown_seconds = 12
	countdown_ratio = 0.8
	queue_redraw()

func seat_angle(index: int) -> float:
	# 本人固定在正下方 (PI / 2)，其余席位按顺时针均分
	return PI * 0.5 + TAU * float(index - front_index) / float(maxi(1, seats.size()))

func table_center() -> Vector2:
	var top_safe: float = 96.0
	var bottom_safe: float = 176.0
	var arena_h: float = maxf(240.0, size.y - top_safe - bottom_safe)
	return Vector2(size.x * 0.5, top_safe + arena_h * 0.53)

func table_radius() -> float:
	var top_safe: float = 96.0
	var bottom_safe: float = 176.0
	var arena_h: float = maxf(240.0, size.y - top_safe - bottom_safe)
	return clampf(minf(size.x * 0.185, arena_h * 0.365), 118.0, 224.0)

func place_local_card(slot: int, from: Vector2, extent: Vector2, angle: float) -> void:
	if _placements.has(slot):
		var old_tween: Tween = _placements[slot]["tween"]
		if is_instance_valid(old_tween):
			old_tween.kill()
	var tween := create_tween()
	var placement: Dictionary = {
		"origin": from,
		"extent": extent,
		"angle": angle,
		"progress": 0.0,
		"tween": tween
	}
	_placements[slot] = placement
	tween.tween_method(func(progress: float) -> void:
		placement["progress"] = progress
		queue_redraw(), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		_placements.erase(slot)
		queue_redraw())

func clear_placements() -> void:
	for placement_var in _placements.values():
		var placement: Dictionary = placement_var
		var tw: Tween = placement.get("tween")
		if is_instance_valid(tw):
			tw.kill()
	_placements.clear()
	queue_redraw()

func _draw() -> void:
	if _ui_font == null:
		_ui_font = get_theme_default_font()
	if seats.is_empty() or _ui_font == null or size.x < 240.0 or size.y < 240.0:
		return

	var center := table_center()
	var radius := table_radius()
	_opponent_deals.clear()
	_seat_plate_rects.clear()

	# 1. 圆桌外围的俯视冷战官僚剪影（紧贴桌沿，被桌沿压住一点手肘）
	_draw_bureaucrats_ring(center, radius)

	# 2. 圆桌主体（版画投影 + 复古圆桌边环 + 扇区 + 刻度）
	_draw_table_disc(center, radius)
	_draw_sectors(center, radius)
	_draw_bezel_ticks(center, radius)

	# 3. 桌面出牌区（锁定牌背 / 结算翻面）
	if deal_progress >= 1.0 or showing_actions:
		_draw_table_cards(center, radius)

	# 4. 桌旁牌堆与中央轮盘指针 + 中心战术仪表
	_draw_deck(center, radius)
	_draw_pointer_and_hub(center, radius)

	# 5. 所有席位的高可读直立明牌档案卡（自动防重叠，清晰易读）
	_draw_seat_plates(center, radius)

	# 6. 发牌飞行演出
	_draw_deal_flights(center, radius)

	# 7. 悬停放大检视浮卡（囤牌很多时可轻松查看完整明牌）
	if _hovered_seat_id > 0:
		_draw_hovered_detail(center)

func _circle_points(center: Vector2, radius: float, begin: float = 0.0, end: float = TAU,
		segments: int = 96, wobble: float = 0.0045) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segments + 1)
	for i in range(segments + 1):
		var angle := lerpf(begin, end, float(i) / float(segments))
		var jitter := (sin(angle * 9.0) * 0.65 + cos(angle * 17.0) * 0.35) * wobble
		pts[i] = center + Vector2.from_angle(angle) * radius * (1.0 + jitter)
	return pts

func _draw_table_disc(center: Vector2, radius: float) -> void:
	# 柔和的纸面墨影
	var shadow := _circle_points(center + Vector2(7.0, 9.0), radius * 1.01, 0.0, TAU, 84, 0.003)
	draw_colored_polygon(shadow.slice(0, shadow.size() - 1), Color(Ink.INK, 0.13))

	# 外圈木边/纸框
	var outer := _circle_points(center, radius, 0.0, TAU, 96, 0.0035)
	draw_colored_polygon(outer.slice(0, outer.size() - 1), TABLE_RIM)
	draw_polyline(outer, Ink.INK, 2.5, true)

	# 内圆盘面
	var inner := _circle_points(center, radius * 0.925, 0.0, TAU, 96, 0.003)
	draw_colored_polygon(inner.slice(0, inner.size() - 1), TABLE_FILL_A)

func _draw_sectors(center: Vector2, radius: float) -> void:
	var count := seats.size()
	var step := TAU / float(count)
	var disc_r := radius * 0.925
	var hub_r := radius * 0.255

	for i in range(count):
		var seat: Dictionary = seats[i]
		var mid := seat_angle(i)
		var begin := mid - step * 0.5
		var end := mid + step * 0.5
		var arc := _circle_points(center, disc_r, begin, end, 24, 0.002)
		var sector := PackedVector2Array([center]) + arc

		var is_hit := i == target_index
		var is_start := i == start_index
		var is_hover := int(seat.get("id", -1)) == _hovered_seat_id
		var fill := TABLE_FILL_A if i % 2 == 0 else TABLE_FILL_B
		if is_hit:
			fill = Color("f6dce0") if not hit_defended else Color("e9edf0")
		elif is_hover:
			fill = Color("efe7d5")
		elif is_start:
			fill = Color("f4ebe0")
		draw_colored_polygon(sector, fill)

		# 命中扇区画冷战漫画朱红斜排线强调
		if is_hit:
			var hatch_col := Color(Ink.INK, 0.22) if hit_defended else Color(Ink.CRIMSON, 0.24)
			var rings: Array[float] = [0.42, 0.58, 0.74, 0.88]
			for ring_t: float in rings:
				var h_arc := _circle_points(center, disc_r * ring_t, begin + 0.04, end - 0.04, 12, 0.0)
				draw_polyline(h_arc, hatch_col, 1.3, true)

		# 初始指向小标记（三角刻度）
		if is_start:
			var d := Vector2.from_angle(mid)
			var perp := d.orthogonal()
			var tip := center + d * (disc_r * 0.87)
			var tri := PackedVector2Array([
				tip,
				center + d * (disc_r * 0.955) + perp * 6.5,
				center + d * (disc_r * 0.955) - perp * 6.5
			])
			draw_colored_polygon(tri, Ink.CRIMSON)

		# 扇区分隔钢笔射线
		var ray := Vector2.from_angle(begin)
		Ink.draw_pen_line(self, center + ray * hub_r, center + ray * disc_r,
			Color(Ink.INK, 0.42), 1.15, i * 17 + 3, 0.55, 0.0)

		# 外沿扇区序号（01..12，高清晰度）
		var mark_pos := center + Vector2.from_angle(mid) * (radius * 0.962)
		var mark_col := Ink.CRIMSON if (is_hit or is_start) else Ink.INK_SOFT
		var num_font := mono_font if mono_font != null else _ui_font
		Ink.draw_centered_text(self, num_font, "%02d" % (i + 1), mark_pos, 11, mark_col)

	# 内圆盘钢笔轮廓线
	var inner_ring := _circle_points(center, disc_r, 0.0, TAU, 96, 0.0025)
	draw_polyline(inner_ring, Ink.INK, 1.8, true)

func _draw_bezel_ticks(center: Vector2, radius: float) -> void:
	for i in range(72):
		var a := TAU * float(i) / 72.0
		var d := Vector2.from_angle(a)
		var inner_k := 0.905 if i % 6 == 0 else 0.914
		draw_line(center + d * (radius * inner_k), center + d * (radius * 0.925),
			Color(Ink.INK, 0.35 if i % 6 == 0 else 0.18), 1.0, true)

func _draw_bureaucrats_ring(center: Vector2, radius: float) -> void:
	var count := seats.size()
	var figure_scale := clampf(1.08 - float(count) * 0.032, 0.66, 0.96)
	for i in range(count):
		var seat: Dictionary = seats[i]
		var id: int = int(seat.get("id", i + 1))
		var angle := seat_angle(i)
		var dir := Vector2.from_angle(angle)
		var alive: bool = seat.get("alive", true)
		var is_hit := i == target_index
		var is_local := id == local_player_id

		# 本人在正下方只露出一双按在桌沿上的手和肩线，给下方手牌扇区让出空间
		var rim_pos := center + dir * (radius + (14.0 if not is_local else 10.0) * figure_scale)
		var shake := Vector2.ZERO
		if is_hit and not hit_defended:
			shake = dir.orthogonal() * (sin(float(_boil_frame) * 2.1 + float(id)) * 2.5)
		_draw_topdown_bureaucrat(rim_pos + shake, angle, figure_scale, id, alive, is_local, is_hit)

func _draw_topdown_bureaucrat(pos: Vector2, seat_ang: float, s: float, id: int,
		alive: bool, is_local: bool, is_hit: bool) -> void:
	# 朝向桌心（-dir），即旋转 seat_ang - PI/2 使局部 -Y 指向桌心
	var xform := Transform2D(seat_ang - PI * 0.5, pos)
	draw_set_transform_matrix(xform)

	var alpha := 1.0 if alive else 0.32
	var ink := Color(Ink.INK, alpha)
	var paper := Color(Ink.PAPER_CARD, alpha)

	# 俯视双臂伸向桌面（呼应参考图黑西装 + 白袖口/手）
	var left_arm := PackedVector2Array([
		Vector2(-19.0, 2.0) * s,
		Vector2(-22.0, -14.0) * s,
		Vector2(-13.0, -18.0) * s,
		Vector2(-11.0, -3.0) * s
	])
	var right_arm := PackedVector2Array([
		Vector2(19.0, 2.0) * s,
		Vector2(22.0, -14.0) * s,
		Vector2(13.0, -18.0) * s,
		Vector2(11.0, -3.0) * s
	])
	draw_colored_polygon(left_arm, ink)
	draw_colored_polygon(right_arm, ink)

	# 白色衬衫袖口与手
	draw_circle(Vector2(-15.5, -17.5) * s, 3.3 * s, paper)
	draw_arc(Vector2(-15.5, -17.5) * s, 3.3 * s, 0.0, TAU, 12, ink, 1.3, true)
	draw_circle(Vector2(15.5, -17.5) * s, 3.3 * s, paper)
	draw_arc(Vector2(15.5, -17.5) * s, 3.3 * s, 0.0, TAU, 12, ink, 1.3, true)

	# 俯视黑西装宽肩躯干（本人加一条朱红领结/领口边便于一眼认出）
	var torso := PackedVector2Array([
		Vector2(-21.0, 10.0) * s,
		Vector2(-20.0, -4.0) * s,
		Vector2(-10.0, -10.0) * s,
		Vector2(10.0, -10.0) * s,
		Vector2(20.0, -4.0) * s,
		Vector2(21.0, 10.0) * s,
		Vector2(12.0, 14.0) * s,
		Vector2(-12.0, 14.0) * s
	])
	draw_colored_polygon(torso, ink)

	# 白色负空间肩线/领口提亮（Saul Steinberg 钢笔笔触灵魂！）
	draw_line(Vector2(-16.0, -3.0) * s, Vector2(-10.0, -7.5) * s, paper, 1.6 * s, true)
	draw_line(Vector2(16.0, -3.0) * s, Vector2(10.0, -7.5) * s, paper, 1.6 * s, true)
	if is_local:
		# 本人领口一点朱红标识
		draw_line(Vector2(-4.0, -8.5) * s, Vector2(4.0, -8.5) * s, Ink.CRIMSON, 2.6 * s, true)

	# 俯视头顶（按 id 给不同秃顶/礼帽/发际线小变体）
	var head_r := 8.5 * s
	var head_c := Vector2(0.0, 0.0)
	draw_circle(head_c, head_r, paper)
	draw_arc(head_c, head_r, 0.0, TAU, 20, ink, 1.9, true)
	var style := posmod(id, 4)
	if is_local:
		# 本人戴带朱红帽带的冷战礼帽俯视
		draw_circle(head_c, head_r * 0.92, ink)
		draw_arc(head_c, head_r * 0.62, 0.0, TAU, 18, Ink.CRIMSON, 2.0 * s, true)
		draw_line(Vector2(0.0, -head_r * 0.5), Vector2(0.0, head_r * 0.5), paper, 1.4 * s, true)
	elif style == 0:
		# 经典地中海秃顶官僚（参考图最底端那个小人！）
		draw_arc(head_c, head_r * 0.72, 0.25, PI - 0.25, 14, ink, 2.4 * s, true)
	elif style == 1:
		# 整头黑发带一条白分缝
		draw_circle(head_c, head_r * 0.85, ink)
		draw_line(Vector2(-3.0, -head_r * 0.75) * s, Vector2(-1.5, head_r * 0.75) * s, paper, 1.7 * s, true)
	elif style == 2:
		# 礼帽俯视
		draw_circle(head_c, head_r * 0.95, ink)
		draw_arc(head_c, head_r * 0.60, 0.0, TAU, 16, paper, 1.2 * s, true)
	else:
		# 几根倔强的稀疏黑发
		draw_line(Vector2(-4.5, -2.0) * s, Vector2(4.5, -1.5) * s, ink, 1.3 * s, true)
		draw_line(Vector2(-4.0, 1.5) * s, Vector2(4.0, 2.2) * s, ink, 1.3 * s, true)

	# 命中时头顶冒朱红冷汗/惊叹线
	if is_hit:
		var burst_col := Ink.INK if hit_defended else Ink.CRIMSON
		var rays: Array[float] = [-1.0, 0.0, 1.0]
		for k: float in rays:
			var bx: float = k * 10.0 * s
			var by: float = 16.0 * s
			Ink.draw_pen_line(self, Vector2(bx, by), Vector2(bx + k * 5.0 * s, by + 8.0 * s),
				burst_col, 2.0, id * 31 + _boil_frame, 0.5, 0.0)

	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_pointer_and_hub(center: Vector2, radius: float) -> void:
	var hub_r := radius * 0.255
	var dir := Vector2.from_angle(needle_angle)
	var perp := dir.orthogonal()

	# 1. 轮盘指针（先画阴影再画主体，针尖直指扇区外缘）
	var tip := center + dir * (radius * 0.85)
	var tail := center - dir * (hub_r * 1.18)
	var wing_l := center + dir * (radius * 0.56) + perp * 7.5
	var wing_r := center + dir * (radius * 0.56) - perp * 7.5
	var needle := PackedVector2Array([tail, wing_l, tip, wing_r])

	var shadow := PackedVector2Array()
	shadow.resize(needle.size())
	for i in range(needle.size()):
		shadow[i] = needle[i] + Vector2(3.5, 4.5)
	draw_colored_polygon(shadow, Color(Ink.INK, 0.16))
	draw_colored_polygon(needle, Ink.CRIMSON)
	var outline := needle.duplicate()
	outline.append(needle[0])
	draw_polyline(outline, Ink.INK, 1.7, true)
	# 指针中脊高光白线
	draw_line(center + dir * (hub_r * 1.05), center + dir * (radius * 0.72), Color(Ink.PAPER_CARD, 0.65), 1.1, true)

	# 2. 中央圆盘枢纽（干练的黑白圆盘 + 倒计时朱红进度环）
	var hub_shadow := _circle_points(center + Vector2(2.5, 3.5), hub_r, 0.0, TAU, 48, 0.002)
	draw_colored_polygon(hub_shadow.slice(0, hub_shadow.size() - 1), Color(Ink.INK, 0.15))

	var hub_ring := _circle_points(center, hub_r, 0.0, TAU, 52, 0.004)
	draw_colored_polygon(hub_ring.slice(0, hub_ring.size() - 1), Ink.PAPER_CARD)
	draw_polyline(hub_ring, Ink.INK, 2.2, true)

	# 倒计时期间在中心圆环内圈画一道清晰朱红剩余时间弧
	if countdown_seconds >= 0 and countdown_ratio > 0.0:
		var urgent := countdown_seconds <= 5
		var arc_col := Ink.CRIMSON if urgent else Color(Ink.INK, 0.72)
		var sweep := TAU * clampf(countdown_ratio, 0.0, 1.0)
		draw_arc(center, hub_r - 5.0, -PI * 0.5, -PI * 0.5 + sweep, 40, arc_col, 3.2 if urgent else 2.2, true)
	else:
		draw_arc(center, hub_r - 5.0, 0.0, TAU, 36, Color(Ink.RULE, 0.7), 1.0, true)

	# 中心读数：主数字（步数/位移/初始号）+ 小字注记
	var num_font := display_font if display_font != null else _ui_font
	var reading_size := clampi(roundi(hub_r * 0.58 * number_scale), 16, 40)
	var reading_col := Ink.CRIMSON if (target_index >= 0 or center_caption == "最终位移") else Ink.INK
	Ink.draw_centered_text(self, num_font, center_steps, center + Vector2(0.0, -5.0), reading_size, reading_col)
	if not center_caption.is_empty():
		Ink.draw_centered_text(self, _ui_font, center_caption, center + Vector2(0.0, hub_r * 0.44), 11, Ink.INK_SOFT)

func _draw_table_cards(center: Vector2, radius: float) -> void:
	var card_w := clampf(radius * 0.19, 28.0, 42.0)
	var card_size := Vector2(card_w, card_w * 1.34)
	for index in range(seats.size()):
		var id: int = int(seats[index]["id"])
		var cards: Dictionary = table_cards.get(id, {})
		if cards.is_empty():
			continue
		var angle := seat_angle(index)
		var dir := Vector2.from_angle(angle)
		var tangent := dir.orthogonal()
		for slot in range(2):
			if not cards.has(slot):
				continue
			var card: Dictionary = cards[slot]
			if bool(card.get("discard", false)) and play_progress >= 0.5:
				continue
			# 避开扇区中心指针线，放在扇区偏侧或并排两张
			var side_offset := (float(slot) - 0.5) * (card_w + 8.0) if cards.size() > 1 else card_w * 0.55
			var pos := center + dir * (radius * 0.62) + tangent * side_offset
			var xform := Transform2D(angle - PI * 0.5, pos)
			var extent := card_size

			if id == local_player_id and _placements.has(slot):
				var placement: Dictionary = _placements[slot]
				var t: float = float(placement["progress"])
				var origin := get_global_transform().affine_inverse() * Vector2(placement["origin"])
				var start_xf := Transform2D(float(placement["angle"]), origin)
				xform = start_xf.interpolate_with(xform, t)
				extent = Vector2(placement["extent"]).lerp(extent, t)

			var face_up: bool = bool(card.get("face_up", false))
			if bool(card.get("flip", false)) or bool(card.get("discard", false)):
				extent.x = maxf(3.0, extent.x * absf(cos(play_progress * PI)))
				face_up = face_up and play_progress >= 0.5

			_draw_table_card(xform, extent, card, face_up)

func _draw_table_card(xform: Transform2D, extent: Vector2, card: Dictionary, face_up: bool) -> void:
	var rect := Rect2(-extent * 0.5, extent)
	var shadow_xf := xform
	shadow_xf.origin += Vector2(2.5, 3.0)
	draw_set_transform_matrix(shadow_xf)
	draw_rect(rect, Color(Ink.INK, 0.22), true)
	draw_set_transform_matrix(xform)
	if face_up:
		_draw_card_face_mini(rect, card, true)
	else:
		_draw_card_back_mini(rect, 1)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_seat_plates(center: Vector2, radius: float) -> void:
	var count := seats.size()
	var compact := count > 8
	var card_w := 22.0 if compact else (25.0 if count > 5 else 28.0)
	var card_h := card_w * 1.28
	var card_gap := 4.0
	var max_cols := 5 if compact else 6

	# 为每个非本人席位先算理想外轨道中心，再做屏幕裁切保护与轻量垂直避让
	var entries: Array[Dictionary] = []
	for i in range(count):
		var seat: Dictionary = seats[i]
		var id: int = int(seat["id"])
		var angle := seat_angle(i)
		var is_local := id == local_player_id
		if is_local:
			_draw_local_rim_badge(center, radius, seat, i == target_index)
			continue

		var raw_cards: Array = seat.get("cards", [])
		var visible_cards: Array = []
		for c_var in raw_cards:
			var c: Dictionary = c_var
			if showing_actions and play_progress >= 0.5 and bool(c.get("played", false)):
				continue
			visible_cards.append(c)

		var num_cards := visible_cards.size()
		var cols := clampi(num_cards, 1, max_cols)
		var rows := maxi(1, ceili(float(num_cards) / float(max_cols)))
		var cards_block_w := float(cols) * card_w + float(maxi(0, cols - 1)) * card_gap
		var cards_block_h := float(rows) * card_h + float(maxi(0, rows - 1)) * 4.0 if num_cards > 0 else 18.0
		var header_h := 24.0
		var plate_w := maxf(138.0 if compact else 156.0, cards_block_w + 20.0)
		var plate_h := header_h + cards_block_h + 16.0

		var dir := Vector2.from_angle(angle)
		# 横向椭圆外推：充分利用 16:10 宽屏左右留白，避免上下挤压
		var orbit_x := radius + 44.0 + plate_w * 0.52
		var orbit_y := radius + 34.0 + plate_h * 0.50
		var anchor := center + Vector2(dir.x * orbit_x, dir.y * orbit_y)

		var min_x := 18.0
		var max_x := maxf(min_x, size.x - plate_w - 18.0)
		var min_y := 92.0
		var max_y := maxf(min_y, size.y - plate_h - 148.0)
		var pos := Vector2(
			clampf(anchor.x - plate_w * 0.5, min_x, max_x),
			clampf(anchor.y - plate_h * 0.5, min_y, max_y)
		)

		entries.append({
			"index": i,
			"id": id,
			"seat": seat,
			"angle": angle,
			"dir": dir,
			"cards": visible_cards,
			"rect": Rect2(pos, Vector2(plate_w, plate_h)),
			"header_h": header_h,
			"max_cols": max_cols,
			"card_w": card_w,
			"card_h": card_h,
			"card_gap": card_gap,
			"side": -1 if dir.x < -0.15 else (1 if dir.x > 0.15 else 0)
		})

	# 简单的左右两侧垂直避让（保证 8～12 人也绝不互相遮盖）
	var sides: Array[int] = [-1, 1]
	for side: int in sides:
		var group: Array[Dictionary] = []
		for e in entries:
			if int(e["side"]) == side:
				group.append(e)
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["rect"] as Rect2).position.y < (b["rect"] as Rect2).position.y)
		for k in range(1, group.size()):
			var prev_r: Rect2 = group[k - 1]["rect"]
			var curr_r: Rect2 = group[k]["rect"]
			var overlap := prev_r.end.y + 8.0 - curr_r.position.y
			if overlap > 0.0:
				curr_r.position.y = minf(size.y - curr_r.size.y - 118.0, curr_r.position.y + overlap)
				group[k]["rect"] = curr_r
		# 如果底部被推紧，再从下往上匀一下
		for k in range(group.size() - 2, -1, -1):
			var next_r: Rect2 = group[k + 1]["rect"]
			var curr_r: Rect2 = group[k]["rect"]
			var overlap := curr_r.end.y + 8.0 - next_r.position.y
			if overlap > 0.0:
				curr_r.position.y = maxf(90.0, curr_r.position.y - overlap)
				group[k]["rect"] = curr_r

	# 绘制每个对手的直立明牌档案卡 + 细钢笔引线
	for e in entries:
		var rect: Rect2 = e["rect"]
		var seat: Dictionary = e["seat"]
		var idx: int = int(e["index"])
		var id: int = int(e["id"])
		var dir: Vector2 = e["dir"]
		var alive: bool = seat.get("alive", true)
		var is_hit := idx == target_index
		var is_start := idx == start_index
		var is_hover := id == _hovered_seat_id
		_seat_plate_rects[id] = rect

		# 细铅笔引线：连接席位卡近端与对应官僚
		var rim_anchor := center + dir * (radius + 26.0)
		var closest := Vector2(
			clampf(rim_anchor.x, rect.position.x, rect.end.x),
			clampf(rim_anchor.y, rect.position.y, rect.end.y)
		)
		if rim_anchor.distance_to(closest) > 6.0:
			var wire_col := Ink.CRIMSON if is_hit else Color(Ink.INK, 0.35)
			draw_line(rim_anchor, closest, wire_col, 1.3 if is_hit else 1.0, true)
			draw_circle(rim_anchor, 2.5, wire_col)

		# 卡片背景与手绘边框
		var alpha := 1.0 if alive else 0.55
		var bg := Color("fdf2f3", alpha) if is_hit else (Color("f7f2e3", alpha) if is_hover else Color(Ink.PAPER_CARD, alpha))
		var border_col := Ink.CRIMSON if (is_hit or is_hover) else Color(Ink.INK, 0.85 * alpha)
		var border_w := 2.2 if (is_hit or is_hover) else 1.5
		if is_hit or is_hover:
			Ink.draw_hatch_shadow(self, rect, Vector2(4.0, 4.0), Color(border_col, 0.28), 4.5)
		Ink.draw_pen_rect(self, rect, bg, border_col, border_w, id * 29 + 7, 0.7, 1.4, false)

		# 顶部标题条（序号 + 名字 + HP / 筹码）
		var header_y := rect.position.y + 16.0
		var name_text := "%02d %s" % [idx + 1, str(seat.get("name", "?")).left(8)]
		var name_col := Ink.CRIMSON if (is_hit or is_start) else Color(Ink.INK, alpha)
		draw_string(_ui_font, Vector2(rect.position.x + 9.0, header_y), name_text,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.56, 13, name_col)

		# 右侧状态标签（HP 菱形点 / 筹码）
		var meta_parts: Array[String] = []
		if seat.has("hp"):
			meta_parts.append("HP %d" % int(seat["hp"]))
		if seat.has("balance"):
			meta_parts.append("%dr" % int(seat["balance"]))
		var meta_str := " · ".join(meta_parts)
		if not meta_str.is_empty():
			var m_font := mono_font if mono_font != null else _ui_font
			var mw := m_font.get_string_size(meta_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var meta_col := Ink.CRIMSON if (seat.has("hp") and int(seat["hp"]) <= 1) else Color(Ink.INK_SOFT, alpha)
			draw_string(m_font, Vector2(rect.end.x - mw - 9.0, header_y), meta_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, meta_col)

		# 标题下极细分隔线
		var sep_y := rect.position.y + float(e["header_h"])
		draw_line(Vector2(rect.position.x + 8.0, sep_y), Vector2(rect.end.x - 8.0, sep_y),
			Color(Ink.RULE, 0.75 * alpha), 1.0, true)

		# 绘制高可读明牌列表
		var visible_cards: Array = e["cards"]
		var cw: float = float(e["card_w"])
		var ch: float = float(e["card_h"])
		var gap: float = float(e["card_gap"])
		var cols_limit: int = int(e["max_cols"])
		var dealt_id: int = int(seat.get("dealt_id", -1))

		if visible_cards.is_empty():
			Ink.draw_centered_text(self, _ui_font, "无手牌",
				Vector2(rect.get_center().x, sep_y + (rect.end.y - sep_y) * 0.5), 11, Color(Ink.INK_SOFT, 0.7))
		else:
			for ci in range(visible_cards.size()):
				var card: Dictionary = visible_cards[ci]
				@warning_ignore("integer_division")
				var row: int = ci / cols_limit
				var col: int = ci % cols_limit
				var row_count := mini(cols_limit, visible_cards.size() - row * cols_limit)
				var row_w := float(row_count) * cw + float(maxi(0, row_count - 1)) * gap
				var start_x := rect.get_center().x - row_w * 0.5
				var cx := start_x + float(col) * (cw + gap)
				var cy := sep_y + 7.0 + float(row) * (ch + 4.0)
				var c_rect := Rect2(Vector2(cx, cy), Vector2(cw, ch))

				if deal_progress < 1.0 and int(card.get("id", -2)) == dealt_id:
					var delay := 0.28 * float(idx) / float(maxi(1, count - 1))
					var flight := clampf((deal_progress - delay) / 0.68, 0.0, 1.0)
					if flight < 1.0:
						if flight > 0.0:
							_opponent_deals.append({
								"target": Transform2D(0.0, c_rect.get_center()),
								"extent": c_rect.size,
								"card": card,
								"progress": flight
							})
						continue

				if bool(card.get("face_up", false)):
					_draw_card_face_mini(c_rect, card, false, alpha)
				else:
					_draw_card_back_mini(c_rect, int(card.get("quantity", 1)), alpha)

		# 命中或防御状态小印章
		if is_hit:
			var stamp_txt := "已防御" if hit_defended else "命 中"
			var stamp_col := Ink.INK if hit_defended else Ink.CRIMSON
			Ink.draw_rubber_stamp(self, Vector2(rect.end.x - 28.0, rect.position.y + 4.0),
				stamp_txt, _ui_font, 11, stamp_col, 8.0, id + 50, Ink.PAPER_CARD)

func _draw_local_rim_badge(center: Vector2, radius: float, seat: Dictionary, is_hit: bool) -> void:
	# 本人（6点钟位置）的精炼名牌条，紧贴桌下沿，手牌在下方扇形区显示
	var badge_w := 178.0
	var badge_h := 28.0
	var pos := Vector2(center.x - badge_w * 0.5, center.y + radius + 24.0)
	var rect := Rect2(pos, Vector2(badge_w, badge_h))
	var bg := Color("fdf2f3") if is_hit else Ink.INK
	var fg := Ink.CRIMSON if is_hit else Ink.PAPER_CARD
	Ink.draw_pen_rect(self, rect, bg, Ink.CRIMSON if is_hit else Ink.INK, 1.8, 99, 0.6, 1.2)
	var parts: Array[String] = ["♦ 你"]
	if seat.has("hp"):
		parts.append("HP %d" % int(seat["hp"]))
	if is_hit:
		parts.append("已防御" if hit_defended else "命中!")
	Ink.draw_centered_text(self, _ui_font, "  ·  ".join(parts), rect.get_center(), 13, fg)

func _draw_card_face_mini(rect: Rect2, card: Dictionary, is_table: bool, alpha: float = 1.0) -> void:
	var played: bool = bool(card.get("played", false))
	var fill := Color("fdeeed", alpha) if (played and is_table) else Color(Ink.PAPER_CARD, alpha)
	var ink := Color(Ink.CRIMSON, alpha) if played else Color(Ink.INK, alpha)
	draw_rect(rect, fill, true)
	draw_rect(rect, ink, false, 1.7 if is_table else 1.45)

	var mark := str(card.get("value", ""))
	if played and card.has("caption"):
		mark = str(card["caption"])
	var points := str(card.get("points", ""))
	var f_size := clampi(roundi(rect.size.x * (0.58 if mark.length() <= 2 else 0.38)), 10, 20)
	var font := display_font if (mark.is_valid_int() and display_font != null) else _ui_font
	if points.is_empty():
		Ink.draw_centered_text(self, font, mark, rect.get_center(), f_size, ink)
	else:
		Ink.draw_centered_text(self, _ui_font, mark, rect.get_center() + Vector2(0.0, -rect.size.y * 0.16),
			clampi(roundi(rect.size.x * 0.34), 9, 13), ink)
		Ink.draw_centered_text(self, font, points, rect.get_center() + Vector2(0.0, rect.size.y * 0.18),
			clampi(roundi(rect.size.x * 0.40), 10, 15), Ink.CRIMSON)

func _draw_card_back_mini(rect: Rect2, quantity: int, alpha: float = 1.0) -> void:
	# 实心黑墨暗牌背 + 象牙菱形纹（与参考图黑西装呼应，一眼与白色明牌区分！）
	draw_rect(rect, Color(Ink.INK, alpha), true)
	if rect.size.x >= 10.0:
		draw_rect(rect.grow(-2.5), Color(Ink.PAPER_CARD, 0.75 * alpha), false, 1.0)
		var c := rect.get_center()
		if quantity > 1:
			Ink.draw_diamond(self, c + Vector2(0.0, -rect.size.y * 0.18),
				rect.size.x * 0.18, rect.size.x * 0.24, Color(Ink.CRIMSON, alpha), true)
			Ink.draw_centered_text(self, _ui_font, "×%d" % quantity,
				c + Vector2(0.0, rect.size.y * 0.22), clampi(roundi(rect.size.x * 0.42), 9, 13),
				Color(Ink.PAPER_CARD, alpha))
		else:
			Ink.draw_diamond(self, c, rect.size.x * 0.22, rect.size.x * 0.30, Color(Ink.CRIMSON, alpha), true)

func _deck_transform(center: Vector2, radius: float) -> Transform2D:
	var deck_pos := center + Vector2(-radius * 1.18, radius * 0.72)
	return Transform2D(-0.18, deck_pos)

func _draw_deck(center: Vector2, radius: float) -> void:
	var xf := _deck_transform(center, radius)
	var rect := Rect2(-DECK_SIZE * 0.5, DECK_SIZE)
	for layer in range(3, 0, -1):
		var sheet := xf
		sheet.origin += Vector2(float(layer) * 1.5, float(layer) * 2.2)
		draw_set_transform_matrix(sheet)
		draw_rect(rect, Ink.PAPER_CARD, true)
		draw_rect(rect, Ink.INK, false, 1.2)
	draw_set_transform_matrix(xf)
	_draw_card_back_mini(rect, 1)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_deal_flights(center: Vector2, radius: float) -> void:
	var deck := _deck_transform(center, radius)
	for flight in _opponent_deals:
		_draw_dealing_card(deck, flight["target"], flight["extent"], flight["card"], float(flight["progress"]))
	if not self_deal.is_empty() and float(self_deal.get("progress", 0.0)) > 0.25:
		var progress := smoothstep(0.25, 1.0, float(self_deal["progress"]))
		var to_local := get_global_transform().affine_inverse()
		var target := to_local * Transform2D(float(self_deal["angle"]), Vector2(self_deal["target"]))
		_draw_dealing_card(deck, target, Vector2(self_deal["extent"]), self_deal["card"], progress)

func _draw_dealing_card(deck: Transform2D, target: Transform2D, extent: Vector2,
		card: Dictionary, progress: float) -> void:
	var pose := deck.interpolate_with(target, progress)
	pose.origin.y -= sin(progress * PI) * 32.0
	var card_size := DECK_SIZE.lerp(extent, progress)
	if progress > 0.45 and progress < 0.78:
		var turn := inverse_lerp(0.45, 0.78, progress)
		card_size.x *= maxf(0.08, absf(cos(turn * PI)))
	_draw_table_card(pose, card_size, card, progress >= 0.62)

func _draw_hovered_detail(_center: Vector2) -> void:
	# 当鼠标悬停在某对手档案卡上且其手牌超过 5 张时，在卡片旁弹出大号放大检视卡
	var target_seat: Dictionary = {}
	for s_var in seats:
		var s: Dictionary = s_var
		if int(s.get("id", -1)) == _hovered_seat_id:
			target_seat = s
			break
	if target_seat.is_empty():
		return
	var cards: Array = target_seat.get("cards", [])
	if cards.size() <= 5 or not _seat_plate_rects.has(_hovered_seat_id):
		return
	var base_r: Rect2 = _seat_plate_rects[_hovered_seat_id]
	var cw := 32.0
	var ch := 42.0
	var gap := 6.0
	var cols := mini(cards.size(), 8)
	var rows := ceili(float(cards.size()) / 8.0)
	var pop_w := maxf(200.0, float(cols) * cw + float(cols - 1) * gap + 24.0)
	var pop_h := 34.0 + float(rows) * ch + float(rows - 1) * 6.0 + 16.0
	var px := clampf(base_r.get_center().x - pop_w * 0.5, 16.0, size.x - pop_w - 16.0)
	var py := base_r.position.y - pop_h - 10.0
	if py < 90.0:
		py = base_r.end.y + 10.0
	var pop := Rect2(Vector2(px, py), Vector2(pop_w, pop_h))
	Ink.draw_hatch_shadow(self, pop, Vector2(6.0, 6.0), Color(Ink.INK, 0.25), 5.0)
	Ink.draw_pen_rect(self, pop, Ink.PAPER_CARD, Ink.INK, 2.0, _hovered_seat_id * 11, 0.6, 1.5, true)
	draw_string(_ui_font, pop.position + Vector2(12.0, 22.0),
		"%s  完整公开手牌（%d）" % [str(target_seat.get("name", "?")), cards.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.CRIMSON)
	for i in range(cards.size()):
		@warning_ignore("integer_division")
		var r_idx: int = i / 8
		var c_idx: int = i % 8
		var cr := Rect2(pop.position + Vector2(12.0 + float(c_idx) * (cw + gap), 32.0 + float(r_idx) * (ch + 6.0)), Vector2(cw, ch))
		var c: Dictionary = cards[i]
		if bool(c.get("face_up", false)):
			_draw_card_face_mini(cr, c, false, 1.0)
		else:
			_draw_card_back_mini(cr, int(c.get("quantity", 1)), 1.0)
