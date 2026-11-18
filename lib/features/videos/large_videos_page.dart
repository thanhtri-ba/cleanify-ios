import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/page_kit.dart';
import '../scan/cleaning_page.dart';
import '../scan/scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';
import '../../core/platform/device_text.dart';

/// Video dung lượng lớn: liệt kê video theo dung lượng giảm dần, lọc theo ngưỡng,
/// người dùng TỰ chọn video cần xóa (không có gì được chọn sẵn). Dung lượng đọc từ
/// metadata của hệ điều hành nên không tải video từ iCloud. Xóa đi qua [CleaningPage].
class LargeVideosPage extends StatefulWidget {
  const LargeVideosPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<LargeVideosPage> createState() => _LargeVideosPageState();
}

class _Vid {
  _Vid(this.asset, this.bytes);
  final AssetEntity asset;
  final int bytes;
}

class _LargeVideosPageState extends State<LargeVideosPage> {
  static const _thresholdsMb = [50, 150, 500];

  bool _loading = true;
  String? _error;
  int _done = 0;
  int _total = 0;
  int _minMb = 150;
  final List<_Vid> _all = [];
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final edits = PhotoEdits();
    if (!edits.supported) {
      setState(() {
        _loading = false;
        _error = 'Tính năng này chỉ có trên iPhone và Android.';
      });
      return;
    }
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) {
        setState(() {
          _loading = false;
          _error = 'Cần cấp quyền truy cập thư viện ảnh.';
        });
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
          onlyAll: true, type: RequestType.video);
      if (paths.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final path = paths.first;
      final total = await path.assetCountAsync;
      if (mounted) setState(() => _total = total);
      const chunk = 200;
      for (var s = 0; s < total; s += chunk) {
        if (!mounted) return;
        final list = await path.getAssetListRange(
            start: s, end: s + chunk > total ? total : s + chunk);
        final sizes = await edits.fileSizes([for (final a in list) a.id]);
        for (final a in list) {
          _all.add(_Vid(a, sizes[a.id] ?? 0));
        }
        _done = _all.length;
        if (mounted) setState(() {});
      }
      _all.sort((a, b) => b.bytes.compareTo(a.bytes));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không đọc được danh sách video: $e';
        });
      }
    }
  }

  List<_Vid> get _shown => [
        for (final v in _all)
          if (v.bytes >= _minMb * 1000 * 1000) v
      ];

  List<_Vid> get _selected => [
        for (final v in _all)
          if (_sel.contains(v.asset.id)) v
      ];

  static String _size(int b) => b >= 1000 * 1000 * 1000
      ? '${(b / 1e9).toStringAsFixed(2)} GB'
      : '${(b / 1e6).round()} MB';

  static String _dur(int sec) {
    final m = (sec ~/ 60).toString();
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _delete() async {
    final sel = _selected;
    if (sel.isEmpty) return;
    final bytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa ${sel.length} video?',
      message: 'Giải phóng ${_size(bytes)}. ${deleteNote('video')}',
      confirmLabel: 'Xóa ${sel.length} video',
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'nodock'),
        builder: (_) => CleaningPage(
            controller: widget.controller,
            assets: [for (final v in sel) v.asset])));
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final shown = _shown;
    final sel = _selected;
    final selBytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final totalBytes = shown.fold<int>(0, (n, v) => n + v.bytes);
    final ready = !_loading && _error == null;

    Widget note(Widget child) => Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(child: child),
        );

    return PageScaffold(
      title: 'Video lớn',
      subtitle:
          ready ? '${shown.length} video · tổng ${_size(totalBytes)}' : null,
      bottomBar: ActionBar(
        title: sel.isEmpty ? 'Chọn video' : 'Xóa ${sel.length} video',
        subtitle: sel.isEmpty ? '' : _size(selBytes),
        button: 'Xóa',
        onPressed: sel.isEmpty ? null : _delete,
      ),
      listCount: ready ? shown.length : 0,
      listBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _row(t, shown[i]),
      ),
      children: [
        Reveal(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(children: [
              for (final th in _thresholdsMb) ...[
                PillChip('>$th MB',
                    on: _minMb == th, onTap: () => setState(() => _minMb = th)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
        ),
        if (_error != null)
          note(Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.mute, height: 1.5))),
        if (_loading)
          note(Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: t.ink),
            const SizedBox(height: 14),
            Text('Đang tải… $_done/$_total',
                style: TextStyle(fontSize: 13, color: t.mute)),
          ])),
        if (ready && shown.isEmpty)
          note(Text('Không có video nào lớn hơn $_minMb MB.',
              style: TextStyle(color: t.mute))),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _row(PastelScheme t, _Vid v) {
    final on = _sel.contains(v.asset.id);
    final d = v.asset.createDateTime;
    return GestureDetector(
      onTap: () =>
          setState(() => on ? _sel.remove(v.asset.id) : _sel.add(v.asset.id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: on ? t.limeBg : t.glass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: on ? t.accent : t.glassBorder, width: on ? 1.5 : 1),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(fit: StackFit.expand, children: [
                AssetEntityImage(v.asset,
                    isOriginal: false,
                    fit: BoxFit.cover,
                    thumbnailSize: const ThumbnailSize.square(240)),
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xCC111111),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_dur(v.asset.duration),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_size(v.bytes),
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: on ? t.limeText : t.ink)),
              const SizedBox(height: 2),
              Text(
                  '${d.day}/${d.month}/${d.year} · ${v.asset.width}×${v.asset.height}',
                  style:
                      TextStyle(fontSize: 12, color: on ? t.limeSub : t.mute)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: on ? t.accent : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: on ? t.accent : t.track, width: 2),
            ),
            child: on
                ? const AppIcon(AppIcons.check,
                    size: 16, color: Colors.white, accent: Colors.white)
                : null,
          ),
        ]),
      ),
    );
  }
}
