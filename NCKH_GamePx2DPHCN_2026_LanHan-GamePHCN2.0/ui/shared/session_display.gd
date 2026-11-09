extends RefCounted

static func progress_ratio(data: Dictionary) -> float:
	if number(data, "completed_reps") == "—" or number(data, "target_reps") == "—": return -1.0
	var target := float(data.target_reps)
	return clampf(float(data.completed_reps) / target, 0.0, 1.0) if target > 0 else -1.0

static func filter_history(entries: Array, map_id: int, state: String, days: int, now: float) -> Array:
	var result: Array = []
	for entry in entries:
		if not entry is Dictionary: continue
		if map_id > 0 and int(entry.get("map_id", 0)) != map_id: continue
		var actual := str(entry.get("status", ""))
		if actual.is_empty() and not str(entry.get("completed_at_utc", "")).is_empty(): actual = "completed"
		if not state.is_empty() and actual != state: continue
		if days > 0:
			var date := str(entry.get("ended_at_utc", entry.get("completed_at_utc", "")))
			if date.length() < 19: continue
			var timestamp := Time.get_unix_time_from_datetime_string(date)
			if timestamp > now or timestamp < now - days * 86400.0: continue
		result.append(entry)
	return result
static func compact_details(data: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(profile(data))
	lines.append(goals(data))
	for item in [["active_seconds", "Tập thực tế"], ["rest_seconds", "Nghỉ giữa hiệp"], ["paused_seconds", "Tạm dừng"], ["tracking_lost_seconds", "Mất nhận diện"]]:
		lines.append(item[1] + ": " + duration(data, item[0]))
	if str(data.get("duration_source", "")) == "godot_state_timer":
		lines.append("Thời lượng do game ghi nhận; thời gian tập gồm lúc chờ vùng động tác.")
	if lines.is_empty(): return "Thông tin bổ sung chưa khả dụng cho buổi tập này."
	return "\n".join(lines)

## Current persisted contract. Legacy missing/null fields never become measured zero.
static func number(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key)
	if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0:
		if key in ["completed_reps", "target_reps", "completed_sets", "target_sets"] and float(value) != floorf(float(value)): return "—"
		return str(int(value))
	return "—"

static func duration(data: Dictionary, key: String) -> String:
	var value := number(data, key)
	if value == "—": return "Chưa có dữ liệu"
	var seconds := int(value)
	return "%02d:%02d:%02d" % [floori(seconds / 3600.0), floori((seconds % 3600) / 60.0), seconds % 60]

static func profile(data: Dictionary) -> String:
	var value: Variant = data.get("patient_id")
	if not value is String or value.strip_edges().is_empty(): value = data.get("profile_id")
	if not value is String or value.strip_edges().is_empty(): return "Hồ sơ: Chưa xác định"
	return "Hồ sơ: " + value.strip_edges()

static func status(data: Dictionary) -> String:
	match str(data.get("status", "")):
		"completed": return "Hoàn thành"
		"stopped_early": return "Dừng sớm"
		"interrupted": return "Gián đoạn"
		_: return "Chưa có trạng thái"

static func goals(data: Dictionary) -> String:
	return "Số lần hoàn thành / mục tiêu: %s / %s   •   Số hiệp: %s / %s" % [number(data, "completed_reps"), number(data, "target_reps"), number(data, "completed_sets"), number(data, "target_sets")]

static func details(data: Dictionary) -> String:
	return "Tập thực tế: %s\nNghỉ giữa hiệp: %s\nTạm dừng: %s\nMất nhận diện: %s" % [duration(data, "active_seconds"), duration(data, "rest_seconds"), duration(data, "paused_seconds"), duration(data, "tracking_lost_seconds")]
