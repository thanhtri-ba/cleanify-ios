
import 'package:flutter/material.dart';

import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../../theme/tick_dial.dart';
import '../shell/page_kit.dart';
import '../../core/platform/device_text.dart';

/// Màn "Bộ nhớ": đồng hồ vạch dung lượng máy (số liệu do Home đọc từ hệ điều hành) và lối tắt
/// tới các công cụ dọn dẹp. Không tự đọc dữ liệu nên không tốn thêm quyền hay thời gian.
class StoragePage extends StatelessWidget {
  const StoragePage({
    super.key,
    required this.total,
    required this.free,
    required this.photoBytes,
    required this.videoBytes,
    required this.photos,
    required this.videos,
    required this.onLargeVideos,
    required this.onScreenshots,
  });

  final int? total, free, photoBytes, videoBytes, photos, videos;
  final VoidCallback onLargeVideos, onScreenshots;

  static String _gb(int? b) => b == null
      ? '—'
      : '${(b / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final used = total != null && free != null ? total! - free! : null;
    final frac = total == null || total == 0 || used == null
        ? 0.0
        : (used / total!).clamp(0.0, 1.0);
    double share(int? b) =>
        (b == null || total == null || total == 0) ? 0 : b / total!;
    final known = photoBytes != null && videoBytes != null;
    final other = used != null && known
        ? (used - photoBytes! - videoBytes!).clamp(0, used).toInt()
        : null;
    final pf = share(photoBytes);
    final vf = share(videoBytes);
    final parts = known
        ? <(double, Color)>[
            (pf, t.chartA),
            (vf, t.chartB),
            ((frac - pf - vf).clamp(0.0, 1.0), t.chartC),
          ]
        : <(double, Color)>[(frac, t.chartA)];
    final calm = reduceMotion(context);
    double barOf(int? b) =>
        (b == null || used == null || used == 0) ? 0 : b / used;

    return PageScaffold(
      title: 'Bộ nhớ',
      subtitle: deviceName,
      children: [
        Reveal(
          index: 1,
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration:
                    calm ? Duration.zero : const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => TickRing(
                  parts: parts,
                  reveal: v,
                  size: 210,
                  track: t.track,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${(frac * 100 * v).round()}',
                          style: TextStyle(
                              fontSize: 54,
                              height: 1.12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -1.6,
                              color: t.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      TextSpan(
                          text: '%',
                          style: TextStyle(fontSize: 22, color: t.mute)),
                    ])),
                    const SizedBox(height: 6),
                    Text(
                        used == null
                            ? 'Dung lượng $deviceName'
                            : '${_gb(used)} / ${_gb(total)} đã dùng',
                        style: TextStyle(fontSize: 12, color: t.mute)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        Reveal(
          index: 2,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              ListRow(
                first: true,
                leading: IconBubble(AppIcons.photoOutlined,
                    bg: t.limeBg2, fg: t.limeText),
                title: 'Ảnh',
                subtitle: photos == null ? null : '$photos ảnh',
                bar: (barOf(photoBytes), t.chartA),
                trailing: Text(_gb(photoBytes),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
              ),
              ListRow(
                leading: IconBubble(AppIcons.videocamOutlined,
                    bg: t.blueBg2, fg: t.blueText),
                title: 'Video',
                subtitle: videos == null ? null : '$videos video',
                bar: (barOf(videoBytes), t.chartB),
                trailing: Text(_gb(videoBytes),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
              ),
              ListRow(
                leading: IconBubble(AppIcons.layersOutlined,
                    bg: t.amberBg2, fg: t.amberText),
                title: 'Khác',
                subtitle: 'Ứng dụng, hệ thống',
                bar: (barOf(other), t.chartC),
                trailing: Text(_gb(other),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
              ),
            ]),
          ),
        ),
        Reveal(
          index: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(children: [
              Expanded(
                child: _Shortcut(
                    icon: AppIcons.videocamOutlined,
                    title: 'Video lớn',
                    sub: 'Chiếm nhiều dung lượng',
                    bg: t.blueBg,
                    bg2: t.blueBg2,
                    fg: t.blueText,
                    subC: t.blueSub,
                    onTap: onLargeVideos),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Shortcut(
                    icon: AppIcons.screenshotOutlined,
                    title: 'Màn hình',
                    sub: 'Ảnh chụp',
                    bg: t.amberBg,
                    bg2: t.amberBg2,
                    fg: t.amberText,
                    subC: t.amberSub,
                    onTap: onScreenshots),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.sub,
    required this.bg,
    required this.bg2,
    required this.fg,
    required this.subC,
    required this.onTap,
  });
  final AppIconData icon;
  final String title, sub;
  final Color bg, bg2, fg, subC;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: PressScale(
          child: Container(
            height: 116,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                  colors: [bg, bg2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppIcon(icon, size: 24, color: fg, accent: fg),
              const Spacer(),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: fg)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: subC)),
            ]),
          ),
        ),
      );
}
