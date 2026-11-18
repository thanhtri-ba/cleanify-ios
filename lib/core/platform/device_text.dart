import 'dart:io' show Platform;

/// Câu chữ khác nhau giữa iOS và Android, gom về một chỗ để giao diện không phải
/// rải `Platform.isIOS` khắp nơi. Chỉ là chữ hiển thị, không có logic nào ở đây.

/// Tên gọi thiết bị trong câu: "iPhone" trên iOS, "máy" ở nơi khác.
String get deviceName => Platform.isIOS ? 'iPhone' : 'máy';

/// Nơi xem dung lượng trong Cài đặt của hệ điều hành.
String get storageSettingsPath => Platform.isIOS
    ? 'Cài đặt > Cài đặt chung > Dung lượng iPhone'
    : 'Cài đặt > Bộ nhớ';

/// Mệnh đề ngắn về số phận của ảnh sau khi xóa, dùng trong hộp xác nhận.
///
/// iOS đưa ảnh vào "Đã xóa gần đây" 30 ngày. Android xóa qua MediaStore, phần lớn
/// máy không có thùng rác hệ thống nên nói rõ là khó lấy lại.
String get trashNote => Platform.isIOS
    ? 'Ảnh vào "Đã xóa gần đây" 30 ngày.'
    : 'Ảnh bị xóa khỏi thư viện, thường không khôi phục được.';

/// Câu đầy đủ cho hộp xác nhận xóa, [noun] là "ảnh" hoặc "video".
String deleteNote(String noun) => Platform.isIOS
    ? 'iOS sẽ hỏi xác nhận lần nữa; $noun vào mục Đã xóa gần đây 30 ngày.'
    : 'Máy có thể hỏi xác nhận lần nữa; $noun bị xóa khỏi thư viện, '
        'thường không khôi phục được.';
