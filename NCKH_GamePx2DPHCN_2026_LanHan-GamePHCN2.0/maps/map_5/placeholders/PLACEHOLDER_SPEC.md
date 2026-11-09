# Chuẩn placeholder Map 5

- Khung tham chiếu `1152 × 648`, mặt đất tham chiếu `y = 320`.
- Nhân vật neo tại `PlayerAnchor` (576, 320), `set_movement_locked(true)` trong suối.
- `PoolFloor` (StaticBody2D) giữ nhân vật trên mặt bể nếu bật physics.
- Không có chướng ngại hay va chạm; đây là trạm thưởng điểm thư giãn.
- Mỗi lần hợp lệ gồm giữ căng `30000 ms`; mỗi phase tương ứng một bên tay.
- Map gồm `2 phase × 1 lần`, nghỉ `30 giây` giữa hai phase (thư giãn trước khi đổi tay).
- Mỗi lần căng hợp lệ cộng `50` điểm thưởng (tối đa `100`).
- Visual và gameplay tách rời để thay sprite/animation mà không đổi contract.
