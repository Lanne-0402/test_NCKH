# Chuẩn placeholder Map 2

- Khung tham chiếu `1152 × 648`, mặt đất `y = 320`.
- Nhân vật dùng placeholder chung, pivot tại chân và collision `42 × 72`.
- Phiến đá rộng `300 px`, cao `60 px`, pivot ở giữa đáy.
- Phiến đá hạ đến `y = 200` rồi dừng an toàn, không va chạm hay trừ Ổn định.
- Mỗi lần hợp lệ gồm giữ đủ `5000 ms`; thanh lực nhận `hold_progress` từ backend.
- Map gồm `2 phase × 5 lần`, nghỉ `30 giây` giữa phase.
- Visual và gameplay tách rời để thay sprite/animation mà không đổi contract.
