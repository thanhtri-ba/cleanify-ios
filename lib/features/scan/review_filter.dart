import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/scanner/scan_session.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/page_kit.dart';

enum SizeBand { all, two, threeFour, fivePlus }

enum PhotoKindFilter { all, screenshot, live }

enum DateBand { all, last30, thisYear, older }

/// Bộ lọc chỉ để ẩn/hiện nhóm trong màn xem; không đổi kết quả quét và chỉ ảnh đang hiển
/// thị mới được tính khi xóa.
class ReviewFilter {
  const ReviewFilter({
    this.size = SizeBand.all,
    this.kind = PhotoKindFilter.all,
    this.date = DateBand.all,
    this.hideFavorites = false,
    this.hideEdited = false,
  });

  final SizeBand size;
  final PhotoKindFilter kind;
  final DateBand date;
  final bool hideFavorites;
  final bool hideEdited;

  int get activeCount =>
      (size != SizeBand.all ? 1 : 0) +
      (kind != PhotoKindFilter.all ? 1 : 0) +
      (date != DateBand.all ? 1 : 0) +
      (hideFavorites ? 1 : 0) +
      (hideEdited ? 1 : 0);

  bool get isActive => activeCount > 0;

  /// Nhãn ngắn của các bộ lọc đang bật, hiện thành chip cạnh nút Bộ lọc.
  List<String> get labels => [
    if (size != SizeBand.all)
      const {
        SizeBand.two: '2 ảnh',
        SizeBand.threeFour: '3–4 ảnh',
        SizeBand.fivePlus: 'Từ 5 ảnh',
      }[size]!,
    if (kind != PhotoKindFilter.all)
      kind == PhotoKindFilter.screenshot ? 'Màn hình' : 'Live Photo',
    if (date != DateBand.all)
      const {
        DateBand.last30: '30 ngày',
        DateBand.thisYear: 'Năm nay',
        DateBand.older: 'Cũ hơn 1 năm',
      }[date]!,
    if (hideFavorites) 'Ẩn yêu thích',
    if (hideEdited) 'Ẩn đã chỉnh',
  ];

  ReviewFilter copyWith({
    SizeBand? size,
    PhotoKindFilter? kind,
    DateBand? date,
    bool? hideFavorites,
    bool? hideEdited,
  }) => ReviewFilter(
    size: size ?? this.size,
    kind: kind ?? this.kind,
    date: date ?? this.date,
    hideFavorites: hideFavorites ?? this.hideFavorites,
    hideEdited: hideEdited ?? this.hideEdited,
  );

  static bool isScreenshot(AssetEntity a) => isScreenshotAsset(a);

  bool passes(DuplicateGroup g, Set<String> edited, {DateTime? now}) {
    final n = g.items.length;
    switch (size) {
      case SizeBand.all:
        break;
      case SizeBand.two:
        if (n != 2) return false;
      case SizeBand.threeFour:
        if (n < 3 || n > 4) return false;
      case SizeBand.fivePlus:
        if (n < 5) return false;
    }
    final assets = [for (final e in g.items) e.asset];
    if (hideFavorites && assets.any((a) => a.isFavorite)) return false;
    if (hideEdited && assets.any((a) => edited.contains(a.id))) return false;
    switch (kind) {
      case PhotoKindFilter.all:
        break;
      case PhotoKindFilter.screenshot:
        if (!assets.any(isScreenshot)) return false;
      case PhotoKindFilter.live:
        if (!assets.any((a) => a.isLivePhoto)) return false;
    }
    if (date != DateBand.all) {
      final t = now ?? DateTime.now();
      final newest = assets
          .map((a) => a.createDateTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      switch (date) {
        case DateBand.last30:
          if (newest.isBefore(t.subtract(const Duration(days: 30)))) {
            return false;
          }
        case DateBand.thisYear:
          if (newest.year != t.year) return false;
        case DateBand.older:
          if (!newest.isBefore(t.subtract(const Duration(days: 365)))) {
            return false;
          }
        case DateBand.all:
          break;
      }
    }
    return true;
  }
}

class ReviewFilterResult {
  const ReviewFilterResult(
    this.filter,
    this.tab,
    this.sim,
    this.tol, {
    this.selection = '',
  });
  final ReviewFilter filter;
  final GroupKind tab;
  final double sim;

  /// Độ lệch cho phép của ảnh tương tự: cosine tối thiểu 0,50 đến dưới 0,85.
  final double tol;
  final String selection;
}

/// Mở bảng lọc. [count] trả về (số nhóm, số ảnh) khớp bộ lọc và loại nhóm đang chỉnh.
/// [showSim] = false thì ẩn thanh độ giống (chỉ áp dụng cho nhóm trùng khi còn dữ liệu PDQ).
Future<ReviewFilterResult?> showReviewFilterSheet(
  BuildContext context, {
  required ReviewFilter initial,
  required GroupKind tab,
  required List<GroupKind> kinds,
  required double sim,
  required bool showSim,
  required double tol,
  required (int, int) Function(ReviewFilter, GroupKind, double) count,
}) {
  return showModalBottomSheet<ReviewFilterResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FilterSheet(
      initial: initial,
      tab: tab,
      kinds: kinds,
      sim: sim,
      showSim: showSim,
      tol: tol,
      count: count,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.tab,
    required this.kinds,
    required this.sim,
    required this.showSim,
    required this.tol,
    required this.count,
  });
  final ReviewFilter initial;
  final GroupKind tab;
  final List<GroupKind> kinds;
  final double sim;
  final bool showSim;
  final double tol;
  final (int, int) Function(ReviewFilter, GroupKind, double) count;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ReviewFilter f = widget.initial;
  late GroupKind tab = widget.tab;
  late double sim = widget.sim;
  late double tol = widget.tol;
  String selection = '';

  PastelScheme get p => PastelScheme.of(context);

  Widget _quickAction(String label, VoidCallback onTap) =>
      PillChip(label, onTap: onTap);

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: p.mute,
      ),
    ),
  );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: p.dark ? p.chip : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: p.line),
    ),
    child: child,
  );

  Widget _segmented() => SegmentedPills<GroupKind>(
    value: tab,
    items: [
      for (final k in widget.kinds)
        (k, k == GroupKind.duplicate ? 'Trùng khớp' : 'Giống nhau'),
    ],
    onChanged: (k) => setState(() => tab = k),
  );

  Widget _simCard() {
    final loose = sim < 84.0;
    return _card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Độ giống tối thiểu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              ),
              Text(
                '${sim.toStringAsFixed(1).replaceAll('.', ',')}%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: p.ink,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: p.accent,
              inactiveTrackColor: p.track,
              thumbColor: Colors.white,
              overlayColor: p.accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11,
                elevation: 4,
              ),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: sim,
              min: 73,
              max: 95,
              divisions: 44,
              onChanged: (v) => setState(() => sim = v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '73% · nhiều ảnh',
                style: TextStyle(fontSize: 12, color: p.mute),
              ),
              Text(
                '95% · chính xác',
                style: TextStyle(fontSize: 12, color: p.mute),
              ),
            ],
          ),
          if (loose)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Dễ gom nhầm ảnh khác nhau',
                style: TextStyle(fontSize: 12, color: p.amberSub),
              ),
            ),
        ],
      ),
    );
  }

  static const double _tolMin = 0.50;
  static const double _tolMax = 0.84;

  String _tolHint(double v) {
    if (v >= 0.80) return SimilarLevel.strict.hint;
    if (v >= 0.65) return SimilarLevel.normal.hint;
    return SimilarLevel.wide.hint;
  }

  /// Thanh kéo "Độ lệch cho phép" cho tab Giống nhau: từ 50% đến dưới 85%, áp dụng
  /// ngay không quét lại. Ba nút nhanh Chặt/Vừa/Rộng nhảy tới 80/65/50%.
  Widget _levelCard() {
    final pct = (tol * 100).round();
    return _card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Giống tối thiểu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: p.ink,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: p.accent,
              inactiveTrackColor: p.track,
              thumbColor: Colors.white,
              overlayColor: p.accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11,
                elevation: 4,
              ),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: (tol * 100).clamp(_tolMin * 100, _tolMax * 100),
              min: _tolMin * 100,
              max: _tolMax * 100,
              divisions: ((_tolMax - _tolMin) * 100).round(),
              onChanged: (v) => setState(() => tol = v / 100),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '50% · nhiều ảnh',
                style: TextStyle(fontSize: 12, color: p.mute),
              ),
              Text(
                '84% · gần như y hệt',
                style: TextStyle(fontSize: 12, color: p.mute),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final l in SimilarLevel.values) ...[
                if (l != SimilarLevel.values.first) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => tol = l.cosine),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (tol - l.cosine).abs() < 0.005
                            ? (p.dark ? const Color(0xFFF2F2F2) : Pastel.ink)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (tol - l.cosine).abs() < 0.005
                              ? Colors.transparent
                              : p.line,
                        ),
                      ),
                      child: Text(
                        '${l.label} ${l.percent}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (tol - l.cosine).abs() < 0.005
                              ? (p.dark ? Pastel.ink : Colors.white)
                              : p.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
            child: Text(
              _tolHint(tol),
              style: TextStyle(fontSize: 13, color: p.mute),
            ),
          ),
          if (tol < 0.58)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
              child: Text(
                'Dễ gom nhầm ảnh khác nhau',
                style: TextStyle(fontSize: 12, color: p.amberSub),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chips<T>(List<(T, String)> opts, T value, ValueChanged<T> onPick) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            PillChip(o.$2, on: o.$1 == value, onTap: () => onPick(o.$1)),
        ],
      );

  Widget _switch(
    String t,
    bool v,
    ValueChanged<bool> on, {
    bool last = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => on(!v),
    child: Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: p.ink,
              ),
            ),
          ),
          PastelToggle(value: v, onChanged: on),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final (groups, photos) = widget.count(f, tab, tol);
    final simChanged = widget.showSim && (sim - widget.sim).abs() > 0.01;
    final dirty =
        f.isActive ||
        simChanged ||
        tab != widget.tab ||
        (tol - kDefaultSimilarTol).abs() > 0.001;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: p.dark ? p.card : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(28),
        border: p.dark ? Border.all(color: p.glassBorder) : null,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: p.track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bộ lọc',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                        color: p.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: dirty
                        ? () => setState(() {
                            f = const ReviewFilter();
                            sim = kDefaultDupSim;
                            tol = kDefaultSimilarTol;
                          })
                        : null,
                    child: Text(
                      'Đặt lại',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: dirty ? p.ink : p.track,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.kinds.length > 1) ...[
                      _label('Loại nhóm'),
                      _segmented(),
                      const SizedBox(height: 2),
                    ],
                    _label('Chọn ảnh'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _quickAction(
                          'Chọn bản trùng hệt',
                          () => setState(() => selection = 'auto'),
                        ),
                        _quickAction(
                          'Chọn hết nhóm',
                          () => setState(() => selection = 'all'),
                        ),
                      ],
                    ),
                    if (widget.showSim && tab == GroupKind.duplicate) ...[
                      const SizedBox(height: 14),
                      _simCard(),
                    ],
                    if (tab == GroupKind.similar) ...[
                      _label('Độ lệch cho phép'),
                      _levelCard(),
                    ],
                    _label('Số ảnh trong nhóm'),
                    _chips(
                      const [
                        (SizeBand.all, 'Tất cả'),
                        (SizeBand.two, '2'),
                        (SizeBand.threeFour, '3–4'),
                        (SizeBand.fivePlus, '5+'),
                      ],
                      f.size,
                      (v) => setState(() => f = f.copyWith(size: v)),
                    ),
                    _label('Loại ảnh'),
                    _chips(
                      const [
                        (PhotoKindFilter.all, 'Tất cả'),
                        (PhotoKindFilter.screenshot, 'Ảnh chụp màn hình'),
                        (PhotoKindFilter.live, 'Live Photo'),
                      ],
                      f.kind,
                      (v) => setState(() => f = f.copyWith(kind: v)),
                    ),
                    _label('Thời gian chụp'),
                    _chips(
                      const [
                        (DateBand.all, 'Mọi lúc'),
                        (DateBand.last30, '30 ngày'),
                        (DateBand.thisYear, 'Năm nay'),
                        (DateBand.older, 'Cũ hơn 1 năm'),
                      ],
                      f.date,
                      (v) => setState(() => f = f.copyWith(date: v)),
                    ),
                    const SizedBox(height: 18),
                    _card(
                      child: Column(
                        children: [
                          _switch(
                            'Ẩn ảnh yêu thích',
                            f.hideFavorites,
                            (v) => setState(
                              () => f = f.copyWith(hideFavorites: v),
                            ),
                          ),
                          _switch(
                            'Ẩn ảnh đã chỉnh sửa',
                            f.hideEdited,
                            (v) =>
                                setState(() => f = f.copyWith(hideEdited: v)),
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                18 + (bottom > 0 ? bottom - 10 : 0),
              ),
              child: GestureDetector(
                onTap: () => Navigator.pop(
                  context,
                  ReviewFilterResult(f, tab, sim, tol, selection: selection),
                ),
                child: Container(
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.dark ? const Color(0xFFF2F2F2) : Pastel.ink,
                    borderRadius: BorderRadius.circular(29),
                  ),
                  child: Text(
                    simChanged ? 'Áp dụng' : 'Xem $groups nhóm · $photos ảnh',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: p.dark ? Pastel.ink : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
