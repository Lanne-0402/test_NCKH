# Cấu trúc dự án

```text
core/
  autoload/        Trạng thái dùng chung toàn game
  exercise/        Vòng đời và dữ liệu phiên tập
  pose/            Hợp đồng pose provider và dữ liệu mock
shared/
  characters/      Nhân vật có thể dùng lại giữa các map
  collectibles/    Vật phẩm dùng lại
  world/           Mặt đất và nền cuộn dùng lại
ui/screens/
  start/            Màn hình chính
  calibration/      Kiểm tra và hiệu chỉnh camera
  map_selection/    Chọn map
  level_selection/  Chọn cấp độ trong map
maps/
  map_1/            Gameplay phá đá theo số lần lặp
  map_2/            Gameplay nâng đá theo tiến trình giữ 5 giây
  map_3/            Gameplay đẩy lùi tường gai theo giữ 5 giây
  map_4/            Gameplay leo vách đá theo chạy bậc + giữ 5 giây
  map_5/            Gameplay suối nước nóng — căng 30 giây + thưởng điểm
tests/
  core/             Smoke test hạ tầng phiên tập
  maps/map_1/       Smoke test Map 1
assets/             Asset nguồn dùng chung; chưa sao chép theo map
```

Quy tắc phụ thuộc: `maps` có thể dùng `core`, `shared` và `assets`; mã trong các thư mục dùng chung không được phụ thuộc ngược vào một map cụ thể.
