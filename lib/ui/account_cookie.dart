import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/state_store.dart';
import '../domain/auth.dart';
import '../domain/models.dart';
import 'common.dart';

Future<void> copyCloudAccountCookie(
  BuildContext context,
  Vault vault,
  CloudPlatform platform,
  String? accountId,
) async {
  // Resolve at click time, using the chosen account even if the active account
  // changed while its menu was open. Never log the value or clipboard errors.
  final credential = vault.credentialFor(platform, accountId);
  if (credential == null) {
    message(context, '此账号未登录或已移除，请重新打开账号菜单');
    return;
  }
  final cookie = LoginCredentials.savedCookie(platform, credential);
  if (cookie == null) {
    message(context, '此账号未保存可复制的 Cookie，可能使用 Token 或其他方式登录');
    return;
  }
  try {
    await Clipboard.setData(ClipboardData(text: cookie));
    if (context.mounted) message(context, 'Cookie 已复制');
  } catch (_) {
    if (context.mounted) message(context, '复制失败，请重试');
  }
}
