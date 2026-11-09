# HƯỚNG DẪN TRIỂN KHAI HỆ THỐNG WEB GAME LÊN GITHUB PAGES & RENDER (MONGODB ATLAS)

Hệ thống được thiết kế độc lập 100% trong thư mục `web_release_system/`, gồm 2 thành phần:

```text
web_release_system/
├── render_backend_api/         # API trung gian deploy lên Render.com (Bảo mật MongoDB Atlas)
└── github_pages_frontend/      # Web App HTML5/Wasm deploy lên GitHub Pages
```

---

## BƯỚC 1: TRIỂN KHAI API TRUNG GIAN LÊN RENDER.COM (BẢO MẬT MONGODB)

1. Đăng nhập [https://render.com](https://render.com) bằng tài khoản GitHub của bạn.
2. Nhấn nút **New +** $\rightarrow$ Chọn **Web Service**.
3. Chọn repository **`test_NCKH`**.
4. Cấu hình dịch vụ:
   * **Name:** `gamephcn-api` (hoặc tên tùy thích).
   * **Region:** `Singapore`.
   * **Branch:** `main` (hoặc nhánh bạn đẩy thư mục này lên).
   * **Root Directory:** `web_release_system/render_backend_api`
   * **Runtime:** `Python 3`
   * **Build Command:** `pip install -r requirements.txt`
   * **Start Command:** `uvicorn app:app --host 0.0.0.0 --port $PORT`
   * **Instance Type:** `Free`.
5. Cuộn xuống mục **Environment Variables** $\rightarrow$ **Add Environment Variable**:
   * `MONGO_URI`: `mongodb+srv://<username>:<password>@clustergamephcn2d...` (Chuỗi kết nối của bạn từ MongoDB Atlas).
   * `MONGO_DB`: `rehab_pixel_game`
   * `API_KEY`: `rehab_pixel_game`
6. Nhấn **Create Web Service**.
7. Sau ~2 phút, Render sẽ cấp cho bạn đường link có dạng:  
   👉 **`https://gamephcn-api.onrender.com`**

*(Mở `https://gamephcn-api.onrender.com/health` trên trình duyệt: thấy `"status": "ONLINE"` là thành công!)*

---

## BƯỚC 2: CẬP NHẬT URL RENDER VÀO FRONTEND WEB

Mở tệp `web_release_system/github_pages_frontend/cloud_config.json` và thay `url` bằng link Render bạn vừa nhận được:
```json
{
  "enabled": true,
  "provider": "mongodb",
  "url": "https://gamephcn-api.onrender.com",
  "api_key": "rehab_pixel_game"
}
```

---

## BƯỚC 3: TRIỂN KHAI FRONTEND LÊN GITHUB PAGES

### Cách 1: Deploy trực tiếp từ nhánh (Khuyên dùng)
1. Đẩy toàn bộ thư mục `web_release_system/github_pages_frontend` lên GitHub.
2. Trên GitHub, vào mục **Settings** của repository `test_NCKH` $\rightarrow$ Chọn thẻ **Pages** ở thanh bên trái.
3. Ở mục **Build and deployment**:
   * **Source:** Chọn `Deploy from a branch`.
   * **Branch:** Chọn nhánh của bạn (ví dụ `main` hoặc `gh-pages`), thư mục chọn `/ (root)` hoặc thư mục tương ứng.
4. Nhấn **Save**.
5. Sau 1–2 phút, trang web game sẽ chính thức hoạt động tại:  
   👉 **`https://lanne-0402.github.io/test_NCKH/web_release_system/github_pages_frontend/`**  
   *(Hoặc trỏ root nếu bạn đẩy riêng nội dung thư mục này vào nhánh `gh-pages`)*.

---

## TẠI SAO GIẢI PHÁP NÀY AN TOÀN TUYỆT ĐỐI?
* **Mật khẩu MongoDB được bảo vệ 100%:** Khách truy cập web không thể xem chuỗi `mongodb+srv://...` vì nó được mã hóa nằm trong Render Dashboard.
* **Camera xử lý tại chỗ:** Trình duyệt tự chạy mô hình MediaPipe Vision Wasm bằng GPU của máy người dùng, video không bị truyền ra ngoài, bảo vệ quyền riêng tư tuyệt đối cho bệnh nhân.
* **Không làm hỏng bản Offline:** Thư mục mã nguồn chính và bản cài đặt `.exe` không bị ảnh hưởng bất cứ chi tiết nào.
