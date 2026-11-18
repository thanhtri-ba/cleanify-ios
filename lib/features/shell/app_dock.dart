import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';
import '../../theme/appearance.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import 'app_toast.dart';

/// Trạng thái dùng chung của thanh dock cố định ở đáy mọi trang.
///
/// Trang chủ đăng ký các hành động (quét, video lớn...) vì chúng cần dữ liệu của trang
/// chủ; dock chỉ gọi lại chúng sau khi đưa người dùng về trang chủ. Tab đang sáng và việc
/// ẩn dock được suy ra từ tên route (xem [_DockObserver]): `tab:N` là tab thứ N,
/// `nodock` là trang toàn màn hình (đang quét, đang dọn, xem ảnh) cần ẩn dock.
class AppDock {
  AppDock._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final NavigatorObserver observer = _DockObserver();

  /// Tab đang sáng: 0 trang chủ, 1 kết quả, 2 bộ nhớ, 3 cài đặt; null nếu không thuộc tab nào.
  static final ValueNotifier<int?> tab = ValueNotifier<int?>(0);

  /// Dock phải ẩn: trang toàn màn hình, HOẶC có bảng trượt / hộp thoại đè lên.
  static final ValueNotifier<bool> pageHidden = ValueNotifier<bool>(false);

  /// Ẩn dock khi chưa vào app (kiểm tra quyền, onboarding).
  static final ValueNotifier<bool> forceHidden = ValueNotifier<bool>(true);

  static VoidCallback? onScan,
      onVideos,
      onScreenshots,
      onStorage,
      onResults,
      onSettings,
      onHomeTop;

  /// Đưa về trang chủ (nếu đang ở trang khác) rồi chạy [act].
  static void go(VoidCallback? act) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    var popped = false;
    nav.popUntil((r) {
      if (!r.isFirst) popped = true;
      return r.isFirst;
    });
    if (act == null) return;
    if (popped) {
      Future<void>.delayed(const Duration(milliseconds: 380), act);
    } else {
      act();
    }
  }

  /// Mở trang đích TRỰC TIẾP từ trang đang xem, không quay về trang chủ trước: trang
  /// mới trượt đè lên trang hiện tại, rồi các trang cũ giữa chừng bị gỡ êm để ngăn xếp
  /// luôn gọn dạng [Trang chủ, Trang đích] (nút quay lại về trang chủ như bình thường).
  /// Chỉ gỡ khi [act] thật sự đã mở trang mới (ví dụ "Kết quả" chưa quét thì chỉ báo).
  static void goReplace(VoidCallback? act) {
    final nav = navigatorKey.currentState;
    if (nav == null || act == null) return;
    final before = (observer as _DockObserver)._stack.toList();
    if (before.length <= 1) {
      act();
      return;
    }
    final olds = before.sublist(1);
    act();
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      final now = (observer as _DockObserver)._stack.toList();
      final opened = now.length > before.length || now.last != before.last;
      if (!opened) return;
      for (final r in olds) {
        if (r.isActive && now.contains(r)) nav.removeRoute(r);
      }
    });
  }

  /// Xóa trạng thái theo dõi ngăn xếp (dùng cho test, vì [observer] là đối tượng dùng chung).
  static void resetForTest() {
    (observer as _DockObserver)
      .._stack.clear()
      .._popups.clear();
    tab.value = 0;
    pageHidden.value = false;
  }

  /// Tên các trang đang trong ngăn xếp (dùng cho test).
  static List<String?> get routeNames =>
      [for (final r in (observer as _DockObserver)._stack) r.settings.name];

  static void say(String msg, {bool warn = false}) =>
      AppToast.show(msg, warn: warn);
}

class _DockObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];
  final List<Route<dynamic>> _popups = [];

  void _update() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final top = _stack.isEmpty ? null : _stack.last;
      final name = top?.settings.name;
      AppDock.pageHidden.value = name == 'nodock' || _popups.isNotEmpty;
      int? tab;
      if (name == '/') {
        tab = 0;
      } else if (name != null && name.startsWith('tab:')) {
        tab = int.tryParse(name.substring(4));
      }
      AppDock.tab.value = tab;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _stack.add(route);
    } else if (route is PopupRoute) {
      _popups.add(route); // Bảng trượt/hộp thoại: ẩn dock cho khỏi đè lên.
    }
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _popups.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _popups.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _stack.remove(oldRoute);
    if (newRoute is PageRoute) _stack.add(newRoute);
    _update();
  }
}

/// Bao quanh Navigator của MaterialApp: VẼ dock đè lên mọi trang. Chỉ vẽ.
///
/// Trước đây lớp này còn bơm thêm `MediaQuery.padding.bottom` cho cả cây
/// Navigator để trang tự né dock. Nghe gọn nhưng sai: padding là thứ dùng
/// chung, nên mỗi lần dock ẩn/hiện là MỌI trang đang nằm trong ngăn xếp phải
/// dựng và đo lại — kể cả trang đang trượt dở giữa chừng, và cả trang nằm dưới
/// một bảng trượt. Đó là nguồn gốc của lỗi nhảy layout ở đáy màn hình.
///
/// Giờ chỗ chừa do CHÍNH trang tự cộng vào padding của nó, qua [reserve]:
/// [PageScaffold] và trang chủ cộng, ba trang toàn màn hình thì không. Dock
/// ẩn hay hiện không còn làm ai phải đo lại.
class DockShell extends StatefulWidget {
  const DockShell({super.key, required this.child});
  final Widget child;

  static const double dockHeight = 68;

  /// Chiều cao cần chừa dưới đáy một trang CÓ dock, tính từ safe area thật.
  /// Trang toàn màn hình (đang quét, đang dọn, chi tiết ảnh) không gọi hàm này.
  static double reserve(BuildContext context) {
    final b = MediaQuery.paddingOf(context).bottom;
    return _gap(b) + dockHeight + 14;
  }

  /// Khoảng hở giữa dock và mép dưới màn hình.
  static double _gap(double safeBottom) =>
      (safeBottom > 0 ? safeBottom - 6 : 12.0) + 6;

  @override
  State<DockShell> createState() => _DockShellState();
}

class _DockShellState extends State<DockShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _menu = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  bool get _open =>
      _menu.status == AnimationStatus.forward ||
      _menu.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    AppDock.pageHidden.addListener(_onHide);
    AppDock.forceHidden.addListener(_onHide);
  }

  void _onHide() {
    if (!mounted) return;
    if (_hidden && _open) _menu.value = 0;
    setState(() {});
  }

  bool get _hidden => AppDock.forceHidden.value || AppDock.pageHidden.value;

  @override
  void dispose() {
    AppDock.pageHidden.removeListener(_onHide);
    AppDock.forceHidden.removeListener(_onHide);
    _menu.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _menu.reverse();
    } else {
      HapticFeedback.selectionClick();
      _menu.forward();
    }
  }

  void _close() {
    if (_open) _menu.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomGap = DockShell._gap(mq.padding.bottom);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Appearance.mode,
      builder: (context, _, __) {
        final t = PastelScheme.of(context);
        // Dock nằm trên Navigator nên không có Material tổ tiên: không bọc thì Text bị
        // gạch chân vàng (kiểu chữ mặc định khi thiếu Material).
        return Material(
            type: MaterialType.transparency,
            child: Stack(children: [
              widget.child,
              // Phủ mờ dần phía trên dock để nội dung cuộn xuống không bị cắt cứng.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomGap + DockShell.dockHeight + 36,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: kMotionMed,
                    opacity: _hidden ? 0 : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            t.page.withValues(alpha: 0),
                            t.page.withValues(alpha: 0.92)
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Nền mờ + tối khi bảng công cụ mở.
              AnimatedBuilder(
                animation: _menu,
                builder: (_, __) {
                  final m = Curves.easeOut.transform(_menu.value);
                  if (m == 0) return const SizedBox.shrink();
                  return Positioned.fill(
                    child: GestureDetector(
                      onTap: _close,
                      child: BackdropFilter(
                        filter:
                            ui.ImageFilter.blur(sigmaX: 9 * m, sigmaY: 9 * m),
                        child: ColoredBox(
                            color: Color.fromRGBO(10, 10, 14, 0.45 * m)),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: bottomGap,
                child: IgnorePointer(
                  ignoring: _hidden,
                  child: AnimatedSlide(
                    duration: kMotionMed,
                    curve: kMotionCurve,
                    offset: _hidden ? const Offset(0, 1.6) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: kMotionMed,
                      opacity: _hidden ? 0 : 1,
                      // Tách lớp: cuộn nội dung phía sau không bắt dock vẽ lại.
                      child: RepaintBoundary(child: _dock(t)),
                    ),
                  ),
                ),
              ),
            ]));
      },
    );
  }

  List<(AppIconData, String, VoidCallback)> _tools() => [
        (AppIcons.scan, 'Quét', () => AppDock.go(AppDock.onScan)),
        (
          AppIcons.videocamOutlined,
          'Video lớn',
          () => AppDock.goReplace(AppDock.onVideos)
        ),
        (
          AppIcons.screenshotOutlined,
          'Màn hình',
          () => AppDock.goReplace(AppDock.onScreenshots)
        ),
        (
          AppIcons.pieChartOutline,
          'Bộ nhớ',
          () => AppDock.goReplace(AppDock.onStorage)
        ),
        (
          AppIcons.copyOutlined,
          'Kết quả',
          () => AppDock.goReplace(AppDock.onResults)
        ),
        (
          AppIcons.settingsOutlined,
          'Cài đặt',
          () => AppDock.goReplace(AppDock.onSettings)
        ),
        (
          AppIcons.shieldOutlined,
          'Riêng tư',
          () => AppDock.say('Ảnh được quét ngay trên máy, không gửi đi đâu.')
        ),
        (
          switch (Appearance.mode.value) {
            ThemeMode.system => AppIcons.autoMode,
            ThemeMode.light => AppIcons.sun,
            ThemeMode.dark => AppIcons.moon,
          },
          Appearance.label(Appearance.mode.value),
          () => Appearance.set(Appearance.next(Appearance.mode.value)),
        ),
      ];

  Widget _dock(PastelScheme t) {
    final calm = reduceMotion(context);
    final tools = _tools();
    final rows = (tools.length / 4).ceil();
    final panelH = 18.0 + rows * 92 + 8;

    final pillDeco = BoxDecoration(
      gradient: LinearGradient(
          colors: [t.dockTop, t.dockBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter),
      border: Border.all(color: t.dockRing),
      boxShadow: [
        BoxShadow(
            color: t.dockShadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -8),
      ],
    );

    return AnimatedBuilder(
      animation: _menu,
      builder: (context, _) {
        final m = calm
            ? (_menu.value > 0.5 ? 1.0 : 0.0)
            : Curves.easeOutBack.transform(_menu.value);
        final lin = _menu.value;
        final h = DockShell.dockHeight + (panelH - DockShell.dockHeight) * m;
        final radius = 34 + 6 * lin;
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              height: h,
              decoration: pillDeco.copyWith(
                  borderRadius: BorderRadius.circular(radius)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      ignoring: lin < 0.6,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 4,
                          mainAxisExtent: 92,
                          padding: EdgeInsets.zero,
                          children: [
                            for (var i = 0; i < tools.length; i++)
                              _toolTile(t, tools[i], i, lin),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: DockShell.dockHeight,
                    child: IgnorePointer(
                      ignoring: lin > 0.05,
                      child: Opacity(
                        opacity: (1 - lin * 3).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 26 * lin),
                          child: _tabBar(t),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
              button: true,
              label: _open ? 'Đóng bảng công cụ' : 'Mở bảng công cụ',
              excludeSemantics: true,
              onTap: _toggle,
              child: GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: DockShell.dockHeight,
                  height: DockShell.dockHeight,
                  decoration: pillDeco.copyWith(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Color.lerp(
                            t.dockRing,
                            t.dark
                                ? const Color(0xFF8E8E8E)
                                : const Color(0xFF111111),
                            lin)!),
                  ),
                  child: Transform.rotate(
                    angle: (calm ? lin.roundToDouble() : m) * math.pi * 0.75,
                    child: Center(
                      child: AppIcon(AppIcons.plus,
                          size: 28, color: t.dockIconOn, accent: t.dockIconOn),
                    ),
                  ),
                ),
              )),
        ]);
      },
    );
  }

  Widget _tabBar(PastelScheme t) {
    final tabs = <(AppIconData, String, VoidCallback?)>[
      (AppIcons.homeOutlined, 'Trang chủ', null),
      (AppIcons.layersOutlined, 'Kết quả', AppDock.onResults),
      (AppIcons.pieChartOutline, 'Bộ nhớ', AppDock.onStorage),
      (AppIcons.settingsOutlined, 'Cài đặt', AppDock.onSettings),
    ];
    return ValueListenableBuilder<int?>(
      valueListenable: AppDock.tab,
      builder: (context, active, _) => LayoutBuilder(builder: (context, box) {
        // Tab đang sáng rộng gấp 2,5 lần để chứa thêm nhãn chữ. Nhưng khi
        // KHÔNG tab nào sáng (trang không thuộc tab nào) thì mẫu số phải đổi,
        // không thì bốn tab chỉ chiếm 4/5,5 bề ngang và dồn hết sang trái,
        // chừa một mảng trống bên phải trông như dock bị vỡ.
        final lit = active != null && active >= 0 && active < tabs.length;
        final unit =
            (box.maxWidth - 14 - 6) / (tabs.length - 1 + (lit ? 2.5 : 1.0));
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Semantics(
                  button: true,
                  selected: i == active,
                  label: tabs[i].$2,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (i == 0) {
                        AppDock.go(null);
                        AppDock.onHomeTop?.call();
                      } else if (active != i) {
                        AppDock.goReplace(tabs[i].$3);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      width: unit * (i == active ? 2.5 : 1),
                      height: 54,
                      decoration: BoxDecoration(
                        color: i == active ? t.tileActive : Colors.transparent,
                        borderRadius: BorderRadius.circular(27),
                        boxShadow: i == active && t.dark
                            ? const [
                                BoxShadow(
                                    color: Color(0x33FFFFFF),
                                    blurRadius: 12,
                                    spreadRadius: -4)
                              ]
                            : null,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            AppIcon(tabs[i].$1,
                                size: 23,
                                color: i == active ? t.dockIconOn : t.dockIcon,
                                accent:
                                    i == active ? t.dockIconOn : t.dockIcon),
                            if (i == active) ...[
                              const SizedBox(width: 7),
                              Text(tabs[i].$2,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: t.dockIconOn)),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  )),
            ],
          ]),
        );
      }),
    );
  }

  Widget _toolTile(PastelScheme t, (AppIconData, String, VoidCallback) tool,
      int i, double lin) {
    final start = (0.16 + i * 0.045).clamp(0.0, 0.8);
    final p = Interval(start, (start + 0.4).clamp(0.0, 1.0),
            curve: Curves.easeOutBack)
        .transform(lin);
    final lab =
        Interval((start + 0.15).clamp(0.0, 1.0), (start + 0.4).clamp(0.0, 1.0))
            .transform(lin);
    final isTheme = i == tools8 - 1;
    return Opacity(
      opacity: p.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.4 + 0.6 * p,
        child: Semantics(
            button: true,
            label: tool.$2,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: t.menuTile,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: t.dark
                          ? const Color(0x14FFFFFF)
                          : const Color(0x0F000000)),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    splashFactory: InkRipple.splashFactory,
                    splashColor: (t.dark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.28),
                    highlightColor: (t.dark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.12),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (!isTheme) _menu.reverse();
                      Future<void>.delayed(
                          Duration(milliseconds: isTheme ? 0 : 260), tool.$3);
                    },
                    child: Center(
                      child: AppIcon(tool.$1,
                          size: 25, color: t.menuIcon, accent: t.menuIcon),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              ExcludeSemantics(
                child: Opacity(
                  opacity: lab.clamp(0.0, 1.0),
                  child: Text(tool.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: t.menuIcon)),
                ),
              ),
            ])),
      ),
    );
  }

  static const int tools8 = 8;
}
