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

  test('StoreRepository loads exchange orders', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (request) async => request.url.path == '/api/v1/me/store-orders'
            ? http.Response.bytes(
                utf8.encode(
                  '{"items":[{"id":"order-1","product_id":"p1","product_name":"贴纸包","points":350,"status":"approved","fulfillment_status":"ready_to_ship","shipping":{"recipient_name":"张三","phone":"13800000000","province":"辽宁省","city":"沈阳市","district":"浑南区","address_detail":"宿舍楼 101","masked_phone":"138****0000"},"review_reason":"","reviewed_at":"2026-08-25T08:00:00Z","created_at":"2026-08-24T08:00:00Z"}]}',
                ),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              )
            : http.Response('{}', 200),
      ),
    );

    final orders = await StoreRepository(client).orders();

    expect(orders.single.id, 'order-1');
    expect(orders.single.productName, '贴纸包');
    expect(orders.single.points, 350);
    expect(orders.single.status, 'approved');
    expect(orders.single.fulfillmentStatus, 'ready_to_ship');
    expect(orders.single.shipping?.phone, '13800000000');
    expect(orders.single.shipping?.maskedPhone, '138****0000');
    expect(orders.single.reviewedAt, isNotNull);
    client.close();
  });

  test('StoreRepository submits order shipping information', () async {
    Map<String, dynamic>? body;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/me/store-orders/order-1/shipping') {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(
              '{"id":"order-1","product_id":"p1","product_name":"贴纸包","points":350,"status":"approved","fulfillment_status":"ready_to_ship","created_at":"2026-08-24T08:00:00Z","shipping":{"recipient_name":"张三","phone":"13800000000","province":"辽宁省","city":"沈阳市","district":"浑南区","address_detail":"宿舍楼 101"}}',
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final order = await StoreRepository(client).submitShipping(
      orderId: 'order-1',
      recipientName: '张三',
      phone: '13800000000',
      province: '辽宁省',
      city: '沈阳市',
      district: '浑南区',
      addressDetail: '宿舍楼 101',
    );

    expect(body?['recipient_name'], '张三');
    expect(body?['address_detail'], '宿舍楼 101');
    expect(order.fulfillmentStatus, 'ready_to_ship');
    expect(order.shipping?.fullAddress, '辽宁省 沈阳市 浑南区 宿舍楼 101');
    client.close();
  });

  test('StoreRepository maps redeemed_count for the product ranking', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (request) async => request.url.path == '/api/v1/store/products'
            ? http.Response.bytes(
                utf8.encode(
                  '{"items":[{"id":"p1","name":"校园徽章","description":"纪念品","emoji":"🏅","points":120,"color":16766842,"redeemed_count":42}]}',
                ),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              )
            : http.Response('{}', 200),
      ),
    );

    final products = await StoreRepository(client).products();

    expect(products.single.redeemedCount, 42);
    client.close();
  });

  test('StoreRepository maps product image_url served by the API', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (request) async => request.url.path == '/api/v1/store/products'
            ? http.Response.bytes(
                utf8.encode(
                  '{"items":[{"id":"badge","name":"论坛纪念徽章","description":"纪念品","emoji":"🏅","points":60,"color":16766842,"image_url":"/api/v1/store/products/badge/image","redeemed_count":0}]}',
                ),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              )
            : http.Response('{}', 200),
      ),
    );

    final products = await StoreRepository(client).products();

    expect(products.single.imageUrl, '/api/v1/store/products/badge/image');
    client.close();
  });
}
