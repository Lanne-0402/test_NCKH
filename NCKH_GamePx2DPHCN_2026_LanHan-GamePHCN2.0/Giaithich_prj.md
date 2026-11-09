# TÀI LIỆU DỰ ÁN & HƯỚNG DẪN KẾT NỐI DATABASE CHO HÂN

> **Đề tài NCKH:** *Nghiên cứu phát triển ứng dụng game Pixel 2D tích hợp trí tuệ nhân tạo nhận diện cử động cánh tay hỗ trợ tập luyện phục hồi chức năng*  
> **Tác giả:** Nông Thị Hồng Lan & Thành viên nhóm (Hân)  
> **Phiên bản:** GamePHCN 2.0 (Tích hợp MongoDB Atlas Cloud & Đo ROM)

---

## 1. TỔNG QUAN KIẾN TRÚC DỰ ÁN

Dự án gồm 2 thành phần chính chạy song song và giao tiếp với nhau theo thời gian thực:

1. **Frontend Game (Godot 4.x - GDScript):**
   * Đồ họa Pixel 2D gồm 5 Map bài tập phục hồi chức năng khớp vai (Ép bả vai, Dạng xoay ngoài, Khép ngang vai, Ôm đầu, Kéo căng qua ngực).
   * Màn hình **Hiệu chuẩn (Calibration)** đo góc vận động khớp vai (ROM - Range of Motion).
   * Màn hình **Báo cáo & Lịch sử tập**: Vẽ biểu đồ đường tiến triển góc ROM theo từng ngày tập và hiển thị bảng tổng kết các buổi tập.
   * Giao tiếp với Backend qua giao thức WebSocket (cổng `8765`) để nhận dữ liệu khung xương và qua HTTP REST (cổng `8766`) để đồng bộ Database.

2. **Backend AI & Database Service (Python 3.12):**
   * **`main.py`**: Luồng chính xử lý Camera, sử dụng Google MediaPipe Pose để trích xuất 33 điểm khớp cơ thể 3D.
   * **`exercises_logic.py`**: Bộ lọc nhiễu EMA và các thuật toán đánh giá góc gập/dạng/xoay của từng Map.
   * **`mongodb_service.py`**: Cầu nối REST API chạy ngầm tại cổng `127.0.0.1:8766`, nhận dữ liệu từ Godot và ghi trực tiếp lên cụm **MongoDB Atlas Cloud**.

---

## 2. CƠ CHẾ KẾT NỐI VÀ LƯU TRỮ DATABASE ONLINE (MONGODB ATLAS)

Hệ thống lưu trữ theo cơ chế **Offline-First**:
* Khi không có mạng, toàn bộ dữ liệu vẫn được lưu tự động trên máy tính (`user://player_progress.json`).
* Khi có mạng và chạy cùng backend Python, dữ liệu sẽ tự động đồng bộ lên Database MongoDB Atlas Cloud trên cụm **`ClusterGamePHCN2D`** theo 2 Collection:
  1. **`patient_profiles`**: Lưu hồ sơ bệnh nhân (`_id = patient_id`), họ tên, góc ROM tối đa, tiến độ mở khóa 5 Map, và mảng `rom_history` theo từng ngày (dùng để vẽ biểu đồ đường ROM).
  2. **`exercise_sessions`**: Lưu chi tiết từng buổi tập (`_id = session_id`), số lần chuẩn (valid reps), số lần chưa đạt (rejected reps), thời gian tập, điểm ổn định (stability), và đánh giá hoàn thành.

---

## 3. HƯỚNG DẪN HÂN PULL VỀ VÀ CHẠY ĐỂ TỰ ĐỘNG KẾT NỐI DATABASE

Khi Hân kéo code mới nhất từ GitHub về máy, **Hân không cần phải ngồi cấu hình Database thủ công từng bước**, chỉ cần làm theo 3 bước đơn giản dưới đây:

### Bước 1: Cài đặt thư viện Python (Nếu máy chưa có)
Mở Terminal/PowerShell tại thư mục dự án và chạy:
```bash
pip install opencv-python mediapipe websockets pymongo dnspython
```
*(Thư viện `pymongo` và `dnspython` dùng để kết nối trực tiếp với MongoDB Atlas Cloud).*

### Bước 2: Kiểm tra file cấu hình có sẵn (`cloud_config.json`)
Trong thư mục gốc dự án đã có sẵn file `cloud_config.json`. Godot khi khởi động sẽ tự động nạp file này:
```json
{
  "enabled": true,
  "provider": "mongodb",
  "url": "http://127.0.0.1:8766",
  "api_key": "rehab_pixel_game"
}
```
* **Lưu ý:** Lan đã cấu hình sẵn cổng bridge nội bộ kết nối tới MongoDB Atlas. Hân không cần sửa gì trong file này.

### Bước 3: Khởi chạy và trải nghiệm
1. **Khởi động Backend Python trước:**
   ```bash
   python main.py
   ```
   * Terminal sẽ bật camera AI MediaPipe và hiển thị dòng:  
     `[MongoDB Bridge] Server REST API dang chay tai: http://127.0.0.1:8766 | Trang thai: SAN SANG`
2. **Khởi động Game bằng Godot Engine:**
   * Mở Godot 4.x $\rightarrow$ Chọn dự án $\rightarrow$ Nhấn **Play (F5)** (hoặc chạy scene `ui/screens/start/start_screen.tscn`).
3. **Kiểm tra trạng thái kết nối:**
   * Tại màn hình chính, nhấp vào **"Báo cáo và lịch sử tập"**.
   * Nhìn lên góc trên bên phải thanh tiêu đề: thấy dòng chữ màu xanh lá:  
     `Cloud DB (MONGODB): Đã bật tự động đồng bộ`  
     $\rightarrow$ Nghĩa là Godot đã kết nối thành công với Database!

---

## 4. CÁC TÍNH NĂNG MỚI ĐÃ HOÀN THIỆN ĐỂ HÂN TEST & THU THẬP SỐ LIỆU

1. **Chuẩn bị sẵn 10 Mã ID bệnh nhân thực tế (`BN001` đến `BN010`):**
   * Đã xóa toàn bộ dữ liệu mẫu giả định.
   * Khi cho người bệnh thử nghiệm, Hân chỉ cần chọn mã ID (ví dụ: `BN001`), nhập họ tên thật của người đó và bấm **"Lưu / Đổi Tên"**.
   * Khi người đó đo Calibration hoặc tập các Map, dữ liệu thật sẽ được ghi nhận vào hồ sơ và đồng bộ lên Database của nhóm.

2. **Nút chuyển đổi "Chế độ: Người bệnh" (Bảo mật riêng tư):**
   * Trên thanh công cụ màn hình Lịch sử có nút chuyển đổi chế độ:
     * **Chế độ Bác sĩ / NCKH (Mặc định):** Lan và Hân có thể chọn qua lại giữa 10 hồ sơ, xem toàn bộ tiến độ, đồng bộ dữ liệu hoặc làm mới ID.
     * **Chế độ Người bệnh:** Khi chuẩn bị đưa máy cho bệnh nhân tập, nhấn nút này để **Khóa**. Giao diện sẽ tự động ẩn dropdown chọn 10 người và ẩn các nút cấu hình kỹ thuật. Người bệnh chỉ nhìn thấy duy nhất kết quả của bản thân họ, không can thiệp vào hệ thống.

3. **Biểu đồ đường ROM (Range of Motion):**
   * Vẽ đường biểu diễn góc mở khớp vai qua các ngày tập với mốc chuẩn 90°.
   * Tự động tính độ tăng giảm góc ROM so với ngày đầu tập để làm báo cáo khoa học.

4. **Nút "Làm mới ID này":**
   * Nếu người bệnh muốn tập thử trước một vài lượt rồi xóa để bắt đầu phiên đo chính thức, chỉ cần bấm **"Làm mới ID này"** để làm sạch riêng hồ sơ đó mà không ảnh hưởng đến các ID khác.

---

## 5. CẤU TRÚC THƯ MỤC CHÍNH ĐỂ HÂN TIỆN THEO DÕI

```text
├── core/
│   ├── autoload/
│   │   └── global.gd           # Quản lý tiến trình, hồ sơ 10 bệnh nhân và đồng bộ Cloud
│   └── exercise/               # Logic tính điểm, số rep, độ ổn định của buổi tập
├── ui/
│   └── screens/
│       ├── calibration/        # Màn hình đo ROM và góc khớp vai
│       └── history/            # Màn hình báo cáo, danh sách buổi tập & biểu đồ ROM
│           ├── history_screen.gd
│           └── rom_line_chart.gd
├── exercises_logic.py          # Bộ nhận diện AI cử động khớp vai MediaPipe (Map 1 -> 5)
├── main.py                     # Luồng camera AI + WebSocket Server + MongoDB Service
├── mongodb_service.py          # Cầu nối REST API MongoDB Atlas
├── cloud_config.json           # Cấu hình kết nối Cloud mặc định
└── Giaithich_prj.md            # Tài liệu này
```
