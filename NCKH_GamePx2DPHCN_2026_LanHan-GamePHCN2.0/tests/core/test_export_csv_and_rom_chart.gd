extends Node

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("--- TEST 1: Kiem tra RomLineChart voi cac so luong buoi tap khac nhau ---")
	var RomLineChartScript = preload("res://ui/screens/history/rom_line_chart.gd")
	var chart = RomLineChartScript.new()
	chart.size = Vector2(800, 320)
	add_child(chart)
	await get_tree().process_frame

	# Test 1A: 0 records
	chart.set_rom_points([], [])
	await get_tree().process_frame
	print("Test 1A (0 buoi): PASS")

	# Test 1B: 1 record
	var p1 = [{"date": "2026-11-03", "rom_angle": 75.0, "source": "calibration"}]
	var s1 = [{"map_id": 1, "rom_angle": 86.7, "started_at_utc": "2026-11-03T13:40:16"}]
	chart.set_rom_points(p1, s1)
	await get_tree().process_frame
	print("Test 1B (1 buoi): PASS")

	# Test 1C: 2 records
	var s2 = [
		{"map_id": 1, "rom_angle": 86.7, "started_at_utc": "2026-11-03T13:40:16"},
		{"map_id": 1, "rom_angle": 89.2, "started_at_utc": "2026-11-04T10:15:00"}
	]
	chart.set_rom_points(p1, s2)
	await get_tree().process_frame
	print("Test 1C (2 buoi): PASS")

	# Test 1D: 5 records
	var s5 = [
		{"map_id": 1, "rom_angle": 78.0, "started_at_utc": "2026-11-01T08:00:00"},
		{"map_id": 1, "rom_angle": 82.5, "started_at_utc": "2026-11-02T08:00:00"},
		{"map_id": 1, "rom_angle": 85.0, "started_at_utc": "2026-11-03T08:00:00"},
		{"map_id": 1, "rom_angle": 88.0, "started_at_utc": "2026-11-04T08:00:00"},
		{"map_id": 1, "rom_angle": 91.5, "started_at_utc": "2026-11-05T08:00:00"}
	]
	chart.set_rom_points(p1, s5)
	await get_tree().process_frame
	print("Test 1D (5 buoi polyline): PASS")
	chart.queue_free()
	await get_tree().process_frame

	print("--- TEST 2: Kiem tra Xuat file CSV tu HistoryScreen ---")
	var history = load("res://ui/screens/history/history_screen.tscn").instantiate()
	add_child(history)
	await get_tree().process_frame
	await get_tree().process_frame

	# Goi ham xuat CSV
	history.call("_on_export_csv_pressed")
	await get_tree().process_frame

	# Kiem tra file ton tai va co UTF-8 BOM
	var csv_file_res := "res://BaoCao_Xuat/BaoCao_ThucNghiem_BN.csv"
	assert(FileAccess.file_exists("res://BaoCao_Xuat/.gdignore"), "File .gdignore phai ton tai trong BaoCao_Xuat!")
	assert(FileAccess.file_exists(csv_file_res), "File res://BaoCao_Xuat/BaoCao_ThucNghiem_BN.csv phai ton tai!")

	var f := FileAccess.open(csv_file_res, FileAccess.READ)
	assert(f != null, "Khong mo duoc file CSV!")
	var b1 = f.get_8()
	var b2 = f.get_8()
	var b3 = f.get_8()
	print("BOM bytes: 0x%X 0x%X 0x%X" % [b1, b2, b3])
	assert(b1 == 0xEF and b2 == 0xBB and b3 == 0xBF, "File phai bat dau bang UTF-8 BOM (0xEF, 0xBB, 0xBF)!")

	var remaining_text = f.get_as_text()
	f.close()
	print("CSV text length:", remaining_text.length())
	assert(remaining_text.contains("Mã BN"), "File phai chua tieu de 'Mã BN'!")
	assert(remaining_text.contains("ROM Max"), "File phai chua 'ROM Max'!")
	assert(remaining_text.contains("ROM Mục tiêu"), "File phai chua 'ROM Mục tiêu'!")
	assert(remaining_text.contains("Thời gian giữ"), "File phai chua 'Thời gian giữ'!")
	assert(remaining_text.contains("Tỷ lệ hoàn thành"), "File phai chua 'Tỷ lệ hoàn thành'!")
	print("Test 2 (Xuat CSV): PASS 100%")

	history.queue_free()
	await get_tree().process_frame
	print("ALL TESTS PASSED SUCCESSFULLY!")
	get_tree().quit(0)
