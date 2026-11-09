# Map 5 - Thiền định thêm điểm

Map 5 triển khai bài tập kéo căng cánh tay qua ngực tại suối nước nóng:

- Dùng cẳng tay bên còn lại kéo nhẹ tay qua ngực.
- Giữ căng 30 giây/lần.
- 2 phase (tay trái → thư giãn 30 giây → tay phải).
- Mỗi lần căng hợp lệ cộng 50 điểm thưởng (tối đa 100).

- `main_level.tscn` / `main_level.gd`: scene và luồng điều phối Map 5.
- `map5_controller.gd`: điểm thưởng, hơi nước và trạng thái từng bên tay.
- `placeholders/`: background suối nước nóng, hơi, minh họa tư thế.

Map sử dụng lại `ExerciseSession`, pose provider, player và `TrackingStability` từ các thư mục dùng chung.
