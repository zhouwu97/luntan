import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/store_repository.dart';

void main() {
  test('StoreRepository preserves real point transaction details', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'balance': 3980,
              'transactions': [
                {
                  'id': 'tx-1',
                  'source': 'store',
                  'delta': -350,
                  'balance_after': 3980,
                  'reason': '主题贴纸包',
                  'created_at': '2026-08-24T08:00:00Z',
                },
              ],
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final overview = await StoreRepository(client).overview();

    expect(overview.balance, 3980);
    expect(overview.transactions.single.delta, -350);
    expect(overview.transactions.single.reason, '主题贴纸包');
    expect(overview.transactions.single.balanceAfter, 3980);
    client.close();
  });
}
