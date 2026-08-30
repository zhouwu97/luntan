import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Web 认证依赖服务端 HttpOnly Cookie，必须显式开启跨域凭证。
http.Client createPlatformHttpClient() =>
    BrowserClient()..withCredentials = true;
