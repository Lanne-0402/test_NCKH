# Mk2 — võ sinh lữ hành (10/10/2026)

Mở mk2_pose_lab.tscn hoặc mk2_upper_body_guide.tscn trong Godot và F6. Trang phục bật mặc định; nút Trang phục hoặc phím O chuyển qua lại với hình Mk2 gốc. H đổi chế độ. J bật/tắt dấu khớp. V đổi cỡ. L đổi bên kéo tay. Trạng thái trang phục được giữ khi mở/đóng phần hướng dẫn.

## Thiết kế thử

Áo xám lam cổ chéo tay ngắn, viền màu cát; đai vải; khăn che nửa mặt và băng đầu gọn; băng cổ tay ngắn; quần nâu than và giày thấp. Không vũ khí, áo choàng hay dải khăn dài. Khuỷu/cẳng tay để lộ, mặt bớt chi tiết.

Đây là các lớp hình vector/pixel-shaped vẽ bằng Godot code trên rig Mk2, KHÔNG phải quần áo thành phẩm có sẵn trong pack, KHÔNG phải PNG mới do AI sinh. 8 PNG nguồn vẫn nguyên vẹn. Thân và chân mặc đồ được vẽ thay phần thân/chân nền để không lộ hình cơ thể qua viền. Tay áo đi theo cánh tay, băng cổ tay theo cẳng tay, khăn theo đầu; vẫn dùng nguyên điểm khớp và góc animation cũ.

Mục tiêu: duyệt khả năng ghép đồ và độ rõ động tác, chưa phải mỹ thuật cuối. Đường nét trang phục hiện phẳng hơn shading của ảnh Mk2; cần vẽ/chỉnh sprite đồng bộ nếu chốt mẫu này. Góc tay sau đầu/khép khuỷu vẫn chỉ là xấp xỉ 2D chưa được chuyên môn duyệt. Chưa thử độ tương phản trên 5 nền map thực tế.

## Phạm vi và kiểm thử

Chỉ thay 3 script Mk2 trong tests/visual, thêm tài liệu này. Không thay PSRC cũ, player chính, map 1–5, project.godot, dữ liệu người chơi hoặc file ảnh nguồn. Tài liệu Mk2 cũ mô tả phiên bản tint trước đây; tài liệu này bổ sung chế độ trang phục mới.

--smoke kiểm bật/tắt không đổi điểm khớp, điều khiển và mở/đóng guide.
--guide-smoke kiểm đồng bộ trang phục hai nhân vật, 3 tư thế, 2 mức zoom, cả hai hướng và 151 thời điểm cho mỗi trường hợp. Kiểm khung tay là kiểm hình học rig; trang phục được kiểm trực quan thêm qua renderer.
--capture / --guide-capture xuất ảnh tên mk2_outfit_*; giữ ảnh baseline mk2_* cũ để so sánh. Trong project thật dùng thêm --no-save.
