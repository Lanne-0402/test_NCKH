# Mk2 pose lab — bản thử độc lập

Mở `tests/visual/mk2_pose_lab.tscn` trong Godot rồi nhấn **F6** (Run Current Scene).
Không dùng F5 vì main scene của game không thay đổi. Esc đóng lượt chạy thử.

Ba nhân vật chạy đồng thời: nâng hai tay; mở/khép khuỷu với tay sau đầu; kéo tay ngang ngực có tay hỗ trợ.
Chu kỳ 8 giây chỉ phục vụ quan sát, không phải thời gian bài tập. Đây là minh họa kỹ thuật, chưa được chuyên môn PHCN duyệt.

## Điều khiển

- Space: chạy/dừng. Kéo thanh biên độ sẽ dừng tự động để xem từng bước.
- J: hiện/ẩn điểm vai, khuỷu, cổ tay và đường nối. Mốc chân màu xanh cố định.
- L: đổi bên kéo tay ở nhân vật thứ ba.
- C: chuyển màu phân biệt bộ phận / xám gốc.
- V: xem kích thước 2× và 3×, không đổi mốc chân.
- T: giữ tư thế đích 100%.

## Phạm vi

Chỉ có 8 PNG nguồn; 14 đoạn ghép (đầu, thân và 6 đoạn mỗi bên) dùng lại texture.
Ảnh không sửa pixel: torso được tint xanh, chân tint xanh xám, tay/đầu tint màu da.
Không phải trang phục hoàn thiện. Không kết nối camera, BE, điều khiển người chơi hoặc lưu kết quả.
Không thay các map chính, player.gd, collider, project.godot hoặc màn Home.

Nhân vật dùng body gốc góc trước–ngang; tay ghép đối xứng là xấp xỉ 2D. Đặc biệt khi khép khuỷu sau đầu, cần đánh giá lại chiều sâu, vùng che khuất và vẽ thêm frame nếu muốn đúng chuyển động trong không gian. Góc quay và độ dài ở đây do bản thử đặt, không phải ngưỡng chấm điểm bài tập.
Các đoạn chân được ghép vừa dáng thử, không áp dụng quy ước collision của player chính.

## Nguồn và mapping

Reactorcore — PSRC Human Mk2 and Ultimate Dev Kit
https://reactorcore.itch.io/psrc-human-mk2-and-ultimate-devkit

Lấy từ `Human Template In Pieces`:

| Nguồn | Tên đưa vào project |
|---|---|
| 0 genderless.png | torso.png |
| 6.png | head.png |
| 27.png | thigh.png |
| 28.png | shin.png |
| 29.png | foot.png |
| 30.png | upper_arm.png |
| 31.png | forearm.png |
| 33.png | hand.png |

Hai tài liệu tác giả được giữ trong assets/characters/mk2_lab. Nội dung license chung và mô tả pack chưa thống nhất; giữ attribution và xác minh trước khi phát hành. Không đưa các chương trình kèm pack vào game.

## Kiểm thử

Chạy scene bằng Godot với đối số người dùng `-- --smoke --no-save`: kiểm 101 mẫu mỗi tư thế, độ dài hai đoạn tay, tọa độ hữu hạn và điều khiển. `-- --capture --no-save` chụp mốc 0%, 50%, 100% khi có renderer thật vào tests/visual/captures. Ảnh thử không cần đưa vào bản build.
