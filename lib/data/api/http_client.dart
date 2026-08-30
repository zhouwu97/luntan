import 'package:http/http.dart' as http;

import 'http_client_stub.dart' if (dart.library.html) 'http_client_web.dart';

/// 按运行平台创建默认 HTTP 客户端。
///
/// Web 端必须携带 HttpOnly refresh Cookie，原生端继续使用普通 IO 客户端。
http.Client createHttpClient() => createPlatformHttpClient();
