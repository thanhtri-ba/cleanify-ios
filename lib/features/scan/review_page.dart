import 'package:flutter/material.dart';
import '../shell/app_dock.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/regroup.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/page_kit.dart';
import 'cleaning_page.dart';
import 'photo_detail_page.dart';
import 'review_filter.dart';
import 'scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';
import '../../core/platform/device_text.dart';

/// Xem từng nhóm ảnh trùng/tương tự và tự chọn ảnh giữ/xóa. Chọn sẵn theo
/// [planBulkCleanup] (mỗi nhóm giữ ảnh đầu) nhưng người dùng sửa được. Chỉ khi bấm
/// nút xóa và xác nhận mới sang [CleaningPage]; một nhóm luôn còn ít nhất 1 ảnh.
class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.controller,
    this.kinds,
    this.initialFilter = const ReviewFilter(),
  });
  final ScanController controller;

  /// Loại nhóm được chọn sẵn để xóa; null = tất cả.
  final Set<GroupKind>? kinds;

  /// Bộ lọc bật sẵn khi mở trang, ví dụ chỉ ảnh cũ hơn một năm khi người dùng
  /// chạm vào một mốc thời gian ở trang Kết quả quét.
  final ReviewFilter initialFilter;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  ScanController get c => widget.controller;
  late GroupKind _tab;

  /// Đang xem tab "Màn hình". Giữ riêng thay vì thêm giá trị vào [GroupKind]:
  /// ảnh chụp màn hình vẫn có nhóm trùng và nhóm tương tự như ảnh thường, nó là
  /// một CÁCH LỌC chứ không phải một loại nhóm mới. Nhét vào GroupKind thì mọi
  /// chỗ đang chia đôi theo loại nhóm đều phải xử lý thêm một nhánh vô nghĩa.
  bool _shots = false;

  /// Nhóm gồm ảnh chụp màn hình. Nhóm không bao giờ lẫn hai loại (bộ quét đã
  /// tách từ lúc dựng nhóm), nên xem ảnh đầu là đủ.
  static bool _isShotGroup(DuplicateGroup g) =>
      isScreenshotAsset(g.items.first.asset);

  /// Nhóm này có thuộc tab đang xem không.
  bool _inTab(DuplicateGroup g) =>
      _shots ? _isShotGroup(g) : (!_isShotGroup(g) && g.kind == _tab);
  Set<String> _del = {}; // id ảnh sẽ xóa

  /// Ngưỡng độ giống (%) lúc quét, tương ứng Hamming 32. Nhóm gốc được tạo theo mức này.
  static const double _scanSim = 87.5;

  /// Độ giống tối thiểu (%) để gom nhóm trùng khi mở màn xem kết quả.
  static const double _defaultSim = kDefaultDupSim;
  static const int _bigBatch = 200; // xóa nhiều hơn số này cần tick xác nhận
  double _sim = _defaultSim;

  /// Nhóm trùng gom lại theo [_sim]; null = dùng kết quả quét gốc.
  List<DuplicateGroup>? _regrouped;

  /// Bộ lọc hiển thị (chỉ ẩn/hiện nhóm, không đổi kết quả quét).
  late ReviewFilter _filter = widget.initialFilter;

  bool _visible(DuplicateGroup g) => _filter.passes(g, _edited);

  /// Tăng mỗi lần gom lại để danh sách chuyển mờ dần thay vì nhảy.
  int _ver = 0;

  /// Ảnh đã chỉnh sửa trong ứng dụng Ảnh. Không tự chọn xóa để khỏi mất bản chỉnh.
  Set<String> _edited = {};
  bool _touched =
      false; // người dùng đã tự đổi lựa chọn: không ghi đè khi _edited tải xong

  /// Mức "độ lệch cho phép" của tab Giống nhau (chỉ ẩn bớt ảnh, không quét lại).
  double _tol = kDefaultSimilarTol;

  /// Ngưỡng để tự chọn xóa. Luôn là 100% (SHA-256 trùng); ảnh gần giống cần
  /// được người dùng chọn thủ công sau khi xem.
  final double _auto = kBulkCleanupDefaultSimilarity;

  /// Dung lượng từng ảnh (byte), đọc từ metadata. Thiếu khoá = chưa đọc xong.
  final Map<String, int> _sizes = {};

  /// Ảnh người dùng tự chọn giữ, theo từng nhóm.
  ///
  /// Khoá là id ảnh ĐẦU TIÊN của nhóm: thứ tự items không đổi trong suốt phiên
  /// nên nó là định danh ổn định, kể cả sau khi người dùng đổi ảnh giữ.
  final Map<String, String> _keeper = {};

  /// Nhóm người dùng đã bỏ qua: thu gọn thành một dòng, không xoá ảnh nào.
  final Set<String> _skipped = {};

  /// Bản làm việc của nhóm trùng sau các lần gộp tay. Null = chưa gộp lần nào.
  List<DuplicateGroup>? _manual;

  static String _groupKey(DuplicateGroup g) => g.items.first.asset.id;

  /// Ảnh đang giữ của một nhóm. Mặc định là ảnh app chọn, trừ khi người dùng đổi.
  String _keeperId(DuplicateGroup g) =>
      _keeper[_groupKey(g)] ?? g.items[keeperIndex(g)].asset.id;

  /// Chỉ nhóm thuộc loại đã chọn lúc quét.
  List<DuplicateGroup> get _all => _allAt(_tol);

  List<DuplicateGroup> _allAt(double tol) {
    final raw = c.session?.groups ?? const <DuplicateGroup>[];
    final gone = _index?.removed ?? const <String>{};
    final dup = <DuplicateGroup>[];
    for (final g in _manual ?? _regrouped ?? raw) {
      if (g.kind != GroupKind.duplicate || !c.shown.duplicates) continue;
      // Nhóm gom lại là bản sao trong UI: bỏ ảnh đã xóa sau lúc gom.
      final items = _regrouped != null || _manual != null
          ? [
              for (final e in g.items)
                if (!gone.contains(e.asset.id)) e,
            ]
          : g.items;
      if (items.length > 1) {
        dup.add(items.length == g.items.length ? g : DuplicateGroup(items));
      }
    }
    // Ảnh đã nằm trong nhóm trùng thì không lặp lại ở tab Tương tự.
    final sim = c.shown.similar
        ? similarExcludingDuplicates([
            ...dup,
            ...raw.where((g) => g.kind == GroupKind.similar),
          ], minCosine: tol)
        : <DuplicateGroup>[];
    return [...dup, ...sim];
  }

  @override
  void initState() {
    super.initState();
    _regrouped = _computeRegrouped();
    _applyDefault();
    _loadEdited();
    _loadSizes();
    _tab =
        c.shown.duplicates &&
            (_all.any(
                  (g) => g.kind == GroupKind.duplicate && g.items.length > 1,
                ) ||
                !c.shown.similar)
        ? GroupKind.duplicate
        : GroupKind.similar;
    // Thư viện chỉ toàn ảnh chụp màn hình thì mở thẳng tab đó, đừng bắt người
    // dùng nhìn một tab rỗng rồi tự đoán phải bấm sang đâu.
    final big = _all.where((g) => g.items.length > 1);
    if (big.isNotEmpty && big.every(_isShotGroup)) _shots = true;
  }

  /// Dung lượng từng ảnh, đọc từ metadata nên không mở file.
  Future<void> _loadSizes() async {
    try {
      final edits = PhotoEdits();
      if (!edits.supported) return;
      final ids = {
        for (final g in c.session?.groups ?? const <DuplicateGroup>[])
          for (final e in g.items) e.asset.id,
      }.toList();
      for (var i = 0; i < ids.length; i += 400) {
        if (!mounted) return;
        final part = ids.sublist(
          i,
          i + 400 > ids.length ? ids.length : i + 400,
        );
        final got = await edits.fileSizes(part);
        if (!mounted) return;
        setState(() => _sizes.addAll(got));
      }
    } catch (_) {
      // Thiếu dung lượng chỉ làm mất phần chú thích dưới ảnh.
    }
  }

  Future<void> _loadEdited() async {
    try {
      final ids = {
        for (final g in c.session?.groups ?? const <DuplicateGroup>[])
          for (final e in g.items) e.asset.id,
      }.toList();
      final edited = await PhotoEdits().editedIds(ids);
      if (!mounted || edited.isEmpty) return;
      setState(() {
        _edited = edited;
        if (!_touched) _applyDefault();
      });
    } catch (_) {
      // Không đọc được thì chỉ mất nhãn "Đã chỉnh", không ảnh hưởng xóa.
    }
  }

  bool _isProtected(AssetEntity a) => a.isFavorite || _edited.contains(a.id);

  void _applyDefault() {
    final plan = planBulkCleanup(
      _all,
      minSimilarity: _auto,
      protectedIds: _edited,
    );
    _del = {
      for (final a in plan.assetsFor(widget.kinds ?? {...GroupKind.values}))
        a.id,
    };
  }

  PdqIndex? get _index => c.session?.pdqIndex;

  /// Gom lại nhóm trùng theo [_sim] mà không quét lại (dữ liệu PDQ nằm trong RAM).
  void _regroup() {
    if (_index == null) return;
    setState(() {
      _ver++;
      _regrouped = _computeRegrouped();
      _manual = null;
      // Gom lại thì các nhóm là nhóm khác: ảnh giữ do người dùng chọn và các
      // nhóm đã bỏ qua không còn ứng với nhóm nào nữa.
      _keeper.clear();
      _skipped.clear();
      _applyDefault();
    });
  }

  /// Nhóm trùng theo [_sim]; null khi đúng ngưỡng lúc quét (dùng kết quả gốc).
  List<DuplicateGroup>? _computeRegrouped() {
    final idx = _index;
    if (idx == null || (_sim - _scanSim).abs() < 0.05) return null;
    return regroupDuplicates(idx, hammingForSimilarity(_sim));
  }

  /// Chọn xóa mọi ảnh trừ ảnh giữ của từng nhóm trong tab đang xem.
  void _selectAllButKeeper() {
    _touched = true;
    setState(() {
      for (final g in _all) {
        if (!_inTab(g) || g.items.length < 2 || !_visible(g)) continue;
        _markGroup(g);
      }
    });
  }

  /// Chọn xoá mọi ảnh của [g] trừ ảnh đang giữ và ảnh được bảo vệ.
  void _markGroup(DuplicateGroup g) {
    if (_skipped.contains(_groupKey(g))) return;
    final keep = _keeperId(g);
    for (final e in g.items) {
      final id = e.asset.id;
      if (id == keep || _isProtected(e.asset) || !e.exact) {
        _del.remove(id);
      } else {
        _del.add(id);
      }
    }
  }

  /// Đặt [it] làm ảnh giữ của nhóm và chọn xoá phần còn lại.
  void _setKeeper(DuplicateGroup g, DuplicateItem it) {
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      _keeper[_groupKey(g)] = it.asset.id;
      _skipped.remove(_groupKey(g));
      _markGroup(g);
    });
    AppDock.say('Đã đặt làm ảnh giữ lại.');
  }

  void _selectGroup(DuplicateGroup g) {
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      _skipped.remove(_groupKey(g));
      _markGroup(g);
    });
  }

  /// Bỏ qua cả nhóm: thu gọn lại và bỏ mọi lựa chọn xoá trong đó.
  /// Danh sách nhóm trùng đang làm việc (đã áp gom lại và các lần gộp tay).
  List<DuplicateGroup> _dupWorking() => _manual ??= [
        for (final x
            in _regrouped ?? c.session?.groups ?? const <DuplicateGroup>[])
          if (x.kind == GroupKind.duplicate) x,
      ];

  /// Nhóm đứng ngay sau [g] trong danh sách trùng, null nếu không có.
  DuplicateGroup? _nextDupOf(DuplicateGroup g) {
    final list = _dupWorking();
    final i = list.indexWhere((x) => _groupKey(x) == _groupKey(g));
    return i < 0 || i + 1 >= list.length ? null : list[i + 1];
  }

  /// Gộp [g] với nhóm đứng ngay sau thành một nhóm. Dùng khi thuật toán tách một
  /// chuỗi chụp thành hai nhóm sát nhau.
  void _mergeWithNext(DuplicateGroup g) {
    final list = _dupWorking();
    final i = list.indexWhere((x) => _groupKey(x) == _groupKey(g));
    if (i < 0 || i + 1 >= list.length) return;
    final next = list[i + 1];
    final have = {for (final e in g.items) e.asset.id};
    final merged = DuplicateGroup([
      ...g.items,
      for (final e in next.items)
        if (have.add(e.asset.id)) e,
    ]);
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      final nk = _groupKey(next);
      _keeper.remove(nk);
      _skipped.remove(nk);
      list[i] = merged;
      list.removeAt(i + 1);
      _ver++;
    });
    AppDock.say('Đã gộp hai nhóm.');
  }

  void _skipGroup(DuplicateGroup g, bool skip) {
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      if (skip) {
        _skipped.add(_groupKey(g));
        for (final e in g.items) {
          _del.remove(e.asset.id);
        }
      } else {
        _skipped.remove(_groupKey(g));
      }
    });
  }

  void _openDetail(DuplicateGroup g, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'nodock'),
        builder: (_) => PhotoDetailPage(group: g, initialIndex: index),
      ),
    );
  }

  void _toggle(DuplicateGroup g, DuplicateItem it) {
    final id = it.asset.id;
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      if (_del.contains(id)) {
        _del.remove(id);
      } else {
        final left = g.items
            .where((e) => e.asset.id != id && !_del.contains(e.asset.id))
            .toList();
        if (left.isEmpty) {
          AppDock.say('Mỗi nhóm phải giữ lại ít nhất 1 ảnh.', warn: true);
          return;
        }
        _del.add(id);
        // Vừa đánh dấu xoá chính ảnh đang giữ: chuyển vai trò giữ sang ảnh còn
        // lại, nếu không thẻ sẽ hiện "Ảnh giữ lại" trên một ảnh sắp bị xoá.
        if (_keeperId(g) == id) {
          _keeper[_groupKey(g)] = left.first.asset.id;
        }
      }
    });
  }

  List<AssetEntity> get _selected => [
    for (final g in _all)
      if (_visible(g) && !_skipped.contains(_groupKey(g)))
        for (final it in g.items)
          if (_del.contains(it.asset.id)) it.asset,
  ];

  Future<void> _delete() async {
    final assets = _selected;
    if (assets.isEmpty) return;
    final nFav = assets.where((a) => a.isFavorite).length;
    final nEdited = assets.where((a) => _edited.contains(a.id)).length;
    // Cần tick xác nhận thêm khi xóa nhiều ảnh hoặc có ảnh yêu thích/đã chỉnh.
    final needTick = assets.length > _bigBatch || nFav > 0 || nEdited > 0;
    final warn = nFav > 0 || nEdited > 0
        ? '${[if (nFav > 0) '$nFav ảnh yêu thích', if (nEdited > 0) '$nEdited ảnh đã chỉnh sửa'].join(' · ')} nằm trong lựa chọn.'
        : null;
    final ok = await showConfirmDialog(
      context,
      title: assets.length > _bigBatch
          ? 'Xóa nhiều ảnh?'
          : 'Xóa ${assets.length} ảnh?',
      message: 'Mỗi nhóm giữ lại ít nhất 1 ảnh. $trashNote',
      warning: warn,
      tickLabel: needTick ? 'Tôi đã xem lại các ảnh này' : null,
      confirmLabel: 'Xóa ${assets.length} ảnh',
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'nodock'),
        builder: (_) => CleaningPage(controller: c, assets: assets),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = context.appColors;
    final t = PastelScheme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final groups = [
          for (final g in _all)
            if (g.items.length > 1 && _inTab(g) && _visible(g)) g,
        ];
        // Đếm theo số ảnh trong các nhóm.
        int photosOf(bool Function(DuplicateGroup) pick) => _all
            .where((g) => g.items.length > 1 && pick(g) && _visible(g))
            .fold(0, (n, g) => n + g.items.length);
        final nDup = photosOf(
          (g) => !_isShotGroup(g) && g.kind == GroupKind.duplicate,
        );
        final nSim = photosOf(
          (g) => !_isShotGroup(g) && g.kind == GroupKind.similar,
        );
        final nShot = photosOf(_isShotGroup);
        final n = _selected.length;
        // Số ảnh chọn xóa trong tab đang xem; phần còn lại nằm ở tab kia.
        final nHere = [
          for (final g in groups)
            for (final it in g.items)
              if (_del.contains(it.asset.id)) it,
        ].length;
        final showSimTab = c.shown.similar || c.canRefine || c.refining;
        return PageScaffold(
          key: ValueKey('$_tab-$_shots-$_ver'),
          title: 'Xem lại',
          subtitle: '',
          trailing: _filterButton(t),
          bottomBar: ActionBar(
            title: n == 0 ? 'Chưa chọn ảnh nào' : 'Xóa $n ảnh',
            subtitle: n == 0 ? '' : '$nHere ở đây · ${n - nHere} khác',
            button: 'Xóa',
            onPressed: n == 0 ? null : _delete,
          ),
          listCount: groups.length,
          listBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Reveal(index: i, child: _group(t, groups[i], i + 1, x)),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.shown.duplicates)
                    PillChip(
                      'Trùng $nDup',
                      on: !_shots && _tab == GroupKind.duplicate,
                      onTap: () => setState(() {
                        _shots = false;
                        _tab = GroupKind.duplicate;
                      }),
                    ),
                  if (showSimTab)
                    PillChip(
                      'Tương tự $nSim',
                      on: !_shots && _tab == GroupKind.similar,
                      onTap: () => setState(() {
                        _shots = false;
                        _tab = GroupKind.similar;
                      }),
                    ),
                  // Chỉ hiện khi thật sự có nhóm ảnh chụp màn hình.
                  if (nShot > 0)
                    PillChip(
                      'Màn hình $nShot',
                      icon: AppIcons.screenshotOutlined,
                      on: _shots,
                      onTap: () => setState(() => _shots = true),
                    ),
                ],
              ),
            ),
            if (!_shots && _tab == GroupKind.similar && c.canRefine)
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tìm thêm ảnh',
                        style: TextStyle(fontSize: 13, color: t.mute),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: c.startRefine,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.lilacBg2,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Chạy AI',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.lilacText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (c.refining)
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Đang phân tích AI'
                        '${c.refineProgress?.fraction == null ? '' : ' · ${(c.refineProgress!.fraction! * 100).round()}%'}',
                        style: TextStyle(fontSize: 13, color: t.mute),
                      ),
                    ),
                  ],
                ),
              ),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    _filter.isActive
                        ? 'Không có nhóm nào khớp bộ lọc.'
                        : 'Không có nhóm nào.',
                    style: TextStyle(color: t.mute),
                  ),
                ),
              ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }

  Future<void> _openFilter() async {
    final r = await showReviewFilterSheet(
      context,
      initial: _filter,
      tab: _tab,
      kinds: [
        if (c.shown.duplicates) GroupKind.duplicate,
        if (c.shown.similar) GroupKind.similar,
      ],
      sim: _sim,
      showSim: _index != null,
      tol: _tol,
      count: (f, tab, tol) {
        var g = 0, p = 0;
        for (final e in _allAt(tol)) {
          if (e.items.length > 1 &&
              !_isShotGroup(e) &&
              e.kind == tab &&
              f.passes(e, _edited)) {
            g++;
            p += e.items.length;
          }
        }
        return (g, p);
      },
    );
    if (r == null || !mounted) return;
    final simChanged = (r.sim - _sim).abs() > 0.01;
    final levelChanged = (r.tol - _tol).abs() > 0.001;
    setState(() {
      _filter = r.filter;
      _tab = r.tab;
      // Chọn tab trong bảng lọc nghĩa là quay về hai tab ảnh thường.
      _shots = false;
      _sim = r.sim;
      _tol = r.tol;
      _ver++;
    });
    if (simChanged) {
      _regroup();
    } else if (levelChanged) {
      setState(_applyDefault);
    }
    if (r.selection == 'auto') setState(_applyDefault);
    if (r.selection == 'all') setState(_selectAllButKeeper);
  }

  Widget _filterButton(PastelScheme t) {
    final n = _filter.activeCount;
    final bg = t.dark ? const Color(0xFFF2F2F2) : Pastel.ink;
    final fg = t.dark ? Pastel.ink : Colors.white;
    return GestureDetector(
      onTap: _openFilter,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.filter, size: 18, color: fg, accent: fg),
            const SizedBox(width: 6),
            Text(
              'Lọc',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: bg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bỏ chọn mọi ảnh trong một nhóm (không thu gọn nhóm lại).
  void _unselectGroup(DuplicateGroup g) {
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      for (final e in g.items) {
        _del.remove(e.asset.id);
      }
    });
  }

  /// Dung lượng một ảnh dưới dạng chữ ngắn; rỗng khi chưa đọc được.
  String _sizeText(String id) {
    final b = _sizes[id] ?? 0;
    return b <= 0 ? '' : _bytesText(b);
  }

  /// Dung lượng các ảnh đang chọn xóa trong một nhóm.
  int _freedOf(DuplicateGroup g) {
    var n = 0;
    for (final e in g.items) {
      if (_del.contains(e.asset.id)) n += _sizes[e.asset.id] ?? 0;
    }
    return n;
  }

  Widget _group(PastelScheme t, DuplicateGroup g, int no, AppColors x) {
    if (_skipped.contains(_groupKey(g))) return _skippedCard(t, g, no);
    final keepId = _keeperId(g);
    final keep = g.items.firstWhere(
      (e) => e.asset.id == keepId,
      orElse: () => g.items.first,
    );
    final others = [
      for (final e in g.items)
        if (e.asset.id != keep.asset.id) e,
    ];
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupHeader(t, g, no),
          const SizedBox(height: 12),
          if (others.length == 1) ...[
            // Nhóm hai ảnh: đặt cạnh nhau, bằng cỡ. Đây đúng là lúc người dùng so
            // sánh trực tiếp, nhét vào lưới ba cột chỉ làm ảnh nhỏ đi vô cớ.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _cell(t, g, keep, x, detail: true)),
                const SizedBox(width: 10),
                Expanded(child: _cell(t, g, others.first, x, detail: true)),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                'Giữ ảnh để chọn ảnh giữ.',
                style: TextStyle(fontSize: 11.5, color: t.mute),
              ),
            ),
          ] else ...[
            _keeperStrip(t, g, keep, x),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, cons) {
                final w = (cons.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final e in others)
                      SizedBox(width: w, child: _cell(t, g, e, x)),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          _groupActions(t, g),
        ],
      ),
    );
  }

  Widget _groupHeader(PastelScheme t, DuplicateGroup g, int no) {
    final del = g.items.where((e) => _del.contains(e.asset.id)).length;
    final freed = _freedOf(g);
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nhóm $no · ${g.items.length} ảnh',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: t.ink,
                  ),
                ),
                if (del > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    freed > 0 ? '$del ảnh · ${_bytesText(freed)}' : '$del ảnh',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.mute),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _openDetail(g, 0),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: AppIcon(
                AppIcons.infoOutline,
                label: 'Chi tiết nhóm',
                size: 18,
                color: t.mute,
                accent: t.mute,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _bytesText(int b) {
    if (b < 1000 * 1000 * 1000) {
      final mb = b / (1000 * 1000);
      return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} MB';
    }
    return '${(b / (1000 * 1000 * 1000)).toStringAsFixed(1).replaceAll('.', ',')} GB';
  }

  /// Ảnh đang giữ, cỡ lớn, kèm thông tin và nhắc cách đổi.
  Widget _keeperStrip(
    PastelScheme t,
    DuplicateGroup g,
    DuplicateItem keep,
    AppColors x,
  ) {
    final size = _sizeText(keep.asset.id);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, height: 96, child: _photo(t, g, keep, x)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                [
                  '${keep.asset.width}×${keep.asset.height}',
                  if (size.isNotEmpty) size,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: t.mute),
              ),
              const SizedBox(height: 6),
              Text(
                'Giữ ảnh khác để đổi ảnh giữ.',
                style: TextStyle(fontSize: 11.5, height: 1.35, color: t.mute),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupActions(PastelScheme t, DuplicateGroup g) {
    final keep = _keeperId(g);
    final left = g.items
        .where(
          (e) =>
              e.asset.id != keep &&
              !_isProtected(e.asset) &&
              !_del.contains(e.asset.id),
        )
        .length;
    // Wrap chứ không Row: nhãn dài ("Chọn 12 ảnh") cộng cỡ chữ lớn của hệ
    // thống là tràn ngang, và tràn ở đây thì cả thẻ nhóm hỏng.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (left > 0)
          _pill(
            t,
            AppIcons.deleteSweepOutlined,
            'Chọn $left ảnh',
            () => _selectGroup(g),
            solid: true,
          )
        else
          _pill(t, AppIcons.refreshRounded, 'Bỏ chọn', () => _unselectGroup(g)),
        if (_nextDupOf(g) != null)
          _pill(t, AppIcons.layersOutlined, 'Gộp nhóm kế',
              () => _mergeWithNext(g)),
        _pill(t, AppIcons.close, 'Ẩn nhóm', () => _skipGroup(g, true)),
      ],
    );
  }

  Widget _pill(
    PastelScheme t,
    AppIconData icon,
    String label,
    VoidCallback tap, {
    bool solid = false,
  }) {
    final bg = solid ? t.accent : t.chip;
    final fg = solid ? t.onAccent : t.ink;
    return GestureDetector(
      onTap: tap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 15, color: fg, accent: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nhóm đã bỏ qua: thu lại một dòng, còn nút hoàn tác.
  Widget _skippedCard(PastelScheme t, DuplicateGroup g, int no) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Nhóm $no · ${g.items.length} ảnh · đã bỏ qua',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: t.mute),
            ),
          ),
          const SizedBox(width: 8),
          _pill(
            t,
            AppIcons.refreshRounded,
            'Hoàn tác',
            () => _skipGroup(g, false),
          ),
        ],
      ),
    );
  }

  /// Một ảnh trong thẻ nhóm: ảnh vuông kèm chú thích dưới.
  Widget _cell(
    PastelScheme t,
    DuplicateGroup g,
    DuplicateItem it,
    AppColors x, {
    bool detail = false,
  }) {
    final size = _sizeText(it.asset.id);
    final caption = detail
        ? [
            '${it.asset.width}×${it.asset.height}',
            if (size.isNotEmpty) size,
          ].join(' · ')
        : size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 1, child: _photo(t, g, it, x)),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: t.mute),
            ),
          ),
      ],
    );
  }

  Widget _photo(
    PastelScheme t,
    DuplicateGroup g,
    DuplicateItem it,
    AppColors x,
  ) {
    final del = _del.contains(it.asset.id);
    final keeper = _keeperId(g) == it.asset.id;
    // Mỗi ô là một lớp riêng. Chạm một ảnh là chạy bốn hiệu ứng (phóng, phủ
    // tối, đổi nhãn); không tách lớp thì cả danh sách nhóm vẽ lại theo, và đó
    // là lúc cuộn giật nhất.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _toggle(g, it),
        onLongPress: () {
          if (keeper) {
            AppDock.say('Đây đã là ảnh giữ lại của nhóm.');
            return;
          }
          _setKeeper(g, it);
        },
        child: AnimatedScale(
          scale: del ? 0.94 : 1,
          duration: kMotionFast,
          curve: kMotionCurve,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'photo_${it.asset.id}',
                  child: AssetEntityImage(
                    it.asset,
                    isOriginal: false,
                    fit: BoxFit.cover,
                    thumbnailSize: const ThumbnailSize.square(320),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: del ? 1 : 0,
                    duration: kMotionFast,
                    child: Container(color: const Color(0x99111111)),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: AnimatedContainer(
                    duration: kMotionFast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: del
                          ? Semantic.danger
                          : (keeper
                                ? Pastel.ink
                                : Colors.white.withValues(alpha: 0.92)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AnimatedSwitcher(
                      duration: kMotionFast,
                      child: Row(
                        key: ValueKey('$del|$keeper'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            del
                                ? AppIcons.deleteOutline
                                : (keeper
                                      ? AppIcons.shieldOutlined
                                      : AppIcons.check),
                            size: 12,
                            color: del || keeper ? Colors.white : Pastel.ink,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            del ? 'Xóa' : (keeper ? 'Ảnh giữ' : 'Giữ'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: del || keeper ? Colors.white : Pastel.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (it.asset.isFavorite || _edited.contains(it.asset.id))
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC111111),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (it.asset.isFavorite)
                            const AppIcon(
                              AppIcons.heart,
                              size: 11,
                              color: Colors.white,
                            ),
                          if (it.asset.isFavorite &&
                              _edited.contains(it.asset.id))
                            const SizedBox(width: 3),
                          if (_edited.contains(it.asset.id))
                            const Text(
                              'Đã chỉnh',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (it.exact || it.similarity != null || it.modelCosine != null)
                  Positioned(
                    right: 6,
                    bottom: 6, // nhãn độ giống
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC111111),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Ảnh do AI tìm ra không được tự chọn xoá. Gắn dấu để
                          // người dùng hiểu vì sao nó không nằm trong lựa chọn sẵn,
                          // bằng biểu tượng thay vì thêm một dòng chữ nữa.
                          if (it.byModel) ...[
                            const AppIcon(
                              AppIcons.autoAwesomeOutlined,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            it.exact
                                ? 'Giống hệt'
                                : (it.similarity != null
                                      ? '${it.similarity!.round()}%'
                                      : cosineBand(it.modelCosine!)),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
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
}
