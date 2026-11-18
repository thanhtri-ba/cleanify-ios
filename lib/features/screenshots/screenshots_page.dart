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

/// Ảnh chụp màn hình: iOS gắn nhãn screenshot, Android lưu vào thư mục Screenshots,
/// nên không cần model. Người dùng
/// TỰ chọn ảnh cần xóa (không chọn sẵn), có "Chọn tất cả". Xóa đi qua [CleaningPage].
class ScreenshotsPage extends StatefulWidget {
  const ScreenshotsPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<ScreenshotsPage> createState() => _ScreenshotsPageState();
}

class _Shot {
  _Shot(this.asset, this.bytes);
  final AssetEntity asset;
  final int bytes;
}

class _ScreenshotsPageState extends State<ScreenshotsPage> {
  bool _loading = true;
  String? _error;
  int _done = 0;
  int _total = 0;
  final List<_Shot> _all = [];
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
      final ids = await edits.screenshotIds();
      if (mounted) setState(() => _total = ids.length);
      const chunk = 100;
      for (var s = 0; s < ids.length; s += chunk) {
        if (!mounted) return;
        final part =
            ids.sublist(s, s + chunk > ids.length ? ids.length : s + chunk);
        final assets =
            await Future.wait([for (final id in part) AssetEntity.fromId(id)]);
        final sizes = await edits.fileSizes(part);
        for (final a in assets) {
          if (a != null) _all.add(_Shot(a, sizes[a.id] ?? 0));
        }
        _done = _all.length;
        if (mounted) setState(() {});
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không đọc được ảnh chụp màn hình: $e';
        });
      }
    }
  }

  List<_Shot> get _selected => [
        for (final v in _all)
          if (_sel.contains(v.asset.id)) v
      ];

  static String _size(int b) => b >= 1000 * 1000 * 1000
      ? '${(b / 1e9).toStringAsFixed(2)} GB'
      : '${(b / 1e6).toStringAsFixed(b >= 10 * 1000 * 1000 ? 0 : 1)} MB';

  Future<void> _delete() async {
    final sel = _selected;
    if (sel.isEmpty) return;
    final bytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa ${sel.length} ảnh chụp màn hình?',
      message: 'Giải phóng ${_size(bytes)}. ${deleteNote('ảnh')}',
      confirmLabel: 'Xóa ${sel.length} ảnh',
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
    final sel = _selected;
    final selBytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final totalBytes = _all.fold<int>(0, (n, v) => n + v.bytes);
    final allOn = _all.isNotEmpty && _sel.length == _all.length;
    final ready = !_loading && _error == null && _all.isNotEmpty;

    Widget note(Widget child) => Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(child: child),
        );

    return PageScaffold(
      title: 'Ảnh chụp màn hình',
      subtitle: ready ? '${_all.length} ảnh · tổng ${_size(totalBytes)}' : null,
      bottomBar: ActionBar(
        title: sel.isEmpty ? 'Chọn ảnh' : 'Xóa ${sel.length} ảnh',
        subtitle: sel.isEmpty ? '' : _size(selBytes),
        button: 'Xóa',
        onPressed: sel.isEmpty ? null : _delete,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.62),
      listCount: ready ? _all.length : 0,
      listBuilder: (_, i) => _tile(t, _all[i]),
      children: [
        if (ready)
          Reveal(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(children: [
                PillChip(allOn ? 'Bỏ chọn' : 'Chọn tất cả',
                    on: allOn,
                    icon: AppIcons.check,
                    onTap: () => setState(() {
                          if (allOn) {
                            _sel.clear();
                          } else {
                            _sel
                              ..clear()
                              ..addAll(_all.map((v) => v.asset.id));
                          }
                        })),
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
        if (!_loading && _error == null && _all.isEmpty)
          note(Text('Không có ảnh chụp màn hình nào.',
              style: TextStyle(color: t.mute))),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _tile(PastelScheme t, _Shot v) {
    final on = _sel.contains(v.asset.id);
    return GestureDetector(
      onTap: () =>
          setState(() => on ? _sel.remove(v.asset.id) : _sel.add(v.asset.id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.all(on ? 3 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: on ? t.accent : Colors.transparent, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(on ? 16 : 18),
          child: Stack(fit: StackFit.expand, children: [
            AssetEntityImage(v.asset,
                isOriginal: false,
                fit: BoxFit.cover,
                thumbnailSize: const ThumbnailSize(300, 480)),
            if (on) Container(color: const Color(0x40000000)),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: on ? t.accent : const Color(0x80FFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5)),
                child: on
                    ? const AppIcon(AppIcons.check,
                        size: 14, color: Colors.white, accent: Colors.white)
                    : null,
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xCC111111),
                    borderRadius: BorderRadius.circular(9)),
                child: Text(_size(v.bytes),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
