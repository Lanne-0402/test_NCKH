extends Control

# Integration hooks for BE; these controls do not read/write report files themselves.
signal csv_export_requested(patient_id: String)
var _csv_button: Button
var _csv_status: Label
var _csv_available := false
var _csv_pending_id := ""
var _rom_report_patient_id := ""
var _rom_report_payload: Dictionary = {}

var _active_section := "overview"
var _section_views: Dictionary = {}
var _section_scrolls: Dictionary = {}
var _section_tabs: Dictionary = {}
var _overview_choices: Dictionary = {}
var _section_nav: HBoxContainer
var _section_title: Label
var _section_back: Button
var _section_patient: Label
var _section_patient_id := ""
var _session_list: VBoxContainer

const Data := preload("res://core/autoload/report_data.gd")
var _reset_dialog: ConfirmationDialog
var _reset_target := ""
var _map_filter: OptionButton
var _status_filter: OptionButton
var _period_filter: OptionButton
var _filter_count: Label
var _pending_label: Label
var _last_pending := -1

const Display := preload("res://ui/shared/session_display.gd")
const RomLineChartScript := preload("res://ui/screens/history/rom_line_chart.gd")

const MAP_NAMES := [
	"Phá cản mở đường (Khép bả vai)",
	"Nâng đá (Dạng xoay ngoài)",
	"Đẩy lùi tường (Khép ngang vai)",
	"Leo vách đá cao (Hai tay ôm đầu)",
	"Thiền định (Kéo căng qua ngực)",
]

var _patient_id_edit: LineEdit
var _patient_name_edit: LineEdit
var _preset_patient_option: OptionButton
var _doctor_section_container: HBoxContainer
var _toolbar_row2: GridContainer
var _mode_toggle_btn: Button
var _patient_mode: bool = true

var _cloud_status_label: Label
var _weekly_stats_label: Label
var _map_progress_label: Label
var _rom_chart: Control

var _cloud_modal: ColorRect
var _cloud_enable_check: CheckBox
var _cloud_provider_option: OptionButton
var _cloud_url_edit: LineEdit
var _cloud_key_edit: LineEdit


func _ready() -> void:
	theme = preload("res://assets/shared/ui/game_theme.tres")
	$Background.hide()
	var forest := preload("res://ui/screens/map_selection/map_preview.gd").new()
	forest.scenery_only = true
	add_child(forest)
	move_child(forest, 0)
	forest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# An nut BackButton goc de tich hop gon gang vao hang Header tren cung
	if has_node("BackButton"):
		$BackButton.visible = false

	$Margin/Column/Scroll.follow_focus = true

	_build_dashboard_ui()
	_build_cloud_config_modal()
	_build_history_filters()
	_build_sections()

	Global.cloud_sync_status_changed.connect(_on_cloud_sync_status_changed)
	Global.patient_profile_changed.connect(func(_pid: String): _refresh_all())

	_refresh_all()


func _build_dashboard_ui() -> void:
	var column: VBoxContainer = $Margin/Column
	var list := $Margin/Column/Scroll/List
	_session_list = list
	var dashboard := VBoxContainer.new()
	dashboard.name = "Dashboard"
	dashboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dashboard.add_theme_constant_override("separation", 16)
	$Margin/Column/Scroll.add_child(dashboard)
	list.reparent(dashboard)


	# 1. Header Row (Gom Back Button, Title va Cloud Status tren 1 hang ngan nap)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	column.add_child(header_row)
	column.move_child(header_row, 0)

	var back_btn := Button.new()
	back_btn.text = "‹ VỀ TRANG CHỦ"
	back_btn.custom_minimum_size = Vector2(150, 36)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_section_back = back_btn
	back_btn.pressed.connect(func():
		if _active_section != "overview":
			_show_section("overview", true)
		else:
			get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")
	)
	header_row.add_child(back_btn)

	# Chuyen Title co san vao giua header_row
	var title_node: Label = $Margin/Column/Title
	_section_title = title_node
	title_node.reparent(header_row)
	title_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_node.text = "BÁO CÁO & LỊCH SỬ TẬP"
	title_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_node.add_theme_font_size_override("font_size", 26)
	title_node.add_theme_color_override("font_color", Color("f5e9c7"))
	title_node.add_theme_color_override("font_outline_color", Color("14251e"))
	title_node.add_theme_constant_override("outline_size", 4)

	_cloud_status_label = _label(_initial_cloud_status_text(), 18)
	_cloud_status_label.custom_minimum_size = Vector2(0, 28)
	_cloud_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cloud_status_label.add_theme_color_override(
		"font_color",
		Color("8ef5a5") if Global.cloud_is_online else Color("f5e9c7")
	)
	column.add_child(_cloud_status_label)
	column.move_child(_cloud_status_label, 1)

	# 2. Patient ID & Actions Toolbar (Chia thanh 2 hang ngang gon gang, chong tran)
	var toolbar_panel := PanelContainer.new()
	toolbar_panel.name = "PatientToolbar"
	dashboard.add_child(toolbar_panel)
	dashboard.move_child(toolbar_panel, 0)

	var toolbar_vbox := VBoxContainer.new()
	toolbar_vbox.add_theme_constant_override("separation", 8)
	toolbar_panel.add_child(toolbar_vbox)

	# --- HANG 1: Thong tin nguoi benh & Chon ho so ---
	var row1 := HBoxContainer.new()
	row1.name = "PatientIdentity"
	row1.add_theme_constant_override("separation", 10)
	toolbar_vbox.add_child(row1)

	var id_group := VBoxContainer.new()
	id_group.custom_minimum_size.x = 100
	row1.add_child(id_group)
	id_group.add_child(_plain_label("Mã ID:", 16))

	_patient_id_edit = LineEdit.new()
	_patient_id_edit.custom_minimum_size = Vector2(100, 42)
	_patient_id_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_patient_id_edit.placeholder_text = "BN001"
	_patient_id_edit.text = Global.current_patient_id
	id_group.add_child(_patient_id_edit)

	var name_group := VBoxContainer.new()
	name_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(name_group)
	name_group.add_child(_plain_label("Họ và tên:", 16))

	_patient_name_edit = LineEdit.new()
	_patient_name_edit.custom_minimum_size = Vector2(180, 42)
	_patient_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_patient_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_patient_name_edit.placeholder_text = "Họ tên người bệnh"
	_patient_name_edit.text = Global.current_patient_name
	name_group.add_child(_patient_name_edit)

	var switch_btn := Button.new()
	switch_btn.text = "Lưu / Đổi Tên"
	switch_btn.custom_minimum_size = Vector2(110, 32)
	switch_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	switch_btn.name = "SavePatientButton"
	switch_btn.custom_minimum_size.y = 42
	switch_btn.add_theme_font_size_override("font_size", 18)
	switch_btn.pressed.connect(_on_switch_patient_pressed)
	row1.add_child(switch_btn)

	var profile_row := HBoxContainer.new()
	profile_row.name = "ProfileAndMode"
	profile_row.add_theme_constant_override("separation", 12)
	toolbar_vbox.add_child(profile_row)
	# Khung chon ho so (se an khi o Che do Nguoi benh)
	_doctor_section_container = HBoxContainer.new()
	_doctor_section_container.add_theme_constant_override("separation", 10)
	profile_row.add_child(_doctor_section_container)

	_doctor_section_container.add_child(_plain_label("Hồ sơ:", 14))

	_preset_patient_option = OptionButton.new()
	_preset_patient_option.custom_minimum_size = Vector2(125, 32)
	_preset_patient_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for pid in Global.PRESET_PATIENT_IDS:
		_preset_patient_option.add_item("Hồ sơ " + pid)
	for i in range(Global.PRESET_PATIENT_IDS.size()):
		if Global.PRESET_PATIENT_IDS[i] == Global.current_patient_id:
			_preset_patient_option.selected = i
			break
	_doctor_section_container.add_child(_preset_patient_option)
	_preset_patient_option.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < Global.PRESET_PATIENT_IDS.size():
			var selected_pid: String = Global.PRESET_PATIENT_IDS[idx]
			_patient_id_edit.text = selected_pid
			var p_name: String = str(Global.patient_profiles.get(selected_pid, {}).get("patient_name", "Bệnh nhân " + selected_pid))
			_patient_name_edit.text = p_name
			Global.switch_patient(selected_pid, p_name)
			_refresh_all()
	)

	_mode_toggle_btn = Button.new()
	_mode_toggle_btn.text = "Giao diện: Người tập"
	_mode_toggle_btn.custom_minimum_size = Vector2(170, 32)
	_mode_toggle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mode_toggle_btn.tooltip_text = "Chỉ đổi cách hiển thị. Đây không phải chức năng đăng nhập hay phân quyền."
	_mode_toggle_btn.pressed.connect(func():
		_patient_mode = not _patient_mode
		_mode_toggle_btn.text = "Giao diện: Người tập" if _patient_mode else "Giao diện: Quản lý"
		_apply_patient_mode_visibility()
	)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(spacer)
	profile_row.add_child(_mode_toggle_btn)

	# --- HANG 2: Cong cu thao tac Database & Dong bo Online ---
	_toolbar_row2 = GridContainer.new()
	_toolbar_row2.name = "ManagementActions"
	_toolbar_row2.columns = 3
	_toolbar_row2.add_theme_constant_override("h_separation", 10)
	_toolbar_row2.add_theme_constant_override("v_separation", 8)
	_toolbar_row2.resized.connect(_update_action_columns)
	toolbar_vbox.add_child(_toolbar_row2)

	var reset_btn := Button.new()
	reset_btn.text = "Xóa dữ liệu hồ sơ…"
	reset_btn.name = "ResetPatientButton"
	reset_btn.custom_minimum_size = Vector2(125, 30)
	reset_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_btn.tooltip_text = "Đưa ID đang chọn về ban đầu: xóa lịch sử, ROM, tiến độ và đặt lại tên. Cần xác nhận trước khi thực hiện."
	reset_btn.pressed.connect(_on_reset_patient_pressed)
	_toolbar_row2.add_child(reset_btn)

	var sync_btn := Button.new()
	sync_btn.text = "Đồng bộ Cloud ngay"
	sync_btn.custom_minimum_size = Vector2(145, 30)
	sync_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sync_btn.pressed.connect(_on_sync_cloud_pressed)
	_toolbar_row2.add_child(sync_btn)

	var config_btn := Button.new()
	config_btn.text = "Cấu hình DB Online"
	config_btn.custom_minimum_size = Vector2(150, 30)
	config_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	config_btn.pressed.connect(func(): _cloud_modal.visible = true)
	_toolbar_row2.add_child(config_btn)
	_csv_button = Button.new()
	_csv_button.name = "ExportCsvButton"
	_csv_button.text = "XUẤT BÁO CÁO CSV"
	_csv_button.tooltip_text = "Xuất toàn bộ dữ liệu của hồ sơ đang chọn; không giới hạn theo bộ lọc lịch sử."
	_csv_button.pressed.connect(_on_csv_export_pressed)
	profile_row.add_child(_csv_button)
	profile_row.move_child(_csv_button, _mode_toggle_btn.get_index())
	_toolbar_row2.move_child(reset_btn, 2)
	_csv_status = _label("", 16)
	_csv_status.add_theme_font_size_override("font_size", 16)
	toolbar_vbox.add_child(_csv_status)
	for action in [sync_btn, config_btn, reset_btn]:
		action.custom_minimum_size = Vector2(210, 44)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("font_size", 18)
	for selector in [_preset_patient_option, _mode_toggle_btn]:
		selector.custom_minimum_size.y = 42
		selector.add_theme_font_size_override("font_size", 18)

	# Reserve the longer mode caption in both states; neither button expands with the spacer.
	for top_action in [_csv_button, _mode_toggle_btn]:
		top_action.add_theme_font_size_override("font_size", 18)
		top_action.custom_minimum_size = Vector2(230, 44)
		top_action.size_flags_horizontal = Control.SIZE_SHRINK_END
		top_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mode_font := _mode_toggle_btn.get_theme_font("font")
	var mode_padding := _mode_toggle_btn.get_theme_stylebox("normal").get_minimum_size().x
	for caption in ["Giao diện: Người tập", "Giao diện: Quản lý"]:
		_mode_toggle_btn.custom_minimum_size.x = maxf(_mode_toggle_btn.custom_minimum_size.x, ceilf(mode_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + mode_padding))

	# 3. Weekly Summary & Map Unlock Progress Cards (2 columns)
	var summary_row := GridContainer.new()
	summary_row.name = "ReportSummary"
	summary_row.columns = 2
	summary_row.resized.connect(func(): summary_row.columns = 1 if summary_row.size.x < 850 else 2)
	summary_row.add_theme_constant_override("separation", 10)
	dashboard.add_child(summary_row)
	dashboard.move_child(summary_row, 1)

	var stats_card := PanelContainer.new()
	stats_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(stats_card)

	_weekly_stats_label = _label("", 18)
	stats_card.add_child(_weekly_stats_label)

	var progress_card := PanelContainer.new()
	progress_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(progress_card)

	_map_progress_label = _label("", 18)
	progress_card.add_child(_map_progress_label)

	# 5. Visual ROM Progression Line Chart
	_rom_chart = RomLineChartScript.new()
	_rom_chart.name = "RomLineChart"
	_rom_chart.custom_minimum_size = Vector2(0, 300)
	dashboard.add_child(_rom_chart)
	dashboard.move_child(_rom_chart, 2)

	_apply_patient_mode_visibility()


func _apply_patient_mode_visibility() -> void:
	if _doctor_section_container != null:
		_doctor_section_container.visible = not _patient_mode
	if _toolbar_row2 != null:
		_toolbar_row2.visible = not _patient_mode
		_update_action_columns()
	if _patient_id_edit != null:
		_patient_id_edit.editable = not _patient_mode


func _update_action_columns() -> void:
	if _toolbar_row2 == null: return
	var available_width := _toolbar_row2.size.x
	_toolbar_row2.columns = 3 if available_width >= 680 else 1


func _build_cloud_config_modal() -> void:
	_cloud_modal = ColorRect.new()
	_cloud_modal.name = "CloudConfigModal"
	_cloud_modal.visible = false
	_cloud_modal.color = Color(0.0, 0.0, 0.0, 0.72)
	_cloud_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cloud_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cloud_modal.add_child(center)

	var dialog := PanelContainer.new()
	dialog.custom_minimum_size = Vector2(620, 440)
	center.add_child(dialog)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(root_vbox)

	# 1. Header (Co dinh o tren)
	var title := _plain_label("CẤU HÌNH DATABASE ONLINE (MONGODB / CLOUD)", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	# 2. Body trong ScrollContainer (Tu dong co cuon, KHONG BAO GIO TRAN RA NGOAI)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var desc := _label(
		"Hệ thống tự động lưu Offline trên máy và đồng bộ lên MongoDB Atlas Cloud qua cổng 8766. Cấu hình này chỉ cần thiết lập 1 lần cho đề tài.",
		13
	)
	vbox.add_child(desc)

	_cloud_enable_check = CheckBox.new()
	_cloud_enable_check.text = "Bật tự động đồng bộ dữ liệu lên Database Online (MongoDB Atlas / Cloud)"
	_cloud_enable_check.button_pressed = Global.cloud_db_enabled
	vbox.add_child(_cloud_enable_check)

	var provider_row := HBoxContainer.new()
	provider_row.add_theme_constant_override("separation", 10)
	vbox.add_child(provider_row)
	provider_row.add_child(_plain_label("Hệ quản trị CSDL:", 14))

	_cloud_provider_option = OptionButton.new()
	_cloud_provider_option.add_item("MongoDB (MongoDB Atlas Cloud / Compass)", 0)
	_cloud_provider_option.add_item("Supabase (PostgreSQL REST API)", 1)
	_cloud_provider_option.add_item("Firebase Realtime Database (JSON REST API)", 2)
	if Global.cloud_db_provider == "supabase":
		_cloud_provider_option.selected = 1
	elif Global.cloud_db_provider == "firebase":
		_cloud_provider_option.selected = 2
	else:
		_cloud_provider_option.selected = 0
	_cloud_provider_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	provider_row.add_child(_cloud_provider_option)

	vbox.add_child(_plain_label("Chuỗi kết nối MongoDB URI (hoặc Project URL):", 14))
	_cloud_url_edit = LineEdit.new()
	_cloud_url_edit.custom_minimum_size.y = 34
	_cloud_url_edit.placeholder_text = "mongodb+srv://<db_username>:<db_password>@clustergamephcn2d.6doylym.mongodb.net/"
	_cloud_url_edit.text = Global.cloud_db_url
	vbox.add_child(_cloud_url_edit)

	vbox.add_child(_plain_label("Tên Database MongoDB (Mặc định: rehab_pixel_game) hoặc API Key:", 14))
	_cloud_key_edit = LineEdit.new()
	_cloud_key_edit.custom_minimum_size.y = 34
	_cloud_key_edit.placeholder_text = "VD: rehab_pixel_game"
	_cloud_key_edit.secret = (Global.cloud_db_provider != "mongodb")
	_cloud_key_edit.text = Global.cloud_db_api_key
	vbox.add_child(_cloud_key_edit)

	_cloud_provider_option.item_selected.connect(func(idx: int):
		if idx == 0:
			_cloud_key_edit.secret = false
			if _cloud_url_edit.text.is_empty():
				_cloud_url_edit.text = "mongodb://localhost:27017"
			if _cloud_key_edit.text.is_empty():
				_cloud_key_edit.text = "rehab_pixel_game"
		else:
			_cloud_key_edit.secret = true
	)

	var sql_note := _label(
		"Lưu ý: Khi chạy game kèm 'python main.py' (hoặc 'python mongodb_service.py'), cầu nối MongoDB (cổng 8766) sẽ tự động chạy ngầm để lưu trực tiếp vào MongoDB Atlas Cloud.",
		12
	)
	vbox.add_child(sql_note)

	# 3. Footer ghim co dinh o day dialog (LUON LUON NHIN THAY VA BAM DUOC)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 12)
	root_vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Lưu cấu hình & Đồng bộ ngay"
	save_btn.custom_minimum_size = Vector2(210, 36)
	save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save_btn.pressed.connect(_on_save_cloud_config_pressed)
	btn_row.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "Đóng"
	close_btn.custom_minimum_size = Vector2(95, 36)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func(): _cloud_modal.visible = false)
	btn_row.add_child(close_btn)


func _refresh_all() -> void:
	_refresh_section_context()
	if _patient_id_edit != null:
		_patient_id_edit.text = Global.current_patient_id
	if _patient_name_edit != null:
		_patient_name_edit.text = Global.current_patient_name
	if _preset_patient_option != null:
		for i in range(Global.PRESET_PATIENT_IDS.size()):
			if Global.PRESET_PATIENT_IDS[i] == Global.current_patient_id:
				_preset_patient_option.selected = i
				break

	var sessions: Array = Global.get_patient_sessions(Global.current_patient_id)
	var rom_points: Array = Data.calibration_points(Global.get_patient_rom_history(Global.current_patient_id))

	_update_weekly_summary_cards(sessions, rom_points)
	_refresh_csv_ui()
	if _rom_chart != null:
		if _rom_report_patient_id == Global.current_patient_id and not _rom_report_payload.is_empty():
			_rom_chart.call("set_progress_data", _rom_report_payload)
		else:
			var default_payload := _build_default_rom_payload(Global.current_patient_id, sessions, rom_points)
			_rom_chart.call("set_progress_data", default_payload)
	var filtered := Display.filter_history(sessions, _map_filter.selected if _map_filter != null else 0,
		["", "completed", "stopped_early", "interrupted"][_status_filter.selected] if _status_filter != null else "",
		[0, 7, 30][_period_filter.selected] if _period_filter != null else 0, Time.get_unix_time_from_system())
	if _filter_count != null: _filter_count.text = "LỊCH SỬ · %d/%d buổi của hồ sơ %s" % [filtered.size(), sessions.size(), Global.current_patient_id]
	_populate_session_list(filtered)


func _update_weekly_summary_cards(sessions: Array, rom_points: Array) -> void:
	var valid := 0
	var rejected := 0
	var finished := 0
	var cleared := {}
	for entry in sessions:
		valid += int(entry.get("valid_reps", 0))
		rejected += int(entry.get("rejected_reps", 0))
		if Data.completed(entry):
			finished += 1
			var map_id := int(entry.get("map_id", 0))
			var level := int(entry.get("difficulty", 0))
			if map_id in range(1, 6) and level in range(1, 4): cleared["%d:%d" % [map_id, level]] = true
	var accuracy := "Chưa có dữ liệu" if valid + rejected == 0 else "%.1f%%" % (100.0 * valid / (valid + rejected))
	var rom_text := "Chưa có phép đo hiệu chuẩn xác định nguồn."
	if not rom_points.is_empty():
		var latest := float(rom_points[-1].rom_angle)
		rom_text = "Chỉ số hiệu chuẩn gần nhất: %.1f (%s)" % [latest, str(rom_points[-1].date)]
		if rom_points.size() > 1:
			var delta := latest - float(rom_points[0].rom_angle)
			rom_text += "\nThay đổi chỉ số so với lần đầu: %+.1f — %s" % [delta, "Tăng" if delta > 2.0 else ("Giảm" if delta < -2.0 else "Ít thay đổi")]
		else: rom_text += "\nCần ít nhất hai ngày đo để so sánh."
	_weekly_stats_label.text = "TỔNG KẾT · TOÀN BỘ LỊCH SỬ\n%d buổi ghi nhận · %d hoàn thành\nHợp lệ: %d · Chưa đạt: %d · Tỷ lệ hợp lệ: %s\n%s" % [sessions.size(), finished, valid, rejected, accuracy, rom_text]
	var lines: Array[String] = ["MỨC ĐÃ HOÀN THÀNH: %d/15 (%.0f%%)" % [cleared.size(), 100.0 * cleared.size() / 15.0]]
	for map_id in range(1, 6):
		var count := 0
		for level in range(1, 4):
			if cleared.has("%d:%d" % [map_id, level]): count += 1
		lines.append("Map %d: %d/3 hoàn thành · mở đến mức %d" % [map_id, count, Global.get_unlocked_level_for_action(map_id)])
	_map_progress_label.text = "\n".join(lines)


func _populate_session_list(sessions: Array) -> void:
	var list: VBoxContainer = _session_list
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	if sessions.is_empty():
		var box := _card(list)
		box.add_child(_label("KHÔNG CÓ BUỔI TẬP PHÙ HỢP · HỒ SƠ %s" % Global.current_patient_id, 20))
		box.add_child(_label("Thử đặt bộ lọc về Tất cả. Nếu chưa có lịch sử, hãy hiệu chỉnh camera rồi bắt đầu buổi tập.", 16))
		var start := Button.new()
		start.text = "CHUẨN BỊ CAMERA"
		start.custom_minimum_size.y = 42
		start.pressed.connect(func():
			get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")
		)
		box.add_child(start)
		return

	for index in range(sessions.size() - 1, -1, -1):
		var entry: Dictionary = sessions[index]
		var box := _card(list)
		var map_id := int(entry.get("map_id", 1))
		var map_name: String = MAP_NAMES[map_id - 1] if map_id >= 1 and map_id <= 5 else "Buổi tập"
		var rom_val: float = float(entry.get("calibration_rom_angle", entry.get("rom_angle", 0.0)))
		var rom_caption := "Hiệu chuẩn" if entry.has("calibration_rom_angle") else "ROM cũ (chưa xác định nguồn)"
		var rom_str := "  •  %s: %.1f" % [rom_caption, rom_val] if rom_val > 0.0 else ""
		box.add_child(_label("Map %d · %s  —  Mức %d%s" % [map_id, map_name, int(entry.get("difficulty", 1)), rom_str], 19))
		box.add_child(_label("%s  •  ID: %s" % [
			_local_time(str(entry.get("ended_at_utc", entry.get("completed_at_utc", "")))),
			str(entry.get("patient_id", Global.current_patient_id)),
		], 15))
		box.add_child(_label(Display.status(entry) if entry.has("status") else ("Hoàn thành (bản ghi cũ)" if Data.completed(entry) else "Chưa có trạng thái"), 18))
		var stats := "Hợp lệ: %d lần     •     Chưa hợp lệ: %d lần" % [int(entry.get("valid_reps", 0)), int(entry.get("rejected_reps", 0))]
		if entry.has("bonus_points"):
			stats += "     •     Điểm thưởng: %d" % int(entry.bonus_points)
		box.add_child(_label(stats, 17))
		box.add_child(_label(Display.goals(entry), 18))
		box.add_child(_label("Thời gian tập: " + Display.duration(entry, "active_seconds"), 18))
		var ratio := Display.progress_ratio(entry)
		if ratio >= 0.0:
			var bar := ProgressBar.new()
			bar.value = ratio * 100.0
			bar.custom_minimum_size.y = 22
			bar.tooltip_text = "Số lần đã thực hiện / mục tiêu; không phải điểm chất lượng động tác."
			box.add_child(bar)
		if TrackingStability.ENABLED and bool(entry.get("stability_enabled", true)):
			box.add_child(_label("Ổn định: %d/3" % int(entry.get("stability", 0)), 16))
		var evaluation := str(entry.get("evaluation", ""))
		if not evaluation.is_empty():
			box.add_child(_label("Đánh giá trong game: " + evaluation, 16))
		var detail := _label(Display.compact_details(entry), 16)
		detail.hide()
		var toggle := Button.new()
		toggle.text = "XEM CHI TIẾT"
		toggle.toggle_mode = true
		toggle.custom_minimum_size.y = 38
		toggle.toggled.connect(func(open: bool):
			detail.visible = open
			toggle.text = "THU GỌN" if open else "XEM CHI TIẾT"
		)
		box.add_child(toggle)
		box.add_child(detail)


func _card(list: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _plain_label(value: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.autowrap_mode = TextServer.AUTOWRAP_OFF
	item.add_theme_font_size_override("font_size", maxi(18, font_size))
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return item


func _label(value: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", maxi(18, font_size))
	return item


func _local_time(utc: String) -> String:
	if utc.is_empty():
		return "Chưa có thông tin thời gian"
	var timestamp := Time.get_unix_time_from_datetime_string(utc)
	var local := Time.get_datetime_dict_from_unix_time(timestamp + int(Time.get_time_zone_from_system().bias) * 60)
	return "%02d/%02d/%04d  ·  %02d:%02d" % [local.day, local.month, local.year, local.hour, local.minute]


func _on_switch_patient_pressed() -> void:
	var new_id := _patient_id_edit.text.strip_edges()
	var new_name := _patient_name_edit.text.strip_edges()
	if new_id.is_empty():
		new_id = "BN001"
	Global.switch_patient(new_id, new_name)
	_refresh_all()


func _on_reset_patient_pressed() -> void:
	if Global.report_sync.busy:
		_on_cloud_sync_status_changed("Đang đồng bộ. Vui lòng đợi xong rồi reset hồ sơ.", false)
		return
	for job in Global.cloud_outbox:
		if job.patient_id == Global.current_patient_id and job.reset:
			_on_cloud_sync_status_changed("Hồ sơ đang chờ reset trên Cloud. Nhấn Đồng bộ để thử lại.", false)
			return
	if Global.cloud_db_enabled and Global.cloud_db_provider != "mongodb":
		_on_cloud_sync_status_changed("Reset đồng bộ hiện chỉ hỗ trợ MongoDB.", false)
		return
	_reset_target = Global.current_patient_id
	if _reset_dialog == null:
		_reset_dialog = ConfirmationDialog.new()
		_reset_dialog.title = "Xác nhận xóa dữ liệu hồ sơ"
		_reset_dialog.ok_button_text = "XÓA DỮ LIỆU HỒ SƠ"
		_reset_dialog.cancel_button_text = "GIỮ LẠI"
		add_child(_reset_dialog)
		_reset_dialog.borderless = true
		var frame := theme.get_stylebox("panel", "PanelContainer").duplicate()
		frame.content_margin_left = 24
		frame.content_margin_right = 24
		frame.content_margin_top = 24
		frame.content_margin_bottom = 24
		_reset_dialog.add_theme_stylebox_override("panel", frame)
		_reset_dialog.get_label().add_theme_color_override("font_color", Color("352716"))
		_reset_dialog.get_label().add_theme_font_size_override("font_size", 20)
		_reset_dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_reset_dialog.get_cancel_button().custom_minimum_size.y = 48
		_reset_dialog.confirmed.connect(func():
			if Global.report_sync.busy: return
			Global.reset_patient(_reset_target)
			_refresh_all()
		)
	_reset_dialog.dialog_text = "Xóa lịch sử, ROM và tiến độ của hồ sơ %s?\nThao tác áp dụng cả trên máy và MongoDB khi đồng bộ.\nCác hồ sơ khác được giữ nguyên." % _reset_target
	_reset_dialog.popup_centered(Vector2i(620, 220))
	_reset_dialog.get_cancel_button().grab_focus()


func _on_sync_cloud_pressed() -> void:
	if not Global.cloud_db_enabled or Global.cloud_db_url.is_empty():
		_cloud_modal.visible = true
		return
	Global.sync_patient_to_cloud(Global.current_patient_id)


func _on_save_cloud_config_pressed() -> void:
	var enabled := _cloud_enable_check.button_pressed
	var provider := "mongodb"
	if _cloud_provider_option.selected == 1:
		provider = "supabase"
	elif _cloud_provider_option.selected == 2:
		provider = "firebase"
	var url := _cloud_url_edit.text.strip_edges()
	var key := _cloud_key_edit.text.strip_edges()
	Global.save_cloud_config(enabled, provider, url, key)
	_cloud_modal.visible = false
	if enabled:
		Global.sync_patient_to_cloud(Global.current_patient_id)


func _on_cloud_sync_status_changed(status_text: String, success: bool) -> void:
	if _cloud_status_label == null:
		return
	_cloud_status_label.text = status_text
	_cloud_status_label.add_theme_color_override(
		"font_color",
		Color("8ef5a5") if success else Color("ff9e9e")
	)


func _initial_cloud_status_text() -> String:
	if Global.cloud_db_enabled and not Global.cloud_db_url.is_empty():
		return Global.cloud_sync_status if Global.cloud_is_online else "Đã cấu hình Cloud · Chưa xác nhận đồng bộ"
	return "Đang lưu trên máy · Chưa bật đồng bộ MongoDB"


func _build_history_filters() -> void:
	var dashboard := $Margin/Column/Scroll/Dashboard
	var filter_panel := PanelContainer.new()
	filter_panel.name = "HistoryFilters"
	dashboard.add_child(filter_panel)
	dashboard.move_child(filter_panel, dashboard.get_child_count() - 2)
	var filters := VBoxContainer.new()
	filter_panel.add_child(filters)
	var filter_heading := HBoxContainer.new()
	filter_heading.add_theme_constant_override("separation", 12)
	filters.add_child(filter_heading)
	_filter_count = _label("", 20)
	_filter_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filter_heading.add_child(_filter_count)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 8)
	filters.add_child(row)
	_map_filter = _add_filter(row, "Map", ["Tất cả map", "Map 1", "Map 2", "Map 3", "Map 4", "Map 5"])
	_status_filter = _add_filter(row, "Trạng thái", ["Tất cả trạng thái", "Hoàn thành", "Dừng sớm", "Gián đoạn"])
	_period_filter = _add_filter(row, "Thời gian", ["Toàn bộ thời gian", "7 ngày gần đây", "30 ngày gần đây"])
	var reset := Button.new()
	reset.name = "ResetHistoryFilters"
	reset.text = "BỎ LỌC"
	reset.custom_minimum_size.y = 42
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func():
		for filter in [_map_filter, _status_filter, _period_filter]: filter.select(0)
		_refresh_all())
	filter_heading.add_child(reset)
	_pending_label = _label("", 18)
	$Margin/Column.add_child(_pending_label)
	$Margin/Column.move_child(_pending_label, 2)
	_pending_label.add_theme_color_override("font_color", Color("fff1be"))
	_process(0)

func _add_filter(row: HFlowContainer, caption: String, options: Array) -> OptionButton:
	var group := VBoxContainer.new()
	row.add_child(group)
	group.add_child(_plain_label(caption, 18))
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(175, 42)
	for text in options: option.add_item(text)
	option.item_selected.connect(func(_index): _refresh_all())
	group.add_child(option)
	return option

func _process(_delta: float) -> void:
	if _pending_label == null: return
	var count := Global.cloud_outbox.size()
	if count == _last_pending: return
	_last_pending = count
	_pending_label.visible = count > 0 and _active_section == "overview"
	_pending_label.text = "%d yêu cầu đang chờ đồng bộ trên máy · Vào giao diện Quản lý → Đồng bộ Cloud ngay để thử lại." % count


func _build_default_rom_payload(_patient_id: String, sessions: Array, rom_points: Array) -> Dictionary:
	var baseline: Variant = null
	if not rom_points.is_empty():
		baseline = float(rom_points[0].get("rom_angle", 0.0))
	elif float(Global.max_rom_angle) > 0.0:
		baseline = float(Global.max_rom_angle)

	var selected_map: int = _map_filter.selected if _map_filter != null else 0
	var session_list: Array = []
	for s in sessions:
		if not s is Dictionary: continue
		var s_map := int(s.get("map_id", 0))
		if selected_map > 0 and s_map != selected_map:
			continue
		var val: Variant = null
		if s.has("rom_angle") and s["rom_angle"] != null:
			val = float(s["rom_angle"])
		elif s.has("calibration_rom_angle") and s["calibration_rom_angle"] != null:
			val = float(s["calibration_rom_angle"])
		elif s.has("max_rom") and s["max_rom"] != null:
			val = float(s["max_rom"])
		if val == null or float(val) <= 0.0:
			continue

		var date_str := ""
		for key in ["ended_at_utc", "started_at_utc", "completed_at_utc", "date"]:
			if s.has(key) and not str(s[key]).is_empty():
				date_str = str(s[key]).substr(0, 10)
				break
		if date_str.length() < 10:
			date_str = Time.get_date_string_from_system()

		session_list.append({
			"date": date_str,
			"value": roundf(float(val) * 10.0) / 10.0
		})

	if session_list.is_empty() and not rom_points.is_empty():
		for p in rom_points:
			session_list.append({
				"date": str(p.get("date", "")),
				"value": roundf(float(p.get("rom_angle", 0.0)) * 10.0) / 10.0
			})

	const MAP_NAMES := {
		1: "Map 1 · Ép hai bả vai",
		2: "Map 2 · Nâng tay áp tường",
		3: "Map 3 · Mở tay sang hai bên",
		4: "Map 4 · Hai tay sau đầu",
		5: "Map 5 · Kéo tay ngang ngực",
	}
	var context: String = MAP_NAMES.get(selected_map, "Toàn bộ bài tập") + " · ROM mỗi buổi"
	var target_val: Variant = 90.0 if not session_list.is_empty() or baseline != null else null

	return {
		"context_label": context,
		"unit": "degrees",
		"baseline": baseline,
		"target": target_val,
		"sessions": session_list
	}


# Call with one coherent exercise/side/metric series for the CURRENT patient.
# Returns false for stale responses, preventing data from another profile appearing.
func set_rom_report_data(patient_id: String, payload: Dictionary) -> bool:
	if patient_id != Global.current_patient_id: return false
	_rom_report_patient_id = patient_id
	_rom_report_payload = payload.duplicate(true)
	_refresh_all()
	return true


# BE enables this only after connecting csv_export_requested to a working exporter.
func set_csv_export_available(available: bool) -> void:
	_csv_available = available
	_refresh_csv_ui()


func _refresh_csv_ui() -> void:
	if _csv_button == null: return
	_csv_button.disabled = not _csv_available or not _csv_pending_id.is_empty()
	_csv_button.text = "ĐANG XUẤT CSV…" if not _csv_pending_id.is_empty() else "XUẤT BÁO CÁO CSV"
	if not _csv_pending_id.is_empty():
		_csv_status.text = "Đang xuất dữ liệu hồ sơ %s…" % _csv_pending_id
	elif _csv_available:
		_csv_status.text = "Hồ sơ %s · Toàn bộ buổi tập · Mở bằng Excel" % Global.current_patient_id
	else:
		_csv_status.text = "Hồ sơ %s · Chờ kết nối chức năng xuất dữ liệu" % Global.current_patient_id


func _on_csv_export_pressed() -> void:
	if not _csv_available or not _csv_pending_id.is_empty(): return
	_csv_pending_id = Global.current_patient_id
	_refresh_csv_ui()
	csv_export_requested.emit(_csv_pending_id)


# Call after save/cancel/error; message should contain a friendly result/file location.
func set_csv_export_result(patient_id: String, succeeded: bool, message: String) -> void:
	if patient_id != _csv_pending_id or _csv_pending_id.is_empty(): return
	_csv_pending_id = ""
	_refresh_csv_ui()
	if patient_id != Global.current_patient_id: return
	_csv_status.text = message if not message.is_empty() else ("Đã xuất báo cáo CSV." if succeeded else "Chưa xuất được báo cáo. Vui lòng thử lại.")


# Three views share the same profile and hooks without rebuilding data on navigation.
func _build_sections() -> void:
	var column: VBoxContainer = $Margin/Column
	var overview_scroll: ScrollContainer = $Margin/Column/Scroll
	var dashboard: VBoxContainer = overview_scroll.get_node("Dashboard")
	_section_views["overview"] = overview_scroll
	_section_scrolls["overview"] = overview_scroll

	var report_scroll := _new_section_scroll("ReportScroll")
	column.add_child(report_scroll)
	var report_content := VBoxContainer.new()
	report_content.name = "ReportContent"
	report_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_content.add_theme_constant_override("separation", 16)
	report_scroll.add_child(report_content)
	dashboard.get_node("ReportSummary").reparent(report_content)
	_rom_chart.reparent(report_content)
	_section_views["report"] = report_scroll
	_section_scrolls["report"] = report_scroll

	var history_page := VBoxContainer.new()
	history_page.name = "HistoryPage"
	history_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_page.add_theme_constant_override("separation", 12)
	column.add_child(history_page)
	dashboard.get_node("HistoryFilters").reparent(history_page)
	var history_scroll := _new_section_scroll("HistoryScroll")
	history_page.add_child(history_scroll)
	_session_list.reparent(history_scroll)
	_section_views["history"] = history_page
	_section_scrolls["history"] = history_scroll

	_section_nav = HBoxContainer.new()
	_section_nav.name = "SectionNavigation"
	_section_nav.add_theme_constant_override("separation", 12)
	column.add_child(_section_nav)
	column.move_child(_section_nav, 3)
	_section_patient = _label("", 18)
	_section_patient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_patient.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_section_patient.add_theme_color_override("font_color", Color("f5e9c7"))
	_section_nav.add_child(_section_patient)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for section in ["report", "history"]:
		var tab := Button.new()
		tab.name = "ReportTab" if section == "report" else "HistoryTab"
		tab.text = "BÁO CÁO" if section == "report" else "LỊCH SỬ TẬP"
		tab.custom_minimum_size = Vector2(160, 44)
		tab.add_theme_font_size_override("font_size", 18)
		tab.toggle_mode = true
		tab.button_group = group
		tab.pressed.connect(_show_section.bind(section, true))
		_section_nav.add_child(tab)
		_section_tabs[section] = tab

	var choices := GridContainer.new()
	choices.name = "SectionChoices"
	choices.columns = 2
	choices.add_theme_constant_override("h_separation", 16)
	choices.add_theme_constant_override("v_separation", 12)
	choices.resized.connect(func(): choices.columns = 1 if choices.size.x < 600 else 2)
	dashboard.add_child(choices)
	_add_section_choice(choices, "report", "BÁO CÁO", "Tổng kết buổi tập, tiến độ các map\nvà biểu đồ ROM.")
	_add_section_choice(choices, "history", "LỊCH SỬ TẬP", "Tìm buổi tập theo map, trạng thái\nvà xem kết quả chi tiết.")
	_show_section("overview")


func _new_section_scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	return scroll


func _add_section_choice(parent: GridContainer, section: String, heading: String, description: String) -> void:
	var button := Button.new()
	button.name = "OpenReportButton" if section == "report" else "OpenHistoryButton"
	button.custom_minimum_size.y = 132
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = heading + ": " + description.replace("\n", " ")
	button.pressed.connect(_show_section.bind(section, true))
	parent.add_child(button)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var title := _label(heading + "  ›", 24)
	var detail := _label(description, 18)
	for label in [title, detail]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", Color("352716"))
		content.add_child(label)
	_overview_choices[section] = button


func _show_section(section: String, focus_navigation := false) -> void:
	if not _section_views.has(section): return
	var previous_section := _active_section
	_active_section = section
	for key in _section_views:
		_section_views[key].visible = key == section
	var is_overview := section == "overview"
	_section_nav.visible = not is_overview
	_cloud_status_label.visible = is_overview
	_pending_label.visible = is_overview and Global.cloud_outbox.size() > 0
	_section_back.text = "‹ VỀ TRANG CHỦ" if is_overview else "‹ TỔNG QUAN"
	_section_title.text = {"overview": "BÁO CÁO & LỊCH SỬ TẬP", "report": "BÁO CÁO TẬP LUYỆN", "history": "LỊCH SỬ BUỔI TẬP"}[section]
	for key in _section_tabs:
		_section_tabs[key].set_pressed_no_signal(key == section)
	_refresh_section_context()
	if focus_navigation:
		if is_overview and _overview_choices.has(previous_section):
			_overview_choices[previous_section].grab_focus()
		elif _section_tabs.has(section):
			_section_tabs[section].grab_focus()


func _refresh_section_context() -> void:
	if _section_patient == null: return
	_section_patient.text = "Hồ sơ %s · %s" % [Global.current_patient_id, Global.current_patient_name]
	if _section_patient_id != Global.current_patient_id:
		_section_patient_id = Global.current_patient_id
		for scroll in _section_scrolls.values(): scroll.scroll_vertical = 0
