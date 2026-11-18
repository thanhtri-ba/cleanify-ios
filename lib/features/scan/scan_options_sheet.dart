import 'package:flutter/material.dart';

import '../../core/scanner/scan_mode.dart';
import '../../theme/app_theme.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/page_kit.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Hộp chọn kiểu quét trước khi bắt đầu. Trả về null nếu người dùng đóng hộp.
/// [photos] là số ảnh trong thư viện, dùng để ước tính thời gian (0 = không biết).
Future<ScanMode?> showScanOptions(BuildContext context, {required int photos}) {
  return showModalBottomSheet<ScanMode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScanOptions(photos: photos),
  );
}

class _ScanOptions extends StatefulWidget {
  const _ScanOptions({required this.photos});
  final int photos;
  @override
  State<_ScanOptions> createState() => _ScanOptionsState();
}

class _ScanOptionsState extends State<_ScanOptions> {
  bool _dup = true;
  bool _sim = false;

  ScanMode get _mode => ScanMode(duplicates: _dup, similar: _sim);

  /// "~45 giây" cho một chế độ; rỗng khi chưa biết số ảnh.
  String _short(Duration d) => widget.photos <= 0 ? '' : '~${_fmt(d)}';

  /// "~45 giây", "~2 phút", dễ đọc hơn mm:ss cho phần ước tính.
  String _fmt(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds < 5 ? 5 : d.inSeconds} giây';
    final m = (d.inSeconds / 60).round();
    return '$m phút';
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: t.dark ? t.card : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(28),
        border: t.dark ? Border.all(color: t.glassBorder) : null,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + (bottom > 0 ? bottom - 10 : 0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: t.track,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Chọn chế độ quét',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.4,
                    color: t.ink,
                  ),
                ),
              ),
              if (widget.photos > 0)
                Text(
                  '${widget.photos} ảnh',
                  style: TextStyle(fontSize: 13, color: t.mute),
                ),
            ],
          ),
          const SizedBox(height: 2),
          _option(
            t: t,
            on: _dup,
            icon: AppIcons.copyOutlined,
            bg: t.limeBg2,
            fg: t.limeText,
            onBg: t.limeBg,
            title: 'Ảnh trùng',
            time: _short(estimateDuplicates(widget.photos)),
            onTap: () => setState(() => _dup = !_dup),
          ),
          _option(
            t: t,
            on: _sim,
            icon: AppIcons.photoOutlined,
            bg: t.lilacBg2,
            fg: t.lilacText,
            onBg: t.lilacBg,
            title: 'Ảnh tương tự',
            time: _short(estimateSimilar(widget.photos)),
            onTap: () => setState(() => _sim = !_sim),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Mục tiêu tối đa khoảng 2 phút. Máy chậm có thể dừng trước khi xử lý hết ảnh; kết quả sẽ ghi rõ phần còn thiếu.',
              style: TextStyle(fontSize: 12, height: 1.35, color: t.mute),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _mode.any ? () => Navigator.pop(context, _mode) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _mode.any
                    ? (t.dark ? const Color(0xFFF2F2F2) : Pastel.ink)
                    : t.chip,
                borderRadius: BorderRadius.circular(29),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.scan,
                    size: 20,
                    color: _mode.any
                        ? (t.dark ? Pastel.ink : Colors.white)
                        : t.mute,
                    accent: _mode.any
                        ? (t.dark ? Pastel.ink : Colors.white)
                        : t.mute,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Bắt đầu quét',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _mode.any
                          ? (t.dark ? Pastel.ink : Colors.white)
                          : t.mute,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required PastelScheme t,
    required bool on,
    required AppIconData icon,
    required Color bg,
    required Color fg,
    required Color onBg,
    required String title,
    required String time,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on ? onBg : (t.dark ? t.chip : Colors.white),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? t.accent : t.line,
              width: on ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              IconBubble(icon, bg: bg, fg: fg, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(time, style: TextStyle(fontSize: 13, color: t.mute)),
              ],
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: on ? t.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: on ? t.accent : t.track, width: 2),
                ),
                child: on
                    ? const AppIcon(
                        AppIcons.check,
                        size: 15,
                        color: Colors.white,
                        accent: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
