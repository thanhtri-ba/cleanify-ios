import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/appearance.dart';
import '../shell/app_dock.dart';
import '../../theme/pastel_scheme.dart';
import '../../theme/reveal_route.dart';
import '../../theme/tick_dial.dart';
import '../../theme/motion.dart';
import '../scan/scan_complete_page.dart';
import '../screenshots/screenshots_page.dart';
import '../videos/large_videos_page.dart';
import '../../core/scanner/scan_mode.dart';
import '../scan/scan_controller.dart';
import '../scan/smart_scan_page.dart';
import '../settings/settings_page.dart';
import '../storage/storage_page.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';
import '../../core/platform/device_text.dart';

/// Màn chính: thẻ Bộ nhớ máy (tổng/còn trống từ hệ điều hành, dung lượng Ảnh/Video cộng
/// từ metadata từng asset, "Khác" là phần còn lại), nút quét, rồi kết quả và các
/// công cụ dọn dẹp. Số chưa đọc xong hiển thị "—" thay vì số giả.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Một vòng 6 giây dùng chung cho các hiệu ứng nền: dải màu chữ, viền nút quét, mảng màu.
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  final GlobalKey _ctaKey = GlobalKey();
  final ScrollController _scroll = ScrollController();

  ScanController get c => widget.controller;

  int? _photos;
  int? _videos;

  /// Quyền thư viện ảnh hiện tại. iOS cho phép người dùng chỉ chọn một số ảnh
  /// (limited); khi đó app chỉ thấy các ảnh đó nên kết quả quét sẽ thiếu.
  PermissionState? _perm;

  // Bộ nhớ máy (byte); null = chưa đọc xong.
  int? _total;
  int? _free;
  int? _photoBytes;
  int? _videoBytes;
  bool _loadingStorage = false;
  ScanStatus? _lastStatus;
  int _lastAssets = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onScan);
    _spin.repeat();
    _registerDock();
    _loadCounts();
    _loadStorage();
  }

  /// Người dùng có thể vừa đổi quyền trong Cài đặt: quay lại app thì đọc lại.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCounts();
      _loadStorage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onScan);
    _spin.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Đọc lại số liệu khi quét xong/hủy hoặc sau khi xóa ảnh.
  void _onScan() {
    final n = c.session?.assets.length ?? 0;
    final statusChanged = c.status != _lastStatus &&
        (c.status == ScanStatus.done || c.status == ScanStatus.idle);
    final deleted = c.status == ScanStatus.done && n != _lastAssets;
    _lastStatus = c.status;
    _lastAssets = n;
    if (statusChanged || deleted) {
      _loadCounts();
      _loadStorage();
    }
  }

  Future<void> _loadCounts() async {
    try {
      final perm = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption());
      if (mounted) setState(() => _perm = perm);
      if (!perm.hasAccess) return;
      Future<int> count(RequestType t) async {
        final ps = await PhotoManager.getAssetPathList(onlyAll: true, type: t);
        return ps.isEmpty ? 0 : await ps.first.assetCountAsync;
      }

      final p = await count(RequestType.image);
      final v = await count(RequestType.video);
      if (mounted) {
        setState(() {
          _photos = p;
          _videos = v;
        });
      }
    } catch (_) {}
  }

  /// Đọc tổng/còn trống rồi cộng dung lượng Ảnh và Video theo lô (không tải iCloud).
  Future<void> _loadStorage() async {
    if (_loadingStorage) return;
    _loadingStorage = true;
    try {
      final edits = PhotoEdits();
      if (!edits.supported) return;
      final st = await edits.storage();
      if (mounted && st != null) {
        setState(() {
          _total = st.total;
          _free = st.free;
        });
      }
      final perm = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption());
      if (!perm.hasAccess) return;
      Future<int> sum(RequestType t) async {
        final ps = await PhotoManager.getAssetPathList(onlyAll: true, type: t);
        if (ps.isEmpty) return 0;
        final n = await ps.first.assetCountAsync;
        var bytes = 0;
        for (var s = 0; s < n; s += 500) {
          if (!mounted) return bytes;
          final list = await ps.first
              .getAssetListRange(start: s, end: s + 500 > n ? n : s + 500);
          final sizes = await edits.fileSizes([for (final a in list) a.id]);
          bytes += sizes.values.fold(0, (a, b) => a + b);
        }
        return bytes;
      }

      final p = await sum(RequestType.image);
      if (mounted) setState(() => _photoBytes = p);
      final v = await sum(RequestType.video);
      if (mounted) setState(() => _videoBytes = v);
    } catch (_) {
      // Giữ "—" nếu lỗi, không hiện số sai.
    } finally {
      _loadingStorage = false;
    }
  }

  /// Đăng ký hành động cho dock dùng chung (dock nằm ngoài trang chủ, ở đáy mọi trang).
  void _registerDock() {
    AppDock.onScan = _scan;
    AppDock.onVideos = _openVideos;
    AppDock.onScreenshots = _openScreenshots;
    AppDock.onStorage = _openStorage;
    AppDock.onResults = _openResults;
    AppDock.onSettings = _openSettings;
    AppDock.onHomeTop = () {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic);
      }
    };
  }

  Future<void> _scan() async {
    // Một chế độ, một lần quét. Trước đây có bảng chọn "ảnh trùng" /
    // "ảnh tương tự"; giờ hai loại nhóm nằm trên cùng một thang phần trăm nên
    // không còn gì để chọn, và bảng đó chỉ là một nhịp chạm thừa.
    c.start(
      mode: const ScanMode(duplicates: true, similar: false),
      photos: _photos,
    );
    // Màn quét mở rộng từ đúng vị trí nút quét tròn.
    final box = _ctaKey.currentContext?.findRenderObject() as RenderBox?;
    final center = box == null
        ? MediaQuery.sizeOf(context).bottomRight(Offset.zero) / 2
        : box.localToGlobal(box.size.center(Offset.zero));
    Navigator.of(context).push(CircleRevealRoute<void>(
        center: center,
        settings: const RouteSettings(name: 'nodock'),
        builder: (_) => SmartScanPage(controller: c)));
  }

  void _say(String msg, {bool warn = false}) => AppDock.say(msg, warn: warn);

  /// Mở một trang công cụ; quay lại thì đọc lại số liệu vì có thể đã xóa.
  Future<void> _openTool(Widget page, {String? name}) async {
    await Navigator.of(context).push(MaterialPageRoute(
        settings: RouteSettings(name: name), builder: (_) => page));
    if (!mounted) return;
    _loadCounts();
    _loadStorage();
  }

  void _openStorage() => _openTool(
      StoragePage(
        total: _total,
        free: _free,
        photoBytes: _photoBytes,
        videoBytes: _videoBytes,
        photos: _photos,
        videos: _videos,
        onLargeVideos: _openVideos,
        onScreenshots: _openScreenshots,
      ),
      name: 'tab:2');

  void _openSettings() => _openTool(SettingsPage(controller: c), name: 'tab:3');

  // Hai trang công cụ này không có tab riêng. Gắn vào tab Bộ nhớ vì chúng là
  // công cụ dọn dung lượng và mở được thẳng từ trang Bộ nhớ; để trống tên thì
  // dock không sáng tab nào và bố cục bị dồn sang trái.
  void _openScreenshots() =>
      _openTool(ScreenshotsPage(controller: c), name: 'tab:2');

  void _openVideos() =>
      _openTool(LargeVideosPage(controller: c), name: 'tab:2');

  void _openResults() {
    if (c.status == ScanStatus.done && c.session != null) {
      // Trang tổng kết là nơi xem kết quả: nó có số ảnh dọn được, dung lượng
      // giải phóng và nút sang Xem lại. Nhảy thẳng vào Xem lại thì người dùng
      // quét xong không bao giờ thấy kết quả.
      Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: 'tab:1'),
          builder: (_) => ScanCompletePage(controller: c)));
    } else {
      _say('Hãy quét trước để xem ảnh trùng.', warn: true);
    }
  }

  double get _scale => MediaQuery.sizeOf(context).width < 360 ? 0.8 : 1.0;
  double _k(double v) => v * _scale;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Appearance.mode,
      builder: (context, _, __) => ListenableBuilder(
        listenable: c,
        builder: (context, _) => _page(context),
      ),
    );
  }

  Widget _page(BuildContext context) {
    final t = PastelScheme.of(context);
    final s = c.session;
    final done = c.status == ScanStatus.done && s != null;
    final scanning = c.status == ScanStatus.scanning;
    final src =
        done ? s.groups : (scanning ? c.keptGroups : <DuplicateGroup>[]);
    final hasData =
        done || (scanning && (c.shown.duplicates || c.shown.similar));
    final groups = [
      for (final g in src)
        if (g.kind == GroupKind.duplicate && c.shown.duplicates) g
    ];
    // Ảnh đã là "trùng" thì không tính lại là "tương tự".
    final similar = c.shown.similar
        ? similarExcludingDuplicates(
            [...groups, ...src.where((g) => g.kind == GroupKind.similar)])
        : <DuplicateGroup>[];
    // Home shows all non-keeper duplicate photos; protected photos remain reviewable.
    final reclaim = hasData && c.shown.duplicates
        ? planBulkCleanup(src, minSimilarity: kBulkCleanupMinSimilarity)
            .countFor(GroupKind.duplicate)
        : 0;
    int bySize(DuplicateGroup a, DuplicateGroup b) =>
        b.items.length.compareTo(a.items.length);
    final dd = [...groups]..sort(bySize);
    final ss = [...similar]..sort(bySize);
    final shown = [...dd.take(3), ...ss.take(3 - dd.take(3).length)];
    int photosOf(List<DuplicateGroup> g) =>
        g.fold(0, (n, x) => n + x.items.length);
    final dupPhotos = photosOf(groups);
    final simPhotos = photosOf(similar);
    final found = dupPhotos + simPhotos;
    final pad = MediaQuery.paddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.page,
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: _scale < 1 ? const TextScaler.linear(0.82) : null),
          child: Stack(children: [
            // Mảng màu mờ phía sau, vẽ TĨNH và tách lớp riêng.
            //
            // Trước đây ba blob này dựng lại mỗi khung hình theo _spin: ba lần
            // làm mờ gauss bán kính 46 trên vùng 210–250px, lặp 60 lần mỗi giây
            // suốt thời gian mở app. Đó là thủ phạm chính làm trang chủ và dock
            // đơ trên Android. Chúng trôi rất chậm nên gần như không ai thấy,
            // đổi lại khung hình thì thấy ngay.
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: Stack(children: [
                    _blob(-60, -50, 250, Pastel.limeGlow, t),
                    _blob(null, 30, 230, const Color(0xFF9A9A9A), t,
                        right: -70),
                    _blob(40, 430, 210, const Color(0xFFD0D0D0), t),
                  ]),
                ),
              ),
            ),
            SingleChildScrollView(
              controller: _scroll,
              padding:
                  EdgeInsets.fromLTRB(20, pad.top + 14, 20,
                      pad.bottom + DockShell.reserve(context) + 24),
              child: Column(children: [
                _accessBanner(t),
                _Reveal(0, _header(t, hasData, found)),
                const SizedBox(height: 4),
                const SizedBox(height: 18),
                _Reveal(1, _storagePanel(t)),
                const SizedBox(height: 12),
                _Reveal(
                    4,
                    _cleanRow(t, hasData, reclaim, dupPhotos, simPhotos,
                        [for (final g in shown) g.items.first.asset])),
                const SizedBox(height: 12),
                _Reveal(5, _cta(t, done)),
              ]),
            ),
            // Thanh tiêu đề thu gọn hiện dần khi cuộn xuống.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (_, __) {
                  final off = _scroll.hasClients ? _scroll.offset : 0.0;
                  final v = ((off - 50) / 50).clamp(0.0, 1.0);
                  // Chưa cuộn tới thì đừng dựng BackdropFilter: nó vẫn tốn một
                  // lần làm mờ toàn thanh dù người dùng không nhìn thấy gì.
                  if (v == 0) return const SizedBox.shrink();
                  return IgnorePointer(
                    ignoring: v < 0.5,
                    child: Opacity(
                      opacity: v,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            height: pad.top + 52,
                            padding: EdgeInsets.fromLTRB(20, pad.top, 20, 0),
                            decoration: BoxDecoration(
                              color: t.page.withValues(alpha: 0.92),
                              border: Border(bottom: BorderSide(color: t.line)),
                            ),
                            child: Row(children: [
                              Text('Cleanify',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                      color: t.ink)),
                              const Spacer(),
                              _badge(hasData, found),
                            ]),
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
      ),
    );
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

  // ---- thành phần dùng chung ----
  Widget _round(PastelScheme t, AppIconData i, VoidCallback? onTap,
          {double size = 42, Color? bg, Color? fg}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: bg ?? t.glass,
            shape: BoxShape.circle,
            boxShadow: [
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
                child: AppIcon(i,
                    size: size * 0.44,
                    color: fg ?? t.ink,
                    accent: fg ?? t.ink)),
          ),
        ),
      );

  Widget _badge(bool hasData, int found) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: Pastel.ink, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: hasData ? Colors.white : Pastel.nightMute,
                  shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(hasData ? '$found ảnh nghi trùng' : 'Chưa quét',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ]),
      );

  // ---- đầu trang: lời chào gọn + huy hiệu đen ----
  Widget _header(PastelScheme t, bool hasData, int found) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Chỉ một dòng chữ ở đầu trang. "Chào bạn," chiếm trọn một dòng
            // 26pt mà không nói điều gì người dùng chưa biết; huy hiệu bên dưới
            // mới là thứ họ mở app ra để xem.
            Text('Cleanify',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: t.ink)),
            const SizedBox(height: 8),
            _badge(hasData, found),
          ]),
        ),
        const SizedBox(width: 12),
        Semantics(
            button: true,
            label: 'Cài đặt',
            excludeSemantics: true,
            onTap: _openSettings,
            child: _round(t, AppIcons.settingsOutlined, _openSettings,
                size: _k(44))),
      ],
    );
  }

  // ---- khối Bộ nhớ: đồng hồ vạch + ba thẻ nhỏ ----
  Widget _storagePanel(PastelScheme t) {
    final total = _total;
    final free = _free;
    final used = total != null && free != null ? total - free : null;
    final frac = total == null || total == 0 || used == null
        ? 0.0
        : (used / total).clamp(0.0, 1.0);
    double share(int? b) =>
        (b == null || total == null || total == 0) ? 0 : b / total;
    final known = _photoBytes != null && _videoBytes != null;
    final pf = share(_photoBytes);
    final vf = share(_videoBytes);
    final other = (frac - pf - vf).clamp(0.0, 1.0);
    final parts = known
        ? <(double, Color)>[(pf, t.chartA), (vf, t.chartB), (other, t.chartC)]
        : <(double, Color)>[(frac, t.chartA)];
    final calm = reduceMotion(context);

    Widget mini(Color bg, Color fg, Color sub, String label, String value,
            Color dot) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: sub)),
                ),
              ]),
              const SizedBox(height: 1),
              Text(value,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        );

    return GestureDetector(
      onTap: _openStorage,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
        decoration: BoxDecoration(
          color: t.glass,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.glassBorder),
          boxShadow: const [
            BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 18,
                offset: Offset(0, 10),
                spreadRadius: -14),
          ],
        ),
        child: Column(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: calm ? Duration.zero : const Duration(milliseconds: 1500),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => TickRing(
              parts: parts,
              reveal: v,
              size: _k(196),
              track: t.track,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${(frac * 100 * v).round()}',
                      style: TextStyle(
                          fontSize: 52,
                          height: 1.12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -1.6,
                          color: t.ink,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  TextSpan(
                      text: '%', style: TextStyle(fontSize: 22, color: t.mute)),
                ])),
                const SizedBox(height: 6),
                Text(
                    used == null
                        ? 'Bộ nhớ $deviceName'
                        : '${_gbShort(used)} / ${_gb(total)} đã dùng',
                    style: TextStyle(fontSize: 12, color: t.mute)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            mini(t.limeBg, t.limeText, t.limeSub, 'Ảnh',
                known ? _gb(_photoBytes) : '…', t.chartA),
            const SizedBox(width: 6),
            mini(t.blueBg, t.blueText, t.blueSub, 'Video',
                known ? _gb(_videoBytes) : '…', t.chartB),
            const SizedBox(width: 6),
            mini(t.chip, t.ink, t.mute, 'Trống', _gb(free), t.track),
          ]),
        ]),
      ),
    );
  }

  // ---- hàng dọn dẹp: ảnh tròn xếp chồng + số ảnh có thể dọn ----
  Widget _cleanRow(PastelScheme t, bool hasData, int reclaim, int dup, int sim,
      List<dynamic> assets) {
    final sub = !hasData
        ? 'Chưa quét'
        : [
            if (c.shown.duplicates) 'trùng $dup',
            if (c.shown.similar) 'giống $sim',
          ].join(' · ');
    Widget lead;
    if (assets.isEmpty) {
      lead = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
            color: t.dark ? t.limeBg2 : Colors.white, shape: BoxShape.circle),
        child: Center(
            child: AppIcon(AppIcons.autoAwesomeOutlined,
                size: 24, color: t.ink, accent: t.ink)),
      );
    } else {
      lead = SizedBox(
        width: 52 + 27.0 * (assets.length - 1),
        height: 52,
        child: Stack(children: [
          for (var i = 0; i < assets.length; i++)
            Positioned(
              left: 27.0 * i,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: t.limeBg, width: 3),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x4D000000),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                          spreadRadius: -3)
                    ]),
                child: ClipOval(
                  child: AssetEntityImage(assets[i],
                      isOriginal: false,
                      fit: BoxFit.cover,
                      thumbnailSize: const ThumbnailSize.square(200)),
                ),
              ),
            ),
        ]),
      );
    }
    return GestureDetector(
      onTap: hasData ? _openResults : (c.busy ? null : _scan),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 13, 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
              colors: [t.limeBg, t.limeBg2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          boxShadow: [
            BoxShadow(
                color:
                    t.dark ? const Color(0x00000000) : const Color(0x33000000),
                blurRadius: 14,
                offset: const Offset(0, 7),
                spreadRadius: -10)
          ],
        ),
        child: Row(children: [
          lead,
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              hasData
                  ? CountUp(
                      value: reclaim.toDouble(),
                      duration: const Duration(milliseconds: 1200),
                      builder: (x) => Text('$x ảnh trùng',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: t.limeText,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])))
                  : Text('Chưa có kết quả',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          color: t.limeText)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: t.limeSub)),
            ]),
          ),
          _round(t, AppIcons.arrowUpRight, null,
              size: 46, bg: t.accent, fg: t.onAccent),
        ]),
      ),
    );
  }

  // ---- nút quét lớn: thẻ đen có ánh sáng màu xoay phía sau ----
  Widget _cta(PastelScheme t, bool done) {
    final off = c.busy;
    final calm = reduceMotion(context);
    return GestureDetector(
      key: _ctaKey,
      onTap: off ? null : _scan,
      child: PressScale(
        enabled: !off,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 80),
            decoration: BoxDecoration(
              color: Pastel.ink,
              border: t.dark ? Border.all(color: t.glassBorder) : null,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(children: [
              if (!off && !calm)
                // Tách lớp: vầng sáng xoay làm mờ lại mỗi khung hình, đừng để
                // nó kéo cả trang chủ vẽ theo.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _spin,
                      // Làm mờ rồi xoay cho ra đúng cùng ảnh với xoay rồi làm
                      // mờ, nên dựng phần đã làm mờ MỘT lần qua `child` và chỉ
                      // xoay lại tấm ảnh đó. Trước đây bộ lọc chạy lại 60 lần
                      // một giây, ngay trên trang đầu tiên người dùng thấy.
                      builder: (_, child) => Transform.rotate(
                        alignment: const Alignment(0.76, 0),
                        angle: _spin.value * 2 * math.pi,
                        child: child,
                      ),
                      child: RepaintBoundary(
                        child: ImageFiltered(
                          imageFilter:
                              ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: Opacity(
                            opacity: 0.55,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: SweepGradient(
                                  center: Alignment(0.76, 0),
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFF9A9A9A),
                                    Color(0xFF4A4A4A),
                                    Color(0xFF9A9A9A),
                                    Color(0xFFFFFFFF)
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              off
                                  ? 'Đang quét…'
                                  : (done ? 'Quét lại' : 'Quét ảnh & video'),
                              style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.3,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(
                              _photos == null
                                  ? 'Ảnh & video'
                                  : '$_photos ảnh · ${_videos ?? 0} video',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFB9B9B9))),
                        ]),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        color: off ? Pastel.night3 : Colors.white,
                        shape: BoxShape.circle),
                    child: Center(
                      child: off
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.6, color: Colors.white))
                          : const AppIcon(AppIcons.scan,
                              size: 28, color: Pastel.ink, accent: Pastel.ink),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static String _gb(int? b) => b == null
      ? '—'
      : '${(b / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

  static String _gbShort(int? b) => b == null
      ? '—'
      : (b / 1e9).toStringAsFixed(b >= 1e10 ? 0 : 1).replaceAll('.', ',');

  // ---- cảnh báo quyền truy cập ảnh ----
  /// Hiện khi chỉ được truy cập một số ảnh (limited) hoặc bị từ chối. App không thể
  /// tự nâng quyền: người dùng phải chọn "Cho phép truy cập tất cả ảnh" trong Cài đặt.
  Widget _accessBanner(PastelScheme t) {
    final perm = _perm;
    if (perm == null || perm == PermissionState.notDetermined) {
      return const SizedBox.shrink();
    }
    final limited = perm == PermissionState.limited;
    if (!limited && perm.hasAccess) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
              colors: [t.amberBg, t.amberBg2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          boxShadow: [
            BoxShadow(
                color:
                    t.dark ? const Color(0x00000000) : const Color(0x40000000),
                blurRadius: 16,
                offset: const Offset(0, 7),
                spreadRadius: -9),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: t.dark ? 0.12 : 0.8),
                  shape: BoxShape.circle),
              child: Center(
                  child: AppIcon(AppIcons.notificationsOutlined,
                      size: 21, color: t.amberText, accent: t.amberText)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        limited
                            ? 'Đang cho phép một số ảnh'
                            : 'Chưa có quyền truy cập ảnh',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: t.amberText)),
                    const SizedBox(height: 3),
                    Text(
                        limited
                            ? 'Chỉ quét được những ảnh bạn đã chọn.'
                            : 'Cần quyền xem thư viện ảnh để quét.',
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: t.amberSub)),
                  ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            GestureDetector(
              onTap: PhotoManager.openSetting,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: t.dark ? t.amberText : Pastel.ink,
                    borderRadius: BorderRadius.circular(21)),
                child: Text(limited ? 'Cho phép tất cả ảnh' : 'Mở Cài đặt',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.dark ? Pastel.ink : Colors.white)),
              ),
            ),
            if (limited) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  await PhotoManager.presentLimited();
                  if (mounted) {
                    _loadCounts();
                    _loadStorage();
                  }
                },
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      border:
                          Border.all(color: t.amberSub.withValues(alpha: 0.5))),
                  child: Text('Chọn thêm ảnh',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.amberText)),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// Hiện dần + trượt nhẹ từ dưới lên, so le theo [index]. Không dùng Timer
/// (một controller với Interval) và tắt khi người dùng bật giảm chuyển động.
class _Reveal extends StatefulWidget {
  const _Reveal(this.index, this.child);
  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final int _total = 420 + 60 * widget.index;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _total))
        ..forward();
  // Tạo một lần. Trước đây build() tạo CurvedAnimation mới mỗi lần dựng lại và không
  // hủy, nên listener tích lũy trên _c và tốn thêm việc ở mỗi khung hình.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _c,
    curve: Interval(60 * widget.index / _total, 1, curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
          .animate(_curve);

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
