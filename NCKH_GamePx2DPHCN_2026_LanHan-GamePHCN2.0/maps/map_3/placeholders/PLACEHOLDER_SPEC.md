# Chuẩn placeholder Map 3

- Khung tham chiếu `1152 × 648`, mặt đất `y = 320`.
- Nhân vật dùng placeholder chung, pivot tại chân và collision `42 × 72`.
- Mỗi tường gai rộng `80 px`, cao `240 px`, pivot ở giữa cạnh hướng vào nhân vật.
- Hai tường dừng ở vị trí an toàn (khoảng cách ~400 px với nhân vật); không va chạm hay trừ Ổn định.
- Mỗi lần hợp lệ gồm giữ đủ `5000 ms`; tường lùi theo `hold_progress` từ backend.
- Map gồm `2 phase × 5 lần`, nghỉ `30 giây` giữa phase.
- Visual và gameplay tách rời để thay sprite/animation mà không đổi contract.
