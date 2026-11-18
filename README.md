# Cleanify — bản chỉ chạy Android

Tách từ `~/Downloads/cleanify_cnn` ngày 15/11/2026. Mã Dart giống hệt bản gốc;
chỗ khác duy nhất là thư mục `ios/` không được chép sang.

## Chạy

```bash
flutter pub get
flutter run -d android
```

## Có gì trong này

| Thư mục | |
|---|---|
| `lib/` | Toàn bộ mã Dart, giống bản gốc |
| `android/` | Gradle, manifest, `MainActivity.kt` (kênh `cleanify/photo_edits`) |
| `assets/` | Model ONNX, font, ảnh onboarding |
| `test/` | Unit test, chạy được bằng `flutter test` |

## Đã bỏ đi

- `ios/` — toàn bộ phần Xcode, CocoaPods, `AppDelegate.swift`
- `build/`, `.dart_tool/` — thư mục sinh ra khi build, `flutter pub get` tự tạo lại
- `tool/`, `pipeline_steps/` — script Python huấn luyện và đánh giá model (669 MB)
- `_old_ui/`, `spike/`, `hollowmere/`, `generated_images/` — tài liệu và thử nghiệm cũ
- `.git/` — chưa khởi tạo kho git mới

## Mã Dart vẫn còn nhánh iOS

`lib/core/platform/photo_edits.dart` và `device_text.dart` vẫn kiểm tra
`Platform.isIOS`. Cố ý để vậy: nhánh đó không bao giờ chạy trên Android, nhưng giữ
nguyên thì còn gộp ngược về bản gốc được. Đừng xoá nếu định đồng bộ hai bên.

## Lưu ý khi sửa

Đây là **bản sao**, không phải nhánh git. Sửa ở đây thì bản gốc `cleanify_cnn`
không đổi theo, và ngược lại. Sửa phần chung (`lib/`) ở hai nơi là nguồn gốc của
lỗi khó tìm — cân nhắc chỉ sửa một bên rồi chép sang.

## Khác biệt Android so với iOS

Xem `android/app/src/main/kotlin/com/example/cleanify/MainActivity.kt`:

- `originalThumbs` luôn rỗng — Android không giữ bản gốc của ảnh đã chỉnh sửa.
- `editedIds` suy đoán theo `DATE_MODIFIED`, không phải cờ chính thức như iOS.
- Xoá ảnh qua MediaStore thường **không khôi phục được**, khác "Đã xoá gần đây" 30 ngày của iOS.
# cleanify-ios
