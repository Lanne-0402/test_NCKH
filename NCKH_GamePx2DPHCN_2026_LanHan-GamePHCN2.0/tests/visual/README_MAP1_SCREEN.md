# Prototype giao diện Map 1

Mở `map1_screen_prototype.tscn` trong Godot rồi nhấn F6. Không thay main scene hay Map 1 chính thức.

- Hướng dẫn: Mk2 nguyên bản, nửa thân trên 5×, động tác Map 1, phụ đề; tự chuyển sau 15 giây hoặc chọn Vào chơi. Đếm ngược 3 giây trước khi mô phỏng chạy.
- Gameplay: Mk2 mặc trang phục 2×, chân y=320; giữ nguyên thế giới. Không còn dải nền vàng phía trên. Settings bên trái, phản hồi giữa, trái tim bên phải.
- Dưới đất: thông số trái; camera placeholder 16:9 bên phải. Chưa đọc camera hoặc backend.
- U: xem lại hướng dẫn, I: dấu khớp, Esc: Settings. Modal dừng hoạt ảnh và đồng hồ mô phỏng. Đóng Settings từ hướng dẫn giữ thời điểm đang xem; chủ động Xem hướng dẫn sẽ bắt đầu lại.
- Settings: âm lượng chỉ là thanh điều khiển thử, chưa phát/lưu âm thanh; camera là khung giao diện; Trang chủ và Chọn Map đi đến các màn có sẵn và rời prototype.
- Chỉ khi chạy với `--prototype-debug`, T mới mô phỏng mất/khôi phục tracking. Mất tracking đóng băng tiến độ; khôi phục đếm ngược trước khi tiếp tục.
- Một chu kỳ tự động 8 giây tương ứng một lần minh họa; 10 lần nghỉ 30 giây; 20 lần hiện kết thúc. Không phải logic chấm tập, không lưu kết quả, không gọi session/backend. Đạo cụ không bị phá theo chu kỳ trong bản thử giao diện này.
- Động tác ép bả vai chỉ là xấp xỉ 2D. Phụ đề và biên độ cần được chuyên môn duyệt trước khi đưa vào tập thật.

Kiểm thử: `--headless --scene res://tests/visual/map1_screen_prototype.tscn -- --screen-smoke --no-save`.
Chụp ảnh: renderer Compatibility, 1152×648, `--screen-capture --no-save`. Ảnh trong `tests/visual/captures/map1_screen_*.png`.
