@tool
extends Control
## 房间大厅的单个成员档案行（手绘官僚剪影头像 + 昵称/身份 + 倾斜状态橡皮章）

const Ink = preload("res://scripts/ui/editorial_ink.gd")

var member_id: int = 1
var member_name: String = "a"
var is_local: bool = false
var is_owner: bool = false
var is_ready: bool = false
var is_online: bool = true
var seat_number: int = 1

func _ready() -> void:
	custom_minimum_size = Vector2(0, 58)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)

func setup(p_seat: int, data: Dictionary, local_id: int, owner_id: int) -> void:
	seat_number = p_seat
	member_id = int(data.get("id", 0))
	member_name = str(data.get("name", "?"))
	is_local = member_id == local_id
	is_owner = member_id == owner_id and owner_id != 0
	is_ready = bool(data.get("ready", false))
	is_online = bool(data.get("online", true))
	queue_redraw()

func _draw() -> void:
	if size.x < 100.0 or size.y < 30.0:
		return
	var font := get_theme_default_font()
	var rect := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	var bg := Ink.PAPER_TINT if not is_online else (Color("f7f2e5") if is_local else Ink.PAPER_CARD)
	var border := Color(Ink.INK, 0.35) if not is_online else Ink.INK
	Ink.draw_pen_rect(self, rect, bg, border, 1.6 if is_local else 1.25, member_id * 19 + 5, 0.75, 1.4, false)

	# 左侧席位序号
	if font != null:
		Ink.draw_centered_text(self, font, "%02d" % seat_number, Vector2(22.0, size.y * 0.5), 13, Ink.INK_SOFT)

	# 钢笔冷战官僚小头像
	Ink.draw_bureaucrat_avatar(self, Vector2(58.0, size.y * 0.5), 18.0, member_id, is_owner, not is_online)

	# 名称与身份小注
	if font != null:
		var text_x := 90.0
		var name_color := Color(Ink.INK, 0.45) if not is_online else Ink.INK
		var display_name := member_name
		if is_local:
			display_name += "  (你)"
		var baseline_top := size.y * 0.5 - 1.0
		draw_string(font, Vector2(text_x, baseline_top), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_color)

		# 次级身份标签（房主 / 离线 / 席位代表）
		var tags: Array[String] = []
		if is_owner:
			tags.append("♦ 会议主持（房主）")
		else:
			tags.append("圆桌代表")
		if not is_online:
			tags.append("连接中断 · 离线")
		var sub_color := Ink.CRIMSON if is_owner and is_online else Ink.INK_SOFT
		draw_string(font, Vector2(text_x, baseline_top + 18.0), "  ·  ".join(tags),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sub_color)

		# 右侧状态橡皮章
		var stamp_center := Vector2(size.x - 66.0, size.y * 0.5)
		if not is_online:
			Ink.draw_rubber_stamp(self, stamp_center, "离 线", font, 12, Color(Ink.INK_SOFT, 0.65), -4.0, member_id + 90)
		elif is_ready:
			Ink.draw_rubber_stamp(self, stamp_center, "已就绪", font, 13, Ink.CRIMSON, -5.0, member_id + 40, Color(Ink.CRIMSON, 0.06))
		else:
			Ink.draw_rubber_stamp(self, stamp_center, "未准备", font, 12, Ink.INK_SOFT, 2.0, member_id + 70)
