/// 统一生成帖子与榜单的公开链接，避免不同页面拼出不同域名。
class AppLinks {
  const AppLinks._();

  static Uri get webBase {
    const configured = String.fromEnvironment(
      'WEB_BASE_URL',
      defaultValue: 'https://luntan.app',
    );
    final parsed = Uri.tryParse(configured.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return Uri.parse('https://luntan.app/');
    }
    final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
    return parsed.replace(path: path, query: '', fragment: '');
  }

  static String post(String postId) =>
      _resolve('posts/${Uri.encodeComponent(postId)}');

  static String ranking(String toyId) =>
      _resolve('ranking/${Uri.encodeComponent(toyId)}');

  /// 官网下载页。Web 与原生端都通过这个入口获取同一份稳定版信息。
  static String get downloadPage => _resolve('download.html');

  static String _resolve(String path) =>
      webBase.resolve(Uri(path: path).toString()).toString();
}
