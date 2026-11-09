extends Node

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("--- TEST HOLD_INTERRUPTED FEEDBACK ---")
	var map1 = load("res://maps/map_1/main_level.tscn").instantiate()
	add_child(map1)
	await get_tree().process_frame
	await get_tree().process_frame

	# Kiem tra ban dich tieng Viet
	var text = map1.call("_feedback_text", "HOLD_INTERRUPTED")
	print("Feedback text for HOLD_INTERRUPTED:", text)
	assert(text == "Giữ chưa đủ thời gian! Hãy thử lại", "Map 1 phai dich dung chuoi tieng Viet!")

	# Kiem tra khi phat HOLD_INTERRUPTED
	map1.call("_on_session_feedback_changed", "HOLD_INTERRUPTED")
	assert(map1.feedback_label.text.contains("Giữ chưa đủ thời gian! Hãy thử lại"), "Label phai hien thi tieng Viet!")
	assert(map1.feedback_label.modulate.r > 0.8, "Label phai co mau do!")
	print("Trigger HOLD_INTERRUPTED: PASS")

	# Cho 2.2 giay de timeout tu dong khoi phuc
	await get_tree().create_timer(2.2).timeout
	print("Label after timeout:", map1.feedback_label.text)
	assert(not map1.feedback_label.text.contains("Giữ chưa đủ thời gian"), "Sau timeout 2.0s phai tu dong chuyen sang huong dan hanh dong!")
	print("Auto-restore after 2.0s: PASS")

	map1.queue_free()
	print("ALL HOLD_INTERRUPTED TESTS PASSED 100%!")
	get_tree().quit(0)
