# Map 1 - Phá đá

Map 1 triển khai bài tập ép hai bả vai ra sau.

- `main_level.tscn` / `main_level.gd`: scene và luồng điều phối của Map 1.
- `map1_controller.gd`: tiến trình đá, Action Zone và hoạt cảnh kết thúc.
- `obstacle.tscn` / `obstacle.gd`: tảng đá riêng của Map 1.
- `visuals/`: background, ground, đá và hang đã dựng từ bộ asset High Forest.
- `placeholders/`: fallback và hướng dẫn tư thế tạm thời cho các asset chưa có.

Map sử dụng lại `ExerciseSession`, pose provider, player và star từ các thư mục dùng chung. Ground và background của Map 1 dùng scene riêng để giữ đồng nhất phong cách hình ảnh.

Quy chuẩn kích thước, pivot, collision và trạng thái animation được ghi tại `placeholders/PLACEHOLDER_SPEC.md`.
Danh sách asset đang dùng và các slot còn thiếu được ghi tại `assets/map_1/README.md`.
