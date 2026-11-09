# Hướng dẫn nửa thân trên — thử nghiệm Mk2

Mở mk2_pose_lab.tscn và F6, bấm **Nửa thân trên [H]**. Hoặc mở mk2_upper_body_guide.tscn và F6 trực tiếp.

- Trái: toàn thân 3×. Phải: cùng chuyển động, từ hông trở lên ở 4×/5×.
- 1/2/3 hoặc nút phía trên: chọn một trong ba động tác.
- Space: chạy/dừng; kéo timeline để dừng và xem một thời điểm.
- V: 4×/5×. J: dấu khớp (mặc định tắt). L: đổi bên khi kéo tay ngang ngực.
- R: chạy lại từ đầu. H/Esc: trở về bản thử toàn thân.

Chu kỳ minh họa 15 giây: chuẩn bị 0–3s, thực hiện 3–7s, giữ 7–11s, trở về 11–15s. Lặp để duyệt hình ảnh, chưa phải popup tự chuyển vào map chính, không phải chỉ định thời gian tập.

Giữ nguyên điểm hông ở cả hai mức zoom. Chỉ không vẽ chân, không cắt bàn tay tại đường hông: khi tay hạ thấp, toàn bộ bàn tay vẫn được hiển thị. Không auto-zoom theo từng frame. Nearest filtering giữ nét pixel; xoay sprite vẫn có hạn chế răng cưa và góc nhìn 2D của Mk2.

Nhân vật toàn thân cũ giữ nguyên mặc định; thuộc tính upper_body_only chỉ bật trên actor của phần hướng dẫn. Không thay player, collider, map 1–5, dữ liệu tiến độ, camera/BE hoặc project.godot. Vẫn dùng đúng 8 PNG đã chọn trước đó, không thêm ảnh nguồn.

Mô phỏng tay sau đầu và khép khuỷu vẫn chỉ là xấp xỉ 2D; cần duyệt chuyên môn và có thể vẽ thêm góc/frame trước khi dùng làm hướng dẫn thật. Tô màu thân chưa phải quần áo hoàn thiện.

Kiểm thử: --guide-smoke trên scene guide kiểm 3 tư thế × 2 mức zoom × 2 hướng × 151 thời điểm, khung chứa toàn bộ đoạn tay/bàn tay (có biên an toàn), điểm hông và đồng bộ với toàn thân. --smoke trên scene lab còn kiểm mở/đóng guide. --guide-capture dùng renderer thật chụp 3 tư thế ở tests/visual/captures/mk2_upper_0..2.png. Khi chạy test trong project chính thêm --no-save.
