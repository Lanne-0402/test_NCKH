extends Control

const CALIBRATION_EXERCISE_ID := "scapular_retraction"
const CALIBRATION_DURATION_MS := 5000

var _patient_id := ""
var _started_ms := 0
var _last_tracking_ms := -10000
var is_calibrating := false
var _tracking_available := false
var _session_id := ""
var _using_mock := true
var _calibration_success := false
var _last_frame_ms := -10000
var _camera_view: TextureRect
var _camera_texture: ImageTexture
var _technical_overlay: Control
var _adapt_callback: Callable

@onready var introduce: Label = %Introduce
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var start_button: Button = %StartCalibButton
@onready var next_button: Button = %NextButton
@onready var connection_label: Label = %PoseStatusPanel/MarginContainer/VBoxContainer/ConnectionLabel
@onready var tracking_label: Label = %PoseStatusPanel/MarginContainer/VBoxContainer/TrackingLabel
@onready var confidence_label: Label = %PoseStatusPanel/MarginContainer/VBoxContainer/ConfidenceLabel
@onready var feedback_label: Label = %PoseStatusPanel/MarginContainer/VBoxContainer/FeedbackLabel


func _ready() -> void:
	if PoseInput.has_method("end_offline_preview"):
		PoseInput.end_offline_preview()
	_using_mock = "mock" in str(PoseInput.get_script().resource_path).to_lower()
	_build_presentation()
	_setup_camera_preview()
	if PoseInput.has_signal("camera_frame_received"):
		PoseInput.connect("camera_frame_received", _on_camera_frame_received)
	PoseInput.connection_changed.connect(_on_connection_changed)
	PoseInput.tracking_status_changed.connect(_on_tracking_status_changed)
	PoseInput.calibration_progressed.connect(_on_calibration_progressed)
	PoseInput.calibration_finished.connect(_on_calibration_finished)
	PoseInput.provider_error_received.connect(_on_provider_error_received)

	progress_bar.value = 0.0
	next_button.disabled = true
	_update_connection_ui(PoseInput.provider_connected)

	if Time.get_ticks_msec() - PoseInput.last_tracking_received_ms < 3000 and not PoseInput.last_tracking_status.is_empty():
		_on_tracking_status_changed(PoseInput.last_tracking_status)
	else:
		_update_start_button()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_technical_overlay) and _technical_overlay.visible:
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			_toggle_technical_info()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if OS.is_debug_build() and (event.physical_keycode == KEY_P or event.keycode == KEY_P):
		get_viewport().set_input_as_handled()
		_enter_offline_preview.call_deferred()
		return
	if event.keycode == KEY_F3:
		_toggle_technical_info()


func _on_start_calib_button_pressed() -> void:
	_update_start_button()
	if start_button.disabled: return
	if not PoseInput.provider_connected:
		_show_warning("Không có kết nối với hệ thống nhận diện.")
		return
	if not _tracking_available:
		_show_warning("Camera chưa nhận diện đủ cơ thể người chơi.")
		return

	is_calibrating = true
	_patient_id = Global.current_patient_id
	_started_ms = Time.get_ticks_msec()
	_calibration_success = false
	%RomLabel.text = "Chỉ số hiện tại: —"
	%ProgressCaption.text = "Thời gian thu mẫu: 0.0 / 5.0 giây"
	_session_id = "calibration-" + Crypto.new().generate_random_bytes(12).hex_encode()
	progress_bar.value = 0.0
	start_button.disabled = true
	next_button.disabled = true
	introduce.text = "Đang đo: giữ tư thế theo hướng dẫn. Chỉ tích lũy khi mẫu hợp lệ."
	introduce.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))

	PoseInput.start_calibration({
		"session_id": _session_id,
		"exercise_id": CALIBRATION_EXERCISE_ID,
		"duration_ms": CALIBRATION_DURATION_MS,
		"target_side": "both",
		"camera_view": "front",
	})


func _on_connection_changed(connected: bool, details: Dictionary) -> void:
	_update_connection_ui(connected, details)
	if not connected:
		_session_id = ""
		_last_tracking_ms = -10000
		_calibration_success = false
		next_button.disabled = true
		is_calibrating = false
		_tracking_available = false
		tracking_label.text = "Nhận diện tạm thời không khả dụng"
		tracking_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
		_show_warning("Mất kết nối với hệ thống nhận diện. Quá trình đo đã dừng.")
	_update_start_button()


func _on_tracking_status_changed(data: Dictionary) -> void:
	_last_tracking_ms = Time.get_ticks_msec()
	_tracking_available = bool(data.get("person_detected", false)) \
			and bool(data.get("required_body_visible", false))

	var status := str(data.get("status", "unknown"))
	var confidence := float(data.get("confidence", 0.0))
	var feedback_code := str(data.get("feedback_code", ""))

	tracking_label.text = _feedback_text(feedback_code) if feedback_code not in ["", "POSITION_OK"] else "Nhận diện: %s" % _tracking_text(status)
	tracking_label.add_theme_color_override("font_color", Color(0.12, 0.37, 0.18) if _tracking_available else Color(0.85, 0.2, 0.15))
	confidence_label.text = "Chỉ báo BE: %d%% (giá trị quy ước)" % roundi(confidence * 100.0)
	feedback_label.text = "Phản hồi: %s" % _feedback_text(feedback_code)

	if is_calibrating and not _tracking_available:
		introduce.text = "Tạm dừng tích lũy mẫu. Hãy trở lại giữa khung camera."
		introduce.add_theme_color_override("font_color", Color(0.9, 0.45, 0.05))
	elif is_calibrating:
		introduce.text = "Đã nhận diện. Bộ đếm sẽ chạy khi tư thế hợp lệ."
		introduce.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))

	_update_start_button()


func _on_calibration_progressed(data: Dictionary) -> void:
	if not _matches_session(data):
		return
	if str(data.get("exercise_id", "")) != CALIBRATION_EXERCISE_ID:
		return

	var progress := clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	progress_bar.value = progress * 100.0
	var duration := maxi(1, int(data.get("duration_ms", CALIBRATION_DURATION_MS)))
	var elapsed := clampi(int(data.get("elapsed_ms", progress * duration)), 0, duration)
	%ProgressCaption.text = "Mẫu hợp lệ: %.1f / %.1f giây" % [elapsed / 1000.0, duration / 1000.0]
	var valid := bool(data.get("tracking_valid", _tracking_available))
	if (data.get("current_rom_value") is float or data.get("current_rom_value") is int) and valid:
		%RomLabel.text = "Chỉ số chuẩn hóa: %.1f / 90" % float(data.current_rom_value)
	else:
		%RomLabel.text = "Chỉ số hiện tại: —"
	if not valid:
		_show_warning("Mẫu chưa hợp lệ: bộ đếm đang tạm dừng. Điều chỉnh theo hướng dẫn.")
	feedback_label.text = "Phản hồi: %s" % _feedback_text(str(data.get("feedback_code", "")))


func _on_calibration_finished(data: Dictionary) -> void:
	if not _matches_session(data): return
	if str(data.get("exercise_id", "")) != CALIBRATION_EXERCISE_ID:
		return

	is_calibrating = false
	next_button.disabled = true
	if not bool(data.get("success", false)):
		_calibration_success = false
		progress_bar.value = 0.0
		_show_warning("Chưa thu đủ mẫu hợp lệ trong thời hạn. Kiểm tra vị trí rồi đo lại.")
		_update_start_button()
		return

	if not PoseInput.provider_connected or not _tracking_fresh() or not _tracking_available or (not _using_mock and not _fresh_camera()):
		_calibration_success = false
		_show_warning("Kết quả đến khi mất nhận diện hoặc camera. Hãy đo lại.")
		_update_start_button()
		return
	if data.has("measurement_kind") and str(data.get("measurement_kind", "")) != "normalized_t_pose":
		_calibration_success = false
		_show_warning("Kết quả đo không đúng định dạng. Hãy đo lại.")
		_update_start_button()
		return
	if data.has("valid_elapsed_ms") and int(data.get("valid_elapsed_ms", 0)) < CALIBRATION_DURATION_MS:
		_calibration_success = false
		_show_warning("Chưa thu đủ thời gian mẫu hợp lệ. Hãy đo lại.")
		_update_start_button()
		return
	if data.has("valid_sample_count") and int(data.get("valid_sample_count", 0)) < 20:
		_calibration_success = false
		_show_warning("Chưa đủ số lượng mẫu hợp lệ. Hãy đo lại.")
		_update_start_button()
		return
	if not data.get("max_rom") is Dictionary: return
	var max_rom: Dictionary = data.get("max_rom", {})
	if not is_finite(float(max_rom.get("combined", 0.0))) or float(max_rom.get("combined", 0.0)) <= 0 or float(max_rom.get("combined", 0.0)) > 90:
		_calibration_success = false
		_show_warning("Kết quả chưa hợp lệ. Hãy đo lại.")
		_update_start_button()
		return
	if _using_mock:
		_calibration_success = false
		_show_warning("Kết quả giả lập không được lưu. Kết nối camera thật để hiệu chỉnh.")
		_update_start_button()
		return
	_calibration_success = true
	Global.max_rom_angle = float(max_rom.get("combined", 0.0))
	if not _using_mock and not Global.record_calibration_rom(Global.max_rom_angle):
		_calibration_success = false
		_show_warning("Đo xong nhưng chưa lưu được hồ sơ. Kiểm tra quyền ghi rồi thử lại.")
		_update_start_button()
		return
	progress_bar.value = 100.0
	introduce.text = "Hoàn tất: chỉ số chuẩn hóa %.1f / 90. Hồ sơ %s." % [Global.max_rom_angle, Global.current_patient_id]
	if _using_mock: introduce.text = "Kết quả giả lập · Không lưu vào lịch sử hiệu chuẩn."
	%ProgressCaption.text = "Mẫu hợp lệ: 5.0 / 5.0 giây (100%)"
	introduce.add_theme_color_override("font_color", Color(0.12, 0.37, 0.18))
	feedback_label.text = "Phản hồi: %s" % _feedback_text(str(data.get("feedback_code", "")))
	_update_start_button()
	start_button.text = "ĐO LẠI"
	next_button.disabled = false
	next_button.grab_focus()


func _on_provider_error_received(data: Dictionary) -> void:
	var error_code := str(data.get("code", "INTERNAL_ERROR"))
	feedback_label.text = "Lỗi: %s" % error_code
	_show_warning("Hệ thống nhận diện gặp lỗi: %s" % error_code)

	if str(data.get("severity", "warning")) == "fatal":
		_calibration_success = false
		next_button.disabled = true
		is_calibrating = false
		_update_start_button()


func _on_next_button_pressed() -> void:
	_update_start_button()
	if next_button.disabled: return
	PoseInput.stop_exercise("scene_changed")
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")


func _on_back_button_pressed() -> void:
	PoseInput.stop_exercise("scene_changed")
	get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")


func _update_connection_ui(connected: bool, details := {}) -> void:
	if details.has("pose_engine"):
		_using_mock = str(details.pose_engine).to_lower() == "mock"
	if connected:
		connection_label.text = "GIẢ LẬP · Không phải số đo camera thật" if _using_mock else "BE đã kết nối · Chờ ảnh camera"
		connection_label.add_theme_color_override("font_color", Color(0.12, 0.37, 0.18))
	else:
		connection_label.text = "Mất kết nối hệ thống nhận diện"
		_last_frame_ms = -10000
		if is_instance_valid(_camera_view):
			_camera_view.texture = null
		_camera_texture = null
		if _adapt_callback.is_valid():
			_adapt_callback.call()
		connection_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))


func _update_start_button() -> void:
	next_button.disabled = not _calibration_success or not PoseInput.provider_connected or not _tracking_fresh() or not _tracking_available or (not _using_mock and not _fresh_camera())
	start_button.disabled = is_calibrating \
			or not PoseInput.provider_connected \
			or not _tracking_available or not _tracking_fresh() \
			or (not _using_mock and not _fresh_camera())


func _show_warning(message: String) -> void:
	introduce.text = message
	introduce.add_theme_color_override("font_color", Color(0.9, 0.25, 0.1))


func _tracking_text(status: String) -> String:
	match status:
		"tracking":
			return "Đã nhận diện người"
		"no_person":
			return "Không tìm thấy người"
		"partial_person":
			return "Chưa thấy đủ cơ thể"
		"low_confidence":
			return "Độ tin cậy thấp"
		"camera_disconnected":
			return "Mất kết nối camera"
		"no_camera":
			return "Không tìm thấy camera"
		_:
			return status


func _feedback_text(code: String) -> String:
	const FEEDBACK_TEXT := {
		"POSITION_OK": "Vị trí phù hợp",
		"MOVE_BACK": "Hãy lùi lại một chút",
		"MOVE_CLOSER": "Hãy tiến gần camera hơn",
		"CENTER_YOUR_BODY": "Hãy đứng giữa khung hình",
		"OPEN_ARMS": "Hãy dang thẳng 2 tay sang 2 bên ngang vai (90°)",
		"KEEP_POSITION": "Hãy giữ nguyên tư thế dang tay ngang vai",
		"TRACKING_LOST": "Không nhìn thấy người chơi",
		"SHOULDERS_NOT_VISIBLE": "Camera chưa thấy rõ hai vai",
		"LEFT_ARM_NOT_VISIBLE": "Camera chưa thấy rõ tay trái",
		"RIGHT_ARM_NOT_VISIBLE": "Camera chưa thấy rõ tay phải",
		"CAMERA_DISCONNECTED": "Mất kết nối Camera! Vui lòng kiểm tra lại dây cắm.",
		"CAMERA_RECONNECTED": "Đã kết nối lại Camera.",
		"LIGHTING_TOO_LOW": "Kiểm tra camera và ánh sáng",
		"CALIBRATION_TIMEOUT": "Chưa đủ mẫu hợp lệ trong thời hạn",
		"CALIBRATION_LOW_CONFIDENCE": "Mẫu chưa đủ tin cậy, hãy đo lại",
		"CALIBRATION_COMPLETED": "Hiệu chỉnh hoàn tất",
	}
	return FEEDBACK_TEXT.get(code, code if not code.is_empty() else "Chờ dữ liệu")


func _build_presentation() -> void:
	var backdrop := preload("res://ui/screens/map_selection/map_preview.gd").new()
	backdrop.map_id = 1
	backdrop.scenery_only = true
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	%DebugPanel.hide()
	%DebugToggle.text = "Thông tin kỹ thuật"
	%DebugToggle.pressed.connect(_toggle_technical_info)
	_build_responsive_layout()
	%BackButton.grab_focus()


func _process(_delta: float) -> void:
	if is_calibrating and (Time.get_ticks_msec() - _started_ms > 25000 or (not _using_mock and not _fresh_camera())):
		_abort_calibration("Đo đã dừng vì camera gián đoạn hoặc quá thời hạn. Hãy thử lại.")
	if not _tracking_fresh():
		_tracking_available = false
		tracking_label.text = "Đang chờ dữ liệu nhận diện mới"
	if not _using_mock:
		var fresh := _fresh_camera()
		%CameraHint.visible = not fresh
		%ColorRect2.show_body = not fresh
		%ColorRect2.queue_redraw()
		if not fresh:
			_camera_view.texture = null
			next_button.disabled = true
		if PoseInput.provider_connected:
			connection_label.text = "BE đã kết nối · Camera đang có hình" if fresh else "BE đã kết nối · Chưa có ảnh camera mới"
		_update_start_button()
	if %DebugPanel.visible:
		%Text.text = _technical_info_text()


func _fresh_camera() -> bool:
	return Time.get_ticks_msec() - _last_frame_ms < 3000


func _setup_camera_preview() -> void:
	_camera_view = TextureRect.new()
	_camera_view.name = "CalibrationCameraRect"
	_camera_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_camera_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_camera_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%ColorRect2.add_child(_camera_view)
	%ColorRect2.move_child(_camera_view, 0)
	_camera_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camera_view.offset_left = 4
	_camera_view.offset_right = -4
	_camera_view.offset_top = 34
	_camera_view.offset_bottom = -4



func _on_camera_frame_received(image: Image) -> void:
	if image == null or image.is_empty():
		return
	# Reference backend already mirrors and draws joints. Preserve its aspect ratio.
	var texture_created := false
	if _camera_texture != null and _camera_texture.get_width() == image.get_width() and _camera_texture.get_height() == image.get_height() and _camera_texture.get_format() == image.get_format():
		_camera_texture.update(image)
	else:
		_camera_texture = ImageTexture.create_from_image(image)
		texture_created = true
	_camera_view.texture = _camera_texture
	_last_frame_ms = Time.get_ticks_msec()
	_update_start_button()
	if texture_created and _adapt_callback.is_valid():
		_adapt_callback.call()


func _tracking_fresh() -> bool:
	return Time.get_ticks_msec() - _last_tracking_ms < 3500

func _matches_session(data: Dictionary) -> bool:
	return is_calibrating and not _session_id.is_empty() and str(data.get("session_id", "")) == _session_id and _patient_id == Global.current_patient_id

func _abort_calibration(message: String) -> void:
	is_calibrating = false
	_calibration_success = false
	_session_id = ""
	next_button.disabled = true
	PoseInput.stop_exercise("calibration_cancelled")
	_show_warning(message)
	_update_start_button()

func _exit_tree() -> void:
	if is_calibrating: PoseInput.stop_exercise("calibration_screen_closed")


func _build_responsive_layout() -> void:
	var margin := MarginContainer.new()
	margin.name = "ResponsiveLayout"
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16 if edge in ["top", "bottom"] else 20)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	%BackButton.reparent(header)
	%BackButton.custom_minimum_size = Vector2(144, 42)
	%Title.reparent(header)
	%Title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Title.add_theme_font_size_override("font_size", 28)
	%Subtitle.reparent(column)
	%Subtitle.text = "01 Chuẩn bị camera   /   02 Hiệu chỉnh   /   03 Chọn bài tập"
	%Subtitle.add_theme_font_size_override("font_size", 16)
	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var columns := BoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	content.add_child(columns)
	var camera_column := VBoxContainer.new()
	camera_column.name = "CameraColumn"
	camera_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_column.size_flags_vertical = Control.SIZE_FILL
	camera_column.size_flags_stretch_ratio = 1.7
	camera_column.add_theme_constant_override("separation", 8)
	columns.add_child(camera_column)
	%ColorRect2.reparent(camera_column)
	%ColorRect2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	%CameraTitle.reparent(%ColorRect2)
	%CameraTitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	%CameraTitle.offset_left = 14
	%CameraTitle.offset_right = -14
	%CameraTitle.offset_top = 8
	%CameraTitle.offset_bottom = 30
	%CameraTitle.add_theme_font_size_override("font_size", 16)
	%ColorRect2.custom_minimum_size = Vector2(0, 300)
	%CameraHint.reparent(%ColorRect2)
	%CameraHint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	%CameraHint.offset_left = 16
	%CameraHint.offset_right = -16
	%CameraHint.offset_bottom = -12
	%CameraHint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	%CameraHint.add_theme_font_size_override("font_size", 18)
	%CameraHint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%PoseStatusPanel.reparent(content)
	var status_margin := %PoseStatusPanel.get_node("MarginContainer")
	var status_labels := status_margin.get_node("VBoxContainer")
	var status_body := VBoxContainer.new()
	status_body.add_theme_constant_override("separation", 8)
	status_margin.add_child(status_body)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	status_body.add_child(status_row)
	status_labels.reparent(status_row)
	status_labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in [connection_label, tracking_label]:
		label.add_theme_font_size_override("font_size", 16)
	%DebugToggle.reparent(status_row)
	%DebugToggle.custom_minimum_size = Vector2(152, 36)
	%DebugToggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%DebugToggle.add_theme_font_size_override("font_size", 14)
	_build_technical_overlay()
	%InstructionCard.reparent(columns)
	%InstructionCard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%InstructionCard.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	%InstructionCard.size_flags_stretch_ratio = 1.0
	var instructions := VBoxContainer.new()
	instructions.add_theme_constant_override("separation", 6)
	%InstructionCard.add_child(instructions)
	%Label2.text = "HIỆU CHỈNH TRƯỚC KHI TẬP"
	%Steps.text = "1. Để rõ vai, khuỷu và hai tay.\n2. Làm theo hướng dẫn, giữ trong khả năng của bạn.\n3. Thu đủ 5 giây mẫu hợp lệ; tối đa 20 giây/lần đo."
	for node in [%Label2, %Steps, %RomLabel, %Introduce, %ProgressCaption, progress_bar, start_button, next_button]:
		node.reparent(instructions)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if node is Label:
			node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			node.add_theme_font_size_override("font_size", 20 if node == %Label2 else 17)
	for button in [start_button, next_button]:
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 17)
	progress_bar.custom_minimum_size.y = 24
	var adapt := func():
		columns.vertical = scroll.size.x < 900
		# Match both columns; keep the shared status strip directly below them.
		var target_height: float = %InstructionCard.get_combined_minimum_size().y
		if columns.vertical: target_height = minf(camera_column.size.x * 0.6, 340)
		%ColorRect2.custom_minimum_size = Vector2(0, maxf(260, target_height))
		%ColorRect2.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_adapt_callback = adapt
	scroll.resized.connect(adapt)
	camera_column.resized.connect(adapt)
	%InstructionCard.minimum_size_changed.connect(adapt)
	adapt.call_deferred()


func _build_technical_overlay() -> void:
	_technical_overlay = Control.new()
	_technical_overlay.name = "TechnicalOverlay"
	_technical_overlay.z_index = 20
	add_child(_technical_overlay)
	_technical_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_technical_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_technical_info())
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_technical_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	%DebugPanel.reparent(center)
	%DebugPanel.mouse_filter = Control.MOUSE_FILTER_STOP
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	%DebugPanel.add_child(body)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	%Text.reparent(detail_scroll)
	%Text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	%Text.add_theme_font_size_override("font_size", 17)
	var close := Button.new()
	close.text = "Đóng"
	close.custom_minimum_size.y = 42
	body.add_child(close)
	close.pressed.connect(_toggle_technical_info)
	var fit := func():
		%DebugPanel.custom_minimum_size = Vector2(minf(620, maxf(260, size.x - 40)), 0)
		detail_scroll.custom_minimum_size.y = clampf(%Text.get_combined_minimum_size().y, 40, maxf(140, size.y - 150))
	resized.connect(fit)
	%Text.minimum_size_changed.connect(fit)
	fit.call_deferred()
	_technical_overlay.hide()


func _toggle_technical_info() -> void:
	var show_details: bool = not %DebugPanel.visible
	%DebugPanel.visible = show_details
	_technical_overlay.visible = show_details
	if show_details:
		%Text.text = _technical_info_text()
		%DebugPanel.get_child(0).get_child(1).grab_focus()
	else:
		%DebugToggle.grab_focus()

func _technical_info_text() -> String:
	var connected := PoseInput.provider_connected
	var camera_live := connected and _fresh_camera()
	var tracking_live := connected and _tracking_fresh()
	var lines := PackedStringArray()
	lines.append("KẾT NỐI & CAMERA")
	lines.append("Kết nối nhận diện: " + ("Đã kết nối" if connected else "Chưa kết nối"))
	lines.append("Ảnh camera: " + ("Đang cập nhật" if camera_live else "Chưa có ảnh mới"))
	if camera_live and _camera_texture != null:
		lines.append("Kích thước ảnh nhận: %d × %d px" % [_camera_texture.get_width(), _camera_texture.get_height()])
	var fps: Variant = PoseInput.last_tracking_status.get("camera_fps")
	if tracking_live and (fps is int or fps is float) and is_finite(float(fps)) and float(fps) >= 0:
		lines.append("Tốc độ camera (BE gửi): %.1f FPS" % float(fps))
	else:
		lines.append("Tốc độ camera: Chưa có dữ liệu mới")
	lines.append("Nhận diện: " + ("Đủ phần cơ thể yêu cầu" if tracking_live and _tracking_available else "Chưa có nhận diện hợp lệ"))
	if tracking_live:
		var code := str(PoseInput.last_tracking_status.get("feedback_code", ""))
		if not code.is_empty(): lines.append("Phản hồi BE: " + _feedback_text(code))
	lines.append("Hiệu chỉnh: " + ("Đang thu mẫu" if is_calibrating else ("Đã hoàn tất" if _calibration_success else "Chưa hoàn tất")))
	lines.append("Chỉ số 0–90 được chuẩn hóa để điều chỉnh game; không phải góc khớp đo thô.")
	return "\n".join(lines)


func _enter_offline_preview() -> void:
	if not OS.is_debug_build(): return
	if not PoseInput.has_method("begin_offline_preview"): return
	is_calibrating = false
	_session_id = ""
	PoseInput.begin_offline_preview()
	var error := get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
	if error != OK:
		PoseInput.end_offline_preview()
		_show_warning("Không mở được màn chọn map. Hãy thử lại.")
