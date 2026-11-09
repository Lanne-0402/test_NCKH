class_name RomLineChart
extends PanelContainer

const Data := preload("res://core/autoload/report_data.gd")
const INK := Color("293d32")
const GREEN := Color("28664d")
const RED := Color("b64d3b")
const GOLD := Color("926516")
const BLUE := Color("426c83")
var _points: Array = []
var _baseline: Variant = null
var _target: Variant = null
var _unit := "index"
var _legacy := true
var _context := ""
var _total := 0
var _heading: Label
var _caption: Label
var _summary: GridContainer
var _values: Array[Label] = []
var _legend: HFlowContainer
var _plot: Control
var _empty: Label
var _note: Label

func _ready() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("ece6d0")
	frame.border_color = Color("a78b59")
	frame.set_border_width_all(2)
	frame.content_margin_left = 18
	frame.content_margin_right = 18
	frame.content_margin_top = 16
	frame.content_margin_bottom = 16
	add_theme_stylebox_override("panel", frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_heading = _label("BIỂU ĐỒ TIẾN TRÌNH ROM", 22)
	column.add_child(_heading)
	_caption = _label("", 16)
	column.add_child(_caption)
	_summary = GridContainer.new()
	_summary.columns = 3
	_summary.add_theme_constant_override("h_separation", 10)
	_summary.add_theme_constant_override("v_separation", 8)
	column.add_child(_summary)
	var titles := ["HIỆU CHUẨN BAN ĐẦU", "BUỔI TẬP GẦN NHẤT", "NGƯỠNG MỤC TIÊU"]
	var colors := [RED, GREEN, GOLD]
	for i in range(3):
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e2d8b8")
		style.border_color = colors[i]
		style.border_width_top = 3
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", style)
		_summary.add_child(card)
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(_label(titles[i], 15))
		var value := _label("—", 25)
		value.add_theme_color_override("font_color", colors[i])
		box.add_child(value)
		_values.append(value)
	_legend = HFlowContainer.new()
	_legend.add_theme_constant_override("h_separation", 22)
	_legend.add_theme_constant_override("v_separation", 6)
	column.add_child(_legend)
	_plot = Control.new()
	_plot.name = "Plot"
	_plot.custom_minimum_size.y = 228
	_plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plot.draw.connect(_draw_plot)
	_plot.resized.connect(_plot.queue_redraw)
	column.add_child(_plot)
	_empty = _label("", 18)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plot.add_child(_empty)
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_note = _label("", 16)
	column.add_child(_note)
	resized.connect(func(): _summary.columns = 1 if size.x < 560 else 3)
	_update_ui()

# Backward-compatible adapter: old calibration indices are NOT session ROM or degrees.
func set_rom_points(points: Array, _legacy_sessions: Array = []) -> void:
	var calibrated := Data.calibration_points(points)
	_total = calibrated.size()
	_points = calibrated.slice(maxi(0, calibrated.size() - 8))
	_baseline = null
	_target = null
	_unit = "index"
	_legacy = true
	_context = "Hiệu chuẩn theo ngày · Chỉ số trong game"
	_update_ui()

# FE-only contract. BE supplies one patient/exercise/metric series at a time.
func set_progress_data(payload: Dictionary) -> void:
	_legacy = false
	_unit = "degrees" if str(payload.get("unit", "index")) == "degrees" else "index"
	_context = str(payload.get("context_label", ""))
	_baseline = _valid_value(payload.get("baseline"))
	_target = _valid_value(payload.get("target"))
	_points = []
	var sessions: Variant = payload.get("sessions", [])
	if not sessions is Array: sessions = []
	for entry in sessions:
		if not entry is Dictionary: continue
		var value: Variant = _valid_value(entry.get("value"))
		if value == null: continue
		_points.append({"rom_angle": value, "date": str(entry.get("date", "")), "ordinal": _points.size() + 1})
	_total = _points.size()
	_points = _points.slice(maxi(0, _points.size() - 8))
	_update_ui()

func _valid_value(value: Variant) -> Variant:
	if not (value is float or value is int): return null
	if not is_finite(float(value)) or float(value) < 0: return null
	return float(value)

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	return label

func _format(value: Variant) -> String:
	return "—" if value == null else "%.1f%s" % [float(value), "°" if _unit == "degrees" else ""]

func _update_ui() -> void:
	if _heading == null: return
	_summary.visible = not _legacy or _points.is_empty()
	_caption.text = _context if not _context.is_empty() else "So sánh hiệu chuẩn ban đầu với từng buổi tập"
	_values[0].text = _format(_baseline)
	_values[1].text = _format(_points[-1].rom_angle) if not _legacy and not _points.is_empty() else "—"
	_values[2].text = _format(_target)
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()
	if _legacy and not _points.is_empty():
		_add_key("●  Hiệu chuẩn theo ngày", BLUE)
	else:
		_add_key("●  Ban đầu", RED)
		_add_key("▥  Buổi tập thực tế", GREEN)
		_add_key("– –  Ngưỡng mục tiêu", GOLD)
	_empty.visible = _points.is_empty() and _baseline == null
	_empty.text = "CHƯA CÓ DỮ LIỆU BIỂU ĐỒ\nHiệu chuẩn và kết quả buổi tập sẽ xuất hiện tại đây."
	if _legacy:
		_note.text = "Chỉ số hiệu chuẩn chưa phải ROM của buổi tập hoặc góc khớp đo thô. Dữ liệu cũ vẫn được giữ trong lịch sử."
	else:
		_note.text = "Đơn vị: độ (°)." if _unit == "degrees" else "Đơn vị: chỉ số trong game, không phải góc khớp đo thô."
		if _target == null: _note.text += " Chưa có ngưỡng mục tiêu."
		if _baseline == null: _note.text += " Chưa có mốc ban đầu."
		if _points.size() == 1: _note.text += " Mới có 1 buổi; chưa đủ để kết luận xu hướng."
	if _total > 8: _note.text += " Hiển thị 8 mốc gần nhất / %d mốc." % _total
	_plot.queue_redraw()

func _add_key(text: String, color: Color) -> void:
	var key := _label(text, 16)
	key.autowrap_mode = TextServer.AUTOWRAP_OFF
	key.add_theme_color_override("font_color", color)
	_legend.add_child(key)

func _draw_plot() -> void:
	if _empty.visible: return
	var font := ThemeDB.fallback_font
	var area := Rect2(54, 25, maxf(_plot.size.x - 76, 1), _plot.size.y - 80)
	var maximum := 1.0
	for point in _points: maximum = maxf(maximum, float(point.rom_angle))
	if _baseline != null: maximum = maxf(maximum, float(_baseline))
	if _target != null: maximum = maxf(maximum, float(_target))
	var step := maxf(1.0, ceilf(maximum / 4.0 / 5.0) * 5.0)
	var ceiling := step * 4.0
	for i in range(5):
		var y := area.end.y - area.size.y * i / 4.0
		_plot.draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color("cdc4a8"))
		_plot.draw_string(font, Vector2(0, y + 5), "%d%s" % [int(i * step), "°" if _unit == "degrees" else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
	if _target != null:
		var target_y := area.end.y - area.size.y * float(_target) / ceiling
		_plot.draw_dashed_line(Vector2(area.position.x, target_y), Vector2(area.end.x, target_y), GOLD, 2.0, 7.0)
	var entries: Array = []
	if _baseline != null: entries.append({"value": _baseline, "label": "Ban đầu", "date": "", "baseline": true})
	for point in _points:
		entries.append({"value": point.rom_angle, "label": _short(point.date) if _legacy else "Buổi %d" % int(point.ordinal), "date": "" if _legacy else _short(point.date), "baseline": false})
	var spacing := area.size.x / maxf(entries.size(), 1)
	var coords := PackedVector2Array()
	for i in range(entries.size()):
		var x := area.position.x + spacing * (i + 0.5)
		if _legacy and _points.size() > 1:
			var first_day := Time.get_unix_time_from_datetime_string(str(_points[0].date) + "T00:00:00")
			var last_day := Time.get_unix_time_from_datetime_string(str(_points[-1].date) + "T00:00:00")
			var current_day := Time.get_unix_time_from_datetime_string(str(_points[i].date) + "T00:00:00")
			var ratio := float(current_day - first_day) / maxf(float(last_day - first_day), 1)
			x = area.position.x + spacing / 2 + (area.size.x - spacing) * ratio
		coords.append(Vector2(x, area.end.y - area.size.y * float(entries[i].value) / ceiling))
	# Lines only join actual session points; baseline remains a distinct reference dot.
	var session_coords := coords.slice(1) if _baseline != null else coords
	if session_coords.size() > 1: _plot.draw_polyline(session_coords, BLUE if _legacy else GREEN, 2.0, true)
	var stride := maxi(1, int(ceilf(70.0 / maxf(spacing, 1))))
	var last_label_x := -100.0
	for i in range(entries.size()):
		var pos := coords[i]
		var entry: Dictionary = entries[i]
		var color := RED if entry.baseline else (BLUE if _legacy else GREEN)
		if not entry.baseline and not _legacy:
			var bar_width := minf(30, spacing * 0.4)
			_plot.draw_rect(Rect2(pos.x - bar_width/2, pos.y, bar_width, area.end.y-pos.y), Color(GREEN, 0.22))
		_plot.draw_circle(pos, 5, color)
		if not entry.baseline: _plot.draw_circle(pos, 2, Color("ece6d0"))
		if i % stride != 0 and i != entries.size()-1: continue
		if _legacy:
			if pos.x - last_label_x < 70: continue
			if i != entries.size()-1 and coords[-1].x - pos.x < 70: continue
		last_label_x = pos.x
		_plot.draw_string(font, Vector2(pos.x - spacing/2, pos.y - 9), _format(entry.value), HORIZONTAL_ALIGNMENT_CENTER, spacing, 15, color)
		_plot.draw_string(font, Vector2(pos.x - spacing/2, area.end.y + 23), entry.label, HORIZONTAL_ALIGNMENT_CENTER, spacing, 15, INK)
		if not str(entry.date).is_empty(): _plot.draw_string(font, Vector2(pos.x - spacing/2, area.end.y + 43), entry.date, HORIZONTAL_ALIGNMENT_CENTER, spacing, 14, INK)

func _short(date: String) -> String:
	return date.substr(8, 2) + "/" + date.substr(5, 2) if date.length() >= 10 else ""
