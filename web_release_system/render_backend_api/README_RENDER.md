# HƯỚNG DẪN TRIỂN KHAI BACKEND API LÊN RENDER.COM (3 BƯỚC)

Dịch vụ này đóng vai trò **API Gateway trung gian** kết nối bảo mật Web Game trên GitHub Pages với cụm cơ sở dữ liệu **MongoDB Atlas Cloud**.

---

### Bước 1: Đăng nhập Render.com
1. Truy cập [https://render.com](https://render.com) và chọn **Sign in with GitHub** (dùng chính tài khoản GitHub của bạn).

---

### Bước 2: Tạo Web Service mới
1. Trên bảng điều khiển (Dashboard) của Render, nhấn nút **New +** $\rightarrow$ Chọn **Web Service**.
2. Chọn kho lưu trữ **`test_NCKH`** của bạn.
3. Điền các thông tin cấu hình:
   * **Name:** `gamephcn-api` (hoặc tên tùy thích).
   * **Region:** `Singapore` (để có tốc độ kết nối nhanh nhất tại Việt Nam).
   * **Branch:** `main` (hoặc nhánh bạn đẩy thư mục này lên).
   * **Root Directory:** `web_release_system/render_backend_api`
   * **Runtime:** `Python 3`
   * **Build Command:** `pip install -r requirements.txt`
   * **Start Command:** `uvicorn app:app --host 0.0.0.0 --port $PORT`
   * **Instance Type:** `Free` (Miễn phí 100%).

---

### Bước 3: Cấu hình Biến Môi Trường (Bảo mật MongoDB)
Cuộn xuống mục **Environment Variables**, nhấn **Add Environment Variable** và thêm:

| Key | Value | Giải thích |
| :--- | :--- | :--- |
| `MONGO_URI` | `mongodb+srv://<user>:<password>@clustergamephcn2d...` | Chuỗi kết nối MongoDB Atlas của bạn |
| `MONGO_DB` | `rehab_pixel_game` | Tên Database lưu trữ |
| `API_KEY` | `rehab_pixel_game` | Khóa bảo mật API |

4. Nhấn **Create Web Service**.
5. Đợi 1–2 phút cho Render build xong, bạn sẽ nhận được đường dẫn API có dạng:
   👉 **`https://gamephcn-api.onrender.com`**

---

### Kiểm tra kết nối thành công:
Mở trình duyệt truy cập: `https://gamephcn-api.onrender.com/health`  
Nếu thấy kết quả:
```json
{
  "ok": true,
  "status": "ONLINE",
  "provider": "MongoDB Atlas Cloud",
  "database": "rehab_pixel_game"
}
```
$\rightarrow$ **Chúc mừng bạn! API đã kết nối hoàn hảo với MongoDB Atlas Cloud một cách tuyệt đối an toàn!**
