import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import 'app_dock.dart';

/// Bộ widget dùng chung cho các trang phụ (Bộ nhớ, Cài đặt, Kết quả...) theo phong cách
/// pastel + sáng/tối của trang chủ. Màu lấy từ [PastelScheme.of]; dock đã được
/// `MediaQuery.padding.bottom` tính sẵn nên nội dung tự né dock.
class PageScaffold extends StatefulWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.trailing,
    this.bottomBar,
    this.showBack = true,
    this.listCount = 0,
    this.listBuilder,
    this.gridDelegate,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;

  /// Thanh hành động cố định nằm ngay trên dock (ví dụ "Xóa N ảnh").
  final Widget? bottomBar;
  final bool showBack;

  /// Danh sách dài dựng lười (video, ảnh...) hiện sau [children].
  final int listCount;
  final IndexedWidgetBuilder? listBuilder;

  /// Nếu có thì danh sách dựng dạng lưới.
  final SliverGridDelegate? gridDelegate;

  @override
  State<PageScaffold> createState() => _PageScaffoldState();
}

class _PageScaffoldState extends State<PageScaffold> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Độ loang của vầng sáng, bằng 2 sigma của bản làm mờ cũ.
  static const double _blobSigma = 46;
  static const double _blobFeather = _blobSigma * 2;

  /// Vầng sáng trang trí ở nền.
  ///
  /// Trước đây đây là hình tròn ĐẶC bọc trong `ImageFiltered(blur sigma 46)`.
  /// Làm mờ Gauss một hình tròn màu đều thì kết quả đúng bằng một dải chuyển
  /// màu tròn — nhưng Flutter không biết thế, nên nó dựng một lớp ngoài màn
  /// hình rồi chạy lại bộ lọc MỖI KHUNG HÌNH mà vùng đó phải vẽ lại. Ba vầng
  /// sáng nhân với mọi trang, cộng thêm lúc chuyển trang có hai trang cùng
  /// sống, là đủ để cả app rớt khung hình. Vẽ thẳng gradient cho ra cùng hình
  /// ảnh với không một lượt lọc nào.
  Widget _blob(
      double? left, double top, double size, Color color, PastelScheme t,
      {double? right}) {
    final r = size / 2;
    final outer = r + _blobFeather;
    final a = t.blobAlpha;
    return Positioned(
      left: left == null ? null : left - _blobFeather,
      right: right == null ? null : right - _blobFeather,
      top: top - _blobFeather,
      child: IgnorePointer(
        child: Container(
          width: outer * 2,
          height: outer * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: a),
                color.withValues(alpha: a * 0.55),
                color.withValues(alpha: 0),
              ],
              stops: [(r - _blobSigma) / outer, r / outer, 1],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final pad = MediaQuery.paddingOf(context);
    // Trang này luôn có dock nên tự chừa chỗ cho nó, thay vì nhận padding bơm
    // sẵn từ DockShell. Xem ghi chú ở DockShell để biết vì sao đổi.
    final dock = DockShell.reserve(context);
    final canPop = Navigator.of(context).canPop();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.page,
        body: Column(children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: Stack(children: [
                      _blob(-60, -50, 240, const Color(0xFFBDBDBD), t),
                      _blob(null, 40, 220, const Color(0xFF9A9A9A), t,
                          right: -70),
                      _blob(40, 520, 200, const Color(0xFFD0D0D0), t),
                    ]),
                  ),
                ),
              ),
              CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, pad.top + 10, 20, 0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.showBack && canPop)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(children: [
                                  RoundIconButton(
                                      AppIcons.arrowBackIosNewRounded,
                                      label: 'Quay lại',
                                      onTap: () =>
                                          Navigator.of(context).maybePop()),
                                  const Spacer(),
                                  if (widget.trailing != null) widget.trailing!,
                                ]),
                              ),
                            Reveal(
                                index: 0,
                                child:
                                    PageTitle(widget.title, widget.subtitle)),
                            ...widget.children,
                          ]),
                    ),
                  ),
                  if (widget.listBuilder != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: widget.gridDelegate != null
                          ? SliverGrid.builder(
                              gridDelegate: widget.gridDelegate!,
                              itemCount: widget.listCount,
                              itemBuilder: widget.listBuilder!,
                            )
                          : SliverList.builder(
                              itemCount: widget.listCount,
                              itemBuilder: widget.listBuilder!,
                            ),
                    ),
                  // Chỗ cuộn thêm ở đáy để dòng cuối không nằm dưới thanh
                  // hành động và dock. Thanh hành động cao nhất (hai nút, chữ
                  // xếp trên) khoảng 120, cộng 34 padding trên và chỗ chừa dock.
                  SliverToBoxAdapter(
                      child: SizedBox(
                          height: widget.bottomBar != null
                              ? pad.bottom + dock + 152
                              : pad.bottom + dock + 24)),
                ],
              ),
              // Thanh hành động nổi trên nội dung, nền mờ dần lên để chữ phía sau không đè nút.
              if (widget.bottomBar != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                        16, 34, 16, (pad.bottom + dock - 2).clamp(0.0, 400.0)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: const [0, 0.62, 1],
                        colors: [
                          t.page,
                          t.page,
                          t.page.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: widget.bottomBar!,
                  ),
                ),
              // Thanh tiêu đề thu gọn khi cuộn.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedBuilder(
                  animation: _scroll,
                  builder: (_, __) {
                    final off = _scroll.hasClients ? _scroll.offset : 0.0;
                    final v = ((off - 50) / 40).clamp(0.0, 1.0);
                    // Chưa cuộn tới thì bỏ hẳn BackdropFilter khỏi cây widget.
                    if (v == 0) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: Opacity(
                        opacity: v,
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              height: pad.top + 52,
                              padding: EdgeInsets.fromLTRB(20, pad.top, 20, 0),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: t.page.withValues(alpha: 0.92),
                                border:
                                    Border(bottom: BorderSide(color: t.line)),
                              ),
                              child: Text(widget.title,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                      color: t.ink)),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, this.subtitle, {super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: TextStyle(
              fontSize: 34,
              height: 1.18,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              color: t.ink)),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle!, style: TextStyle(fontSize: 13, color: t.mute)),
      ],
    ]);
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton(this.icon,
      {super.key, required this.onTap, this.size = 44, this.label});
  final AppIconData icon;
  final VoidCallback? onTap;
  final double size;

  /// Nhãn cho VoiceOver (nút chỉ có biểu tượng).
  final String? label;
  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return Semantics(
        button: true,
        label: label,
        excludeSemantics: label != null,
        child: Container(
          width: size,
          height: size,
          decoration:
              BoxDecoration(color: t.glass, shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: t.line, offset: const Offset(0, 1)),
            const BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 10,
                offset: Offset(0, 4),
                spreadRadius: -5),
          ]),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                  child: AppIcon(icon,
                      size: size * 0.44, color: t.ink, accent: t.ink)),
            ),
          ),
        ));
  }
}

/// Thẻ kính mờ bo 28.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(top: 14),
    this.gradient,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? t.glass : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: gradient == null ? Border.all(color: t.glassBorder) : null,
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
              spreadRadius: -12),
        ],
      ),
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null ? card : GestureDetector(onTap: onTap, child: card),
    );
  }
}

/// Biểu tượng nằm trong vòng tròn pastel.
class IconBubble extends StatelessWidget {
  const IconBubble(this.icon,
      {super.key, required this.bg, required this.fg, this.size = 42});
  final AppIconData icon;
  final Color bg;
  final Color fg;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Center(
            child: AppIcon(icon, size: size * 0.46, color: fg, accent: fg)),
      );
}

/// Một hàng trong thẻ danh sách: biểu tượng + tiêu đề/phụ đề + trailing.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.first = false,
    this.bar,
  });
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool first;

  /// Thanh phần trăm 0..1 dưới phụ đề, kèm màu.
  final (double, Color)? bar;

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            border: first ? null : Border(top: BorderSide(color: t.line))),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500, color: t.ink)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 12, color: t.mute)),
              if (bar != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: bar!.$1.clamp(0.0, 1.0)),
                    duration: reduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 1000),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      color: bar!.$2,
                      backgroundColor: t.track,
                    ),
                  ),
                ),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip(this.label,
      {super.key, this.on = false, this.onTap, this.icon});
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final AppIconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return Semantics(
        button: onTap != null,
        selected: on,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            // Vùng chạm tối thiểu ~44pt khi chip bấm được.
            padding: EdgeInsets.symmetric(
                horizontal: 15, vertical: onTap != null ? 13.5 : 9),
            decoration: BoxDecoration(
              color: on ? t.ink : t.glass,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? t.ink : t.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                AppIcon(icon!,
                    size: 15,
                    color: on ? t.page : t.ink,
                    accent: on ? t.page : t.ink),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? t.page : t.ink)),
            ]),
          ),
        ));
  }
}

/// Công tắc lime có núm nảy.
class PastelToggle extends StatelessWidget {
  const PastelToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return Semantics(
        toggled: value,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
                color: value ? t.accent : t.track,
                borderRadius: BorderRadius.circular(15)),
            child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: value ? t.onAccent : Colors.white,
                    shape: BoxShape.circle)),
          ),
        ));
  }
}

/// Chọn một trong vài mục dạng viên thuốc (Tự động / Sáng / Tối).
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills(
      {super.key,
      required this.items,
      required this.value,
      required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration:
          BoxDecoration(color: t.chip, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(it.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: it.$1 == value ? t.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: it.$1 == value
                      ? const [
                          BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                              spreadRadius: -2)
                        ]
                      : null,
                ),
                child: Text(it.$2,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            it.$1 == value ? FontWeight.w600 : FontWeight.w500,
                        color: it.$1 == value ? t.ink : t.mute)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Thanh hành động nổi trên dock: nền đen (đảo màu ở chế độ tối) + nút lime.
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onPressed,
    this.icon = AppIcons.deleteOutline,
    this.secondary,
    this.onSecondary,
  });
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback? onPressed;
  final AppIconData icon;

  /// Nút phụ dạng viền rỗng, đứng trước nút chính. Null thì không hiện.
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final on = onPressed != null;
    final bg = on ? (t.dark ? const Color(0xFFF2F2F2) : Pastel.ink) : t.chip;
    final fg = on ? (t.dark ? Pastel.ink : Colors.white) : t.mute;
    final hasSecond = secondary != null && onSecondary != null;

    final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: fg)),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.7))),
        ]);

    final ghost = GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSecondary!();
      },
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: fg.withValues(alpha: 0.45)),
        ),
        child: Text(secondary ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
      ),
    );

    final primary = GestureDetector(
      onTap: onPressed == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onPressed!();
            },
      child: Container(
        height: 46,
        padding: EdgeInsets.symmetric(horizontal: hasSecond ? 12 : 20),
        // Chỉ căn giữa khi nút nằm trong Expanded. Container có alignment mà
        // cha cho ràng buộc rộng thoải mái thì nó tự giãn hết chỗ.
        alignment: hasSecond ? Alignment.center : null,
        decoration: BoxDecoration(
            color: on ? (t.dark ? Pastel.ink : Colors.white) : t.track,
            borderRadius: BorderRadius.circular(23)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!hasSecond) ...[
            AppIcon(icon,
                size: 18,
                color: on ? (t.dark ? Colors.white : Pastel.ink) : t.mute,
                accent: on ? (t.dark ? Colors.white : Pastel.ink) : t.mute),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(button,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: on ? (t.dark ? Colors.white : Pastel.ink) : t.mute)),
          ),
        ]),
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: hasSecond
          ? const EdgeInsets.fromLTRB(18, 14, 18, 14)
          : const EdgeInsets.fromLTRB(20, 10, 10, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: on
            ? const [
                BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                    spreadRadius: -9)
              ]
            : null,
      ),
      // Một nút thì chữ trái, nút phải. HAI nút thì xếp chồng: nhét chữ cùng
      // hai nút vào một hàng, trên máy 320-390px phần chữ chỉ còn vài chục
      // pixel nên tiêu đề bị cắt hoặc xuống dòng làm thanh phình cao.
      child: hasSecond
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: double.infinity, child: text),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ghost),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: primary),
              ]),
            ])
          : Row(children: [Expanded(child: text), primary]),
    );
  }
}

/// Hộp thoại xác nhận xóa theo phong cách mới: biểu tượng thùng rác trong vòng tròn,
/// tiêu đề, nội dung, dòng cảnh báo (tùy chọn), ô tick xác nhận (tùy chọn) và hai nút.
/// Trả về true khi người dùng bấm nút xác nhận.
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? warning,
  String? tickLabel,
  AppIconData icon = AppIcons.deleteOutline,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Đóng',
    barrierColor: const Color(0x80000000),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, _, __) {
      var ticked = tickLabel == null;
      return StatefulBuilder(builder: (ctx, setD) {
        final t = PastelScheme.of(ctx);
        final danger = t.ink;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
              decoration: BoxDecoration(
                color: t.dark ? t.card : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(28),
                border: t.dark ? Border.all(color: t.glassBorder) : null,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconBubble(icon, size: 72, bg: t.chip, fg: danger),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                        color: t.ink)),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: t.mute)),
                if (warning != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: t.amberBg,
                        borderRadius: BorderRadius.circular(18)),
                    child: Row(children: [
                      AppIcon(AppIcons.warningAmberRounded,
                          size: 20, color: t.amberText, accent: t.amberText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(warning,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: t.amberText)),
                      ),
                    ]),
                  ),
                ],
                if (tickLabel != null) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setD(() => ticked = !ticked),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: ticked ? t.accent : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: ticked ? t.accent : t.track, width: 2),
                        ),
                        child: ticked
                            ? AppIcon(AppIcons.check,
                                size: 15, color: t.onAccent, accent: t.onAccent)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tickLabel,
                            style: TextStyle(fontSize: 13, color: t.ink)),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: t.chip,
                            borderRadius: BorderRadius.circular(26)),
                        child: Text('Hủy',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: t.ink)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: ticked ? () => Navigator.pop(ctx, true) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: ticked ? t.accent : t.track,
                            borderRadius: BorderRadius.circular(26)),
                        child: Text(confirmLabel,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ticked ? t.onAccent : Colors.white)),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        );
      });
    },
    transitionBuilder: (ctx, anim, _, child) {
      final c = CurvedAnimation(
          parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
            scale: Tween(begin: 0.88, end: 1.0).animate(c), child: child),
      );
    },
  );
}
