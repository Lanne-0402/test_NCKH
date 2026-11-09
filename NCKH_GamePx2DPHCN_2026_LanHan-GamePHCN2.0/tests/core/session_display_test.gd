extends SceneTree
const Display = preload("res://ui/shared/session_display.gd")
func _initialize() -> void:
	assert(Display.number({}, "target_reps") == "—")
	assert(Display.duration({"active_seconds": null}, "active_seconds") == "Chưa có dữ liệu")
	assert(Display.duration({"active_seconds": -2}, "active_seconds") == "Chưa có dữ liệu")
	assert(Display.duration({"active_seconds": 0}, "active_seconds") == "00:00:00")
	assert(Display.duration({"active_seconds": 3661}, "active_seconds") == "01:01:01")
	assert(Display.status({"status": "stopped_early"}) == "Dừng sớm")
	assert(Display.status({"status": "interrupted"}) == "Gián đoạn")
	assert(Display.profile({}) == "Hồ sơ: Chưa xác định")
	assert(Display.goals({"phase_count": 2}).contains("— / —"))
	print("SESSION_DISPLAY_PASS")
	quit()
