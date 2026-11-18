import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/scan_progress.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../../theme/scan_ring.dart';
import 'scan_complete_page.dart';
import 'scan_controller.dart';
import 'scan_error_page.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';
import '../../core/platform/device_text.dart';

/// Màn "Đang quét ảnh của bạn". Tiến độ lấy từ [ScanController].
class SmartScanPage extends StatefulWidget {
  const SmartScanPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<SmartScanPage> createState() => _SmartScanPageState();
}

class _SmartScanPageState extends State<SmartScanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beam = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  Timer? _tick;
  Timer? _go;
  final Map<String, Widget> _orbThumbs = {};
  bool _left = false;
  bool _celebrate = false;

  /// Thời điểm (theo đồng hồ quét) mỗi giai đoạn bắt đầu, để tính thời gian từng mốc.
  final Map<int, Duration> _phaseStart = {};
  int _lastPhase = -1;

  void _trackPhase(ScanProgress? p) {
    final i = p?.phase.index ?? 0;
    if (i == _lastPhase) return;
    _lastPhase = i;
    _phaseStart.putIfAbsent(i, () => c.elapsed);
  }

  ScanController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    // Đồng hồ chỉ đổi khi controller notify (theo batch); ticker này để thời gian
    // chạy mượt và cho thấy rõ quét đang chậm hay đã kẹt.
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beam.stop();
    } else if (!_beam.isAnimating) {
      _beam.repeat();
    }
  }

  void _onChange() {
    if (_left || !mounted) return;
    if (c.status == ScanStatus.done) {
      _left = true;
      // Khoảng lặng ngắn với dấu tích "Quét xong" rồi mới sang màn kết quả.
      HapticFeedback.mediumImpact();
      setState(() => _celebrate = true);
      _go = Timer(const Duration(milliseconds: 1300), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'tab:1'),
            builder: (_) => ScanCompletePage(controller: c),
          ),
        );
      });
    } else if (c.status == ScanStatus.error) {
      _left = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'nodock'),
          builder: (_) => ScanErrorPage(controller: c),
        ),
      );
    } else if (c.status == ScanStatus.idle && c.session == null) {
      _leave(); // đã hủy xong
    }
  }

  /// Rời màn ngay. Dùng pop() trực tiếp: maybePop() bị PopScope(canPop: false) chặn.
  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pop();
  }

  /// Hủy quét và thoát ngay, không chờ batch đang chạy kết thúc.
  void _cancel() {
    c.cancel();
    _leave();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _go?.cancel();
    c.removeListener(_onChange);
    _beam.dispose();
    super.dispose();
  }

  /// Tiến độ tổng do controller tính (đơn điệu, chỉ đạt 100% khi quét xong).
  double get _fraction => c.overall.clamp(0.0, 1.0);

  /// Số ảnh đã đọc: đang ở bước đọc thì lấy tiến độ bước đó, sau đó là toàn bộ ảnh.
  int _readCount(ScanProgress? p) {
    if (p == null) return 0;
    if (p.phase == ScanPhase.reading) return p.done;
    return c.session?.assets.length ?? p.total;
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final dark = t.dark;
    final bg = dark ? Pastel.night : t.page;
    final card = dark ? Pastel.night2 : Colors.white;
    final card2 = dark ? Pastel.night3 : t.chip;
    final ink = dark ? Colors.white : t.ink;
    final mute = dark ? Pastel.nightMute : t.mute;
    final acc = t.accent;
    final onAcc = t.onAccent;
    final calm = reduceMotion(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cancel();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              // Vầng sáng "thở" sau vòng tiến độ.
              Positioned(
                top: 130,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    // Vòng sáng đập liên tục: đóng khung để nó không kéo cả màn
                    // hình quét vẽ lại 60 lần một giây, trong khi máy đang bận băm ảnh.
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _beam,
                        builder: (_, __) {
                          final k = calm
                              ? 1.0
                              : 1 + 0.06 * math.sin(_beam.value * 2 * math.pi);
                          return Transform.scale(
                            scale: k,
                            child: Container(
                              width: 330,
                              height: 330,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    dark
                                        ? const Color(0x33E6E6E6)
                                        : const Color(0x40808080),
                                    dark
                                        ? const Color(0x20A8A8A8)
                                        : const Color(0x20B0B0B0),
                                    const Color(0x00000000),
                                  ],
                                  stops: const [0, 0.5, 1],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) {
                    final p = c.progress;
                    final s = c.session;
                    final found = s == null
                        ? 0
                        : (s.groups.isNotEmpty
                              ? s.groups.length
                              : s.liveGroups);
                    _trackPhase(p);
                    final cur = p?.phase.index ?? 0;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            children: [
                              Material(
                                color: card2,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _cancel,
                                  child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: AppIcon(
                                      AppIcons.close,
                                      label: 'Hủy quét',
                                      size: 18,
                                      color: ink,
                                      accent: ink,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  c.paused ? 'Đã tạm dừng' : 'Đang quét',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                    color: ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 42),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                            children: [
                              const SizedBox(height: 6),
                              Center(
                                child: SizedBox(
                                  width: 230,
                                  height: 230,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(end: _fraction),
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOut,
                                    builder: (_, f, __) => Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (!calm && !c.paused)
                                          _orbs(_readCount(p)),
                                        CustomPaint(
                                          size: const Size(230, 230),
                                          painter: ScanRingPainter(
                                            f,
                                            width: 12,
                                            track: dark
                                                ? Pastel.night3
                                                : const Color(0xFFE2E2E2),
                                            from: t.chartA,
                                            to: t.chartB,
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${(f * 100).round()}',
                                                  style: TextStyle(
                                                    fontSize: 62,
                                                    height: 1.12,
                                                    fontWeight: FontWeight.w400,
                                                    letterSpacing: -1.6,
                                                    color: ink,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 9,
                                                        left: 2,
                                                      ),
                                                  child: Text(
                                                    '%',
                                                    style: TextStyle(
                                                      fontSize: 20,
                                                      color: mute,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              c.paused
                                                  ? 'Đã tạm dừng'
                                                  : 'Đang xử lý ảnh của bạn',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: mute,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  _stat(
                                    card,
                                    ink,
                                    mute,
                                    '${_readCount(p)}',
                                    'Ảnh đã đọc',
                                  ),
                                  const SizedBox(width: 8),
                                  _stat(
                                    card,
                                    ink,
                                    mute,
                                    '$found',
                                    'Nhóm tìm thấy',
                                  ),
                                  const SizedBox(width: 8),
                                  _stat(
                                    card,
                                    ink,
                                    mute,
                                    formatElapsed(c.elapsed),
                                    'Thời gian',
                                  ),
                                ],
                              ),
                              if (p != null && p.total > 0) ...[
                                const SizedBox(height: 10),
                                _milestoneCard(card, ink, mute, p),
                              ],
                              if ((c.session?.assets.length ?? 0) > 0) ...[
                                const SizedBox(height: 16),
                                _recentRow(t, ink, mute, _readCount(p)),
                              ],
                              const SizedBox(height: 16),
                              _phaseCard(
                                t,
                                card,
                                card2,
                                ink,
                                mute,
                                acc,
                                onAcc,
                                cur,
                                p,
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: Text(
                                  'Ngân sách mục tiêu${c.estimated > Duration.zero ? ' ~${formatElapsed(c.estimated)}' : ''}'
                                  ' · Bạn vẫn dùng $deviceName bình thường',
                                  style: TextStyle(fontSize: 11, color: mute),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: c.paused ? c.resume : c.pause,
                                  child: Container(
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: dark
                                          ? Pastel.night3
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(27),
                                      boxShadow: dark
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: t.line,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        AppIcon(
                                          c.paused
                                              ? AppIcons.playArrowRounded
                                              : AppIcons.pauseRounded,
                                          size: 18,
                                          color: ink,
                                          accent: ink,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          c.paused ? 'Tiếp tục' : 'Tạm dừng',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _cancel,
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: dark ? Pastel.night3 : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: dark
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: t.line,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                  ),
                                  child: Center(
                                    child: AppIcon(
                                      AppIcons.close,
                                      label: 'Hủy quét',
                                      size: 18,
                                      color: mute,
                                      accent: mute,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Quét xong: dấu tích bật lên trước khi sang màn kết quả.
              IgnorePointer(
                ignoring: !_celebrate,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 450),
                  opacity: _celebrate ? 1 : 0,
                  child: Container(
                    color: bg,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _celebrate ? 1 : 0),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutBack,
                            builder: (_, v, child) =>
                                Transform.scale(scale: v, child: child),
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [t.chartA, t.chartB],
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33FFFFFF),
                                    spreadRadius: 14,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: AppIcon(
                                  AppIcons.checkRounded,
                                  size: 58,
                                  color: Pastel.ink,
                                  accent: Pastel.ink,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            (c.session?.incompleteStages.isNotEmpty ?? false)
                                ? 'Đã dừng theo giới hạn'
                                : 'Quét xong',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.5,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(Color card, Color ink, Color mute, String v, String l) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  v,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(l, style: TextStyle(fontSize: 11, color: mute)),
            ],
          ),
        ),
      );

  Widget _milestoneCard(Color card, Color ink, Color mute, ScanProgress p) {
    final activeBatch =
        p.phase == ScanPhase.reading ||
        p.phase == ScanPhase.embedding ||
        p.phase == ScanPhase.exact;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeBatch
                      ? '${_phaseTitle(p.phase)} · ${p.milestoneLabel}'
                      : 'Đang hoàn tất chỉ mục',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  activeBatch
                      ? 'Mốc ${p.batchRangeLabel} · còn ${p.remaining} ảnh'
                      : 'Đã đọc ${c.session?.assets.length ?? 0} ảnh · đang so khớp',
                  style: TextStyle(fontSize: 11, color: mute),
                ),
              ],
            ),
          ),
          Text(
            '${((p.fraction ?? 0).clamp(0.0, 1.0) * 100).round()}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: mute,
            ),
          ),
        ],
      ),
    );
  }

  String _phaseTitle(ScanPhase phase) => switch (phase) {
    ScanPhase.reading => 'Ảnh đã đọc',
    ScanPhase.embedding => 'AI đã phân tích',
    ScanPhase.exact => 'Ảnh đã đối chiếu',
    ScanPhase.matching => 'Đang so khớp',
  };

  /// Ảnh thật vừa được đọc: lấy theo vị trí đang đọc trong danh sách ảnh của lần quét.
  List<AssetEntity> _recent(int read, int n) {
    final all = c.session?.assets ?? const <AssetEntity>[];
    if (all.isEmpty) return const [];
    // Sau bước đọc thì không còn "vị trí đọc", cho chạy dần qua thư viện để hàng ảnh vẫn sống.
    final base = c.progress?.phase == ScanPhase.reading
        ? read - 1
        : c.elapsed.inSeconds * 5;
    return [
      for (var i = 0; i < n; i++)
        all[((base - i) % all.length + all.length) % all.length],
    ];
  }

  Widget _recentRow(PastelScheme t, Color ink, Color mute, int read) {
    final items = _recent(read, 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Vừa đọc',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const Spacer(),
            Text(
              '${c.session?.assets.length ?? 0} ảnh trong lần quét',
              style: TextStyle(fontSize: 12, color: mute),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: AssetEntityImage(
                        items[i],
                        key: ValueKey('${items[i].id}-$i'),
                        isOriginal: false,
                        fit: BoxFit.cover,
                        thumbnailSize: const ThumbnailSize.square(200),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Ảnh thật bay từ rìa vào tâm vòng tiến độ (lấy từ ảnh của lần quét).
  /// Ảnh của một quả cầu bay, giữ theo id. Vòng sáng chạy 60 khung mỗi giây; trả về
  /// cùng một instance nên Flutter bỏ qua việc dựng lại thay vì dựng 7 ảnh mỗi khung.
  Widget _orbThumb(AssetEntity a) {
    if (_orbThumbs.length > 40) _orbThumbs.clear();
    return _orbThumbs.putIfAbsent(
      a.id,
      () => AssetEntityImage(
        a,
        isOriginal: false,
        fit: BoxFit.cover,
        thumbnailSize: const ThumbnailSize.square(120),
      ),
    );
  }

  Widget _orbs(int read) {
    final all = c.session?.assets ?? const <AssetEntity>[];
    return AnimatedBuilder(
      animation: _beam,
      builder: (_, __) {
        const n = 7;
        final tt = _beam.value;
        return SizedBox(
          width: 230,
          height: 230,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n; i++)
                Builder(
                  builder: (_) {
                    final ph = (tt * 2 + i / n) % 1; // 0 = rìa, 1 = tâm
                    final cycle = (tt * 2 + i / n).floor();
                    final ang = i * 2.399963 + cycle * 1.3;
                    final r = 160 * (1 - ph) + 8;
                    final k = ph < 0.15 ? ph / 0.15 : 1.0;
                    final sc = (1 - ph * 0.8) * k;
                    final size = 44.0 * sc;
                    final x = 115 + math.cos(ang) * r - size / 2;
                    final y = 115 + math.sin(ang) * r - size / 2;
                    return Positioned(
                      left: x,
                      top: y,
                      width: size,
                      height: size,
                      child: Opacity(
                        opacity: (1 - ph * 0.5).clamp(0.0, 1.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13 * sc),
                          child: all.isEmpty
                              ? const ColoredBox(color: Pastel.blueSoft)
                              : _orbThumb(all[((cycle * n + i) * 53 + read) %
                                  all.length]),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _phaseCard(
    PastelScheme t,
    Color card,
    Color card2,
    Color ink,
    Color mute,
    Color acc,
    Color onAcc,
    int cur,
    ScanProgress? p,
  ) {
    final titles = {
      0: c.mode.duplicates ? 'Đọc và băm ảnh' : 'Đọc thư viện ảnh',
      1: 'So khớp ứng viên',
      2: 'Đối chiếu file gốc',
      3: 'Phân tích AI',
    };
    final icons = {
      0: AppIcons.photoLibraryOutlined,
      1: AppIcons.search,
      2: AppIcons.fingerprint,
      3: AppIcons.autoAwesomeOutlined,
    };
    final pct = math.min(99, ((p?.fraction ?? 0) * 100).round());
    final start = _phaseStart[cur];
    final inPhase = start == null ? Duration.zero : c.elapsed - start;
    final frac = p?.fraction ?? 0;
    var detail = 'Đã chạy ${formatElapsed(inPhase)}';
    if (frac >= 0.03 && inPhase.inSeconds >= 3) {
      final eta = Duration(
        milliseconds: (inPhase.inMilliseconds * (1 - frac) / frac).round(),
      );
      detail += ' · còn ~${formatElapsed(eta)}';
    }
    // Mốc 1.000 ảnh đứng trước thời gian: lúc quét lâu, câu hỏi đầu tiên của
    // người dùng là còn bao nhiêu ảnh, không phải đã chạy bao lâu. Giai đoạn
    // so khớp không đếm theo ảnh nên không có mốc để hiện.
    if (p != null && p.milestoneTotal > 0 && p.phase != ScanPhase.matching) {
      detail = '${p.milestoneShort} · $detail';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: t.chartA, shape: BoxShape.circle),
            child: Center(
              child: AppIcon(
                icons[cur] ?? AppIcons.search,
                size: 20,
                color: Pastel.ink,
                accent: Pastel.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titles[cur] ?? 'Đang quét',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                    Text(
                      c.paused
                          ? 'Tạm dừng'
                          : (p?.phase == ScanPhase.matching
                                ? 'Đang chạy'
                                : '$pct%'),
                      style: TextStyle(fontSize: 12, color: mute),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: p?.phase == ScanPhase.matching
                      ? LinearProgressIndicator(
                          minHeight: 6,
                          color: t.chartA,
                          backgroundColor: card2,
                        )
                      : Container(
                          height: 6,
                          color: card2,
                          alignment: Alignment.centerLeft,
                          // Thanh tiến độ bước có gradient lime sang xanh.
                          child: AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            widthFactor: frac.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [t.chartA, t.chartB],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                Text(detail, style: TextStyle(fontSize: 11, color: mute)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
