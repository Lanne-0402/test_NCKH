extends Node

var was_clicked := false

func _ready() -> void:
	print("--- BAT DAU KIEM THU HAND CURSOR LAYER ---")
	await get_tree().process_frame

	# 1. Kiem tra Autoload HandCursor
	var hand_cursor = get_node_or_null("/root/HandCursor")
	assert(hand_cursor != null, "HandCursor autoload phai ton tai!")
	print("[PASS] Autoload HandCursor da duoc dang ky thanh cong.")

	# 2. Kiem tra layer = 120
	assert(hand_cursor.layer == 120, "HandCursor layer phai la 120!")
	print("[PASS] HandCursor layer = 120 (lop tren cung).")

	# 3. Tao nut bam thu nghiem
	var test_btn := Button.new()
	test_btn.text = "TEST BUTTON"
	test_btn.position = Vector2(200, 200)
	test_btn.size = Vector2(150, 50)
	test_btn.pressed.connect(func(): was_clicked = true)
	add_child(test_btn)
	await get_tree().process_frame

	# 4. Gui goi tin hand_control vao vi tri cua nut
	var nx := 275.0 / 1152.0
	var ny := 225.0 / 648.0
	PoseInput.hand_control_received.emit({
		"active": true,
		"cursor_x": nx,
		"cursor_y": ny,
		"confidence": 0.95
	})

	# 5. Cho 1.8s (vuot qua Dwell Time 1.5s)
	print("Dang cho nap Dwell Time 1.5s...")
	var elapsed := 0.0
	while elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	assert(was_clicked, "Nut phai duoc kich hoat sau khi nap du 1.5s Dwell Time!")
	print("[PASS] Dwell Time 1.5s da kich hoat su kien pressed.emit() thanh cong!")

	# 6. Kiem tra vo hieu hoa con tro
	PoseInput.hand_control_received.emit({
		"active": false,
		"cursor_x": nx,
		"cursor_y": ny,
		"confidence": 0.0
	})
	await get_tree().process_frame
	assert(not hand_cursor.visual.visible, "Con tro phai an khi active = false!")
	print("[PASS] Con tro da an chinh xac khi active = false.")

	print("--- TAT CA KIEM THU HAND CURSOR: HOAN TOAN DAT CHUAN ---")
	get_tree().quit(0)
