import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luntan/controllers/app_update_coordinator.dart';
import 'package:luntan/data/api/app_update_cache.dart';
import 'package:luntan/data/api/app_update_service.dart';
import 'package:luntan/screens/app_update_sheet.dart';

void main() {
  AppUpdateCoordinator createMockCoordinator({bool requiredUpdate = false}) {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'platform': 'android',
            'channel': 'stable',
            'latest_version_name': '1.1.0',
            'latest_version_code': 2,
            'minimum_supported_version_code': requiredUpdate ? 2 : 1,
            'title': 'v1.1.0 更新',
            'changelog': '新版本优化',
            'file_name': 'app.apk',
            'file_size': 1024,
            'sha256': 'a' * 64,
            'download_url': '/downloads/app.apk',
            'published_at': '2026-08-30T00:00:00Z',
            'check_after_seconds': 21600,
            'update_available': true,
            'update_type': requiredUpdate ? 'required' : 'optional',
          }),
        ),
        200,
      );
    });

    return AppUpdateCoordinator(
      cache: MemoryAppUpdateCache(),
      service: AppUpdateService(
        baseUri: Uri.parse('http://server.test'),
        client: client,
      ),
      packageInfoResolver: () async => PackageInfo(
        appName: 'luntan',
        packageName: 'com.shengbeijiang.luntan',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester, {required bool force}) async {
    final coordinator = createMockCoordinator(requiredUpdate: force);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showAppUpdateSheet(
                    context,
                    force: force,
                    coordinator: coordinator,
                  );
                },
                child: const Text('打开更新弹层'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开更新弹层'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
  }

  testWidgets('普通检查更新弹层保留关闭按钮，点遮罩可关闭', (tester) async {
    await openSheet(tester, force: false);

    expect(find.byTooltip('关闭'), findsOneWidget);
    await tester.tapAt(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsNothing);
  });

  testWidgets('强制更新弹层没有关闭入口，点遮罩与返回键都无法关闭', (tester) async {
    await openSheet(tester, force: true);

    expect(find.byTooltip('关闭'), findsNothing);

    await tester.tapAt(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
  });
}
