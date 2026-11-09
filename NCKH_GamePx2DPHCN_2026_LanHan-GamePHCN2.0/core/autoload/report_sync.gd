extends Node

const Data := preload("res://core/autoload/report_data.gd")
var busy := false
var http: HTTPRequest
var _heartbeat_timer := 0.0
const HEARTBEAT_INTERVAL := 30.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	kick.call_deferred()


func _process(delta: float) -> void:
	if Global.cloud_outbox.is_empty() or busy:
		_heartbeat_timer = 0.0
		return
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		kick()


func enqueue(pid: String, reset := false) -> void:
	if not Global.persistence_enabled: return
	var job := {"patient_id": pid, "reset": reset, "token": Crypto.new().generate_random_bytes(12).hex_encode(), "generation": int(Global.patient_profiles.get(pid, {}).get("generation", 0))}
	# Keep reset requests in order; coalesce ordinary snapshots only.
	if not reset:
		for existing in Global.cloud_outbox:
			if existing.patient_id == pid and not existing.reset:
				existing.token = job.token
				Global.save_progress()
				return
	Global.cloud_outbox.append(job)
	Global.save_progress()
	kick.call_deferred()


func kick() -> void:
	if busy or not Global.persistence_enabled or not Global.is_cloud_configured() or Global.cloud_db_provider != "mongodb": return
	busy = true
	while not Global.cloud_outbox.is_empty():
		var job: Dictionary = Global.cloud_outbox[0].duplicate(true)
		var ok := await _perform(job)
		if not ok:
			busy = false
			return # Retain the outbox for manual retry or next launch.
		if not Global.cloud_outbox.is_empty() and str(Global.cloud_outbox[0].token) == str(job.token): Global.cloud_outbox.pop_front()
		Global.save_progress()
	busy = false


func _request(path: String, method: int, payload: Dictionary = {}) -> Dictionary:
	var error := http.request(Global._get_mongodb_bridge_base() + path, Global._get_mongodb_headers(), method, JSON.stringify(payload) if method != HTTPClient.METHOD_GET else "")
	if error != OK: return {"code": 0, "data": {}, "error": "Không gửi được yêu cầu đồng bộ (mã %d)" % error}
	var reply: Array = await http.request_completed
	return _decode_reply(int(reply[0]), int(reply[1]), reply[3])


func _decode_reply(result: int, code: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "data": {}, "error": "Chưa nhận được phản hồi từ dịch vụ đồng bộ (mã %d)" % result}
	var text := body.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return {"code": code, "data": {}, "error": "Dịch vụ đồng bộ trả về nội dung rỗng"}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"code": code, "data": {}, "error": "Phản hồi đồng bộ không đúng định dạng JSON"}
	return {"code": code, "data": parser.data}


func _profile_matches(profile: Dictionary, pid: String) -> bool:
	if str(profile.get("patient_id", "")) != pid: return false
	for field in ["sessions", "rom_history"]:
		if profile.has(field) and not profile[field] is Array: return false
	if profile.has("levels") and not profile.levels is Dictionary: return false
	return true


func _perform(job: Dictionary) -> bool:
	var pid := str(job.patient_id)
	var endpoint := "/api/patients/" + pid.uri_encode()
	Global._update_cloud_status("Đang đồng bộ hồ sơ %s…" % pid, false)
	var reply: Dictionary
	if bool(job.reset):
		reply = await _request(endpoint + "/reset", HTTPClient.METHOD_POST, {"expected_generation": job.generation, "reset_token": job.token})
		if reply.has("error"): return _failed(pid, int(reply.code), str(reply.error))
		if int(reply.code) == 200:
			var generation: Variant = reply.data.get("generation")
			if reply.data.get("ok") != true or not (generation is int or generation is float):
				return _failed(pid, 422, "Phản hồi đặt lại hồ sơ chưa hợp lệ")
			if not is_finite(float(generation)) or float(generation) != float(job.generation) + 1.0:
				return _failed(pid, 422, "Phiên bản hồ sơ trả về không khớp")
			if reply.data.has("patient_id") and str(reply.data.patient_id) != pid:
				return _failed(pid, 422, "Phản hồi thuộc hồ sơ khác")
			# New data collected offline after reset belongs to the new generation.
			var local: Dictionary = Global.patient_profiles.get(pid, {}).duplicate(true)
			local["generation"] = int(generation)
			Global.patient_profiles[pid] = local
			Global.save_progress()
			Global._update_cloud_status("Đã reset hồ sơ %s trên Cloud" % pid, true)
			return true
	else:
		reply = await _request(endpoint, HTTPClient.METHOD_GET)
		if reply.has("error"): return _failed(pid, int(reply.code), str(reply.error))
		if int(reply.code) == 200 and not _profile_matches(reply.data, pid):
			return _failed(pid, 422, "Dữ liệu hồ sơ trả về chưa hợp lệ")
		if int(reply.code) == 404 and str(reply.data.get("error", "")) != "PATIENT_NOT_FOUND":
			return _failed(pid, 404, "Dịch vụ không tìm thấy đường dẫn hồ sơ")
		if int(reply.code) not in [200, 404]: return _failed(pid, int(reply.code))
		Global._sync_active_patient_into_profiles()
		var local: Dictionary = Global.patient_profiles.get(pid, {}).duplicate(true)
		var remote: Dictionary = reply.data if int(reply.code) == 200 else {}
		if not remote.is_empty() and str(remote.get("patient_id", "")) != pid: return _failed(pid, 422)
		var merged := Data.merge_profile(local, remote) if not remote.is_empty() else local
		Global.apply_cloud_profile(pid, merged)
		reply = await _request(endpoint, HTTPClient.METHOD_POST, merged)
		if reply.has("error"): return _failed(pid, int(reply.code), str(reply.error))
		if int(reply.code) == 200:
			if reply.data.get("ok") != true or str(reply.data.get("patient_id", "")) != pid:
				return _failed(pid, 422, "Dịch vụ chưa xác nhận lưu đúng hồ sơ")
			if reply.data.has("profile") and (not reply.data.profile is Dictionary or not _profile_matches(reply.data.profile, pid)):
				return _failed(pid, 422, "Hồ sơ trong xác nhận đồng bộ chưa hợp lệ")
			if reply.data.get("profile") is Dictionary:
				Global.apply_cloud_profile(pid, Data.merge_profile(Global.patient_profiles.get(pid, {}), reply.data.profile))
			Global._update_cloud_status("Đã đồng bộ hồ sơ và lịch sử %s (%s)" % [pid, Time.get_time_string_from_system().substr(0, 5)], true)
			return true
	return _failed(pid, int(reply.code))


func _failed(pid: String, _code: int, _detail := "") -> bool:
	Global._update_cloud_status("Chế độ Ngoại tuyến — Hồ sơ %s đã lưu an toàn trên máy" % pid, false)
	return false
