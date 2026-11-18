import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';

Future<PermissionState> _defaultRequest() =>
    PhotoManager.requestPermissionExtend();
Future<void> _defaultOpenSettings() => PhotoManager.openSetting();

enum _Perm { initial, requesting, denied }

/// Onboarding 3 trang giới thiệu + trang xin quyền Ảnh. Không lưu cờ "đã xem" xuống đĩa
/// (app stateless): nơi gọi quyết định có hiển thị hay không.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.onFinished,
    this.requestPermission = _defaultRequest,
    this.openSettings = _defaultOpenSettings,
  });

  final VoidCallback onFinished;
  final Future<PermissionState> Function() requestPermission;
  final Future<void> Function() openSettings;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const int _permStep = 3;
  int _step = 0;
  _Perm _perm = _Perm.initial;

  static const _data = <_StepData>[
    _StepData(
      title: 'Dọn ảnh trùng,\nnhẹ máy ngay',
      body:
          'Giải phóng dung lượng bằng cách tìm\nnhững ảnh giống nhau trong thư viện.',
      cta: 'Bắt đầu',
    ),
    _StepData(
      title: 'Giữ bản đẹp nhất,\nbỏ bản trùng',
      body:
          'Ảnh giống nhau được gom thành nhóm.\nBạn chọn, chỉ xóa khi xác nhận.',
      cta: 'Tiếp tục',
    ),
    _StepData(
      title: 'Ảnh của bạn ở lại\ntrên máy',
      body:
          'Quét và so sánh ngay trên điện thoại.\nMọi thao tác xóa đều hỏi bạn trước.',
      cta: 'Tiếp tục',
    ),
    _StepData(
      title: 'Cho phép truy cập\nthư viện ảnh',
      body: 'Cleanify cần đọc thư viện để tìm ảnh trùng và gợi ý bản nên giữ. '
          'Nếu chỉ chọn một số ảnh, chỉ những ảnh đó được quét.',
      cta: 'Cho phép truy cập ảnh',
    ),
  ];

  bool get _busy => _perm == _Perm.requesting;

  void _go(int step) {
    if (_busy || step < 0 || step > _permStep || step == _step) return;
    HapticFeedback.selectionClick();
    setState(() => _step = step);
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _perm = _Perm.requesting);
    PermissionState result;
    try {
      result = await widget.requestPermission();
    } catch (_) {
      result = PermissionState.denied;
    }
    if (!mounted) return;
    if (result.hasAccess) {
      widget.onFinished();
    } else {
      setState(() => _perm = _Perm.denied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final d = _data[_step];
    final denied = _perm == _Perm.denied;
    final isPerm = _step == _permStep;
    final label = isPerm && denied ? 'Mở Cài đặt' : d.cta;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.page,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v < -300) _go(_step + 1);
            if (v > 300) _go(_step - 1);
          },
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _topBar(t, isPerm),
                            const SizedBox(height: 14),
                            // Khung hình minh họa: mỗi bước một cảnh chuyển động riêng.
                            Container(
                              height: math.min(330, box.maxHeight * 0.4),
                              decoration: BoxDecoration(
                                color:
                                    t.dark ? t.card : const Color(0xFFECECEC),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: t.line),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                switchInCurve: Curves.easeOutBack,
                                transitionBuilder: (child, a) => FadeTransition(
                                  opacity: a,
                                  child: ScaleTransition(
                                      scale: Tween(begin: 0.94, end: 1.0)
                                          .animate(a),
                                      child: child),
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey(_step),
                                  // Chữ trong hình minh họa là trang trí: không phóng theo cỡ chữ hệ thống.
                                  child: MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                        textScaler: TextScaler.noScaling),
                                    child: _scene(t, _step, denied),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              transitionBuilder: (child, a) => FadeTransition(
                                opacity: a,
                                child: SlideTransition(
                                  position: Tween(
                                          begin: const Offset(0, 0.12),
                                          end: Offset.zero)
                                      .animate(a),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                key: ValueKey('t$_step'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.title,
                                      style: TextStyle(
                                          fontSize: 34,
                                          height: 1.18,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.6,
                                          color: t.ink)),
                                  const SizedBox(height: 12),
                                  Text(d.body,
                                      style: TextStyle(
                                          fontSize: 14,
                                          height: 1.55,
                                          color: t.mute)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: 2),
                            _dots(t),
                            const SizedBox(height: 2),
                            Row(children: [
                              AnimatedSize(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutBack,
                                child: _step == 0
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding:
                                            const EdgeInsets.only(right: 10),
                                        child: Semantics(
                                          button: true,
                                          label: 'Quay lại',
                                          child: GestureDetector(
                                            onTap: _busy
                                                ? null
                                                : () => _go(_step - 1),
                                            child: Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                  color: t.chip,
                                                  shape: BoxShape.circle),
                                              child: Center(
                                                child: AppIcon(
                                                    AppIcons
                                                        .arrowBackIosNewRounded,
                                                    size: 20,
                                                    color: t.ink,
                                                    accent: t.ink),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              Expanded(
                                child: PressScale(
                                  child: GestureDetector(
                                    onTap: _busy
                                        ? null
                                        : () {
                                            if (!isPerm) {
                                              _go(_step + 1);
                                            } else if (denied) {
                                              widget.openSettings();
                                            } else {
                                              _allow();
                                            }
                                          },
                                    child: Container(
                                      height: 60,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                          color: t.accent,
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                      child: _busy
                                          ? SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  color: t.onAccent))
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                  Flexible(
                                                    child: Text(label,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: t.onAccent)),
                                                  ),
                                                  if (!isPerm && _step > 0) ...[
                                                    const SizedBox(width: 8),
                                                    AppIcon(
                                                        AppIcons
                                                            .arrowForwardRounded,
                                                        size: 20,
                                                        color: t.onAccent,
                                                        accent: t.onAccent),
                                                  ],
                                                ]),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                            SizedBox(
                              height: 48,
                              child: Center(
                                child: isPerm
                                    ? TextButton(
                                        onPressed:
                                            _busy ? null : widget.onFinished,
                                        child: Text('Để sau',
                                            style: TextStyle(
                                                fontSize: 14, color: t.mute)),
                                      )
                                    : Text(
                                        _step == 0 ? 'Không cần tài khoản' : '',
                                        style: TextStyle(
                                            fontSize: 13, color: t.mute)),
                              ),
                            ),
                          ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(PastelScheme t, bool isPerm) => SizedBox(
        height: 44,
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(10)),
            child: Center(
                child: AppIcon(AppIcons.autoAwesomeOutlined,
                    size: 17, color: t.onAccent, accent: t.onAccent)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Cleanify',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: t.ink)),
          ),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: isPerm ? 0 : 1,
            child: GestureDetector(
              onTap: isPerm ? null : () => _go(_permStep),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                    color: t.chip, borderRadius: BorderRadius.circular(99)),
                child: Text('Bỏ qua',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
              ),
            ),
          ),
        ]),
      );

  Widget _dots(PastelScheme t) => Row(children: [
        for (var i = 0; i < _data.length; i++)
          Semantics(
              button: true,
              selected: i == _step,
              label: 'Bước ${i + 1} trên ${_data.length}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => _go(i),
                behavior: HitTestBehavior.opaque,
                // Vùng chạm cao ~44pt dù chấm chỉ 8pt.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 6, 18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    width: i == _step ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: i == _step ? t.ink : t.track,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              )),
      ]);

  Widget _scene(PastelScheme t, int i, bool denied) {
    switch (i) {
      case 0:
        return _FlyScene(t: t);
      case 1:
        return _KeepScene(t: t);
      case 2:
        return _PrivacyScene(t: t);
      default:
        return _PermScene(t: t, denied: denied);
    }
  }
}

class _StepData {
  const _StepData({required this.title, required this.body, required this.cta});
  final String title;
  final String body;
  final String cta;
}

// ---------------------------------------------------------------------------
// Bốn cảnh minh họa (chỉ đen/trắng/xám)
// ---------------------------------------------------------------------------

const _grads = [
  [Color(0xFF6B6B6B), Color(0xFFC9C9C9)],
  [Color(0xFF8A8A8A), Color(0xFFDADADA)],
  [Color(0xFF3A3A3A), Color(0xFFA0A0A0)],
  [Color(0xFFB8B8B8), Color(0xFFEDEDED)],
];

/// Chạy một hoạt ảnh vào cảnh (một lần), trả về giá trị 0..1; tắt khi giảm chuyển động.
class _Enter extends StatelessWidget {
  const _Enter({required this.builder});
  final Widget Function(double v) builder;
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return builder(1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1800),
      builder: (_, v, __) => builder(v),
    );
  }
}

double _stage(double v, double a, double b, [Curve c = Curves.easeOutBack]) =>
    c.transform(((v - a) / (b - a)).clamp(0.0, 1.0));

Widget _chip(PastelScheme t, IconData? _, AppIconData icon, String text,
        {Color? bg, Color? fg}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: bg ?? (t.dark ? t.chip : Colors.white),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000),
              blurRadius: 12,
              offset: Offset(0, 10),
              spreadRadius: -5)
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(icon, size: 15, color: fg ?? t.ink, accent: fg ?? t.ink),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: fg ?? t.ink)),
      ]),
    );

/// Cảnh 1: bốn ảnh trùng bay vào gom lại, kèm hai nhãn nhấp nhô.
class _FlyScene extends StatelessWidget {
  const _FlyScene({required this.t});
  final PastelScheme t;
  @override
  Widget build(BuildContext context) {
    const from = [
      Offset(-120, -90),
      Offset(110, -70),
      Offset(-100, 90),
      Offset(120, 96)
    ];
    const rot = [-0.24, 0.21, 0.17, -0.17];
    return _Enter(
      builder: (v) => Stack(alignment: Alignment.center, children: [
        for (var i = 0; i < 4; i++)
          Builder(builder: (_) {
            final k = _stage(v, i * 0.07, 0.6 + i * 0.07, Curves.easeOutBack);
            return Transform.translate(
              offset: from[i] * (1 - k),
              child: Transform.rotate(
                angle: rot[i] * (1 - k),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                        colors: _grads[i],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 22,
                          offset: Offset(0, 7),
                          spreadRadius: -5)
                    ],
                  ),
                ),
              ),
            );
          }),
        Positioned(
          left: 22,
          top: 24,
          child: Opacity(
              opacity: _stage(v, 0.5, 0.8, Curves.easeOut),
              child: _chip(t, null, AppIcons.copyOutlined, '248 ảnh trùng')),
        ),
        Positioned(
          right: 22,
          bottom: 24,
          child: Opacity(
              opacity: _stage(v, 0.6, 0.9, Curves.easeOut),
              child:
                  _chip(t, null, AppIcons.cleaningServicesOutlined, '-1,9 GB')),
        ),
      ]),
    );
  }
}

/// Cảnh 2: ba ảnh, một nhãn Giữ (trắng) và hai nhãn Xóa (đen), thẻ "bản đẹp nhất".
class _KeepScene extends StatelessWidget {
  const _KeepScene({required this.t});
  final PastelScheme t;
  @override
  Widget build(BuildContext context) {
    return _Enter(
      builder: (v) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        child: Column(children: [
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Opacity(
                    opacity: i == 0 ? 1 : 0.55,
                    child: Stack(children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                              colors: _grads[(i + 2) % 4],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Transform.scale(
                          scale: _stage(v, 0.15 + i * 0.12, 0.45 + i * 0.12),
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: i == 0 ? Colors.white : Pastel.ink,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              AppIcon(
                                  i == 0
                                      ? AppIcons.check
                                      : AppIcons.deleteOutline,
                                  size: 12,
                                  color: i == 0 ? Pastel.ink : Colors.white,
                                  accent: i == 0 ? Pastel.ink : Colors.white),
                              const SizedBox(width: 3),
                              Text(i == 0 ? 'Giữ' : 'Xóa',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          i == 0 ? Pastel.ink : Colors.white)),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
          const Spacer(),
          Transform.translate(
            offset: Offset(0, 18 * (1 - _stage(v, 0.5, 0.85))),
            child: Opacity(
              opacity: _stage(v, 0.5, 0.85, Curves.easeOut),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: t.dark ? t.chip : Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 12,
                        offset: Offset(0, 10),
                        spreadRadius: -5)
                  ],
                ),
                child: Row(children: [
                  AppIcon(AppIcons.photoOutlined,
                      size: 20, color: t.ink, accent: t.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Bản đẹp nhất được giữ',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.ink)),
                  ),
                  Text('4032×3024',
                      style: TextStyle(fontSize: 12, color: t.mute)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Cảnh 3: điện thoại có khiên khóa, vòng lan tỏa, ba ảnh nhỏ và hai nhãn.
class _PrivacyScene extends StatefulWidget {
  const _PrivacyScene({required this.t});
  final PastelScheme t;
  @override
  State<_PrivacyScene> createState() => _PrivacySceneState();
}

class _PrivacySceneState extends State<_PrivacyScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return _Enter(
      builder: (v) => Stack(alignment: Alignment.center, children: [
        Container(
          width: 140,
          height: 240,
          decoration: BoxDecoration(
            color: t.dark ? t.chip : Colors.white,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: t.ink, width: 3),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 96,
              height: 96,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) =>
                    Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 70 + 26 * _c.value,
                    height: 70 + 26 * _c.value,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.ink.withValues(alpha: 0.18 * (1 - _c.value))),
                  ),
                  Container(
                    width: 70,
                    height: 70,
                    decoration:
                        BoxDecoration(color: t.accent, shape: BoxShape.circle),
                    child: Center(
                        child: AppIcon(AppIcons.shieldOutlined,
                            size: 34, color: t.onAccent, accent: t.onAccent)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Transform.scale(
                    scale: _stage(v, 0.2 + i * 0.12, 0.5 + i * 0.12),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        gradient: LinearGradient(colors: _grads[i]),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        Positioned(
          left: 20,
          top: 34,
          child: Opacity(
              opacity: _stage(v, 0.4, 0.7, Curves.easeOut),
              child: _chip(t, null, AppIcons.lockOutline, 'Không tải lên',
                  fg: t.mute)),
        ),
        Positioned(
          right: 20,
          bottom: 34,
          child: Opacity(
              opacity: _stage(v, 0.5, 0.8, Curves.easeOut),
              child: _chip(
                  t, null, AppIcons.shieldOutlined, 'Không lưu lịch sử',
                  fg: t.mute)),
        ),
      ]),
    );
  }
}

/// Cảnh 4: xin quyền Ảnh: biểu tượng ảnh lớn, ba dòng giải thích bật lên lần lượt và
/// trạng thái quyền ("Chưa cấp quyền" / "Bị từ chối").
class _PermScene extends StatelessWidget {
  const _PermScene({required this.t, required this.denied});
  final PastelScheme t;
  final bool denied;
  @override
  Widget build(BuildContext context) {
    final items = [
      (AppIcons.search, 'Quét ngay trên điện thoại'),
      (AppIcons.deleteOutline, 'Chỉ xóa khi bạn xác nhận'),
      (AppIcons.settingsOutlined, 'Đổi lại quyền trong Cài đặt'),
    ];
    return _Enter(
      builder: (v) => LayoutBuilder(
        builder: (context, box) => Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: math.max(220.0, box.maxWidth - 44),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration:
                      BoxDecoration(color: t.accent, shape: BoxShape.circle),
                  child: Center(
                      child: AppIcon(AppIcons.photoLibraryOutlined,
                          size: 36, color: t.onAccent, accent: t.onAccent)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                      color: denied ? t.accent : t.chip,
                      borderRadius: BorderRadius.circular(99)),
                  child: Text(denied ? 'Bị từ chối' : 'Chưa cấp quyền',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: denied ? t.onAccent : t.mute)),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Transform.scale(
                      scale:
                          0.9 + 0.1 * _stage(v, 0.2 + i * 0.15, 0.5 + i * 0.15),
                      child: Opacity(
                        opacity: _stage(
                            v, 0.2 + i * 0.15, 0.5 + i * 0.15, Curves.easeOut),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          decoration: BoxDecoration(
                            color: t.dark ? t.chip : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(children: [
                            AppIcon(items[i].$1,
                                size: 18, color: t.ink, accent: t.ink),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(items[i].$2,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: t.ink)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
