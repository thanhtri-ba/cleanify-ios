
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/feature_prints.dart';
import '../../core/scanner/scan_diagnostics.dart';
import '../../core/scanner/split_diagnostic.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/app_dock.dart';
import '../shell/page_kit.dart';
import 'scan_controller.dart';

/// Số liệu đo của lần quét: vì sao mỗi ảnh được xếp vào nhóm đang xem.
///
/// Mỗi ảnh hiện khoảng cách PDQ, độ giống quy ra phần trăm, cosine của mô hình
/// (nếu có) và ngưỡng đang áp dụng. Người dùng chấm từng nhóm ĐÚNG hay SAI, và
/// trang tự tính precision = ✓ / (✓ + ✗) cho tab đó.
///
/// Đây là cách rẻ nhất để biết ngưỡng hiện tại có hợp thư viện của mình không.
/// Bộ công cụ đầy đủ nằm ở `tool/calibrate.py`, nhưng nó đòi xuất vài trăm ảnh
/// ra máy tính rồi gán nhãn; chấm ngay trong app thì chỉ tốn vài phút.
///
/// Số liệu chỉ nằm trong RAM và mất khi quét lại.
class ScanDiagPage extends StatefulWidget {
  const ScanDiagPage({super.key, required this.controller});
  final ScanController controller;

  @override
  State<ScanDiagPage> createState() => _ScanDiagPageState();
}

class _ScanDiagPageState extends State<ScanDiagPage> {
  ScanController get c => widget.controller;
  ScanDiagnostics? get diag => c.diag;

  /// Tab đang xem. Khớp với cách chia ở trang Xem lại.
  _DiagTab _tab = _DiagTab.duplicate;

  /// Khoảng cách Vision (feature print) của từng ảnh so với ảnh gốc nhóm, theo id.
  final Map<String, double> _visionDist = {};

  /// Ảnh đang chọn để chẩn đoán tách nhóm. Chạm ảnh để chọn hoặc bỏ chọn.
  final Set<String> _picked = <String>{};
  bool _visionBusy = false;

  static bool _isShot(DuplicateGroup g) =>
      isScreenshotAsset(g.items.first.asset);

  List<DuplicateGroup> _groupsOf(_DiagTab tab) {
    final all = c.session?.groups ?? const <DuplicateGroup>[];
    return [
      for (final g in all)
        if (g.items.length > 1)
          if (switch (tab) {
            _DiagTab.duplicate => !_isShot(g) && g.kind == GroupKind.duplicate,
            _DiagTab.similar => !_isShot(g) && g.kind == GroupKind.similar,
            _DiagTab.screenshot => _isShot(g),
          })
            g
    ];
  }

  /// Đo khoảng cách Vision cho tối đa 40 nhóm đang xem. Chỉ iOS.
  Future<void> _measureVision() async {
    if (_visionBusy || !FeaturePrints.supported) return;
    final groups = _groupsOf(_tab).take(40).toList();
    final ids = <String>{
      for (final g in groups)
        for (final it in g.items) it.asset.id,
    };
    setState(() => _visionBusy = true);
    try {
      final vecs = await FeaturePrints.of(ids.toList());
      final dist = <String, double>{};
      for (final g in groups) {
        final anchor = g.items.first.asset.id;
        final av = vecs[anchor];
        if (av == null) continue;
        for (final it in g.items) {
          final v = vecs[it.asset.id];
          if (v == null || it.asset.id == anchor) continue;
          dist[it.asset.id] = featureDistance(av, v);
        }
      }
      if (!mounted) return;
      setState(() {
        _visionDist
          ..clear()
          ..addAll(dist);
        _visionBusy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _visionBusy = false);
    }
  }

  void _grade(DuplicateGroup g, DiagVerdict v) {
    final d = diag;
    if (d == null) return;
    HapticFeedback.selectionClick();
    // Chấm lại đúng nhãn đang có thì bỏ nhãn: không cần nút "xoá chấm" riêng.
    setState(() => d.setVerdict(g, d.verdictOf(g) == v ? null : v));
  }

  Future<void> _export() async {
    final d = diag;
    if (d == null) return;
    try {
      final file = await d.writeCsv({
        for (final tab in _DiagTab.values) tab.label: _groupsOf(tab),
      });
      if (!mounted) return;
      AppDock.say('Đã lưu ${file.path.split('/').last}');
    } catch (e) {
      if (!mounted) return;
      AppDock.say('Không lưu được tệp.', warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final d = diag;
    if (d == null) {
      return PageScaffold(
        title: 'Số liệu đo',
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text('Hãy quét trước để có số liệu.',
                  style: TextStyle(color: t.mute)),
            ),
          ),
        ],
      );
    }
    final groups = _groupsOf(_tab);
    final stats = d.statsFor(groups);
    final p = stats.precision;
    return PageScaffold(
      title: 'Số liệu đo',
      subtitle: p == null
          ? 'Chấm vài nhóm để biết ngưỡng có hợp không'
          : 'Đúng ${stats.yes} · sai ${stats.no} · chuẩn xác '
              '${(p * 100).round()}%',
      bottomBar: ActionBar(
        title: '${groups.length} nhóm',
        subtitle: 'Đã chấm ${stats.graded}',
        button: 'Xuất CSV',
        onPressed: groups.isEmpty ? null : _export,
      ),
      listCount: groups.length,
      listBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _card(t, d, groups[i], i + 1),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final tab in _DiagTab.values)
              if (_groupsOf(tab).isNotEmpty || tab == _tab)
                PillChip('${tab.label} ${_groupsOf(tab).length}',
                    on: _tab == tab, onTap: () => setState(() => _tab = tab)),
            if (FeaturePrints.supported && groups.isNotEmpty)
              PillChip(_visionBusy ? 'Đang đo Vision…' : 'Đo Vision',
                  on: _visionDist.isNotEmpty, onTap: _measureVision),
            if (_picked.isNotEmpty)
              PillChip('Chẩn đoán ${_picked.length} ảnh',
                  on: _picked.length >= 2, onTap: _runSplit),
            if (_picked.isNotEmpty)
              PillChip('Bỏ chọn',
                  on: false, onTap: () => setState(() => _picked.clear())),
          ]),
        ),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child:
                  Text('Tab này không có nhóm nào.', style: TextStyle(color: t.mute)),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  void _togglePick(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  /// Chẩn đoán các ảnh đã chọn (chỉ đọc cache), rồi hiện bảng từng cặp.
  Future<void> _runSplit() async {
    final all = c.session?.groups ?? const <DuplicateGroup>[];
    final assets = <AssetEntity>[];
    final labels = <String>[];
    final groupLabels = <String?>[];
    final seen = <String>{};
    for (var gi = 0; gi < all.length; gi++) {
      for (final it in all[gi].items) {
        final id = it.asset.id;
        if (!_picked.contains(id) || !seen.add(id)) continue;
        assets.add(it.asset);
        labels.add('Ảnh ${assets.length}');
        groupLabels.add('Nhóm ${gi + 1}');
      }
    }
    if (assets.length < 2) return;
    final report = await SplitDiagnostic.run(
      assets: assets,
      labels: labels,
      groupLabels: groupLabels,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chẩn đoán tách nhóm'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(report,
                style: const TextStyle(fontSize: 12, height: 1.35)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _card(
      PastelScheme t, ScanDiagnostics d, DuplicateGroup g, int no) {
    final rows = {for (final r in d.rowsOf(g)) r.assetId: r};
    final anchor = g.items.first.asset;
    final verdict = d.verdictOf(g);
    String? threshold;
    for (final r in rows.values) {
      if (r.threshold.isNotEmpty) {
        threshold = r.threshold;
        break;
      }
    }
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Nhóm $no · ${g.items.length} ảnh',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: t.ink)),
          ),
          if (threshold != null)
            Text(threshold, style: TextStyle(fontSize: 11.5, color: t.mute)),
        ]),
        const SizedBox(height: 10),
        for (final it in g.items)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _togglePick(it.asset.id),
            child: _photoRow(t, it.asset, anchor, rows[it.asset.id],
                _visionDist[it.asset.id],
                picked: _picked.contains(it.asset.id)),
          ),
        const SizedBox(height: 10),
        // Chấm nhóm: nhóm này gom đúng, gom sai, hay không chắc.
        Row(children: [
          for (final v in DiagVerdict.values) ...[
            _verdictButton(t, v, verdict == v, () => _grade(g, v)),
            const SizedBox(width: 8),
          ],
        ]),
      ]),
    );
  }

  Widget _photoRow(PastelScheme t, AssetEntity a, AssetEntity anchor,
      DiagRow? r, double? vision, {bool picked = false}) {
    final isAnchor = a.id == anchor.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: AssetEntityImage(a,
                isOriginal: false,
                fit: BoxFit.cover,
                thumbnailSize: const ThumbnailSize.square(160)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isAnchor ? 'Ảnh gốc của nhóm' : _numbers(r, vision),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (!isAnchor && (r?.reason.isNotEmpty ?? false)) ...[
              const SizedBox(height: 2),
              Text(r!.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.3, color: t.mute)),
            ],
          ]),
        ),
        if (picked) ...[
          const SizedBox(width: 8),
          Icon(Icons.check_circle, size: 20, color: t.accent),
        ],
      ]),
    );
  }

  /// Các con số của một ảnh so với ảnh gốc, bỏ qua phần nào không đo được.
  String _numbers(DiagRow? r, double? vision) {
    final parts = <String>[
      if (vision != null) 'V ${vision.toStringAsFixed(2)}',
    ];
    if (r == null) return parts.isEmpty ? 'Không có số liệu' : parts.join(' · ');
    parts.addAll([
      if (r.hamming != null) 'H ${r.hamming}',
      if (r.pdqPercent != null) 'PDQ ${r.pdqPercent!.toStringAsFixed(1)}%',
      if (r.cosDino != null) 'cos ${r.cosDino!.toStringAsFixed(3)}',
      if (r.cosReid != null) 'reid ${r.cosReid!.toStringAsFixed(3)}',
    ]);
    return parts.isEmpty ? 'Không có số liệu' : parts.join(' · ');
  }

  Widget _verdictButton(
      PastelScheme t, DiagVerdict v, bool on, VoidCallback onTap) {
    final bg = on ? t.accent : t.chip;
    final fg = on ? t.onAccent : t.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(17)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(v.symbol,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          const SizedBox(width: 5),
          Text(v.label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}

enum _DiagTab {
  duplicate('Trùng'),
  similar('Tương tự'),
  screenshot('Màn hình');

  const _DiagTab(this.label);
  final String label;
}

extension on DiagVerdict {
  String get label => switch (this) {
        DiagVerdict.yes => 'Đúng',
        DiagVerdict.no => 'Sai',
        DiagVerdict.unsure => 'Chưa rõ',
      };
}
