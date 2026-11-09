# Chuẩn placeholder Map 4

- Khung tham chiếu `1152 × 648`, bậc đầu tại `Step_00` (220, 320).
- Nhân vật dùng placeholder chung, pivot tại chân và collision `42 × 72`.
- `Map4ClimbTrack` gồm `Step_00` … `Step_10`, mỗi bậc:
  - `LedgeVisual` (180 × 18 px, pivot giữa mặt trên bậc)
  - `LedgePlatform` (`StaticBody2D` + collision)
  - `RunStart` / `JumpZone` (`Marker2D`, cách nhau 120 px)
- Nhân vật neo bằng `set_movement_locked()` khi chạy, giữ tư thế và nghỉ.
- Mỗi bậc cho phép chạy ~5 giây trước vùng nhảy; không va chạm hay trừ Ổn định.
- Mỗi lần hợp lệ gồm giữ đủ `5000 ms`; nhân vật nhảy lên bậc kế tiếp sau khi backend xác nhận `rep_completed`.
- Map gồm `2 phase × 5 bậc`, nghỉ `30 giây` giữa phase; `SummitVisual` trên `Step_10` hiện cờ khi hoàn thành 10 bậc.
- `Camera2D` gắn trên Player, theo dõi leo vách.
- Visual và gameplay tách rời để thay sprite/animation mà không đổi contract.
