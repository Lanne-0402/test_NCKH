# Chuẩn placeholder Map 1

## Hệ tọa độ

- Khung tham chiếu: `1152 × 648 px`.
- Mặt đất: `y = 320 px`.
- Nhân vật, đá và cửa hang dùng pivot tại điểm chạm mặt đất.
- Gameplay/collision độc lập với hình vẽ để có thể thay sprite mà không đổi backend.

## Nhân vật

- Khung hình tham chiếu: `68 × 96 px`.
- Pivot: giữa hai chân `(0, 0)`.
- Collision: `42 × 72 px`, tâm `(0, -36)`.
- Các trạng thái tối thiểu khi thay asset thật: `idle`, `run`, `exercise`, `tracking_lost`, `finish`.

## Tảng đá

- Khung hình tham chiếu: `68 × 58 px`.
- Pivot: giữa đáy `(0, 0)`.
- Collision: `68 × 58 px`, tâm `(0, -29)`.
- Animation tối thiểu: `approach`, `waiting`, `break`.
- Đá phải dừng tại `Action Zone`; không dùng va chạm để phạt người chơi.

## Bối cảnh và cửa hang

- Background che vùng từ `y = 0` đến `y = 320` và hỗ trợ hai lớp cuộn.
- Cửa hang dùng pivot tại mặt đất và chỉ xuất hiện khi hoàn thành đủ 20 lần.

## Hướng dẫn tư thế

- Luôn hiển thị trước countdown.
- Minh họa khuỷu tay 90°, hai tay thả lỏng trước khi gập và ép hai bả vai ra sau chậm rãi.
- Nội dung phải nhắc 2 phase × 10 lần và nghỉ 30 giây giữa phase.
