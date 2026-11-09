# Maps

Mỗi map nằm trong một thư mục độc lập `map_<số>`.

- `map_1`: gameplay đang hoạt động.
- `map_2`: gameplay nâng đá bằng động tác giữ 5 giây.
- `map_3`: gameplay đẩy lùi tường gai bằng giữ tư thế dạng tay 5 giây.
- `map_4`: gameplay leo vách đá bằng chạy bậc + giữ tư thế ôm đầu 5 giây.
- `map_5`: gameplay suối nước nóng — kéo căng 30 giây, thư giãn 30 giây, đổi tay.

Một map chỉ nên chứa scene, controller và vật thể riêng của map đó. Thành phần có thể dùng lại giữa nhiều map phải đặt trong `core` hoặc `shared`.
