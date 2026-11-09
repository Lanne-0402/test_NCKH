extends RefCounted
## Frontend scenery/animation pace only. Never scale exercise or wall-clock timers.
const SPEEDS := [1.0, 1.5, 2.0]

static func factor() -> float:
	return SPEEDS[level_index()]

static func level_index() -> int:
	return 2 if Global.speed_multiplier >= 2.0 else (1 if Global.speed_multiplier >= 1.5 else 0)

static func duration(base_seconds: float) -> float:
	return base_seconds / factor()

static func motion_description(map_id: int) -> String:
	return [
		"Đá tiến đến và hiệu ứng chưởng",
		"Đá hạ xuống và hiệu ứng nâng đá",
		"Tường tiến vào và hiệu ứng đẩy tường",
		"Nhân vật chạy và nhảy lên bậc đá",
		"Hơi nước và hiệu ứng quanh nhân vật",
	][clampi(map_id, 1, 5) - 1]

static func exercise_note(map_id: int) -> String:
	var hold := "0,7 giây" if map_id == 1 else ("30 giây mỗi bên" if map_id == 5 else "5 giây")
	return "Giữ tư thế: %s · Nghỉ giữa hiệp: 30 giây" % hold
