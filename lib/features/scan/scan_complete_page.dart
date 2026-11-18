import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/device_text.dart';
import '../../core/platform/file_share.dart';
import '../../core/platform/photo_edits.dart';
import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/scan_progress.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/app_dock.dart';
import '../shell/page_kit.dart';
import 'cleaning_page.dart';
import 'review_filter.dart';
import 'review_page.dart';
import 'scan_controller.dart';
import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';

/// Màn "Quét xong". Trả lời đúng ba câu người dùng hỏi khi quét xong:
/// dọn được bao nhiêu ảnh, nhẹ máy bao nhiêu GB, và dọn ngay hay xem lại.
///
/// Số liệu lấy từ [planBulkCleanup] (mỗi nhóm giữ 1 ảnh), dung lượng lấy từ
/// metadata qua [PhotoEdits.fileSizes] nên không tải file. Không xóa gì trước
/// khi người dùng xác nhận.
class ScanCompletePage extends StatefulWidget {
  const ScanCompletePage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<ScanCompletePage> createState() => _ScanCompletePageState();
}

class _ScanCompletePageState extends State<ScanCompletePage> {
  late final Set<GroupKind> _kinds = {
    if (widget.controller.shown.duplicates) GroupKind.duplicate,
    if (widget.controller.shown.similar) GroupKind.similar,
  };

  ScanController get c => widget.controller;

  /// Dung lượng từng ảnh (byte), nạp dần theo lô. Thiếu khóa = chưa đọc xong.
  final Map<String, int> _sizes = {};

  /// Ảnh đã chỉnh sửa: không bao giờ tự chọn xóa, kể cả khi bấm "Dọn ngay".
  final Set<String> _edited = {};

  bool _loading = false;
  bool _exporting = false;

  /// Đã nạp xong dung lượng VÀ danh sách ảnh đã chỉnh sửa chưa.
  ///
  /// Nút "Dọn ngay" phải chờ cờ này. [planBulkCleanup] dùng [_edited] làm
  /// protectedIds; bấm dọn lúc danh sách còn rỗng thì ảnh người dùng đã chỉnh
  /// sửa KHÔNG được bảo vệ và bị xoá mất. Nút "Xem lại" không cần chờ vì ở đó
  /// người dùng tự nhìn từng ảnh.
  bool _metaReady = false;

  /// Số nhóm đã nạp dung lượng, để biết lúc nào AI tìm thêm nhóm thì nạp lại.
  int _loadedFor = -1;

  late bool _seenSimilar = c.shown.similar;

  @override
  void initState() {
    super.initState();
    c.addListener(_onScan);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    c.removeListener(_onScan);
    super.dispose();
  }

  void _onScan() {
    if (_allGroups.length != _loadedFor) _load();
  }

  // ---------------------------------------------------------------- dữ liệu

  /// Nhóm thật (>= 2 ảnh) của một loại; nhóm tương tự đã bỏ ảnh nằm trong nhóm trùng.
  List<DuplicateGroup> _groupList(GroupKind k) {
    final raw = c.session?.groups ?? const <DuplicateGroup>[];
    if (k == GroupKind.similar) {
      final dup = c.shown.duplicates
          ? raw.where((g) => g.kind == GroupKind.duplicate)
          : const <DuplicateGroup>[];
      return similarExcludingDuplicates([
        ...dup,
        ...raw.where((g) => g.kind == GroupKind.similar),
      ], minCosine: kDefaultSimilarTol);
    }
    return [
      for (final g in raw)
        if (g.kind == k && g.items.length > 1) g,
    ];
  }

  int _groupsOf(GroupKind k) => _groupList(k).length;
  int _itemsOf(GroupKind k) =>
      _groupList(k).fold(0, (n, g) => n + g.items.length);

  /// Mọi nhóm đang hiển thị được, cả hai loại.
  List<DuplicateGroup> get _allGroups => [
    if (c.shown.duplicates) ..._groupList(GroupKind.duplicate),
    if (c.shown.similar) ..._groupList(GroupKind.similar),
  ];

  /// Nhóm thuộc các loại người dùng đang bật.
  List<DuplicateGroup> get _pickedGroups => [
    for (final k in _kinds) ..._groupList(k),
  ];

  /// Kế hoạch dọn nhanh. Lập trên TẤT CẢ nhóm để ảnh giữ lại của nhóm này không
  /// bị nhóm kia xóa, rồi mới lọc theo loại đang bật.
  BulkCleanupPlan get _plan => planBulkCleanup(
    _allGroups,
    minSimilarity: kBulkCleanupDefaultSimilarity,
    protectedIds: _edited,
  );

  List<AssetEntity> get _toDelete => _plan.assetsFor(_kinds);

  /// Tổng dung lượng các ảnh sẽ dọn. Ảnh chưa đọc xong tính bằng 0.
  int _bytesOf(List<AssetEntity> assets) =>
      assets.fold(0, (n, a) => n + (_sizes[a.id] ?? 0));

  /// Đã biết dung lượng của mọi ảnh trong kế hoạch chưa.
  bool _sized(List<AssetEntity> assets) =>
      assets.every((a) => _sizes.containsKey(a.id));

  /// Nạp dung lượng và danh sách ảnh đã chỉnh, theo lô để giao diện hiện dần.
  Future<void> _load() async {
    if (_loading || !mounted) return;
    _loading = true;
    final groups = _allGroups;
    _loadedFor = groups.length;
    try {
      final edits = PhotoEdits();
      if (!edits.supported) return;
      final ids = <String>[
        for (final g in groups)
          for (final it in g.items) it.asset.id,
      ];
      for (var s = 0; s < ids.length; s += _chunk) {
        if (!mounted) return;
        final part = ids.sublist(s, math.min(s + _chunk, ids.length));
        final sizes = await edits.fileSizes(part);
        final edited = await edits.editedIds(part);
        if (!mounted) return;
        setState(() {
          _sizes.addAll(sizes);
          _edited.addAll(edited);
        });
      }
      if (mounted) setState(() => _metaReady = true);
    } catch (_) {
      // Thiếu dung lượng thì hiện "—"; mọi thứ còn lại vẫn dùng được.
    } finally {
      _loading = false;
    }
  }

  static const int _chunk = 400;

  // ------------------------------------------------------------- hành động

  /// Mở trang xem ảnh để tự chọn giữ/xóa; không xóa gì ở đây.
  void _review({ReviewFilter filter = const ReviewFilter()}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'tab:1'),
        builder: (_) => ReviewPage(
          controller: c,
          kinds: {..._kinds},
          initialFilter: filter,
        ),
      ),
    );
  }

  /// Dọn nhanh: áp dụng thẳng kế hoạch mặc định, vẫn phải xác nhận.
  Future<void> _cleanNow() async {
    if (!_metaReady) return;
    final assets = _toDelete;
    if (assets.isEmpty) return;
    final n = assets.length;
    final big = n > _bigBatch;
    final freed = _sized(assets)
        ? ' Giải phóng khoảng ${_size(_bytesOf(assets))}.'
        : '';
    final ok = await showConfirmDialog(
      context,
      title: big ? 'Dọn nhiều ảnh?' : 'Dọn $n ảnh?',
      message: 'Mỗi nhóm giữ lại 1 ảnh tốt nhất.$freed $trashNote',
      tickLabel: big ? 'Tôi đã hiểu và muốn dọn $n ảnh' : null,
      confirmLabel: 'Dọn $n ảnh',
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'nodock'),
        builder: (_) => CleaningPage(controller: c, assets: assets),
      ),
    );
  }

  static const int _bigBatch = 200;

  void _toggle(GroupKind k) =>
      setState(() => _kinds.contains(k) ? _kinds.remove(k) : _kinds.add(k));

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await c.exportScanCsv();
      if (!mounted) return;
      if (file == null) {
        AppDock.say('Chưa có dữ liệu quét để xuất.', warn: true);
      } else {
        final shared = await FileShare.share(file.path);
        if (!mounted) return;
        AppDock.say(
          shared
              ? 'Đã chia sẻ CSV.'
              : 'CSV đã tạo. Chọn “Lưu vào Tệp” trong bảng chia sẻ để lưu ra ngoài.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppDock.say('Không lưu/chia sẻ được CSV: $e', warn: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _exportRow(PastelScheme t) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListRow(
        first: true,
        leading: IconBubble(AppIcons.copyOutlined, bg: t.chip, fg: t.ink),
        title: _exporting
            ? 'Đang tạo báo cáo…'
            : c.scanReportPath == null
            ? 'Tạo và lưu báo cáo CSV'
            : 'Lưu hoặc chia sẻ báo cáo CSV',
        subtitle: c.refining
            ? 'AI đang hoàn tất nhóm; báo cáo sẽ được cập nhật sau đó'
            : c.scanReportPath == null
            ? (c.session?.reportError == null
                  ? 'Chạm để tạo CSV rồi chọn Lưu vào Tệp'
                  : 'Chưa lưu tự động; chạm để thử lại và xem bảng chia sẻ')
            : 'Chạm rồi chọn Lưu vào Tệp, Numbers hoặc Excel',
        trailing: _exporting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.file_download_outlined, color: t.mute),
        onTap: _exporting || c.refining ? null : _exportCsv,
      ),
    ),
  );

  /// Ảnh đại diện của vài nhóm lớn nhất của một loại, dùng cho ô chọn loại.
  List<AssetEntity> _thumbs(GroupKind k) {
    final groups = [..._groupList(k)]
      ..sort((a, b) => b.items.length.compareTo(a.items.length));
    return [for (final g in groups.take(3)) g.items.first.asset];
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (c.shown.similar && !_seenSimilar) {
        _seenSimilar = true;
        _kinds.add(GroupKind.similar);
      }
      final t = PastelScheme.of(context);
      final nothing = _allGroups.isEmpty && !c.refining && !c.canRefine;
      return nothing ? _clean(t) : _body(t);
    },
  );

  /// Thư viện đã gọn: không có nhóm nào và cũng không còn bước nào đang chạy.
  Widget _clean(PastelScheme t) {
    final scanned = c.session?.assets.length ?? 0;
    final incomplete = c.session?.incompleteStages.isNotEmpty ?? false;
    return PageScaffold(
      title: 'Kết quả quét',
      subtitle: incomplete
          ? '${formatElapsed(c.elapsed)} · phân tích chưa đầy đủ'
          : formatElapsed(c.elapsed),
      children: [
        Reveal(
          index: 1,
          child: GlassCard(
            margin: const EdgeInsets.only(top: 40),
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
            child: Column(
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: t.chip,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.checkCircleOutline,
                      size: 52,
                      color: t.ink,
                      accent: t.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  incomplete ? 'Đã dừng theo giới hạn' : 'Thư viện đã gọn',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.4,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  incomplete
                      ? 'Đã xử lý $scanned/${c.session!.libraryTotal} ảnh. Bước ${c.session!.incompleteStages.join(', ')} chưa xong; đây chưa phải kết quả toàn thư viện.'
                      : scanned > 0
                      ? 'Đã xem $scanned ảnh, không tìm thấy ảnh nào trùng nhau.'
                      : 'Không tìm thấy ảnh nào trùng nhau.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: t.mute),
                ),
              ],
            ),
          ),
        ),
        Reveal(index: 2, child: _exportRow(t)),
        Reveal(
          index: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: Text(
                  'Về trang chủ',
                  style: TextStyle(fontSize: 14, color: t.mute),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(PastelScheme t) {
    final dupItems = c.shown.duplicates ? _itemsOf(GroupKind.duplicate) : 0;
    final simItems = c.shown.similar ? _itemsOf(GroupKind.similar) : 0;
    final cardBg = t.dark ? t.card : Colors.white;

    // Lập kế hoạch MỘT lần cho cả khung hình: nó duyệt toàn bộ nhóm nên gọi lại
    // bốn năm lần trong một lần dựng là đủ để thấy giật ở thư viện lớn.
    final plan = _plan;
    final picked = _pickedGroups;
    final toDelete = plan.assetsFor(_kinds);
    final dupDel = _kinds.contains(GroupKind.duplicate)
        ? plan.countFor(GroupKind.duplicate)
        : 0;
    final simDel = _kinds.contains(GroupKind.similar)
        ? plan.countFor(GroupKind.similar)
        : 0;
    final total = dupDel + simDel;

    return PageScaffold(
      title: 'Kết quả quét',
      subtitle: (c.session?.incompleteStages.isNotEmpty ?? false)
          ? '${formatElapsed(c.elapsed)} · kết quả một phần'
          : formatElapsed(c.elapsed),
      bottomBar: total == 0 && picked.isNotEmpty
          // Có nhóm nhưng không ảnh nào đạt ngưỡng tự chọn. Để nguyên nút
          // "Dọn ngay" màu xám ở đây là bỏ người dùng giữa đường: họ thấy app
          // tìm ra ảnh trùng mà không làm gì được, và không biết vì sao.
          ? ActionBar(
              title: 'Cần xem lại',
              subtitle: '${picked.length} nhóm · xem lại trước khi chọn xóa',
              button: 'Xem lại',
              onPressed: () => _review(),
            )
          : ActionBar(
              title: total > 0 ? 'Dọn $total ảnh' : 'Không có ảnh trùng',
              subtitle: total > 0
                  ? 'Giữ lại 1 ảnh mỗi nhóm'
                  : 'Xem lại nhóm ảnh',
              secondary: picked.isEmpty ? null : 'Xem lại',
              onSecondary: picked.isEmpty ? null : () => _review(),
              button: 'Dọn ngay',
              onPressed: (total == 0 || !_metaReady) ? null : _cleanNow,
            ),
      children: [
        _exportRow(t),
        if (c.session?.incompleteStages.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(14),
              child: Text(
                'Kết quả một phần: đã xử lý ${c.session?.scanned ?? 0}/${c.session?.libraryTotal ?? 0} ảnh. Chưa hoàn tất: ${c.session?.incompleteStages.join(', ')}.',
                style: TextStyle(fontSize: 13, height: 1.4, color: t.ink),
              ),
            ),
          ),
        // ---- Chọn loại ảnh ----
        Reveal(index: 2, child: _section(t, 'Nhóm ảnh', 'Chọn nhóm')),
        Reveal(
          index: 2,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.shown.duplicates)
                  Expanded(
                    child: _tile(
                      t,
                      cardBg,
                      GroupKind.duplicate,
                      t.chartA,
                      'Ảnh trùng',
                      '$dupItems',
                      '${_groupsOf(GroupKind.duplicate)} nhóm · chỉ chọn bản trùng khớp chính xác',
                    ),
                  ),
                if (c.shown.duplicates &&
                    (c.shown.similar || c.refining || c.canRefine))
                  const SizedBox(width: 10),
                if (!c.shown.similar && (c.refining || c.canRefine))
                  Expanded(child: _pendingTile(t, cardBg)),
                if (c.shown.similar)
                  Expanded(
                    child: _tile(
                      t,
                      cardBg,
                      GroupKind.similar,
                      t.chartB,
                      'Ảnh tương tự',
                      '$simItems',
                      '${_groupsOf(GroupKind.similar)} nhóm · xem lại',
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ---- Dọn theo thời gian ----
        ..._timeSection(t, picked, toDelete),
      ],
    );
  }

  /// Lối tắt lọc theo thời gian chụp. Ba mốc này dùng đúng định nghĩa của
  /// [ReviewFilter] nên con số ở đây khớp với trang mở ra khi chạm, kể cả khi
  /// chúng chồng lấn nhau (30 ngày qua cũng nằm trong năm nay).
  List<Widget> _timeSection(
    PastelScheme t,
    List<DuplicateGroup> picked,
    List<AssetEntity> toDelete,
  ) {
    if (picked.isEmpty) return const [];
    const bands = [
      (DateBand.last30, '30 ngày qua'),
      (DateBand.thisYear, 'Trong năm nay'),
      (DateBand.older, 'Cũ hơn 1 năm'),
    ];
    final rows = <Widget>[];
    final del = {for (final a in toDelete) a.id};
    for (final band in bands) {
      final f = ReviewFilter(date: band.$1);
      var groups = 0, photos = 0, bytes = 0;
      for (final g in picked) {
        if (!f.passes(g, _edited)) continue;
        groups++;
        for (final it in g.items) {
          if (!del.contains(it.asset.id)) continue;
          photos++;
          bytes += _sizes[it.asset.id] ?? 0;
        }
      }
      if (groups == 0) continue;
      rows.add(
        ListRow(
          first: rows.isEmpty,
          leading: IconBubble(AppIcons.schedule, bg: t.chip, fg: t.ink),
          title: band.$2,
          subtitle: photos > 0
              ? '$groups nhóm · dọn được $photos ảnh'
              : '$groups nhóm · không có ảnh tự dọn',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bytes > 0 ? _size(bytes) : '—',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              const SizedBox(width: 6),
              AppIcon(
                AppIcons.chevronRight,
                size: 18,
                color: t.mute,
                accent: t.mute,
              ),
            ],
          ),
          onTap: () => _review(filter: ReviewFilter(date: band.$1)),
        ),
      );
    }
    if (rows.isEmpty) return const [];
    return [
      Reveal(
        index: 3,
        child: _section(t, 'Dọn theo thời gian', 'Ảnh cũ thường dọn trước'),
      ),
      Reveal(
        index: 3,
        child: GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: rows),
        ),
      ),
    ];
  }

  /// Ô chờ: ảnh tương tự chưa có — đang chạy AI nền hoặc để người dùng bấm quét.
  Widget _pendingTile(PastelScheme t, Color cardBg) {
    final run = c.refining;
    final pr = c.refineProgress;
    return Semantics(
      button: !run,
      label: run ? 'Đang tìm ảnh tương tự' : 'Quét ảnh tương tự',
      excludeSemantics: true,
      onTap: run ? null : c.startRefine,
      child: GestureDetector(
        onTap: run ? null : c.startRefine,
        child: PressScale(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: t.line, offset: const Offset(0, 1))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: run
                      ? CircularProgressIndicator(
                          strokeWidth: 3,
                          color: t.chartB,
                          value: pr?.fraction,
                        )
                      : AppIcon(
                          AppIcons.autoAwesomeOutlined,
                          size: 22,
                          color: t.chartB,
                          accent: t.chartB,
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ảnh tương tự',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  run
                      ? 'AI đang tìm, vẫn dùng app được…'
                      : 'Chạm để quét bằng AI',
                  style: TextStyle(fontSize: 11, color: t.mute),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(PastelScheme t, String title, String trailing) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              color: t.ink,
            ),
          ),
        ),
        Flexible(
          child: Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: t.mute),
          ),
        ),
      ],
    ),
  );

  /// Ô chọn loại ảnh: chạm để bật/tắt; ô bật phủ màu của loại (khớp cung trên vòng).
  Widget _tile(
    PastelScheme t,
    Color cardBg,
    GroupKind k,
    Color col,
    String title,
    String big,
    String sub,
  ) {
    final on = _kinds.contains(k);
    final thumbs = _thumbs(k);
    return Semantics(
      button: true,
      selected: on,
      label: '$title, $big ảnh',
      excludeSemantics: true,
      onTap: () => _toggle(k),
      child: GestureDetector(
        onTap: () => _toggle(k),
        child: PressScale(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: on
                  ? Color.alphaBlend(
                      col.withValues(alpha: t.dark ? 0.18 : 0.16),
                      cardBg,
                    )
                  : cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: on ? col : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: on
                  ? null
                  : [BoxShadow(color: t.line, offset: const Offset(0, 1))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      height: 26,
                      width: thumbs.isEmpty
                          ? 0
                          : 26 + 17.0 * (thumbs.length - 1),
                      child: Stack(
                        children: [
                          for (var i = 0; i < thumbs.length; i++)
                            Positioned(
                              left: 17.0 * i,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cardBg, width: 2),
                                ),
                                child: ClipOval(
                                  child: AssetEntityImage(
                                    thumbs[i],
                                    isOriginal: false,
                                    fit: BoxFit.cover,
                                    thumbnailSize: const ThumbnailSize.square(
                                      80,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: on ? col : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: on ? col : t.track, width: 2),
                      ),
                      child: on
                          ? const AppIcon(
                              AppIcons.check,
                              size: 14,
                              color: Colors.white,
                              accent: Colors.white,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  big,
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.12,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -1.0,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.ink,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: t.mute),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: t.mute.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 400),
                      widthFactor: on ? 1 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: col,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "412 MB", "2,4 GB". Dấu phẩy thập phân cho khớp phần còn lại của app.
  static String _size(int b) {
    if (b <= 0) return '0 MB';
    final mb = b / 1e6;
    if (mb < 1000) {
      return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} MB';
    }
    return '${(b / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';
  }
}
