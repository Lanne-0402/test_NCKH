extends Node
var map_id := 1
var action: AudioStreamPlayer
var effects: AudioStreamPlayer
var session: Node
var countdown: Label
var last_count := ""
var last_tracking_warning := -10000
var last_rejected := -10000
var previous_pause := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = get_parent().get_node("ExerciseSession")
	countdown = get_parent().get_node("UI/CountdownLabel")
	action = AudioStreamPlayer.new()
	action.volume_db = -13
	add_child(action)
	effects = AudioStreamPlayer.new()
	effects.volume_db = -7
	add_child(effects)
	AudioManager.play_music(map_id)
	session.hold_started.connect(_hold)
	session.hold_interrupted.connect(func(_data): action.stop())
	session.repetition_accepted.connect(_accepted)
	session.repetition_rejected.connect(_rejected)
	session.state_changed.connect(_state)
	session.session_completed.connect(func(_data): _effect("session_complete"))
	var controller := get_parent().get_node_or_null("Map%dController" % map_id)
	if controller != null:
		if map_id == 1:
			controller.action_window_changed.connect(func(open: bool):
				if open and session.state == ExerciseSession.State.ACTIVE: _effect("map_01_charge"))
		if map_id == 2:
			controller.action_window_changed.connect(func(open: bool):
				if open: _effect("map_02_stone_settle"))
		if map_id == 4:
			controller.climb_progress_changed.connect(func(completed: int, _total: int):
				if completed > 0: _effect("map_04_land"))

func _effect(sound: String) -> void:
	effects.stream = AudioManager.stream("sfx/" + sound + ".wav")
	effects.play()

func _loop(sound: String) -> void:
	action.stream = AudioManager.stream("sfx/" + sound + ".wav", true)
	action.play()

func _hold(_data: Dictionary) -> void:
	if get_tree().paused: return
	if map_id == 2: _loop("map_02_lift")
	if map_id == 3: _loop("map_03_wall_push")

func _accepted(_data: Dictionary) -> void:
	if map_id != 5: action.stop()
	match map_id:
		1: _effect("map_01_rock_break")
		2: _effect("map_02_lift_success")
		3: _effect("rep_success")
		4: _effect("map_04_jump")
		5: _effect("rep_success")

func _rejected(_data: Dictionary) -> void:
	action.stop()
	var now := Time.get_ticks_msec()
	if now - last_rejected > 1500:
		last_rejected = now
		_effect("exercise_retry")

func _state(current: int, previous: int) -> void:
	if current != ExerciseSession.State.ACTIVE: action.stop()
	elif map_id == 5: _loop("map_05_breath")
	if current == ExerciseSession.State.ACTIVE and previous == ExerciseSession.State.READY:
		_effect("exercise_start")
	if current == ExerciseSession.State.TRACKING_LOST:
		var now := Time.get_ticks_msec()
		if now - last_tracking_warning > 10000:
			last_tracking_warning = now
			_effect("tracking_lost")

func _process(_delta: float) -> void:
	var paused := get_tree().paused
	if paused and not previous_pause:
		action.stop()
		effects.stop()
		AudioManager.play_sfx("pause")
	elif previous_pause and not paused and map_id == 5 and session.state == ExerciseSession.State.ACTIVE:
		_loop("map_05_breath")
	previous_pause = paused
	# A changed integer on the actual countdown label triggers one tick only.
	var value := countdown.text if countdown.visible else ""
	if value != last_count:
		last_count = value
		if value.is_valid_int() and not paused: _effect("countdown_tick")

func _exit_tree() -> void:
	action.stop()
	action.stream = null
	effects.stop()
	effects.stream = null
	if is_instance_valid(AudioManager.music) and AudioManager.current_track == map_id:
		AudioManager.music.stop()
