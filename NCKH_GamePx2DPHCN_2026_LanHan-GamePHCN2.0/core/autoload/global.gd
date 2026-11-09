extends Node

signal save_finished(success: bool)
signal patient_profile_changed(patient_id: String)
signal cloud_sync_status_changed(status_text: String, success: bool)

const ReportData := preload("res://core/autoload/report_data.gd")
var cloud_outbox: Array = []
var report_sync: Node

const SAVE_VERSION := 1
var save_path := "user://player_progress.json"
var cloud_config_path := "user://cloud_config.json"
var persistence_enabled := true
var volume_percent := 100.0
var audio_muted := false
var session_history: Array = []
var last_save_error := ""

# --- QUAN LY HO SO NGUOI TAP THEO ID & LICH SU BIEN DO ROM ---
var current_patient_id := "BN001"
var current_patient_name := "Bệnh nhân BN001"
var patient_profiles: Dictionary = {}
var rom_history: Array = [] # [{ "date": "2026-10-24", "rom_angle": 82.5, "source": "calibration" }]

# Danh sach 10 Ma ID Benh nhan san sang cho thu nghiem lam sang NCKH (BN001 - BN010)
const PRESET_PATIENT_IDS: Array[String] = [
	"BN001", "BN002", "BN003", "BN004", "BN005",
	"BN006", "BN007", "BN008", "BN009", "BN010"
]

const PRESET_PATIENTS: Array[Dictionary] = [
	{"id": "BN001", "name": "Bệnh nhân BN001"},
	{"id": "BN002", "name": "Bệnh nhân BN002"},
	{"id": "BN003", "name": "Bệnh nhân BN003"},
	{"id": "BN004", "name": "Bệnh nhân BN004"},
	{"id": "BN005", "name": "Bệnh nhân BN005"},
	{"id": "BN006", "name": "Bệnh nhân BN006"},
	{"id": "BN007", "name": "Bệnh nhân BN007"},
	{"id": "BN008", "name": "Bệnh nhân BN008"},
	{"id": "BN009", "name": "Bệnh nhân BN009"},
	{"id": "BN010", "name": "Bệnh nhân BN010"},
]

# --- CAU HINH ONLINE CLOUD DATABASE (MONGODB / SUPABASE / FIREBASE CHO WEB APP) ---
# provider: "mongodb" | "supabase" | "firebase"
const DEFAULT_MONGO_BRIDGE_URL := "http://127.0.0.1:8766"
var cloud_db_enabled := false
var cloud_db_provider := "mongodb"
var cloud_db_url := "mongodb://localhost:27017"
var cloud_db_api_key := "rehab_pixel_game"
var cloud_sync_status := "Lưu cục bộ (Nhấn 'Cấu hình DB Online' để bật MongoDB)"
var cloud_is_online := false
var _http_sync_profile: HTTPRequest
var _http_sync_session: HTTPRequest
var _http_fetch_profile: HTTPRequest


func _ready() -> void:
	# Tu dong phong to cua so game fit voi toan bo khung man hinh may tinh
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

	add_child(preload("res://ui/shared/scene_reveal.gd").new())
	add_child(preload("res://ui/shared/save_notice.gd").new())
	add_child(preload("res://ui/shared/screen_keyboard.gd").new())

	_setup_cloud_http_nodes()
	report_sync = preload("res://core/autoload/report_sync.gd").new()
	add_child(report_sync)

	# Smoke tests never touch the player's real profile.
	for argument in OS.get_cmdline_user_args():
		if argument == "--no-save":
			persistence_enabled = false
		elif argument.begins_with("--save-path="):
			save_path = argument.trim_prefix("--save-path=")
	if persistence_enabled:
		load_cloud_config()
		load_progress()
	else:
		_ensure_current_patient_profile()
	apply_audio()
	report_sync.kick.call_deferred()


func _setup_cloud_http_nodes() -> void:
	_http_sync_profile = HTTPRequest.new()
	_http_sync_profile.name = "HttpSyncProfile"
	_http_sync_profile.timeout = 10.0
	add_child(_http_sync_profile)
	_http_sync_profile.request_completed.connect(_on_sync_profile_completed)

	_http_sync_session = HTTPRequest.new()
	_http_sync_session.name = "HttpSyncSession"
	_http_sync_session.timeout = 10.0
	add_child(_http_sync_session)
	_http_sync_session.request_completed.connect(_on_sync_session_completed)

	_http_fetch_profile = HTTPRequest.new()
	_http_fetch_profile.name = "HttpFetchProfile"
	_http_fetch_profile.timeout = 10.0
	add_child(_http_fetch_profile)
	_http_fetch_profile.request_completed.connect(_on_fetch_profile_completed)


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume_percent / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, audio_muted)


func set_audio_settings(volume: float, muted: bool) -> void:
	volume_percent = clampf(volume, 0.0, 100.0)
	audio_muted = muted
	apply_audio()
	save_progress()


func _valid_save(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != SAVE_VERSION:
		return false
	if not value.get("levels") is Dictionary or not value.get("audio") is Dictionary or not value.get("sessions") is Array:
		return false
	var audio: Dictionary = value.audio
	if not (audio.get("volume") is float or audio.get("volume") is int) or not audio.get("muted") is bool:
		return false
	if not is_finite(float(audio.volume)) or float(audio.volume) < 0 or float(audio.volume) > 100:
		return false
	for action in range(1, 6):
		var level: Variant = value.levels.get(str(action))
		if not (level is float or level is int) or level < 1 or level > 3 or float(level) != floorf(float(level)):
			return false
	for entry in value.sessions:
		if not entry is Dictionary or not entry.get("session_id") is String:
			return false
	return true


func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	var value: Variant = parser.data
	return value if _valid_save(value) else null


func load_progress() -> bool:
	var value: Variant = _read_save(save_path)
	if value == null:
		value = _read_save(save_path + ".bak")
	if value == null:
		_ensure_current_patient_profile()
		return false
	for action in range(1, 6):
		unlocked_levels_by_action[action] = int(value.levels[str(action)])
	highest_unlocked_level = get_highest_unlocked_level(selected_action)
	volume_percent = float(value.audio.volume)
	audio_muted = bool(value.audio.muted)
	session_history = value.sessions.duplicate(true)
	cloud_outbox = value.get("cloud_outbox", []).duplicate(true)

	if value.get("current_patient_id") is String and not str(value.get("current_patient_id")).strip_edges().is_empty():
		current_patient_id = str(value.get("current_patient_id")).strip_edges()
	if value.get("current_patient_name") is String and not str(value.get("current_patient_name")).strip_edges().is_empty():
		current_patient_name = str(value.get("current_patient_name")).strip_edges()
	if value.get("patient_profiles") is Dictionary:
		patient_profiles = value.get("patient_profiles").duplicate(true)
	if value.get("rom_history") is Array:
		rom_history = value.get("rom_history").duplicate(true)
	if value.get("max_rom_angle") is float or value.get("max_rom_angle") is int:
		max_rom_angle = float(value.get("max_rom_angle", 0.0))

	_ensure_current_patient_profile()
	_load_active_patient_from_profiles()
	apply_audio()
	return true


func save_progress() -> bool:
	_sync_active_patient_into_profiles()
	if not persistence_enabled:
		return true
	var levels := {}
	for action in range(1, 6):
		levels[str(action)] = get_highest_unlocked_level(action)
	var value := {
		"version": SAVE_VERSION,
		"cloud_outbox": cloud_outbox,
		"levels": levels,
		"audio": {"volume": volume_percent, "muted": audio_muted},
		"sessions": session_history,
		"current_patient_id": current_patient_id,
		"current_patient_name": current_patient_name,
		"max_rom_angle": max_rom_angle,
		"rom_history": rom_history,
		"patient_profiles": patient_profiles,
	}
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _save_failed("Không thể ghi dữ liệu tiến độ.")
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or _read_save(temporary) == null:
		return _save_failed("Không thể hoàn tất ghi dữ liệu tiến độ.")
	# Preserve the last valid file, never replace a good backup with corrupt data.
	if _read_save(save_path) != null:
		if DirAccess.copy_absolute(save_path, save_path + ".bak") != OK:
			return _save_failed("Không thể tạo bản sao lưu tiến độ.")
	if DirAccess.rename_absolute(temporary, save_path) != OK:
		return _save_failed("Không thể cập nhật file tiến độ.")
	last_save_error = ""
	save_finished.emit(true)
	return true


func _save_failed(message: String) -> bool:
	last_save_error = message
	save_finished.emit(false)
	push_warning(message)
	return false


func _clean_legacy_demo_data() -> void:
	var cleaned := false
	var valid_sessions: Array = []
	for s in session_history:
		if s is Dictionary:
			var sid := str(s.get("session_id", ""))
			if sid.begins_with("demo-"):
				cleaned = true
				continue
			valid_sessions.append(s)
	if cleaned:
		session_history = valid_sessions



func _ensure_current_patient_profile() -> void:
	if current_patient_id.strip_edges().is_empty():
		current_patient_id = "BN001"
	# Dam bao luon co du 10 ID (BN001 - BN010) san sang nhan du lieu nguoi tap that
	for pid in PRESET_PATIENT_IDS:
		if not patient_profiles.has(pid):
			var default_levels := {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1}
			patient_profiles[pid] = {
				"patient_id": pid,
				"patient_name": "Bệnh nhân " + pid,
				"max_rom_angle": 0.0,
				"levels": default_levels,
				"rom_history": [],
				"sessions": [],
				"updated_at_utc": Time.get_datetime_string_from_system(true),
			}
	_clean_legacy_demo_data()
	if not patient_profiles.has(current_patient_id):
		current_patient_id = "BN001"


func _sync_active_patient_into_profiles() -> void:
	_ensure_current_patient_profile()
	var levels := {}
	for action in range(1, 6):
		levels[str(action)] = get_highest_unlocked_level(action)
	patient_profiles[current_patient_id] = {
		"patient_id": current_patient_id,
		"generation": int(patient_profiles.get(current_patient_id, {}).get("generation", 0)),
		"patient_name": current_patient_name,
		"max_rom_angle": max_rom_angle,
		"levels": levels,
		"rom_history": rom_history.duplicate(true),
		"sessions": get_patient_sessions(current_patient_id),
		"updated_at_utc": Time.get_datetime_string_from_system(true),
	}


func _load_active_patient_from_profiles() -> void:
	if not patient_profiles.has(current_patient_id):
		return
	var prof: Dictionary = patient_profiles[current_patient_id]
	current_patient_name = str(prof.get("patient_name", "Bệnh nhân " + current_patient_id))
	max_rom_angle = float(prof.get("max_rom_angle", 0.0))
	if prof.get("levels") is Dictionary:
		for action in range(1, 6):
			unlocked_levels_by_action[action] = clampi(int(prof.levels.get(str(action), 1)), 1, 3)
	highest_unlocked_level = get_highest_unlocked_level(selected_action)
	if prof.get("rom_history") is Array:
		rom_history = prof.get("rom_history").duplicate(true)
	else:
		rom_history = []


func switch_patient(new_patient_id: String, new_patient_name := "") -> void:
	var clean_id := new_patient_id.strip_edges().to_upper()
	if clean_id.is_empty():
		return
	_sync_active_patient_into_profiles()
	current_patient_id = clean_id
	if not patient_profiles.has(clean_id):
		var default_name := new_patient_name.strip_edges() if not new_patient_name.strip_edges().is_empty() else "Bệnh nhân " + clean_id
		patient_profiles[clean_id] = {
			"patient_id": clean_id,
			"patient_name": default_name,
			"max_rom_angle": 0.0,
			"levels": {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1},
			"rom_history": [],
			"sessions": [],
			"updated_at_utc": Time.get_datetime_string_from_system(true),
		}
	else:
		if not new_patient_name.strip_edges().is_empty():
			patient_profiles[clean_id]["patient_name"] = new_patient_name.strip_edges()
	_load_active_patient_from_profiles()
	save_progress()
	patient_profile_changed.emit(current_patient_id)
	if is_cloud_configured():
		fetch_patient_from_cloud(current_patient_id)


func reset_patient(target_id := "") -> void:
	if report_sync.busy: return
	var pid := current_patient_id if target_id.is_empty() else target_id.strip_edges().to_upper()
	var generation := int(patient_profiles.get(pid, {}).get("generation", 0))
	for job in cloud_outbox:
		if job.patient_id == pid and job.reset: return
	cloud_outbox = cloud_outbox.filter(func(job): return str(job.patient_id) != pid)
	# Queue a durable, idempotent reset before clearing the local snapshot.
	if cloud_db_provider == "mongodb":
		report_sync.enqueue(pid, true)
	patient_profiles[pid] = {
		"patient_id": pid,
		"generation": generation + 1,
		"patient_name": "Bệnh nhân " + pid,
		"max_rom_angle": 0.0,
		"levels": {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1},
		"rom_history": [],
		"sessions": [],
		"updated_at_utc": Time.get_datetime_string_from_system(true),
	}
	var kept_sessions: Array = []
	for s in session_history:
		if s is Dictionary and str(s.get("patient_id", "")) != pid:
			kept_sessions.append(s)
	session_history = kept_sessions
	if pid == current_patient_id:
		current_patient_name = "Bệnh nhân " + pid
		max_rom_angle = 0.0
		rom_history = []
		for action in range(1, 6):
			unlocked_levels_by_action[action] = 1
		highest_unlocked_level = 1
	save_progress()
	patient_profile_changed.emit(pid)
	sync_patient_to_cloud(pid)


func get_patient_sessions(patient_id := "") -> Array:
	var target_id := current_patient_id if patient_id.is_empty() else patient_id
	var filtered: Array = []
	for entry in session_history:
		if not entry is Dictionary:
			continue
		if not entry.has("patient_id"):
			continue # Keep legacy unassigned records in storage, never attribute them to every patient.
		var entry_pid := str(entry.get("patient_id", target_id))
		if entry_pid == target_id:
			filtered.append(entry)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("ended_at_utc", a.get("completed_at_utc", ""))) < str(b.get("ended_at_utc", b.get("completed_at_utc", ""))))
	return filtered


func get_patient_rom_history(patient_id := "") -> Array:
	var target_id := current_patient_id if patient_id.is_empty() else patient_id
	if target_id == current_patient_id:
		return rom_history
	if patient_profiles.has(target_id) and patient_profiles[target_id].get("rom_history") is Array:
		return patient_profiles[target_id]["rom_history"]
	return []


func record_calibration_rom(rom_deg: float, date_override := "") -> bool:
	if PoseInput.get("offline_preview_enabled") == true: return false
	if not is_finite(rom_deg) or rom_deg <= 0.0:
		return false
	max_rom_angle = roundf(rom_deg * 10.0) / 10.0
	var date_str := date_override if not date_override.is_empty() else Time.get_date_string_from_system()
	_upsert_daily_rom(date_str, max_rom_angle, "calibration")
	var saved := save_progress()
	sync_patient_to_cloud()
	return saved


func _upsert_daily_rom(date_str: String, rom_deg: float, source: String) -> void:
	var rounded := roundf(rom_deg * 10.0) / 10.0
	for i in range(rom_history.size()):
		var item: Dictionary = rom_history[i]
		if str(item.get("date", "")) == date_str and str(item.get("source", "")) == source:
			if rounded >= float(item.get("rom_angle", 0.0)):
				item["rom_angle"] = rounded
				item["source"] = source
				item["updated_at_utc"] = Time.get_datetime_string_from_system(true)
				rom_history[i] = item
			return
	rom_history.append({
		"date": date_str,
		"rom_angle": rounded,
		"source": source,
		"patient_id": current_patient_id,
		"updated_at_utc": Time.get_datetime_string_from_system(true),
	})
	rom_history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("date", "")) < str(b.get("date", ""))
	)


func record_session(summary: Dictionary) -> void:
	if PoseInput.get("offline_preview_enabled") == true: return
	for entry in session_history:
		if str(entry.get("session_id", "")) == str(summary.get("session_id", "")):
			return
	var enriched := summary.duplicate(true)
	if not enriched.has("patient_id"):
		enriched["patient_id"] = current_patient_id
	if not enriched.has("patient_name"):
		enriched["patient_name"] = current_patient_name
	session_history.append(enriched)
	# Session ROM is not a new calibration measurement.

	save_progress()
	sync_session_to_cloud(enriched)
	sync_patient_to_cloud()


func seed_demo_weekly_data(_patient_id := "") -> void:
	# Khong dung du lieu gia lap. Dam bao ho so sach de san sang ghi nhan du lieu that.
	save_progress()
	patient_profile_changed.emit(current_patient_id)


func seed_all_preset_patients() -> void:
	# Dam bao 10 ho so trong (BN001 - BN010) san sang cho 10 nguoi that thu nghiem NCKH.
	_ensure_current_patient_profile()
	save_progress()
	patient_profile_changed.emit(current_patient_id)


func sync_all_patients_to_cloud() -> void:
	if not persistence_enabled or not is_cloud_configured():
		return
	for pid in patient_profiles.keys():
		sync_patient_to_cloud(str(pid))


# ==========================================
# DONG BO DATABASE ONLINE (MONGODB / SUPABASE / FIREBASE)
# ==========================================
func load_cloud_config() -> void:
	var env_url := OS.get_environment("PHCN_CLOUD_URL")
	var env_key := OS.get_environment("PHCN_CLOUD_API_KEY")
	var env_provider := OS.get_environment("PHCN_CLOUD_PROVIDER")
	if not env_url.is_empty():
		cloud_db_enabled = true
		cloud_db_url = env_url.strip_edges().trim_suffix("/")
		cloud_db_api_key = env_key.strip_edges()
		if not env_provider.is_empty():
			cloud_db_provider = env_provider.strip_edges().to_lower()
		_update_cloud_status("Đã cấu hình Cloud (%s) từ biến môi trường" % cloud_db_provider.to_upper(), true)
		return

	var target_cfg_path := cloud_config_path
	if not FileAccess.file_exists(target_cfg_path):
		if FileAccess.file_exists("res://cloud_config.json"):
			target_cfg_path = "res://cloud_config.json"
		elif FileAccess.file_exists("res://mongodb_config.json"):
			target_cfg_path = "res://mongodb_config.json"
		else:
			return

	var file := FileAccess.open(target_cfg_path, FileAccess.READ)
	if file == null:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return
	var cfg: Dictionary = parser.data
	cloud_db_enabled = bool(cfg.get("enabled", true))
	cloud_db_provider = str(cfg.get("provider", cfg.get("cloud_provider", "mongodb"))).to_lower()
	cloud_db_url = str(cfg.get("url", cfg.get("mongodb_uri", "mongodb://localhost:27017"))).strip_edges().trim_suffix("/")
	cloud_db_api_key = str(cfg.get("api_key", cfg.get("database_name", "rehab_pixel_game"))).strip_edges()
	if is_cloud_configured():
		_update_cloud_status("Cloud DB sẵn sàng (%s)" % cloud_db_provider.to_upper(), true)


func save_cloud_config(enabled: bool, provider: String, url: String, api_key: String) -> void:
	cloud_db_enabled = enabled
	cloud_db_provider = provider.strip_edges().to_lower()
	cloud_db_url = url.strip_edges().trim_suffix("/")
	cloud_db_api_key = api_key.strip_edges()
	if cloud_db_provider == "mongodb":
		if cloud_db_url.is_empty():
			cloud_db_url = "mongodb://localhost:27017"
		if cloud_db_api_key.is_empty():
			cloud_db_api_key = "rehab_pixel_game"
	if persistence_enabled:
		var file := FileAccess.open(cloud_config_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({
				"enabled": cloud_db_enabled,
				"provider": cloud_db_provider,
				"url": cloud_db_url,
				"api_key": cloud_db_api_key,
			}, "\t"))
			file.close()
	if is_cloud_configured():
		_update_cloud_status("Đang kết nối %s..." % cloud_db_provider.to_upper(), true)
		sync_patient_to_cloud(current_patient_id)
	else:
		_update_cloud_status("Cloud DB: Đang lưu Offline trên máy", false)


func is_cloud_configured() -> bool:
	if not cloud_db_enabled:
		return false
	if cloud_db_provider == "mongodb":
		return true
	if cloud_db_url.is_empty():
		return false
	if cloud_db_provider == "supabase" and cloud_db_api_key.is_empty():
		return false
	return cloud_db_url.begins_with("http://") or cloud_db_url.begins_with("https://")


func _get_mongodb_bridge_base() -> String:
	if cloud_db_url.begins_with("http://") or cloud_db_url.begins_with("https://"):
		return cloud_db_url
	return DEFAULT_MONGO_BRIDGE_URL


func _get_mongodb_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if cloud_db_url.begins_with("mongodb://") or cloud_db_url.begins_with("mongodb+srv://"):
		headers.append("X-Mongo-URI: %s" % cloud_db_url)
	if not cloud_db_api_key.is_empty():
		headers.append("X-Mongo-DB: %s" % cloud_db_api_key)
	return headers


func _update_cloud_status(text: String, success: bool) -> void:
	cloud_sync_status = text
	cloud_is_online = success
	cloud_sync_status_changed.emit(text, success)


func sync_patient_to_cloud(patient_id := "") -> void:
	if cloud_db_provider == "mongodb":
		var pid := current_patient_id if patient_id.is_empty() else patient_id.strip_edges().to_upper()
		report_sync.enqueue(pid)
		report_sync.kick.call_deferred()
		return
	if not persistence_enabled or not is_cloud_configured() or not is_instance_valid(_http_sync_profile):
		return
	_sync_active_patient_into_profiles()
	var target_id := current_patient_id if patient_id.is_empty() else patient_id.strip_edges().to_upper()
	var profile_data: Dictionary = patient_profiles.get(target_id, {})
	if profile_data.is_empty():
		return

	_http_sync_profile.cancel_request()
	if cloud_db_provider == "mongodb":
		var endpoint := "%s/api/patients/%s" % [_get_mongodb_bridge_base(), target_id.uri_encode()]
		var headers := _get_mongodb_headers()
		_http_sync_profile.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(profile_data))
	elif cloud_db_provider == "supabase":
		var endpoint := "%s/rest/v1/patient_profiles?on_conflict=patient_id" % cloud_db_url
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"apikey: %s" % cloud_db_api_key,
			"Authorization: Bearer %s" % cloud_db_api_key,
			"Prefer: resolution=merge-duplicates,return=minimal",
		])
		var payload := {
			"patient_id": target_id,
			"patient_name": str(profile_data.get("patient_name", current_patient_name)),
			"max_rom_angle": float(profile_data.get("max_rom_angle", max_rom_angle)),
			"levels": profile_data.get("levels", {}),
			"rom_history": profile_data.get("rom_history", []),
			"sessions": profile_data.get("sessions", []),
			"updated_at_utc": Time.get_datetime_string_from_system(true),
		}
		_http_sync_profile.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	else:
		# Firebase Realtime Database REST API
		var endpoint := "%s/patients/%s.json" % [cloud_db_url, target_id.uri_encode()]
		if not cloud_db_api_key.is_empty():
			endpoint += "?auth=%s" % cloud_db_api_key.uri_encode()
		var headers := PackedStringArray(["Content-Type: application/json"])
		_http_sync_profile.request(endpoint, headers, HTTPClient.METHOD_PUT, JSON.stringify(profile_data))


func sync_session_to_cloud(session_entry: Dictionary) -> void:
	if cloud_db_provider == "mongodb":
		report_sync.enqueue(str(session_entry.get("patient_id", current_patient_id)))
		return
	if not persistence_enabled or not is_cloud_configured() or not is_instance_valid(_http_sync_session):
		return
	_http_sync_session.cancel_request()
	if cloud_db_provider == "mongodb":
		var endpoint := "%s/api/sessions" % _get_mongodb_bridge_base()
		var headers := _get_mongodb_headers()
		_http_sync_session.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(session_entry))
	elif cloud_db_provider == "supabase":
		var endpoint := "%s/rest/v1/exercise_sessions?on_conflict=session_id" % cloud_db_url
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"apikey: %s" % cloud_db_api_key,
			"Authorization: Bearer %s" % cloud_db_api_key,
			"Prefer: resolution=merge-duplicates,return=minimal",
		])
		var payload := {
			"session_id": str(session_entry.get("session_id", "")),
			"patient_id": str(session_entry.get("patient_id", current_patient_id)),
			"patient_name": str(session_entry.get("patient_name", current_patient_name)),
			"map_id": int(session_entry.get("map_id", 1)),
			"exercise_id": str(session_entry.get("exercise_id", "")),
			"difficulty": int(session_entry.get("difficulty", 1)),
			"valid_reps": int(session_entry.get("valid_reps", 0)),
			"rejected_reps": int(session_entry.get("rejected_reps", 0)),
			"stability": int(session_entry.get("stability", 3)),
			"rom_angle": float(session_entry.get("rom_angle", max_rom_angle)),
			"evaluation": str(session_entry.get("evaluation", "")),
			"completed_at_utc": str(session_entry.get("completed_at_utc", Time.get_datetime_string_from_system(true))),
		}
		_http_sync_session.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	else:
		var sid := str(session_entry.get("session_id", "session")).uri_encode()
		var endpoint := "%s/sessions/%s/%s.json" % [cloud_db_url, current_patient_id.uri_encode(), sid]
		if not cloud_db_api_key.is_empty():
			endpoint += "?auth=%s" % cloud_db_api_key.uri_encode()
		var headers := PackedStringArray(["Content-Type: application/json"])
		_http_sync_session.request(endpoint, headers, HTTPClient.METHOD_PUT, JSON.stringify(session_entry))


func fetch_patient_from_cloud(patient_id := "") -> void:
	if cloud_db_provider == "mongodb":
		sync_patient_to_cloud(patient_id)
		return
	if not persistence_enabled or not is_cloud_configured() or not is_instance_valid(_http_fetch_profile):
		return
	var target_id := current_patient_id if patient_id.is_empty() else patient_id.strip_edges().to_upper()
	_http_fetch_profile.cancel_request()
	_update_cloud_status("Đang tải hồ sơ %s từ %s..." % [target_id, cloud_db_provider.to_upper()], true)

	if cloud_db_provider == "mongodb":
		var endpoint := "%s/api/patients/%s" % [_get_mongodb_bridge_base(), target_id.uri_encode()]
		var headers := _get_mongodb_headers()
		_http_fetch_profile.request(endpoint, headers, HTTPClient.METHOD_GET)
	elif cloud_db_provider == "supabase":
		var endpoint := "%s/rest/v1/patient_profiles?patient_id=eq.%s&select=*" % [cloud_db_url, target_id.uri_encode()]
		var headers := PackedStringArray([
			"apikey: %s" % cloud_db_api_key,
			"Authorization: Bearer %s" % cloud_db_api_key,
		])
		_http_fetch_profile.request(endpoint, headers, HTTPClient.METHOD_GET)
	else:
		var endpoint := "%s/patients/%s.json" % [cloud_db_url, target_id.uri_encode()]
		if not cloud_db_api_key.is_empty():
			endpoint += "?auth=%s" % cloud_db_api_key.uri_encode()
		_http_fetch_profile.request(endpoint, PackedStringArray(), HTTPClient.METHOD_GET)


func _on_sync_profile_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var time_str := Time.get_time_string_from_system().substr(0, 5)
		_update_cloud_status("Đã đồng bộ %s thành công (%s)" % [cloud_db_provider.to_upper(), time_str], true)
	else:
		if cloud_db_provider == "mongodb" and response_code == 0:
			_update_cloud_status("Lưu cục bộ (Chưa bật main.py hoặc mongodb_service.py ở cổng 8766)", false)
		else:
			_update_cloud_status("Lưu cục bộ (Lỗi kết nối %s - HTTP %d)" % [cloud_db_provider.to_upper(), response_code], false)


func _on_sync_session_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	pass


func _on_fetch_profile_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if cloud_db_provider == "mongodb" and response_code == 404:
		_update_cloud_status("Hồ sơ mới (%s) — Đang tạo mới trên MongoDB..." % current_patient_id, true)
		sync_patient_to_cloud(current_patient_id)
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_update_cloud_status("Không tải được từ %s (HTTP %d) — Dùng dữ liệu cục bộ" % [cloud_db_provider.to_upper(), response_code], false)
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return
	var data: Variant = parser.data
	var prof_dict: Dictionary = {}
	if cloud_db_provider == "supabase" and data is Array and not data.is_empty() and data[0] is Dictionary:
		var row: Dictionary = data[0]
		prof_dict = {
			"patient_id": str(row.get("patient_id", current_patient_id)),
			"patient_name": str(row.get("patient_name", current_patient_name)),
			"max_rom_angle": float(row.get("max_rom_angle", max_rom_angle)),
			"levels": row.get("levels", row.get("unlocked_levels", {})),
			"rom_history": row.get("rom_history", []),
			"sessions": row.get("sessions", []),
		}
	elif data is Dictionary and not data.is_empty() and not data.has("error"):
		prof_dict = data

	if not prof_dict.is_empty():
		var pid := str(prof_dict.get("patient_id", current_patient_id))
		patient_profiles[pid] = prof_dict
		if prof_dict.get("sessions") is Array:
			var existing_ids := {}
			for s in session_history:
				if s is Dictionary and s.has("session_id"):
					existing_ids[str(s["session_id"])] = true
			for s in prof_dict["sessions"]:
				if s is Dictionary and s.has("session_id") and not existing_ids.has(str(s["session_id"])):
					session_history.append(s)
		if pid == current_patient_id:
			_load_active_patient_from_profiles()
			save_progress()
			patient_profile_changed.emit(current_patient_id)
		_update_cloud_status("Đã tải hồ sơ %s từ %s" % [pid, cloud_db_provider.to_upper()], true)
	else:
		_update_cloud_status("Hồ sơ mới (%s) — Đang lưu lên %s..." % [current_patient_id, cloud_db_provider.to_upper()], true)
		sync_patient_to_cloud(current_patient_id)

var speed_multiplier = 1.0
var highest_unlocked_level = 1
var unlocked_levels_by_action := {
	1: 1,
	2: 1,
	3: 1,
	4: 1,
	5: 1,
}

var selected_action = 1

const MAP_SCENES := {
	1: "res://maps/map_1/main_level.tscn",
	2: "res://maps/map_2/main_level.tscn",
	3: "res://maps/map_3/main_level.tscn",
	4: "res://maps/map_4/main_level.tscn",
	5: "res://maps/map_5/main_level.tscn",
}

# --- MỚI: Biến lưu biên độ tối đa (Max Range of Motion) ---
# Ví dụ: 100 là giơ tay thẳng đứng. Khởi tạo bằng 0.
var max_rom_angle: float = 0.0


func get_highest_unlocked_level(action_id: int) -> int:
	return int(unlocked_levels_by_action.get(action_id, 1))


func get_unlocked_level_for_action(action_id: int) -> int:
	return get_highest_unlocked_level(action_id)


func unlock_level_for_action(action_id: int, level: int) -> void:
	if PoseInput.get("offline_preview_enabled") == true: return
	var next_level := clampi(level, 1, 3)
	unlocked_levels_by_action[action_id] = maxi(get_highest_unlocked_level(action_id), next_level)
	# Keep the old field synchronized for older UI/code that may still read it.
	highest_unlocked_level = get_highest_unlocked_level(action_id)
	save_progress()


func get_selected_map_scene() -> String:
	return str(MAP_SCENES.get(selected_action, ""))


func is_map_implemented(action_id: int) -> bool:
	return MAP_SCENES.has(action_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var current_mode = DisplayServer.window_get_mode()
			if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			elif current_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func apply_cloud_profile(pid: String, profile: Dictionary) -> void:
	patient_profiles[pid] = profile.duplicate(true)
	var kept: Array = []
	for entry in session_history:
		if str(entry.get("patient_id", "")) != pid: kept.append(entry)
	for entry in profile.get("sessions", []):
		if entry is Dictionary and str(entry.get("patient_id", "")) == pid: kept.append(entry)
	session_history = kept
	if pid == current_patient_id: _load_active_patient_from_profiles()
	save_progress()
	patient_profile_changed.emit(pid)
