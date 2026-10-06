import '../../core/json.dart';
import '../../domain/auth.dart';
import '../../domain/models.dart';
import '../http.dart';
import '../login_cookies.dart';
import 'lanzou_protocol.dart';

/// A separate cookie jar for each official account/password login attempt.
class LanzouPasswordLogin {
  LanzouPasswordLogin(this.http, {DateTime Function()? clock})
    : cookies = LoginCookieJar(_domains, clock: clock);
  final JsonHttp http;
  final LoginCookieJar cookies;
  static const _domains = {
    'woozooo.com',
    'accounts.woozooo.com',
    'pc.woozooo.com',
    'up.woozooo.com',
  };
  static final _entry = Uri.parse(
    'https://accounts.woozooo.com/accounts.php?action=login&ref=pc.woozooo.com',
  );
  static final _disk = Uri.parse('https://pc.woozooo.com/mydisk.php');

  Future<Credential> submit(String username, String password) async {
    username = username.trim();
    require(username.isNotEmpty && username.length <= 100, '请输入蓝奏云账号');
    require(
      password.length >= 6 && password.length <= 1024,
      '请输入正确的蓝奏云密码（至少 6 位）',
    );
    try {
      await _request('GET', _entry, _entry);
      final response = await _request(
        'POST',
        _entry.resolve('/accounts.php'),
        _entry,
        body: form({
          'task': 'uselogin',
          'username': username,
          'password': password,
          'ref': 'pc.woozooo.com',
        }),
      );
      Json data;
      try {
        data = response.json;
      } on AppException {
        throw const AppException('蓝奏登录需要网页验证，请切换网页登录后完成验证');
      }
      require(data.containsKey('zt'), '蓝奏登录响应异常，请稍后重试或切换网页登录');
      if (data.integer('zt') != 1) {
        final detail = data.str('msgs');
        throw AppException(
          RegExp(r'频繁|次数|稍后|限制').hasMatch(detail)
              ? '蓝奏登录请求频繁，请稍后重试'
              : RegExp(r'验证|安全|滑块').hasMatch(detail)
              ? '蓝奏登录需要网页验证，请切换网页登录后完成验证'
              : '蓝奏账号或密码错误，请检查后重试',
        );
      }
      final callback = data.str('msgs').trim();
      require(callback.isNotEmpty, '蓝奏未返回登录跳转地址，请切换网页登录');
      var uri = _checked(_entry.resolve(callback));
      var referer = _entry;
      for (var step = 0; step < 8; step++) {
        final page = await _request('GET', uri, referer);
        final cookie = cookies.header(_disk);
        if (LoginCredentials.plausible(CloudPlatform.lanzou, cookie)) {
          return Credential(CloudPlatform.lanzou.label, {
            'primary': cookie,
            'authType': 'passwordCookie',
            'username': username,
            'password': password,
          });
        }
        final next = _redirect(page);
        require(next != null, '蓝奏登录尚未完成，请切换网页登录后进入「我的文件」');
        referer = uri;
        uri = _checked(uri.resolve(next!));
      }
      throw const AppException('蓝奏登录跳转次数过多，请切换网页登录');
    } finally {
      cookies.clear();
    }
  }

  Uri _checked(Uri uri) {
    require(
      uri.scheme == 'https' &&
          _domains.contains(uri.host) &&
          uri.userInfo.isEmpty &&
          uri.port == 443,
      '蓝奏登录跳转地址异常，请切换网页登录',
    );
    return uri;
  }

  Future<HttpResult> _request(
    String method,
    Uri uri,
    Uri referer, {
    String? body,
  }) async {
    _checked(uri);
    for (var attempt = 0; attempt < 2; attempt++) {
      RequestScope.checkpoint();
      final cookie = cookies.header(uri);
      final response = await http.request(
        method,
        uri.toString(),
        body: body,
        headers: {
          'User-Agent': WebLoginTarget.desktopUserAgent,
          'Referer': referer.toString(),
          if (cookie.isNotEmpty) 'Cookie': cookie,
          if (body != null) 'Origin': _entry.origin,
          if (body != null) 'X-Requested-With': 'XMLHttpRequest',
        },
        contentType: body == null
            ? null
            : 'application/x-www-form-urlencoded; charset=utf-8',
        followRedirects: false,
      );
      RequestScope.checkpoint();
      require(response.body.length <= 1024 * 1024, '蓝奏登录响应异常，请切换网页登录');
      require(response.status != 429, '蓝奏登录请求频繁，请稍后重试');
      require(
        response.successful ||
            {301, 302, 303, 307, 308}.contains(response.status),
        '蓝奏登录服务暂不可用，请稍后重试或切换网页登录',
      );
      cookies.absorb(uri, response);
      final challenge = lanzouChallengeCookie(response.body);
      if (challenge == null) return response;
      require(attempt == 0, '蓝奏登录需要网页验证，请切换网页登录后完成验证');
      cookies.absorb(
        uri,
        HttpResult(200, '', {
          'set-cookie': ['acw_sc__v2=$challenge; Path=/; Secure'],
        }),
      );
    }
    throw const AppException('蓝奏登录需要网页验证，请切换网页登录');
  }

  String? _redirect(HttpResult response) {
    if ({301, 302, 303, 307, 308}.contains(response.status)) {
      final location = response.header('location').trim();
      return location.isEmpty ? null : location;
    }
    // Read literal redirects only; never evaluate JavaScript from a login page.
    final script = LanzouPage(response.body).script;
    final match =
        RegExp(
          r'''\b(?:(?:window|document|top|self)\s*\.\s*)?location\s*(?:\.\s*href\s*)?=\s*(['"])(.*?)\1''',
        ).firstMatch(script) ??
        RegExp(
          r'''\b(?:(?:window|document|top|self)\s*\.\s*)?location\s*\.\s*(?:replace|assign)\s*\(\s*(['"])(.*?)\1''',
        ).firstMatch(script);
    final target = match
        ?.group(2)
        ?.replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&');
    return target?.isNotEmpty == true ? target : null;
  }
}
