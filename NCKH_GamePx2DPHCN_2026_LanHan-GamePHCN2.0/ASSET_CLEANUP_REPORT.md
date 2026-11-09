# Rà soát và tách assets — 09/10/2026

## Phạm vi

Project thực tế: `D:/-NCKH-GamePixel2D_PHCN/-NCKH-GamePixel2D_PHCN/-NCKH-GamePixel2D_PHCN`.
Kho lưu ngoài project: `D:/-NCKH-GamePixel2D_PHCN/ASSETS_UNUSED_2026-10-09`.

Đối chiếu project.godot, toàn bộ code/scene trong core, maps, ui, tests và tài nguyên tham chiếu tiếp theo; kiểm tra load/preload, UID kèm đường dẫn, tải map bằng đường dẫn động và công cụ prepare_art. Không tìm thấy code gameplay quét/tải toàn bộ thư mục assets. Bộ lọc giữ cả tài nguyên được test tham chiếu, không chỉ entry scene. Không coi .import hoặc tài liệu README là bằng chứng một ảnh đang được game sử dụng.

Không duyệt mỹ thuật từng frame của hơn 4.400 file. Đây là kiểm tra sử dụng/phụ thuộc và khả năng tiếp tục dùng theo scene hiện tại; việc thẩm định bản quyền/chất lượng toàn bộ gói là công việc riêng.

## Số liệu trước khi Godot import lại

| Nhóm | Số file | Dung lượng byte |
|---|---:|---:|
| Giữ: tài nguyên game/test và .import đi kèm | 37 | 63.874 |
| Giữ: README và giấy phép | 8 | 5.456 |
| Tách: nguồn phục vụ chỉnh sửa/tạo lại ảnh, nên giữ backup | 2.633 | 4.825.694 |
| Tách: ứng viên không có tham chiếu, chưa dùng | 1.770 | 13.583.801 |
| Metadata .import được Godot tự dọn khi editor còn mở | 1 | 992 |
| Tổng ghi nhận trong manifest | 4.449 | 18.479.817 |

Assets giảm từ 349 xuống 12 thư mục con. Giữ 45 file; tách 4.403 file (~17,56 MiB), gồm 2.244 file nguồn/tài liệu và 2.159 file .import. 37 file tài nguyên giữ lại tương ứng 18 ảnh + 18 .import + 1 theme. Không được hiểu số file là số ảnh: một phần lớn là metadata hoặc định dạng khác.

Lần kiểm đầu thấy 4.447 file; editor còn mở sinh thêm 2 .import trước lượt di chuyển. Việc tách bị ngắt tại một file đang bị khóa, sau đó tiếp tục khi người dùng xác nhận đóng editor. Godot đã tự dọn `assets/IconGodotNode/IconGodotNode/node/icon_path_follow.png.import`; ảnh PNG tương ứng được giữ nguyên trong kho lưu. Manifest đánh dấu `EDITOR_REMOVED_METADATA`, không coi là file đã chuyển và script khôi phục bỏ qua metadata này (Godot có thể tạo lại). Không mất ảnh/file nguồn. Các file đã chuyển được đối chiếu SHA256.

## Đang dùng — tiếp tục giữ

| Vị trí | Nội dung | Nhận xét |
|---|---|---|
| assets/map_1/environment | background_sky, forest_far, forest_near, ground_grass_tile, ground_rock_tile | Nền, cây, đất map 1; tiếp tục dùng được |
| assets/map_1/obstacles/rock_base.png | Đá map 1 | Đang dùng; có thể giữ |
| assets/map_1/goal/cave_entrance.png | Lối ra map 1 | Đang dùng nhưng là thân cây rỗng, chưa phải cửa hang đá đúng kịch bản |
| assets/shared/environment | sky, forest, bushes, grass, stone, rocks, water, spikes | Home và các map dùng qua scene/script; giữ cả phụ thuộc preload |
| assets/shared/ui | game_theme.tres, panel_tan_inlay, button_tan, button_brown_pressed | Theme dùng chung, tiếp tục dùng được |
| assets/map_1 và assets/shared | README, LICENSE-KENNEY.txt | Giữ nguồn gốc/giấy phép |

Map 2 vẫn dùng phiến đá ghép tile; map 3 dùng tường/gai; map 4 thiếu vách liền mạch và cờ đỉnh hoàn thiện; map 5 chưa có suối nước nóng riêng. Giữ assets hiện tại không đồng nghĩa mỹ thuật đã hoàn thiện. Nhân vật và guide còn placeholder trong scene/code, không phụ thuộc các bộ nhân vật đã tải. Không xóa placeholder đang phục vụ gameplay.

Icon Settings nằm tại ui/shared/settings_gear.svg, icon project tại icon.svg: ngoài assets và vẫn giữ nguyên. Không đụng settings_app_icon.png, code gameplay, dữ liệu lưu người chơi, .git hay chủ động xóa .godot.

## Đã tách — chưa xóa dữ liệu

Giữ nguyên đường dẫn tương đối dưới kho lưu; xem manifest.csv cho từng file, lý do, SHA256 và nơi tham chiếu.

- `assets/itch.io/Legacy-Fantasy - High Forest 2.0`: nguồn nền/cây/đá/nước đã được cắt ra bản dùng trong game. Không tải trực tiếp khi chơi, nhưng NÊN GIỮ để chỉnh art.
- `assets/itch.io/Treasure Hunters`: nguồn gai đang dùng. NÊN GIỮ cùng nguồn/điều khoản tải.
- `assets/itch.io/kenney_pixel-ui-pack`: nguồn UI đang dùng. NÊN GIỮ source và license.
- `assets/itch.io/Kings and Pigs`, `assets/itch.io/Legacy Fantasy - Debug Map`: chưa có tham chiếu gameplay; chỉ giữ nếu nhóm còn muốn khai thác.
- `assets/FreeCharactersAnimationsAssetPack`, `assets/Runner1-Updated`: chưa dùng; chưa phù hợp đủ động tác PHCN.
- `assets/IconGodotNode`: bộ icon chưa dùng trong UI hiện tại.
- `assets/background`, `assets/font`: ảnh nền và font ứng viên chưa dùng.
- `assets/map_1/ui`: tách theme cũ và các ảnh UI đã được thay bằng shared theme; giấy phép vẫn giữ trong project.
- `assets/shared/ui/panel_brown.png` và .import: không còn tham chiếu.

Không nên xóa cả kho lưu chỉ vì không được tải lúc chơi. Ba gói nguồn High Forest, Treasure Hunters, Kenney còn giá trị chỉnh sửa; giữ một bản backup ngoài project là đủ để tránh Godot import chúng. README cũ/ASSET_AUDIT.md là ghi nhận lịch sử trước đợt tách này; đường dẫn source cũ nay nằm trong kho lưu.

## Công cụ tạo lại ảnh và khôi phục

tools/prepare_art.gd nay nhận đường dẫn gói nguồn ngoài project; không tự chạy lại để tránh ghi đè ảnh nhóm đã chỉnh. Ví dụ đối số khi chạy script Godot:

`--headless --path <project> --script res://tools/prepare_art.gd -- --source-assets=D:/-NCKH-GamePixel2D_PHCN/ASSETS_UNUSED_2026-10-09/assets`

Script vẫn dùng source trong res://assets nếu đã khôi phục. Bản script trước thay đổi được lưu trong kho lưu tại prepare_art.before.gd.

Để khôi phục toàn bộ assets: chạy restore_assets.ps1 trong kho lưu bằng PowerShell. Script kiểm SHA256 trước, từ chối ghi đè file đã thay đổi và COPY lại dữ liệu; không xóa kho lưu. Có thể tự copy chỉ một gói cần dùng theo đường dẫn trong manifest.

## Kiểm tra

audit_assets.ps1 chạy resource_paths_smoke_test trước khi di chuyển; lưu baseline.log ở thư mục công cụ. Kiểm SHA256 từng file đã chuyển và file giữ lại trước import. Sau đó import và chạy 9 test: resource paths, art layout, Settings, navigation, map 1–5. Kết quả thực tế nằm trong các file .log của kho lưu; chỉ các dòng PASS mới xác nhận test hoàn thành. Test dùng --no-save để không ghi tiến độ thật. Headless không thay thế kiểm tra hình ảnh bằng mắt.

## Hiệu năng

Giảm mạnh số file Godot phải quét/import khi mở project hoặc import mới. Trong bản hiện tại, các gói bị tách không được gameplay nạp toàn bộ vào RAM, nên chưa có cơ sở khẳng định FPS hoặc thời gian vào map sẽ tăng đáng kể. Không đo benchmark FPS hay export executable trong đợt này. Cache .godot có thể vẫn chứa tài nguyên cũ; không cần xóa cache thủ công để hoàn thành việc tách nguồn.

## Kết quả xác nhận cuối cùng

- Baseline resource_paths_smoke_test: PASS.
- 9/9 test sau tách trên project thật: PASS; không có SCRIPT ERROR/ERROR trong log test.
- Bản sao chỉ chứa tài nguyên còn giữ, không copy .godot cũ: import lại xong; resource_paths_smoke_test và art_layout_test PASS. Lượt import đầu có cảnh báo theme do cache chưa sinh; sau import, lượt kiểm lại không còn lỗi tài nguyên.
- tools/prepare_art.gd: kiểm cú pháp PASS; chạy với --source-assets trỏ kho ngoài project trên bản sao tạm: CURATED_ART PASS. Không chạy công cụ ghi đè art trong project thật.
- File backup source có hash kiểm chứng; restore_assets.ps1 hỗ trợ phục hồi nhưng chưa chạy khôi phục vào project thật vì sẽ đưa assets thừa trở lại.
- Toàn bộ thay đổi sẵn có trong Git được giữ; không reset/checkout/commit. Việc chuyển assets khiến Git hiển thị các đường dẫn cũ là deleted; dữ liệu nằm ở kho ngoài project, không nằm trong commit mặc định. Khi chuyển máy, cần sao lưu riêng kho này.
