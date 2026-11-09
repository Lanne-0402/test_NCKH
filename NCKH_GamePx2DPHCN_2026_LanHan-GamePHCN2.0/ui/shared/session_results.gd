extends Node
const Display = preload("res://ui/shared/session_display.gd")
var summary: Dictionary = {}
var panel: PanelContainer
var source: Label
var content: VBoxContainer
var backdrop: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var level := get_parent()
	panel = level.get_node("UI/ResultPanel")
	source = level.get_node("UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel")
	content = source.get_parent()
	level.get_node("ExerciseSession").session_completed.connect(func(data: Dictionary):
		summary = data.duplicate(true)
		if panel.visible: _refresh())
	panel.theme = preload("res://assets/shared/ui/game_theme.tres")
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.10
	panel.anchor_right = 0.90
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	get_viewport().size_changed.connect(func(): _fit_panel_height.call_deferred())
	source.hide()
	content.add_theme_constant_override("separation", 10)
	content.minimum_size_changed.connect(panel.queue_sort)
	var old_button: Button = content.get_node("ResultButton")
	# Keep the scene's signal target intact, but remove this redundant navigation from the UI.
	old_button.hide()
	old_button.focus_mode = Control.FOCUS_NONE
	var margin: MarginContainer = content.get_parent()
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 22)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	backdrop = ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.025, 0.8)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.get_parent().add_child(backdrop)
	panel.get_parent().move_child(backdrop, panel.get_index())
	backdrop.hide()
	panel.visibility_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	backdrop.visible = panel.visible
	if not panel.visible: return
	for child in content.get_children():
		if child.has_meta("result_generated"):
			content.remove_child(child)
			child.queue_free()
	_insert(_label(Display.status(summary).to_upper() if summary.has("status") else "KẾT QUẢ BUỔI TẬP", 26), 0)
	var scroll := ScrollContainer.new()
	scroll.name = "SummaryScroll"
	scroll.custom_minimum_size.y = 80
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_insert(scroll, 1)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	body.minimum_size_changed.connect(func(): _fit_panel_height.call_deferred())
	if summary.is_empty():
		body.add_child(_label(source.text, 20))
		body.add_child(_label("Chưa có bản tổng hợp chi tiết cho buổi tập này.", 18))
	else:
		body.add_child(_label("Map %s · Mức %s" % [Display.number(summary,"map_id"), Display.number(summary,"difficulty")], 22))
		body.add_child(_label("Hợp lệ: %s · Chưa hợp lệ: %s" % [Display.number(summary,"valid_reps"), Display.number(summary,"rejected_reps")], 20))
		body.add_child(_metrics([
			"Số lần hoàn thành / mục tiêu: %s / %s" % [Display.number(summary,"completed_reps"), Display.number(summary,"target_reps")],
			"Số hiệp: %s / %s" % [Display.number(summary,"completed_sets"), Display.number(summary,"target_sets")],
		], 18))
		var ratio := Display.progress_ratio(summary)
		if ratio >= 0:
			var bar := ProgressBar.new()
			bar.value = ratio * 100
			bar.custom_minimum_size.y = 22
			bar.tooltip_text = "Tiến độ số lần thực hiện, không phải điểm chất lượng động tác."
			body.add_child(bar)
		var highlights := ["Thời gian tập: " + Display.duration(summary,"active_seconds")]
		if summary.has("bonus_points"): highlights.append("Điểm thưởng: " + Display.number(summary,"bonus_points"))
		body.add_child(_metrics(highlights, 20))
		var evaluation := str(summary.get("evaluation", "")).strip_edges()
		if not evaluation.is_empty() and evaluation.to_upper() != Display.status(summary).to_upper():
			body.add_child(_label("Đánh giá trong game: " + evaluation, 18))
		for line in source.text.split("\n", false):
			if line.begins_with("Cấp độ tiếp theo") or line.begins_with("Chưa mở cấp độ") or line.begins_with("Đã hoàn thành cấp độ"):
				body.add_child(_label(line, 18))
	if not summary.is_empty():
		var detail := VBoxContainer.new()
		detail.name = "AdditionalDetails"
		detail.add_theme_constant_override("separation", 8)
		detail.hide()
		# Only supplementary data here; goals and active time already appear above.
		detail.add_child(_label(Display.profile(summary), 18))
		detail.add_child(_metrics([
			"Nghỉ giữa hiệp\n" + Display.duration(summary,"rest_seconds"),
			"Tạm dừng\n" + Display.duration(summary,"paused_seconds"),
			"Mất nhận diện\n" + Display.duration(summary,"tracking_lost_seconds"),
		], 18))
		if str(summary.get("duration_source", "")) == "godot_state_timer":
			detail.add_child(_label("Thời gian tập gồm cả lúc chờ vùng động tác; các khoảng thời gian do game ghi nhận.", 16))
		var toggle := Button.new()
		toggle.name = "DetailsToggle"
		toggle.text = "XEM CHI TIẾT"
		toggle.toggle_mode = true
		toggle.custom_minimum_size.y = 40
		toggle.toggled.connect(func(open: bool):
			detail.visible = open
			toggle.text = "THU GỌN" if open else "XEM CHI TIẾT")
		body.add_child(toggle)
		body.add_child(detail)
	var actions := HBoxContainer.new()
	actions.name = "ResultActions"
	actions.add_theme_constant_override("separation", 10)
	_insert(actions, content.get_child_count())
	for action in [["TẬP LẠI", ""], ["CHỌN MAP", "res://ui/screens/map_selection/level_selection.tscn"], ["LỊCH SỬ", "res://ui/screens/history/history_screen.tscn"]]:
		var button := Button.new()
		button.text = action[0]
		button.custom_minimum_size = Vector2(150, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		var path: String = action[1]
		button.pressed.connect(func():
			get_tree().paused = false
			AudioManager.stop_music()
			AudioManager.stop_all_sfx()
			if path.is_empty(): get_tree().reload_current_scene()
			else: get_tree().change_scene_to_file(path))
		actions.add_child(button)
		if path.is_empty(): button.grab_focus()
	panel.queue_sort.call_deferred()
	_fit_panel_height.call_deferred()

func _fit_panel_height() -> void:
	if not panel.visible or not content.has_node("SummaryScroll"): return
	var scroll: ScrollContainer = content.get_node("SummaryScroll")
	if scroll.get_child_count() == 0: return
	var body: Control = scroll.get_child(0)
	var chrome_height := panel.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	var wanted := chrome_height + maxf(80.0, body.get_combined_minimum_size().y)
	var height := maxf(panel.get_combined_minimum_size().y, minf(wanted, get_viewport().get_visible_rect().size.y * 0.88))
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.queue_sort()

func _metrics(values: Array, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for value in values:
		var item := _label(str(value), font_size)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)
	return row

func _insert(control: Control, index: int) -> void:
	control.set_meta("result_generated", true)
	content.add_child(control)
	content.move_child(control, index)

func _label(value: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", font_size)
	return item
