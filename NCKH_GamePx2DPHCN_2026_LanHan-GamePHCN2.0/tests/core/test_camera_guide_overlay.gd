extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Global.selected_action = 1
	var map = load("res://maps/map_1/main_level.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud = map.get_node("GamePresentation")
	var instruction_panel = map.get_node("UI/InstructionPanel")

	# SCENARIO 1: Map intro guide is showing
	assert(instruction_panel.visible, "InstructionPanel phai dang hien thi o dau map")
	hud._sync_camera_visibility()
	assert(not hud.camera_box.visible, "CameraBox phai AN khi InstructionPanel dang mo (Khong duoc de len huong dan)")
	print("[PASS] Kich ban 1: CameraBox an hoan toan khi bang huong dan dau map mo.")

	# Gia lap camera nhan frame trong khi huong dan van mo
	var sample := Image.create(320, 240, false, Image.FORMAT_RGB8)
	sample.fill(Color("26434b"))
	PoseInput.camera_frame_received.emit(sample)
	await get_tree().process_frame
	hud._sync_camera_visibility()
	assert(not hud.camera_box.visible, "CameraBox van phai AN du co frame camera den")
	assert(hud.camera_rect.texture != null, "Texture camera van phai duoc cap nhat ngam san sang")
	print("[PASS] Kich ban 1: Nhan tin hieu camera ngam nhung CameraBox van khong de len huong dan.")

	# Nguoi choi bam SAN SANG -> vao game
	map.instruction_start_button.pressed.emit()
	await get_tree().process_frame
	hud._sync_camera_visibility()
	assert(not instruction_panel.visible, "InstructionPanel da dong")
	assert(hud.camera_box.visible, "CameraBox phai HIEN THI tro lai khi bat dau vao choi")
	print("[PASS] Kich ban 1: CameraBox xuat hien ngay khi nguoi choi nhan San sang.")

	# SCENARIO 2: Nguoi choi bam Xem huong dan [U]
	map._intro_running = false
	hud._review()
	await get_tree().process_frame
	assert(is_instance_valid(hud.replay), "Replay guide phai duoc tao thanh cong")
	assert(not hud.camera_box.visible, "CameraBox phai AN khi nguoi choi xem lai huong dan [U]")
	print("[PASS] Kich ban 2: CameraBox an hoan toan khi nguoi choi mo xem lai dong tac [U].")

	# Gia lap camera mat tin hieu trong khi xem lai
	hud._clear_camera("Hinh anh camera bi gian doan\nDang cho anh moi...")
	await get_tree().process_frame
	hud._sync_camera_visibility()
	assert(not hud.camera_box.visible, "CameraBox van phai AN du camera bi mat tin hieu/stale")
	print("[PASS] Kich ban 2: Thong bao mat tin hieu khong bi de len bang xem lai huong dan.")

	# Dong replay
	hud._resume()
	hud.resuming = 0.0 # Force resume ngay de test
	hud._process(0.1)
	await get_tree().process_frame
	assert(hud.replay == null, "Replay da duoc giai phong")
	hud._sync_camera_visibility()
	assert(hud.camera_box.visible, "CameraBox phai HIEN THI tro lai sau khi dong xem huong dan")
	print("[PASS] Kich ban 2: CameraBox tro lai binh thuong sau khi tiep tuc choi.")

	map.queue_free()
	await get_tree().process_frame
	print("--- TAT CA KIEM THU CAMERA GUIDE OVERLAY: HOAN TOAN DAT CHUAN ---")
	get_tree().quit()
