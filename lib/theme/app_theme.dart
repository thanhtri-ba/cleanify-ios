import 'package:flutter/material.dart';

import 'motion.dart';

/// Bảng màu duy nhất của app: chỉ đen, trắng và các sắc xám trung tính.
/// Mọi nơi khác phải lấy màu từ đây (hoặc từ [AppColors]), không viết hex riêng.
abstract final class Mono {
  static const ink =
      Color(0xFF111111); // đen: chữ chính, nút chính, trạng thái "bật"
  static const ink2 = Color(0xFF444444); // chữ phụ
  static const ink3 =
      Color(0xFF6B6B6B); // chữ mờ (tương phản >= 4,5 trên trắng)
  static const mid = Color(0xFF8A8A8A); // icon/biểu đồ mức giữa
  static const soft = Color(0xFFB8B8B8); // biểu đồ mức nhạt, chấm trang trí
  static const stroke = Color(0xFFD0D0D0); // viền nhấn, nút tắt
  static const border = Color(0xFFE4E4E4); // viền thẻ, đường kẻ
  static const chip = Color(0xFFEDEDED); // nền chip, nút phụ
  static const surface = Color(0xFFF0F0F0); // nền khối trong thẻ
  static const bg = Color(0xFFF5F5F5); // nền trang
  static const faint = Color(0xFFFAFAFA);
  static const white = Color(0xFFFFFFFF);
}

/// Màu ngữ nghĩa, chỉ dùng ở chỗ màu mang thông tin: biểu đồ dung lượng,
/// trạng thái xóa/lỗi, cảnh báo. Mọi nơi khác giữ đen-trắng-xám ([Mono]).
abstract final class Semantic {
  // Không còn màu ngữ nghĩa: mọi trạng thái dùng đen/trắng/xám.
  static const photos = Color(0xFF111111);
  static const videos = Color(0xFF6B6B6B);
  static const other = Color(0xFFB4B4B4);
  static const danger = Color(0xFF111111);
  static const warning = Color(0xFF6B6B6B);
}

/// Bảng pastel cho trang chủ và màn quét: mỗi loại dữ liệu giữ một màu xuyên suốt
/// (ảnh lime, video xanh dương, màn hình cam, quét tím). `*Bg` là nền nhạt, `*Deep`
/// là chữ/icon đậm trên nền đó, còn lại là màu nhấn.
abstract final class Pastel {
  static const page = Color(0xFFF5F5F5);
  static const ink = Color(0xFF111111);
  static const mute = Color(0xFF666666);
  static const line = Color(0xFFE4E4E4);
  static const track = Color(0xFFD6D6D6);

  // Tên giữ từ bảng pastel cũ để code dùng chung, nhưng mọi giá trị đều là đen/trắng/xám.
  static const lime = Color(0xFF8A8A8A);
  static const limeGlow = Color(0xFFEDEDED);
  static const limeBg = Color(0xFFF0F0F0);
  static const limeBg2 = Color(0xFFE2E2E2);
  static const limeDeep = Color(0xFF111111);
  static const limeText = Color(0xFF111111);
  static const limeSub = Color(0xFF595959);

  static const blue = Color(0xFF6B6B6B);
  static const blueSoft = Color(0xFFBDBDBD);
  static const blueBg = Color(0xFFECECEC);
  static const blueDeep = Color(0xFF111111);

  static const amber = Color(0xFFB4B4B4);
  static const amberBg = Color(0xFFF2F2F2);
  static const amberDeep = Color(0xFF111111);

  static const lilac = Color(0xFF4A4A4A);
  static const lilacBg = Color(0xFFEEEEEE);
  static const lilacBg2 = Color(0xFFDEDEDE);
  static const lilacDeep = Color(0xFF111111);
  static const lilacSub = Color(0xFF595959);

  // Màn quét/dọn nền đen.
  static const night = Color(0xFF0F0F0F);
  static const night2 = Color(0xFF1A1A1A);
  static const night3 = Color(0xFF2A2A2A);
  static const nightMute = Color(0xFF9A9A9A);
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surfaceAlt,
    required this.line,
    required this.stroke,
    required this.text2,
    required this.text3,
    required this.accent1,
    required this.accent2,
    required this.accentSoft,
    required this.tint1,
    required this.tint2,
  });

  final Color surfaceAlt;
  final Color line;
  final Color stroke;
  final Color text2;
  final Color text3;
  final Color accent1; // nhấn = đen (sáng) / trắng (tối)
  final Color accent2;
  final Color accentSoft;
  final Color tint1; // nền nhẹ cho huy hiệu
  final Color tint2;

  LinearGradient get gradient => LinearGradient(colors: [accentSoft, accent1]);

  static const light = AppColors(
    surfaceAlt: Mono.surface,
    line: Mono.border,
    stroke: Mono.stroke,
    text2: Mono.ink2,
    text3: Mono.ink3,
    accent1: Mono.ink,
    accent2: Mono.ink2,
    accentSoft: Mono.mid,
    tint1: Color(0x14000000),
    tint2: Color(0x0A000000),
  );

  static const dark = AppColors(
    surfaceAlt: Color(0xFF1C1C1C),
    line: Color(0xFF2C2C2C),
    stroke: Color(0xFF444444),
    text2: Color(0xFFBDBDBD),
    text3: Color(0xFF9E9E9E),
    accent1: Mono.white,
    accent2: Color(0xFFBDBDBD),
    accentSoft: Color(0xFFBDBDBD),
    tint1: Color(0x24FFFFFF),
    tint2: Color(0x14FFFFFF),
  );

  @override
  AppColors copyWith({
    Color? surfaceAlt,
    Color? line,
    Color? stroke,
    Color? text2,
    Color? text3,
    Color? accent1,
    Color? accent2,
    Color? accentSoft,
    Color? tint1,
    Color? tint2,
  }) =>
      AppColors(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        line: line ?? this.line,
        stroke: stroke ?? this.stroke,
        text2: text2 ?? this.text2,
        text3: text3 ?? this.text3,
        accent1: accent1 ?? this.accent1,
        accent2: accent2 ?? this.accent2,
        accentSoft: accentSoft ?? this.accentSoft,
        tint1: tint1 ?? this.tint1,
        tint2: tint2 ?? this.tint2,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      line: Color.lerp(line, other.line, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent1: Color.lerp(accent1, other.accent1, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      tint1: Color.lerp(tint1, other.tint1, t)!,
      tint2: Color.lerp(tint2, other.tint2, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppColors.dark
          : AppColors.light);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final x = dark ? AppColors.dark : AppColors.light;
  // Khớp đúng PastelScheme.page: lệch một sắc là lộ vệt khi trang trượt.
  final bg = dark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);
  final surface = dark ? const Color(0xFF141414) : Mono.white;
  final ink = dark ? Mono.white : Mono.ink;
  final inkOn = dark ? Mono.ink : Mono.white;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink,
    onPrimary: inkOn,
    secondary: ink,
    onSecondary: inkOn,
    error: ink,
    onError: inkOn,
    surface: surface,
    onSurface: ink,
    outline: x.line,
    surfaceTint: Colors.transparent,
  );

  final shape16 =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    extensions: [x],
    splashFactory: NoSplash.splashFactory,
    textTheme: Typography.material2021()
        .black
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          titleLarge: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: ink),
          titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: ink),
          bodyMedium: TextStyle(
              fontSize: 14, height: 1.4, letterSpacing: 0, color: ink),
        ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle:
          TextStyle(color: inkOn, fontSize: 14, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ink, linearTrackColor: x.line, circularTrackColor: x.line),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Không ép full-width: nút trong dialog/Row sẽ giãn vô hạn. Trang nào cần
        // nút rộng thì tự bọc SizedBox(width: double.infinity).
        minimumSize: const Size(64, 52),
        shape: shape16,
        elevation: 0,
        backgroundColor: ink,
        foregroundColor: inkOn,
        disabledBackgroundColor: dark ? const Color(0xFF242424) : Mono.chip,
        disabledForegroundColor: dark ? const Color(0xFF6E6E6E) : Mono.mid,
        textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape16,
        side: BorderSide(color: x.stroke),
        foregroundColor: ink,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: x.text2),
    ),
    dividerColor: x.line,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SlidePageTransitionsBuilder(),
    }),
  );
}
