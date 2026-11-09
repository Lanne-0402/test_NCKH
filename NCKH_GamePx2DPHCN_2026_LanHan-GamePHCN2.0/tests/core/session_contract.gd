extends Node
const Display := preload("res://ui/shared/session_display.gd")
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	assert(Display.number({"target_reps": 1.5}, "target_reps") == "—")
	assert(Display.duration({"active_seconds":0},"active_seconds") == "00:00:00")
	assert(Display.duration({"active_seconds":null},"active_seconds") == "Chưa có dữ liệu")
	assert(Display.duration({"active_seconds":NAN},"active_seconds") == "Chưa có dữ liệu")
	assert(Display.profile({"patient_id":null,"profile_id":"OLD"}) == "Hồ sơ: OLD")
	assert(Display.compact_details({}).contains("Mất nhận diện: Chưa có dữ liệu"))
	Global.session_history = []
	var session := ExerciseSession.new()
	add_child(session)
	session.set_process(false)
	session.config = {"phase_count":2, "repetitions_per_phase":5}
	session._patient_id = "TEST-OWNER"
	session._patient_name = "Synthetic"
	session.session_id = "contract-test"
	session._session_started = true
	session.state = ExerciseSession.State.ACTIVE
	session._process(12.5)
	session.state = ExerciseSession.State.RESTING
	session.rest_seconds_remaining = 30
	session._process(4)
	session.state = ExerciseSession.State.TRACKING_LOST
	session._process(3)
	session._menu_paused = true
	session._process(2)
	session.total_valid_reps = 5
	# Exiting during rest after set 1 must retain one completed set.
	session.current_phase = 1
	var stopped := session._build_summary("stopped_early")
	assert(stopped.completed_sets == 1 and stopped.target_sets == 2)
	assert(stopped.completed_reps == 5 and stopped.target_reps == 10)
	assert(stopped.active_seconds == 12.5 and stopped.rest_seconds == 4)
	assert(stopped.paused_seconds == 2 and stopped.tracking_lost_seconds == 3)
	assert(stopped.patient_id == "TEST-OWNER" and stopped.duration_source == "godot_state_timer")
	assert(not stopped.has("completed_at_utc"))
	session.stop_session("user_cancelled")
	assert(Global.session_history.size() == 1 and Global.session_history[0].status == "stopped_early")
	session.stop_session("scene_changed")
	assert(Global.session_history.size() == 1)
	session._session_started = true
	session.session_id = "contract-interrupted"
	session.stop_session("provider_shutdown")
	assert(Global.session_history[-1].status == "interrupted")
	session.total_valid_reps = 10
	var done := session._build_summary("completed")
	assert(done.completed_sets == 2 and done.has("completed_at_utc"))
	session.queue_free()
	await get_tree().process_frame
	print("SESSION_CONTRACT_PASS")
	get_tree().quit()
