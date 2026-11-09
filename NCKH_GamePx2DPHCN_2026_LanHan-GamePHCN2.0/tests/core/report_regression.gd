extends Node
const Data := preload("res://core/autoload/report_data.gd")
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	Global.persistence_enabled = false
	assert(not Global.persistence_enabled)
	Global.session_history = [{"session_id": "legacy"}, {"session_id": "one", "patient_id": "BN001"}, {"session_id": "two", "patient_id": "BN002"}]
	assert(Global.get_patient_sessions("BN001").size() == 1)
	assert(Global.get_patient_sessions("BN002").size() == 1)
	var a := {"patient_id": "BN001", "sessions": [{"session_id": "a", "patient_id": "BN001"}]}
	var b := {"patient_id": "BN001", "sessions": [{"session_id": "b", "patient_id": "BN001"}]}
	assert(Data.merge_profile(a,b).sessions.size() == 2)
	b["generation"] = 1
	assert(Data.merge_profile(a,b).sessions.size() == 1)
	assert(Data.calibration_points([{"date": "2026-11-01", "source": "session", "rom_angle": 90}]).is_empty())
	Global.session_history = []
	Global.rom_history = []
	var screen = load("res://ui/screens/history/history_screen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	assert(screen._weekly_stats_label.text.contains("Chưa có dữ liệu"))
	assert(screen._map_progress_label.text.contains("0/15 (0%)"))
	screen._update_weekly_summary_cards([], [{"date":"2026-10-01", "rom_angle":80}, {"date":"2026-11-01", "rom_angle":60}])
	assert(screen._weekly_stats_label.text.contains("Giảm"))
	screen._on_reset_patient_pressed()
	assert(screen._reset_dialog.visible)
	assert(Global.session_history.is_empty())
	screen.queue_free()
	var session := ExerciseSession.new()
	add_child(session)
	session.config = {"phase_count": 2, "repetitions_per_phase": 5}
	session._patient_id = "TEST"
	session.total_valid_reps = 3
	session._calibration_rom = 75.0
	var report: Dictionary = session._build_summary("stopped_early")
	assert(report.target_reps == 10 and report.completed_reps == 3)
	assert(report.status == "stopped_early" and not report.has("rom_angle"))
	assert(report.calibration_rom_angle == 75.0)
	var fake = preload("res://tests/core/report_fake_sync.gd").new()
	add_child(fake)
	Global.session_history = [{"session_id":"local", "patient_id":"BN001"}]
	Global._sync_active_patient_into_profiles()
	fake.replies = [{"code":200,"data":{"patient_id":"BN001","sessions":[{"session_id":"remote","patient_id":"BN001"}]}}, {"code":200,"data":{"ok":true,"patient_id":"BN001"}}]
	assert(await fake._perform({"patient_id":"BN001","reset":false}))
	assert(fake.calls.size() == 2)
	assert(fake.calls[0].method == HTTPClient.METHOD_GET)
	assert(fake.calls[1].payload.sessions.size() == 2)
	assert(Global.get_patient_sessions("BN001").size() == 2)
	fake.replies = [{"code":0,"data":{}}]
	assert(not await fake._perform({"patient_id":"BN001","reset":false}))
	assert(not Global.cloud_is_online)
	fake.queue_free()
	session.queue_free()
	await get_tree().process_frame
	print("REPORT_REGRESSION_PASS")
	get_tree().quit()
