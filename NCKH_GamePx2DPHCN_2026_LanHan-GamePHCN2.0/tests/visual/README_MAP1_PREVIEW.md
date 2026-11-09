# Map 1 + Mk2 — kiểm tra nhân vật trên nền

Mở map1_mk2_preview.tscn rồi F6. Đây là scene thử riêng, KHÔNG phải bản thay thế main_level.tscn.

Tái sử dụng chính scene nền rừng, mặt đất, đá và cửa ra của Map 1. Nhân vật bắt đầu tại (285,320), cỡ 2×, chân đúng y=320. Mốc đá x=540 theo vùng hành động; cửa ra đưa vào x=1030 để quan sát. HUD được rút gọn và bảng điều khiển đặt dưới mặt đất để không phủ nhân vật. Vì vậy đây là bài thử mỹ thuật trên môi trường Map 1, chưa phải toàn bộ giao diện/gameplay thật.

- O / nút Trang phục: đổi có/không trang phục tại đúng cùng vị trí và cùng thời điểm animation — cách so sánh chính.
- B: thêm mẫu không trang phục ở bên phải để xem đồng thời. Hai vị trí có nền khác nhau nên không thay thế phép so sánh tại chỗ.
- J: dấu khớp, mặc định tắt. V: đổi 2×/3×. Space: chạy/dừng.
- Kéo thanh biên độ: dừng ở một tư thế. Kéo Vị trí trên nền: di chuyển mẫu chính; không có animation đi bộ hay va chạm.
- N: đổi mảng nền rừng dưới nhân vật, nền đứng yên để dễ đối chiếu A/B.
- Chọn một trong 4 động tác; mặc định mô phỏng gập khuỷu/ép vai Map 1. Đây là xấp xỉ 2D, không phải hướng dẫn chuyên môn hoặc ngưỡng chấm điểm.
- Esc: thoát.

Không thêm camera, backend, session, chấm điểm hoặc ghi kết quả. Không sửa main map, player, collider hoặc các bản thử khác. Nhân vật là bản vẽ prototype, chưa thay Player thật. Quần áo hiện là lớp code-native thử nghiệm, không phải sprite art hoàn thiện.

Riêng instance mặt đất trong preview: đưa GrassTop lên 10 px local (20 px màn hình) vì ảnh cỏ có 10 hàng trong suốt ở đầu. Nhờ đó mặt cỏ nhìn thấy trùng mốc chân y=320, tránh cảm giác lơ lửng. Không sửa scene ground gốc hoặc collider.

--preview-smoke --no-save kiểm 4 tư thế, bật/tắt đồ cùng vị trí, đồng bộ hai actor, mốc chân, đổi cỡ và đổi nền. --preview-capture --no-save chụp có đồ, không đồ, và so sánh cạnh nhau ở cỡ 2×. Chưa thực hiện nghiên cứu khả năng quan sát trên người tập; cần người dùng duyệt ảnh và thử trực tiếp.
