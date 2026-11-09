# PSRC Human cũ — bản thử đối chiếu Mk2

Mở `psrc_pose_lab.tscn` và F6: 3 tư thế đồng thời, toàn thân 2×/3×.
Nhấn H hoặc nút Nửa thân trên để vào hướng dẫn so sánh toàn thân 3× với nửa thân 4×/5×.
Cũng có thể mở `psrc_upper_body_guide.tscn` và F6 trực tiếp.

Điều khiển giống bản Mk2: Space chạy/dừng, J dấu khớp, V đổi zoom, L đổi bên kéo tay; trong hướng dẫn 1/2/3 chọn tư thế, R chạy lại, H/Esc trở về.

## So sánh công bằng

Giữ nguyên góc quay, độ dài tay 14+14 px, pivot, màu tint, nhịp 8s ở lab/15s ở guide và kích thước hiển thị của Mk2. Điểm khác: PNG nguồn thuộc PSRC cũ, tay gốc dọc được đặt đúng trục trước khi xoay. Giữ chiều rộng PNG gốc, không kéo thân cho giống Mk2. Cùng hệ neo là phép thử có kiểm soát, không phải bản rig tối ưu riêng cho PSRC. Đánh giá khi tắt J để tránh nhầm dấu khớp do code thêm với độ rõ của art.

Chỉ thêm 8 PNG, giữ giấy phép. Không thay bất kỳ file Mk2 hay các map chính, player, collider, project.godot và tiến độ thật. Đây là bản minh họa thị giác, không phải động tác đã duyệt chuyên môn; tay sau đầu/khép khuỷu vẫn là xấp xỉ 2D. Trang phục chỉ là tint.

## Nguồn

Reactorcore — PSRC 2D Sprites - Human Character
https://reactorcore.itch.io/psrc-2d-sprites-human-character
CC BY 4.0 theo file đi kèm (bản nguyên văn tại assets/characters/psrc_lab/SOURCE_LICENSE_CC_BY_4.txt).
https://creativecommons.org/licenses/by/4.0/

Từ thư mục Template: 19.png → head; 87.png → torso (16×26, cùng khung thân Mk2); 114.png → upper_arm; 126.png → forearm; 142.png → hand; 183.png → thigh; 189.png → shin; 195.png → foot.
Ảnh nguồn được copy không sửa pixel; trong game được ghép, quay, tint và căn theo rig thử. Giữ credit khi chia sẻ demo.

## Kiểm thử

- Scene lab: `-- --smoke --no-save` (độ dài tay, 101 bước, điều khiển, mở/đóng guide).
- Scene guide: `-- --guide-smoke --no-save` (151 thời điểm × 3 tư thế × 2 mức zoom × 2 hướng; hông cố định, tay không bị cắt).
- Renderer thật: `-- --capture --no-save` / `-- --guide-capture --no-save` tạo ảnh psrc_0/50/100 và psrc_upper_0/1/2 trong tests/visual/captures.
