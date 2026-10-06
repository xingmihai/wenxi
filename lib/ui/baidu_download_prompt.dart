import 'package:flutter/material.dart';
import '../app_services.dart';
import '../domain/models.dart';
import 'common.dart';

/// Confirm at the user's download action, before collecting or preparing files.
/// Playback and background retries must not ask for this confirmation.
Future<bool> confirmBaiduDownload(
  BuildContext context,
  AppServices services,
  CloudPlatform? platform,
) async {
  if (!context.mounted) return false;
  if (platform != CloudPlatform.baidu ||
      services.settings.hideBaiduDownloadNotice) {
    return true;
  }
  // null cancels; false downloads once; true downloads and remembers the choice.
  final hide = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const ValueKey('baidu-download-notice'),
      scrollable: true,
      title: const Text('百度网盘下载提示'),
      content: const Text(
        '普通非会员账号下载文件时，300 MB 以下不限速，超过 300 MB 会限速。',
        style: TextStyle(fontSize: 14, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('不再显示'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('继续下载'),
        ),
      ],
    ),
  );
  if (hide == null || !context.mounted) return false;
  if (hide) {
    try {
      await services.updateSettings({'hideBaiduDownloadNotice': true});
    } catch (error) {
      if (context.mounted) message(context, errorText(error));
    }
  }
  return context.mounted;
}
