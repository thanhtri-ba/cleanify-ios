import 'package:flutter/material.dart';
import '../shell/app_dock.dart';
import '../../theme/app_theme.dart';
import '../../theme/appearance.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import '../shell/page_kit.dart';
import 'package:photo_manager/photo_manager.dart';

import '../scan/scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';
import '../../core/platform/device_text.dart';
import '../../core/scanner/photo_store.dart';
import '../../core/scanner/scan_diagnostics.dart';
import '../scan/scan_diag_page.dart';

/// Cài đặt: trạng thái quyền ảnh (+ lối tắt sửa), xóa kết quả quét đang giữ trong
/// bộ nhớ, và cam kết riêng tư. App không lưu dữ liệu nên không có cài đặt tài khoản.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  PermissionState? _perm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
    if (mounted) setState(() => _perm = p);
  }

  String get _permText {
    switch (_perm) {
      case null:
        return 'Đang kiểm tra…';
      case PermissionState.authorized:
        return 'Đã cho phép truy cập tất cả ảnh';
      case PermissionState.limited:
        return 'Chỉ truy cập một phần ảnh — kết quả quét sẽ thiếu';
      default:
        return 'Chưa được cấp quyền truy cập ảnh';
    }
  }

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa kết quả quét?',
      message: 'Chỉ xóa kết quả quét. Ảnh trong thư viện không bị đụng tới.',
      confirmLabel: 'Xóa kết quả',
    );
    if (ok != true) return;
    await widget.controller.clearResults();
    await PhotoStore.clear();
    if (!mounted) return;
    AppDock.say('Đã xóa kết quả quét.');
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final limited = _perm == PermissionState.limited;
    final denied = _perm != null && !(_perm!.hasAccess);
    final warn = limited || denied;
    return PageScaffold(
      title: 'Cài đặt',
      children: [
        Reveal(
          index: 1,
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              colors: warn ? [t.amberBg, t.amberBg2] : [t.limeBg, t.limeBg2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBubble(
                      warn ? AppIcons.warningAmberRounded : AppIcons.lockOpen,
                      bg: Colors.white.withValues(alpha: t.dark ? 0.12 : 0.75),
                      fg: warn ? t.amberText : t.limeText,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quyền truy cập ảnh',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: warn ? t.amberText : t.limeText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _permText,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: warn ? t.amberSub : t.limeSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (limited || denied) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GestureDetector(
                        onTap: () => PhotoManager.openSetting(),
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: t.dark ? t.amberText : Pastel.ink,
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: Text(
                            'Cho phép tất cả ảnh',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.dark ? Pastel.ink : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (limited)
                        GestureDetector(
                          onTap: () => PhotoManager.presentLimited(),
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(
                                color: t.amberSub.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              'Chọn thêm ảnh',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: t.amberText,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Reveal(
          index: 2,
          child: GlassCard(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: Appearance.mode,
              builder: (_, m, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Giao diện',
                    style: TextStyle(fontSize: 11, color: t.mute),
                  ),
                  const SizedBox(height: 10),
                  SegmentedPills<ThemeMode>(
                    value: m,
                    items: const [
                      (ThemeMode.system, 'Tự động'),
                      (ThemeMode.light, 'Sáng'),
                      (ThemeMode.dark, 'Tối'),
                    ],
                    onChanged: Appearance.set,
                  ),
                ],
              ),
            ),
          ),
        ),
        Reveal(
          index: 3,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (_, __) => Column(
                children: [
                  ListRow(
                    first: true,
                    leading: IconBubble(
                      AppIcons.notificationsOutlined,
                      bg: t.limeBg2,
                      fg: t.limeText,
                    ),
                    title: 'Báo khi quét xong',
                    subtitle: 'Gửi thông báo khi bạn đã thoát app',
                    trailing: PastelToggle(
                      value: widget.controller.notifyWhenDone,
                      onChanged: widget.controller.setNotifyWhenDone,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: PhotoStore.enabled,
                    builder: (_, on, __) => ListRow(
                      leading: IconBubble(
                        AppIcons.schedule,
                        bg: t.blueBg2,
                        fg: t.blueText,
                      ),
                      title: 'Nhớ vân tay ảnh',
                      subtitle: on
                          ? 'Lần sau chỉ xử lý ảnh mới hoặc đã sửa'
                          : 'Tắt — lần sau tính lại toàn bộ từ đầu',
                      trailing: PastelToggle(
                        value: on,
                        onChanged: PhotoStore.setEnabled,
                      ),
                    ),
                  ),
                  ListRow(
                    leading: IconBubble(
                      AppIcons.shieldOutlined,
                      bg: t.lilacBg2,
                      fg: t.lilacText,
                    ),
                    title: 'Quyền riêng tư',
                    subtitle: 'Ảnh được quét ngay trên máy',
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _PrivacySheet(t: t),
                    ),
                    trailing: AppIcon(
                      AppIcons.chevronRight,
                      size: 18,
                      color: t.mute,
                      accent: t.mute,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Reveal(
          index: 4,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (_, __) => ListRow(
                first: true,
                leading: IconBubble(
                  AppIcons.deleteSweepOutlined,
                  bg: t.chip,
                  fg: t.ink,
                ),
                title: 'Xóa kết quả quét',
                subtitle: 'Không xóa ảnh trong máy',
                onTap: widget.controller.busy ? null : _clear,
              ),
            ),
          ),
        ),
        // Chỉ có ở bản debug hoặc khi build với --dart-define=SCAN_DIAG=true.
        if (scanDiagEnabled())
          Reveal(
            index: 5,
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListRow(
                first: true,
                leading: IconBubble(
                  AppIcons.pieChartOutline,
                  bg: t.chip,
                  fg: t.ink,
                ),
                title: 'Số liệu đo',
                subtitle: 'Vì sao mỗi ảnh được gom vào nhóm',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: 'nodock'),
                    builder: (_) => ScanDiagPage(controller: widget.controller),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Center(
            child: Text(
              'Cleanify · Quét ngoại tuyến',
              style: TextStyle(fontSize: 11, color: t.mute),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrivacySheet extends StatelessWidget {
  const _PrivacySheet({required this.t});
  final PastelScheme t;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    decoration: BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Riêng tư',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '• Quét hoàn toàn trên máy, không tải ảnh lên mạng.\n'
          '• Không lưu nhóm ảnh hay kết quả quét; chúng mất khi đóng app.\n'
          '• Chỉ xóa ảnh sau khi bạn xác nhận. $trashNote\n'
          '• Bật "Nhớ vân tay ảnh" thì app ghi thêm vân tay PDQ, SHA-256, chữ ký '
          'MediaStore và vector mô hình của từng ảnh vào một file trong bộ nhớ '
          'riêng của app, chỉ để lần quét sau bỏ qua ảnh chưa đổi. Đều là số một '
          'chiều, không dựng lại được ảnh. Tắt hoặc bấm "Xóa kết quả quét" là xóa hết.',
          style: TextStyle(fontSize: 14, height: 1.55, color: t.mute),
        ),
      ],
    ),
  );
}
