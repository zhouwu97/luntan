import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/governance_screens.dart';
import 'package:luntan/widgets/composer_sheet.dart';

void main() {
  testWidgets('发帖编辑器不再展示投票类型下拉与投票选项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostEditorScreen(
          initialCommunityId: 'community-campus',
          enableSampleMedia: true,
          onPublish: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('内容类型'), findsNothing);
    expect(find.text('投票'), findsNothing);
    expect(find.text('投票选项'), findsNothing);
    expect(find.text('添加选项'), findsNothing);
    expect(find.text('允许多选'), findsNothing);
    expect(find.text('给帖子起一个清楚的标题'), findsOneWidget);
    expect(find.text('分享你的真实体验、问题或发现……'), findsOneWidget);
    expect(find.text('添加示例图'), findsOneWidget);
  });

  testWidgets('治理中心展示结构化工作台与功能卡片', (tester) async {
    var openedUsers = false;
    var openedLogs = false;

    await tester.pumpWidget(
      MaterialApp(
        home: GovernanceCenterScreen(
          onOpenModeration: () {},
          onOpenUsers: () => openedUsers = true,
          onOpenLogs: () => openedLogs = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('治理中心'), findsOneWidget);
    expect(find.text('治理工作台'), findsOneWidget);
    expect(find.text('内容审核与推荐'), findsOneWidget);
    expect(find.text('审核与用户处罚'), findsOneWidget);
    expect(find.text('用户管理'), findsOneWidget);
    expect(find.text('操作日志'), findsOneWidget);

    await tester.tap(find.text('用户管理'));
    expect(openedUsers, isTrue);

    await tester.tap(find.text('操作日志'));
    expect(openedLogs, isTrue);
  });

  testWidgets('ManagedUserListScreen 支持分页、状态筛选和角色中文显示', (tester) async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/admin/users') {
          final query = request.url.queryParameters;
          if (query['status'] == 'suspended') {
            return http.Response(
              '{"items":[{"id":"u2","username":"user_two","nickname":"测试用户2","email":"u2@test.com","status":"suspended","account_type":"email","created_at":"2026-08-20T00:00:00Z","roles":["community_moderator:community-campus"],"banned":false,"muted":true}],"has_more":false,"next_cursor":null}',
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (query['cursor'] == 'cursor_page_2') {
            return http.Response(
              '{"items":[{"id":"u2","username":"user_two","nickname":"测试用户2","email":"u2@test.com","status":"suspended","account_type":"email","created_at":"2026-08-20T00:00:00Z","roles":["community_moderator:community-campus"],"banned":false,"muted":true}],"has_more":false,"next_cursor":null}',
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final page1Items = List.generate(
            10,
            (i) => {
              'id': 'u1_$i',
              'username': 'user_$i',
              'nickname': '测试用户$i',
              'email': 'u$i@test.com',
              'status': 'active',
              'account_type': 'email',
              'created_at': '2026-08-22T00:00:00Z',
              'roles': ['platform_admin'],
              'banned': false,
              'muted': false,
            },
          );
          return http.Response(
            '{"items":${page1Items.map((e) => '{"id":"${e['id']}","username":"${e['username']}","nickname":"${e['nickname']}","email":"${e['email']}","status":"${e['status']}","account_type":"${e['account_type']}","created_at":"${e['created_at']}","roles":["platform_admin"],"banned":false,"muted":false}').toList()},"has_more":true,"next_cursor":"cursor_page_2"}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200, headers: const {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final repo = PlatformRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: ManagedUserListScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试用户0'), findsOneWidget);
    expect(find.text('平台管理员'), findsWidgets);
    expect(find.text('正常'), findsWidgets);

    // 触底滚动加载下一页
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(find.text('测试用户2'), findsOneWidget);
    expect(find.text('社区版主（community-campus）'), findsOneWidget);

    // 切换状态筛选 Tab
    await tester.tap(find.widgetWithText(ChoiceChip, '已暂停'));
    await tester.pumpAndSettle();

    expect(find.text('测试用户2'), findsOneWidget);
    expect(find.text('测试用户0'), findsNothing);

    client.close();
  });

  testWidgets('ManagedUserDetailScreen 支持角色格式化与点击帖子跳转', (tester) async {
    String? openedPostId;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/admin/users/u1') {
          return http.Response(
            '{"id":"u1","username":"admin_user","nickname":"超管喵","email":"admin@test.com","status":"active","account_type":"email","created_at":"2026-08-20T00:00:00Z","roles":[{"name":"super_admin","community_id":""}],"banned":false,"muted":false,"punishments":[{"type":"mute","reason":"测试禁言","starts_at":"2026-08-21"}],"recent_posts":[{"id":"p100","title":"测评帖子标题","content":"帖子正文预览"}]}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200, headers: const {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final repo = PlatformRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: ManagedUserDetailScreen(
          repository: repo,
          userId: 'u1',
          onOpenPostId: (id) => openedPostId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('超管喵'), findsOneWidget);
    expect(find.text('超级管理员'), findsOneWidget);
    expect(find.text('禁言账号：测试禁言'), findsOneWidget);
    expect(find.text('测评帖子标题'), findsOneWidget);

    await tester.tap(find.text('测评帖子标题'));
    expect(openedPostId, 'p100');

    client.close();
  });

  testWidgets('AdminRoleEditorScreen 撤销权限强制要求输入理由', (tester) async {
    String? capturedReason;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        if (request.method == 'PUT' &&
            request.url.path == '/api/v1/admins/a1/roles') {
          capturedReason = '违反平台保密协议';
          return http.Response('{"success":true}', 200, headers: const {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('{}', 200, headers: const {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final repo = PlatformRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminRoleEditorScreen(
          repository: repo,
          adminId: 'a1',
          displayName: '测试管理员',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销管理员权限'));
    await tester.pumpAndSettle();

    expect(find.text('撤销全部管理员角色？'), findsOneWidget);
    expect(find.text('撤销理由（必填）'), findsOneWidget);

    // 未填理由直接点确认应该被拦截
    await tester.tap(find.widgetWithText(FilledButton, '确认撤销'));
    await tester.pumpAndSettle();
    expect(find.text('请填写撤销理由'), findsOneWidget);
    expect(capturedReason, isNull);

    // 填写理由后确认
    await tester.enterText(
      find.widgetWithText(TextField, '').last,
      '违反平台保密协议',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确认撤销'));
    await tester.pumpAndSettle();

    expect(capturedReason, '违反平台保密协议');
    client.close();
  });
}
