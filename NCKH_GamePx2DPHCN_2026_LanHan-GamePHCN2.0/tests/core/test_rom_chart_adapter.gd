extends Node

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("--- BAT DAU TEST ROM CHART ADAPTER (KET NOI BACKEND - FRONTEND HAN) ---")
	
	# Chuẩn bị dữ liệu mẫu cho bệnh nhân BN001
	var pid := "BN001"
	Global.current_patient_id = pid
	Global.max_rom_angle = 68.5
	Global.rom_history = [
		{"date": "2026-11-01", "rom_angle": 68.5, "source": "calibration", "patient_id": pid}
	]
	Global.session_history = [
		{"patient_id": pid, "map_id": 1, "calibration_rom_angle": 72.0, "started_at_utc": "2026-11-02T08:00:00", "valid_reps": 10, "status": "completed"},
		{"patient_id": pid, "map_id": 1, "rom_angle": 76.5, "started_at_utc": "2026-11-03T08:00:00", "valid_reps": 10, "status": "completed"},
		{"patient_id": pid, "map_id": 2, "rom_angle": 81.0, "started_at_utc": "2026-11-04T08:00:00", "valid_reps": 10, "status": "completed"},
		{"patient_id": pid, "map_id": 1, "rom_angle": 88.0, "started_at_utc": "2026-11-05T08:00:00", "valid_reps": 10, "status": "completed"}
	]

	var history_scene = load("res://ui/screens/history/history_screen.tscn")
	var history = history_scene.instantiate()
	add_child(history)
	await get_tree().process_frame
	await get_tree().process_frame

	var chart = history.get("_rom_chart")
	assert(chart != null, "RomLineChart phai duoc khoi tao trong HistoryScreen")

	# Test 1: Kiem tra payload tu dong duoc tao tu Backend sessions
	print("Test 1: Kiem tra du lieu tu dong nap vao RomLineChart...")
	assert(chart._legacy == false, "Chart phai o che do set_progress_data (khong phai legacy)")
	assert(chart._unit == "degrees", "Don vi phai la degrees (do)")
	assert(is_equal_approx(float(chart._baseline), 68.5), "Baseline phai la 68.5 tu calibration")
	assert(is_equal_approx(float(chart._target), 90.0), "Muc tieu phai la 90.0 do")
	assert(chart._points.size() == 4, "Phai co 4 diem tap duoc load vao chart")
	print("  -> Baseline: ", chart._baseline, "° | Target: ", chart._target, "° | So diem: ", chart._points.size())
	print("  -> Test 1 PASS!")

	# Test 2: Kiem tra loc theo Map 1
	print("Test 2: Kiem tra loc theo Map 1...")
	var map_filter: OptionButton = history.get("_map_filter")
	assert(map_filter != null, "_map_filter phai ton tai")
	map_filter.select(1) # Chon Map 1
	history._refresh_all()
	await get_tree().process_frame

	assert(chart._points.size() == 3, "Map 1 chi co 3 buoi tap")
	assert(chart._context.contains("Map 1"), "Tieu de phai chua Map 1")
	print("  -> Map 1 filter thanh cong, context: ", chart._context, " | So diem: ", chart._points.size())
	print("  -> Test 2 PASS!")

	# Test 3: Kiem tra API set_rom_report_data do Han yeu cau
	print("Test 3: Kiem tra API set_rom_report_data()...")
	var wrong_pid_success: bool = history.set_rom_report_data("BN_KHAC", {
		"context_label": "Hacker data",
		"unit": "degrees",
		"baseline": 50.0,
		"target": 90.0,
		"sessions": []
	})
	assert(wrong_pid_success == false, "set_rom_report_data phai tu choi neu sai patient_id")

	var custom_payload: Dictionary = {
		"context_label": "Bác sĩ can thiệp · Map 1 · Ép hai bả vai",
		"unit": "degrees",
		"baseline": 65.0,
		"target": 90.0,
		"sessions": [
			{"date": "2026-11-05", "value": 85.5}
		]
	}
	var correct_pid_success: bool = history.set_rom_report_data(pid, custom_payload)
	assert(correct_pid_success == true, "set_rom_report_data phai thanh cong khi dung patient_id")
	assert(chart._context == "Bác sĩ can thiệp · Map 1 · Ép hai bả vai")
	assert(chart._points.size() == 1)
	assert(is_equal_approx(float(chart._points[0]["rom_angle"]), 85.5))
	print("  -> API set_rom_report_data hoat dong hoan hao!")
	print("  -> Test 3 PASS!")

	# Test 4: Chuyen section qua tab 'report' va kiem tra hien thi
	print("Test 4: Kiem tra chuyen giao dien qua Tab Báo cáo...")
	history._show_section("report")
	await get_tree().process_frame
	var report_view = history._section_views.get("report")
	assert(report_view != null and report_view.visible == true, "Tab Bao cao phai hien thi")
	assert(chart.is_inside_tree() and chart.visible == true, "RomLineChart phai nam trong tree va hien thi")
	print("  -> Tab Bao cao va RomLineChart hien thi chuan xac!")
	print("  -> Test 4 PASS!")

	# Test 5: Tuong thich nguoc set_rom_points (legacy adapter)
	print("Test 5: Kiem tra tuong thich nguoc cho set_rom_points...")
	var legacy_chart = load("res://ui/screens/history/rom_line_chart.gd").new()
	add_child(legacy_chart)
	legacy_chart.set_rom_points([{"date": "2026-11-01", "rom_angle": 70.0, "source": "calibration"}])
	assert(legacy_chart._legacy == true)
	# Goi voi 2 tham so (backward compatibility)
	legacy_chart.set_rom_points([{"date": "2026-11-02", "rom_angle": 75.0, "source": "calibration"}], [{"session": 1}])
	assert(legacy_chart._points.size() == 1)
	legacy_chart.queue_free()
	print("  -> Tuong thich nguoc 1 tham so va 2 tham so hoan toan thanh cong!")
	print("  -> Test 5 PASS!")

	history.queue_free()
	await get_tree().process_frame

	print("--- TAT CA CAC TEST CHO ROM CHART ADAPTER DEU PASS 100% ---")
	get_tree().quit(0)
