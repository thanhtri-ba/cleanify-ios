import 'package:flutter/material.dart';

import 'appearance.dart';

/// Bảng màu pastel theo giao diện sáng/tối cho trang chủ. Màu nhấn (lime, xanh, cam,
/// tím) lấy từ [Pastel]; ở đây là phần thay đổi theo sáng/tối: nền, thẻ, chữ và các thẻ
/// pastel (đậm hơn ở chế độ tối).
@immutable
class PastelScheme {
  const PastelScheme._({
    required this.dark,
    required this.page,
    required this.ink,
    required this.mute,
    required this.line,
    required this.card,
    required this.glass,
    required this.glassBorder,
    required this.chip,
    required this.track,
    required this.dockTop,
    required this.dockBottom,
    required this.dockRing,
    required this.tileActive,
    required this.menuTile,
    required this.dockIcon,
    required this.dockIconOn,
    required this.menuIcon,
    required this.dockShadow,
    required this.blobAlpha,
    required this.accent,
    required this.onAccent,
    required this.chartA,
    required this.chartB,
    required this.chartC,
    required this.limeBg,
    required this.limeBg2,
    required this.limeText,
    required this.limeSub,
    required this.blueBg,
    required this.blueBg2,
    required this.blueText,
    required this.blueSub,
    required this.amberBg,
    required this.amberBg2,
    required this.amberText,
    required this.amberSub,
    required this.lilacBg,
    required this.lilacBg2,
    required this.lilacText,
    required this.lilacSub,
  });

  final bool dark;
  final Color page, ink, mute, line, card, glass, glassBorder, chip, track;
  final Color dockTop, dockBottom, dockRing, tileActive, menuTile;
  final Color dockIcon, dockIconOn, menuIcon, dockShadow;
  final double blobAlpha;

  /// Màu nhấn trạng thái bật/được chọn: đen (sáng) hoặc trắng (tối); [onAccent] là màu ngược lại.
  final Color accent, onAccent;

  /// Ba màu cho biểu đồ dung lượng (ảnh lime, video xanh dương, khác cam): chỗ duy nhất
  /// trong app dùng màu, để mỗi loại dữ liệu dễ phân biệt.
  final Color chartA, chartB, chartC;
  final Color limeBg, limeBg2, limeText, limeSub;
  final Color blueBg, blueBg2, blueText, blueSub;
  final Color amberBg, amberBg2, amberText, amberSub;
  final Color lilacBg, lilacBg2, lilacText, lilacSub;

  static const light = PastelScheme._(
    dark: false,
    page: Color(0xFFF5F5F5),
    ink: Color(0xFF111111),
    mute: Color(0xFF666666),
    line: Color(0xFFE4E4E4),
    card: Color(0xFFFFFFFF),
    glass: Color(0xBDFFFFFF),
    glassBorder: Color(0xF2FFFFFF),
    chip: Color(0xFFEBEBEB),
    track: Color(0xFFD6D6D6),
    dockTop: Color(0xFFFFFFFF),
    dockBottom: Color(0xFFF4F4F4),
    dockRing: Color(0xFFE4E4E4),
    tileActive: Color(0xFFEAEAEA),
    menuTile: Color(0xFFEEEEEE),
    dockIcon: Color(0xFF767676),
    dockIconOn: Color(0xFF111111),
    menuIcon: Color(0xFF111111),
    dockShadow: Color(0x40000000),
    blobAlpha: 0.5,
    accent: Color(0xFF111111),
    onAccent: Color(0xFFFFFFFF),
    chartA: Color(0xFF2B2B2B),
    chartB: Color(0xFF7A7A7A),
    chartC: Color(0xFFC4C4C4),
    limeBg: Color(0xFFF0F0F0),
    limeBg2: Color(0xFFE2E2E2),
    limeText: Color(0xFF111111),
    limeSub: Color(0xFF595959),
    blueBg: Color(0xFFECECEC),
    blueBg2: Color(0xFFDADADA),
    blueText: Color(0xFF111111),
    blueSub: Color(0xFF595959),
    amberBg: Color(0xFFF2F2F2),
    amberBg2: Color(0xFFE6E6E6),
    amberText: Color(0xFF111111),
    amberSub: Color(0xFF595959),
    lilacBg: Color(0xFFEEEEEE),
    lilacBg2: Color(0xFFDEDEDE),
    lilacText: Color(0xFF111111),
    lilacSub: Color(0xFF595959),
  );

  static const darkScheme = PastelScheme._(
    dark: true,
    page: Color(0xFF0A0A0A),
    ink: Color(0xFFF2F2F2),
    mute: Color(0xFF8E8E8E),
    line: Color(0xFF262626),
    card: Color(0xFF141414),
    glass: Color(0xB81C1C1C),
    glassBorder: Color(0xFF2A2A2A),
    chip: Color(0xFF222222),
    track: Color(0xFF3A3A3A),
    dockTop: Color(0xFF2A2A2A),
    dockBottom: Color(0xFF181818),
    dockRing: Color(0xFF383838),
    tileActive: Color(0xFF383838),
    menuTile: Color(0xFF303030),
    dockIcon: Color(0xFF9A9A9A),
    dockIconOn: Color(0xFFF2F2F2),
    menuIcon: Color(0xFFF2F2F2),
    dockShadow: Color(0xB3000000),
    blobAlpha: 0.16,
    accent: Color(0xFFF2F2F2),
    onAccent: Color(0xFF111111),
    chartA: Color(0xFFE6E6E6),
    chartB: Color(0xFFA8A8A8),
    chartC: Color(0xFF6E6E6E),
    limeBg: Color(0xFF1F1F1F),
    limeBg2: Color(0xFF2C2C2C),
    limeText: Color(0xFFF2F2F2),
    limeSub: Color(0xFF9A9A9A),
    blueBg: Color(0xFF1C1C1C),
    blueBg2: Color(0xFF292929),
    blueText: Color(0xFFF2F2F2),
    blueSub: Color(0xFF9A9A9A),
    amberBg: Color(0xFF212121),
    amberBg2: Color(0xFF2E2E2E),
    amberText: Color(0xFFF2F2F2),
    amberSub: Color(0xFF9A9A9A),
    lilacBg: Color(0xFF1E1E1E),
    lilacBg2: Color(0xFF2B2B2B),
    lilacText: Color(0xFFF2F2F2),
    lilacSub: Color(0xFF9A9A9A),
  );

  /// Chọn bảng màu theo chế độ đã lưu ([Appearance]) hoặc theo hệ thống.
  static PastelScheme of(BuildContext context) {
    final m = Appearance.mode.value;
    final dark = switch (m) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    return dark ? darkScheme : light;
  }
}
