# Báo cáo assets và quy ước hình ảnh — 02/10/2026

## Phạm vi và kết luận

Đã kiểm tra cấu trúc thư mục assets, các tài nguyên đang được scene tham chiếu, ảnh nền/atlas/vật thể được chọn và ảnh dựng của Home + 5 map. Đây là kiểm tra khả năng ghép vào game, không phải duyệt từng frame của mọi gói tải về.

Game đã có lớp hình ảnh pixel nền tảng cho 5 map, nhưng CHƯA hoàn thiện mỹ thuật. Nhân vật, hướng dẫn động tác, âm thanh, hiệu ứng và backend thật được để lại theo kế hoạch nhóm. Các map 2–5 dùng lại một phần môi trường rừng: cần ảnh riêng để tăng nhận diện từng map.

## Tài nguyên hiện có và cách dùng

| Nhóm | Đánh giá | Xử lý |
|---|---|---|
| Legacy-Fantasy / High Forest 2.3 (nằm trong thư mục tên 2.0) | Phù hợp rừng, đá, cỏ, nước; atlas có nhiều sprite và chữ đánh dấu nên không kéo cả atlas vào scene | Chọn/cắt tài nguyên vào assets/shared/environment; giữ bản gốc |
| Kenney Pixel UI | Phù hợp làm khung UI tạm đồng nhất; có License.txt CC0 | Dùng panel, button qua assets/shared/ui/game_theme.tres; kèm LICENSE-KENNEY.txt |
| Treasure Hunters | Có sprite gai dùng cho tường; phong cách/độ tương phản cần cân chỉnh thêm | Dùng sprite Spikes cho map 3; chưa thấy file license riêng trong thư mục gói |
| Kings and Pigs | Có art platformer nhưng không đủ động tác PHCN tương ứng | Chưa đưa nhân vật của gói vào game |
| Legacy Fantasy - Debug Map | Có Terms.txt; không tự suy rộng điều khoản sang gói High Forest khác | Giữ nguyên, cần nhóm đối chiếu nguồn tải nếu dùng |
| FreeCharactersAnimationsAssetPack / Runner1-Updated | Nhân vật chưa phù hợp bộ động tác cần thiết | Không ép thay nhân vật tạm |
| assets/background/*.jpg | Chưa chọn làm nền chuẩn cho lần ghép này | Không mặc định dùng chung với môi trường pixel nhiều lớp |
| assets/font/SVN-Determination-Sans.otf | Có font, nhưng chưa thấy giấy phép kèm riêng và chưa kiểm đủ glyph tiếng Việt | Giữ font Godot hiện có để chữ tiếng Việt dễ đọc; chưa ép font pixel |

Lưu ý giấy phép: đây là ghi nhận file hiện có trong thư mục, không xác nhận quyền phát hành. Cần bổ sung bằng chứng nguồn tải/điều khoản của High Forest, Treasure Hunters và font trước khi phát hành công khai.

## Assets thiếu hoặc chưa đạt theo map

| Map | Đã ghép | Thiếu / chưa đạt | Ưu tiên |
|---|---|---|---|
| 1 — Phá cản | Nền rừng, đất cỏ, đá, lối ra; đá bỏ scale méo, đáy khớp pivot | cave_entrance.png thực tế là thân cây rỗng, không phải hang đá. Hiện ghi LỐI RA. Cần vẽ/chọn cửa hang đúng chủ đề nếu giữ kịch bản hang | Cao |
| 2 — Nâng đá | Phiến đá ghép tile, mặt đất chuẩn, nền rừng biến thể | Chưa có sprite phiến đá nguyên khối/chi tiết nứt đẹp; thiếu môi trường riêng. Tile hiện dùng được về kỹ thuật nhưng còn lặp | Cao |
| 3 — Đẩy tường | Tường đá và gai hướng vào vùng chơi, giữ chuyển hướng theo controller | Cần bộ tường/gai cùng phong cách và nền riêng; góc chéo vẫn xoay sprite nên pixel không đều như ảnh vẽ chéo riêng | Cao |
| 4 — Leo vách | Bậc đá có cỏ, hình đá nền, camera bám nhân vật | Vách nền đang lặp đá phóng lớn, chưa phải bộ vách liền mạch; cờ đỉnh vẫn placeholder | Cao |
| 5 — Thiền định | Bể ghép đá + mặt nước từ atlas, môi trường rừng | Chưa có bộ suối nước nóng/bờ đá tự nhiên riêng; hơi nước và chỉ báo tay là placeholder | Cao |
| Dùng chung | Icon Settings, khung bảng/nút và quy ước nhân vật | Nhân vật chính + guide động tác còn placeholder; thiếu bộ icon trạng thái/âm lượng đồng nhất, thanh tiến độ vẫn giao diện Godot | Sau khi chốt 5 map |

Không xóa các scene placeholders; chỉ thay đường dẫn phần art đã có. Các hiệu ứng phá đá, sóng năng lượng, hơi nước hiện tại không được coi là assets hoàn thiện.

## Quy ước nhân vật đã chốt

- Frame nguồn: 64 × 64 px, nền trong suốt; hiển thị ở scale 2× thành vùng 128 × 128.
- Điểm đặt chân trong frame: (32, 64), giữa cạnh dưới. Mọi frame cùng pivot, không auto-trim làm lệch chân.
- Root Player / Marker2D FootAnchor: (0, 0) là vị trí chân trong world.
- Khi ghép Sprite2D centered: đặt trong Visuals tại (0, -64), scale (2, 2). Không scale root Player.
- Khung thiết kế SpriteFrame: x=-64..64, y=-128..0, ẩn khi chạy.
- Collision giữ 42 × 72, tâm (0, -36), đáy tại y=0; không tự tăng collision theo khung ảnh.
- Placeholder hiện tại khoảng 68 × 96 px (kể cả tay). 128 × 128 là vùng chứa sprite tương lai, không phải yêu cầu vẽ người kín toàn khung.
- Cần các nhóm animation sau: idle, run, jump/land, động tác map 1, raise/hold map 2, push theo hướng map 3, hands-behind-head map 4, stretch trái/phải map 5, hit, finish.
- player.gd hiện còn điều khiển Shape/ArmLeft/ArmRight của placeholder. Khi tích hợp sprite thật cần chuyển các hàm phản hồi sang animation; không chỉ xóa placeholder là xong.
- Map 4: mặt va chạm bậc được căn về y=0 của bậc, trùng RunStart và đáy chân; không đổi kích thước collider nhân vật.

## Quy ước UI và thay đổi đã làm

- Viewport chuẩn 1152 × 648; canvas_items + keep để giữ bố cục khi thay tỉ lệ cửa sổ.
- Nearest filtering cho hình ảnh pixel. Dùng scale nguyên cho tile; chuyển động vẫn được phép dùng tọa độ float.
- Shared theme Kenney màu cát/nâu áp dụng cho nút và panel; Home, chọn map, chọn mức, calibration, lịch sử dùng bảng màu chung.
- Home dùng cùng SettingsMenu như 5 map, cùng settings_gear.svg và vị trí góc trái.
- Settings trong map: âm lượng, tắt âm, Trang chủ, camera, chọn map, Tiếp tục chơi. Mở Settings tạm dừng session; chuyển trang trong map có xác nhận.
- Settings ở Home: không hiện nút về Home; nút cuối là ĐÓNG; chuyển trang không cảnh báo kết thúc buổi tập khi chưa ở trong map.
- TRẠNG THÁI và ỔN ĐỊNH giữ trục giữa bên phải; HIỆP giữ ngay dưới tiến độ bên trái. Điểm thưởng map 5 giữ cùng trục bên phải.
- Thanh giữ động tác map 2–5 chuyển xuống vùng dưới màn chơi, tránh đè lên phiến đá/tường ở trung tâm.
- Đây là UI tạm có thể thay texture/theme khi nhóm gửi thiết kế Settings chính thức; không đổi các đường dẫn nút phục vụ logic.

## Kiểm tra và phần chưa xác nhận

- Có test mới tests/core/art_layout_test.tscn: Home Settings, 5 map, pivot, collider, đứng trên sàn, menu vừa khung, phiên ACTIVE.
- Chế độ --capture chụp Home và các map ở trạng thái hướng dẫn/chơi/Settings bằng renderer thật; ảnh tại tests/visual_output trong bản kiểm thử.
- Các smoke test map, Settings, navigation và persistence được chạy với --no-save hoặc profile riêng, không đụng dữ liệu tiến độ thật.
- Kết quả chạy cụ thể được ghi trong ART_VALIDATION.txt sau khi hoàn tất kiểm tra.
- Chưa kiểm thử camera/MediaPipe/backend thật, thiết bị màn hình cảm ứng hoặc mọi GPU.
- Chưa xuất .exe: không tìm thấy export templates trong thư mục Godot tiêu chuẩn trên máy; chưa cài thêm template.
- Vẫn cần kiểm tra người dùng thực tế và bổ sung ảnh đặc trưng trước khi gọi là bản art hoàn chỉnh.

## Thứ tự tiếp theo

1. Nhóm duyệt bố cục và báo cáo này; bổ sung hang map 1, phiến/tường đá, vách liền mạch, suối nước nóng.
2. Chốt palette, mật độ pixel và loại bỏ đường nối lặp ở nền các map.
3. Vẽ nhân vật/guide theo khung và pivot ở trên; thay logic placeholder bằng animation thật.
4. Thêm âm thanh/VFX sau khi hình ảnh được duyệt.
5. Nhận data và tích hợp backend/camera, chạy lại bộ test luồng + kiểm thử tracking thật.
6. Xác minh nguồn/license và cài export template phù hợp để đóng gói demo.
