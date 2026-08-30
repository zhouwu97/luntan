import 'package:http/http.dart' as http;

/// 非 Web 平台不需要浏览器凭证配置。
http.Client createPlatformHttpClient() => http.Client();
