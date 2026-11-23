# WiFi Password Cracker (Offline Brute-Force Simulator)

Ứng dụng Flutter ngoại tuyến mô phỏng thuật toán dò tìm mật khẩu brute-force (chuyển thể từ đoạn mã Python sang Dart chạy trên `Isolate` nền với bộ nhớ O(1)), kèm tính năng yêu cầu đăng ký kênh YouTube trước khi sử dụng.

> ⚠️ **Lưu ý:** Ứng dụng chỉ mô phỏng thuật toán kiểm tra độ mạnh mật khẩu trên chuỗi bạn tự nhập vào, **không** kết nối hay xâm nhập mạng Wi-Fi thật.

## Tính năng đã hoàn thiện

1. **Thuật toán brute-force tối ưu chạy trên `Isolate` riêng (`lib/services/brute_force_engine.dart`):**
   - Không còn bị đơ giao diện (`Future` trên main thread) và không bị tràn RAM (bỏ lưu toàn bộ tổ hợp vào `List<String>`).
   - Hỗ trợ 3 bộ ký tự: Chỉ số (`0–9`), Chữ thường + số, và Đầy đủ (khớp bộ ký tự bản Python gốc).
   - Hiển thị trực tiếp số tổ hợp đã thử, mẫu đang quét, thời gian chạy, tốc độ thử/giây và nút **Dừng** tức thì.
2. **Yêu cầu đăng ký kênh YouTube + lưu trạng thái (`shared_preferences` + `url_launcher`):**
   - Mở trực tiếp kênh YouTube qua ứng dụng/trình duyệt ngoài (đã khai báo đầy đủ `<queries>` trên Android 11+ và `LSApplicationQueriesSchemes` trên iOS).
   - Lưu cờ `youtube_subscribed` để người dùng chỉ cần xác nhận 1 lần.
3. **Đa nền tảng Android & iOS:**
   - Android: Gradle Kotlin DSL chuẩn Flutter 3.50 (`minSdk 24`, `targetSdk 36`), build sẵn file `.apk` release.
   - iOS: Đã đặt `IPHONEOS_DEPLOYMENT_TARGET = 13.0` & `MinimumOSVersion = 13.0` (tương thích từ iPhone 7 đến các đời mới nhất) và kèm workflow GitHub Actions tự động đóng gói `.ipa` trên `macos-latest`.

## Thay link kênh YouTube của bạn

Mở `lib/main.dart` và đổi hằng số `youtubeChannelUrl` tại lớp `WiFiCrackerPage`:

```dart
static const String youtubeChannelUrl =
    'https://youtube.com/@hellohello-b3o?si=2p-iPYMxKX6DmL_n';
```

## Chạy kiểm thử & Build Android APK

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

File APK xuất ra tại: `build/app/outputs/flutter-apk/app-release.apk`

## Tự động đóng gói file `.ipa` cho iPhone trên GitHub Actions

Workflow đã cấu hình sẵn tại `.github/workflows/build-ios.yml` (`runs-on: macos-latest`).

```powershell
git init -b main
git add .
git commit -m "Complete WiFi Cracker offline simulator Flutter project"
git remote add origin https://github.com/<tai-khoan>/<ten-repo>.git
git push -u origin main
```

Sau khi push, vào tab **Actions** → chọn lượt chạy **Build iOS IPA** → tải file `WiFiCracker-unsigned.ipa` ở mục **Artifacts** (hoặc cấu hình thêm 4 Secrets chứng chỉ Apple để xuất bản `.ipa` đã ký).
