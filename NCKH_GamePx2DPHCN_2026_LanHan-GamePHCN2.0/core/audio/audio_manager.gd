extends Node
const ROOT := "res://assets/audio_placeholder/"
const TRACKS := ["menu_theme", "map_01_forest_path", "map_02_stone_lift", "map_03_wall_push", "map_04_cliff_climb", "map_05_meditation"]
var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var cache: Dictionary = {}
var current_track := -1
var last_scene: Node
var hover_time := 0
var click_time := 0
var music_fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = AudioStreamPlayer.new()
	music.volume_db = -14
	add_child(music)
	for i in range(6):
		var player := AudioStreamPlayer.new()
		player.volume_db = -8
		add_child(player)
		voices.append(player)
	get_tree().node_added.connect(_wire_button)
	_scan_buttons(get_tree().root)

func _scan_buttons(node: Node) -> void:
	_wire_button(node)
	for child in node.get_children(): _scan_buttons(child)

func _wire_button(node: Node) -> void:
	if not node is BaseButton or node.has_meta("placeholder_audio"): return
	node.set_meta("placeholder_audio", true)
	node.pressed.connect(_click)
	node.mouse_entered.connect(func():
		if is_instance_valid(node) and not node.disabled and node.is_visible_in_tree():
			var now := Time.get_ticks_msec()
			if now - hover_time > 180:
				hover_time = now
				play_sfx("ui_hover"))

func _click() -> void:
	var now := Time.get_ticks_msec()
	if now - click_time < 50: return
	click_time = now
	play_sfx("ui_click")

func stream(path: String, looping := false) -> AudioStream:
	var key := path + str(looping)
	if cache.has(key): return cache[key]
	var source := load(ROOT + path) as AudioStream
	if source == null: return null
	var result := source.duplicate() as AudioStream
	if result is AudioStreamWAV and looping:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_begin = 0
		result.loop_end = int(round(result.get_length() * result.mix_rate))
	cache[key] = result
	return result

func stop_music() -> void:
	if music_fade != null: music_fade.kill()
	if music != null:
		music.stop()
		music.stream = null
	current_track = -1

func stop_all_sfx() -> void:
	for player in voices:
		if player != null: player.stop()

func play_music(id: int) -> void:
	id = clampi(id, 0, 5)
	if current_track == id and music.playing: return
	current_track = id
	if music_fade != null: music_fade.kill()
	music.stream = stream("music/" + TRACKS[id] + "_loop.wav", true)
	music.volume_db = -40
	music.play()
	music_fade = create_tween()
	music_fade.tween_property(music, "volume_db", -14.0, 0.4)

func play_sfx(sound: String) -> void:
	for player in voices:
		if not player.playing:
			player.volume_db = -18 if sound == "ui_hover" else (-12 if sound == "ui_click" else -8)
			player.stream = stream("sfx/" + sound + ".wav")
			player.play()
			return

func _process(_delta: float) -> void:
	music.stream_paused = get_tree().paused
	var scene := get_tree().current_scene
	if scene != last_scene:
		last_scene = scene
		for player in voices: player.stop()
		if is_instance_valid(scene) and scene.scene_file_path.begins_with("res://ui/screens/"):
			play_music(0)

func attach_level(level: Node, id: int) -> void:
	if not is_instance_valid(level) or level.has_node("GameplayAudio"): return
	var audio := preload("res://core/audio/gameplay_audio.gd").new()
	audio.name = "GameplayAudio"
	audio.map_id = id
	level.add_child(audio)

func _exit_tree() -> void:
	if music_fade != null: music_fade.kill()
	music.stop()
	music.stream = null
	for player in voices:
		player.stop()
		player.stream = null
	cache.clear()
