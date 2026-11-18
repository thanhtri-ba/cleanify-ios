import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/pixel_diff.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/app_icons.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/page_kit.dart';

/// Xem chi tiết một nhóm: vuốt hoặc chạm dải ảnh để chuyển ảnh, xem điểm giống với ảnh
/// giữ (đại diện) và, nếu người dùng muốn, so sánh điểm ảnh. Chỉ xem, không xóa.
class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage(
      {super.key, required this.group, this.initialIndex = 0});
  final DuplicateGroup group;
  final int initialIndex;
  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  late final PageController _pc =
      PageController(initialPage: widget.initialIndex);
  late int _i = widget.initialIndex;
  final Map<int, Future<PixelDiff>> _diffs = {};
  bool _showDiff = false;

  /// Đã từng bật: chỉ tính heatmap khi người dùng yêu cầu.
  bool _diffRequested = false;

  List<DuplicateItem> get _items => widget.group.items;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<PixelDiff> _diffOf(int index) => _diffs.putIfAbsent(index, () async {
        final a = await _items.first.asset
            .thumbnailDataWithSize(const ThumbnailSize.square(192));
        final b = await _items[index]
            .asset
            .thumbnailDataWithSize(const ThumbnailSize.square(192));
        if (a == null || b == null) {
          throw StateError('Không đọc được ảnh để so sánh');
        }
        return compute(computePixelDiff, [a, b]);
      });

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _pct(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final it = _items[_i];
    final isRep = _i == 0;
    final pad = MediaQuery.paddingOf(context);
    final kind =
        widget.group.kind == GroupKind.duplicate ? 'trùng' : 'tương tự';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.page,
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 24),
          children: [
            Row(children: [
              RoundIconButton(AppIcons.arrowBackIosNewRounded,
                  label: 'Quay lại', onTap: () => Navigator.of(context).pop()),
              Expanded(
                child: Column(children: [
                  Text('Chi tiết ảnh',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                          color: t.ink)),
                  Text('Nhóm $kind · ${_items.length} ảnh',
                      style: TextStyle(fontSize: 11, color: t.mute)),
                ]),
              ),
              const SizedBox(width: 44),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: math.min(MediaQuery.sizeOf(context).height * 0.4, 360),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(
                    color: t.chip,
                    child: PageView.builder(
                      controller: _pc,
                      itemCount: _items.length,
                      onPageChanged: (v) => setState(() => _i = v),
                      itemBuilder: (_, k) => InteractiveViewer(
                        child: Stack(fit: StackFit.expand, children: [
                          Hero(
                            tag: 'photo_${_items[k].asset.id}',
                            child: AssetEntityImage(_items[k].asset,
                                isOriginal: false,
                                fit: BoxFit.contain,
                                thumbnailSize:
                                    const ThumbnailSize.square(1080)),
                          ),
                          if (_diffRequested && k != 0)
                            AnimatedOpacity(
                              opacity: _showDiff ? 1 : 0,
                              duration: const Duration(milliseconds: 250),
                              child: _heatmap(k),
                            ),
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: _pill(t, isRep ? 'Giữ lại' : 'So sánh',
                        bg: isRep
                            ? t.chartA.withValues(alpha: 0.9)
                            : Colors.black54,
                        fg: isRep ? Colors.black : Colors.white),
                  ),
                  Positioned(
                    right: 14,
                    top: 14,
                    child: _pill(t, '${_i + 1} / ${_items.length}',
                        bg: Colors.black54, fg: Colors.white),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            _thumbStrip(t),
            if (isRep)
              GlassCard(
                child: Text(
                    'Ảnh đề xuất giữ (độ phân giải cao nhất, cũ nhất). Các ảnh còn lại được so với ảnh này.',
                    style: TextStyle(fontSize: 13, height: 1.45, color: t.ink)),
              )
            else ...[
              _scoreCard(t, it),
              _diffToggleCard(t),
            ],
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                _kv(t, 'Ngày chụp', _date(it.asset.createDateTime),
                    first: true),
                _kv(t, 'Kích thước', '${it.asset.width} × ${it.asset.height}'),
                if (it.asset.isFavorite) _kv(t, 'Yêu thích', 'Có'),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(PastelScheme t, String text,
          {required Color bg, required Color fg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _kv(PastelScheme t, String k, String v, {bool first = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: first
            ? null
            : BoxDecoration(border: Border(top: BorderSide(color: t.line))),
        child: Row(children: [
          Text(k, style: TextStyle(fontSize: 13, color: t.mute)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: t.ink)),
          ),
        ]),
      );

  /// Dải ảnh nhỏ của nhóm: chạm để nhảy tới ảnh đó, ảnh đang xem có viền đậm.
  Widget _thumbStrip(PastelScheme t) => SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, k) => Semantics(
            button: true,
            selected: k == _i,
            label: k == 0 ? 'Ảnh giữ' : 'Ảnh ${k + 1}',
            child: GestureDetector(
              onTap: () => _pc.animateToPage(k,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 54,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: k == _i ? t.ink : Colors.transparent, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Opacity(
                    opacity: k == _i ? 1 : 0.65,
                    child: AssetEntityImage(_items[k].asset,
                        isOriginal: false,
                        fit: BoxFit.cover,
                        thumbnailSize: const ThumbnailSize.square(160)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// Thẻ điểm giống với ảnh giữ: vòng điểm + nhãn mức. Ảnh nhóm trùng theo PDQ hiện %
  /// PDQ, ảnh nhóm theo AI hiện cosine thật.
  Widget _scoreCard(PastelScheme t, DuplicateItem it) {
    if (it.exact) {
      return GlassCard(
        child: Row(children: [
          Expanded(
            child: Text('Giống hệt từng byte (cùng SHA-256)',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: t.ink)),
          ),
        ]),
      );
    }
    final s = it.similarity;
    final c = it.modelCosine;
    double? value;
    String center, caption, band, detail;
    if (c != null) {
      value = c.clamp(0.0, 1.0);
      center = c.toStringAsFixed(2).replaceAll('.', ',');
      caption = 'Cosine AI';
      band = cosineBand(c);
      detail =
          'Mức Vừa cần từ ${SimilarLevel.normal.cosine.toStringAsFixed(2).replaceAll('.', ',')}';
    } else if (s != null) {
      value = (s / 100).clamp(0.0, 1.0);
      center = '${s.round()}%';
      caption = 'PDQ';
      band = cosineBand(s / 100);
      final h = (256 * (1 - s / 100)).round();
      detail = 'Giống ${_pct(s)}% · lệch $h/256 bit';
    } else {
      return GlassCard(
        child: Text('Không có điểm số (nhóm theo cách khác)',
            style: TextStyle(fontSize: 13, color: t.mute)),
      );
    }
    final col =
        value >= 0.85 ? t.chartA : (value >= 0.65 ? t.chartB : t.chartC);
    return GlassCard(
      child: Row(children: [
        SizedBox(
          width: 82,
          height: 82,
          child: CustomPaint(
            painter: _GaugePainter(value, col, t.track),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.3,
                        color: t.ink)),
                Text(caption, style: TextStyle(fontSize: 9.5, color: t.mute)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: col.withValues(alpha: t.dark ? 0.25 : 0.2),
                  borderRadius: BorderRadius.circular(99)),
              child: Text(band,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: t.ink)),
            ),
            const SizedBox(height: 6),
            Text(detail,
                style: TextStyle(fontSize: 12, height: 1.4, color: t.mute)),
          ]),
        ),
      ]),
    );
  }

  Widget _diffToggleCard(PastelScheme t) => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('So sánh điểm ảnh',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: t.ink)),
                    Text('Vùng sáng là chỗ khác ảnh giữ',
                        style: TextStyle(fontSize: 11, color: t.mute)),
                  ]),
            ),
            PastelToggle(
              value: _showDiff,
              onChanged: (v) => setState(() {
                _showDiff = v;
                if (v) _diffRequested = true;
              }),
            ),
          ]),
          if (_showDiff) _diffBody(t, _i),
        ]),
      );

  Widget _heatmap(int k) => FutureBuilder<PixelDiff>(
        future: _diffOf(k),
        builder: (_, snap) => snap.hasData
            ? IgnorePointer(
                child: Image.memory(snap.data!.heatmapPng,
                    fit: BoxFit.fill, filterQuality: FilterQuality.low))
            : const SizedBox.shrink(),
      );

  Widget _bar(PastelScheme t, double pct, Color col) => Container(
        height: 6,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
            color: t.mute.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(9)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (pct / 100).clamp(0.0, 1.0),
            child: Container(
                decoration: BoxDecoration(
                    color: col, borderRadius: BorderRadius.circular(9))),
          ),
        ),
      );

  Widget _diffBody(PastelScheme t, int k) => FutureBuilder<PixelDiff>(
        future: _diffOf(k),
        builder: (_, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Không so sánh được hai ảnh này.',
                  style: TextStyle(fontSize: 13, color: t.mute)),
            );
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final d = snap.data!;
          final far = d.differentPercent > 50;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CountUp(
                  value: d.samePercent,
                  decimals: 1,
                  builder: (v) => _scoreRow(t, 'Điểm giống', '$v%')),
              _bar(t, d.samePercent, t.chartA),
              const SizedBox(height: 10),
              CountUp(
                  value: d.differentPercent,
                  decimals: 1,
                  builder: (v) => _scoreRow(t, 'Điểm khác', '$v%')),
              _bar(t, d.differentPercent, t.chartC),
              const SizedBox(height: 10),
              Text(
                  far
                      ? 'Khác trên 50%: ảnh này không được tính là tương tự khi quét. '
                          'Ảnh lệch khung sẽ báo khác nhiều.'
                      : 'So sánh trên bản thu nhỏ, chỉ mang tính tham khảo. '
                          'Ảnh khác trên 50% không được tính là tương tự.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: far ? FontWeight.w600 : FontWeight.w400,
                      color: far ? t.ink : t.mute)),
            ]),
          );
        },
      );

  Widget _scoreRow(PastelScheme t, String k, String v) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: TextStyle(fontSize: 13, color: t.mute)),
        Text(v,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: t.ink)),
      ]);
}

/// Vòng điểm: nền [track], cung [color] chiếm [v] (0..1) bắt đầu từ đỉnh.
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.v, this.color, this.track);
  final double v;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    const w = 8.0;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, p);
    if (v > 0) {
      canvas.drawArc(
          rect, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.v != v || o.color != color || o.track != track;
}
