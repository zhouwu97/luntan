import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/app_network_image.dart';
import 'package:luntan/widgets/post_media_preview.dart';

void main() {
  MediaAsset asset(String id, int w, int h) => MediaAsset(
    id: id,
    type: MediaType.image,
    url: 'https://example.com/$id.jpg',
    width: w,
    height: h,
  );

  Widget feedHost(List<MediaAsset> images, {double width = 360}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [PostMediaPreview(images: images)],
          ),
        ),
      ),
    );
  }

  group('calculateFeedSingleImageSize 宽度优先模型', () {
    test('390dp 内容宽度触发 250 上限，各比例尺寸正确', () {
      final cases = <String, (double?, double)>{
        '16:9': (16 / 9, 250 / (16 / 9)),
        '4:3': (4 / 3, 250 / (4 / 3)),
        '1:1': (1.0, 250),
        '4:5': (0.8, 250 / 0.8),
        '3:4': (0.75, 250 / 0.75),
        '9:16 长图': (0.5625, 250 / 0.75),
        '超长截图': (0.2, 250 / 0.75),
        '无元数据兜底 4:3': (null, 250 / (4 / 3)),
      };

      cases.forEach((name, c) {
        final size = calculateFeedSingleImageSize(
          availableWidth: 390,
          aspectRatio: c.$1,
        );
        expect(size.width, closeTo(250, 0.001), reason: name);
        expect(size.height, closeTo(c.$2, 0.001), reason: name);
      });
    });

    test('窄容器下宽度跟随 0.70 系数不触发上限', () {
      final size = calculateFeedSingleImageSize(
        availableWidth: 200,
        aspectRatio: 1.0,
      );
      expect(size.width, closeTo(140, 0.001));
      expect(size.height, closeTo(140, 0.001));
    });
  });

  group('Feed 单图', () {
    testWidgets('3:4 完整展示：contain + center + 无长图角标', (tester) async {
      await tester.pumpWidget(feedHost([asset('normal-3-4', 300, 400)]));

      final size = tester.getSize(find.byType(PostMediaPreview));
      // 250 / 0.75 + 10 top padding
      expect(size.height, closeTo(343.33, 0.5));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.center);
      expect(find.text('长图'), findsNothing);
    });

    testWidgets('9:16 长图：cover + topCenter + 长图角标，宽度 250 未占满', (tester) async {
      await tester.pumpWidget(feedHost([asset('long-9-16', 90, 160)]));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, Alignment.topCenter);
      expect(find.text('长图'), findsOneWidget);
      expect(tester.getSize(find.byType(Image)).width, closeTo(250, 0.5));

      // 解码按原图比例 0.5625 展开，而不是 3:4 预览框比例，避免位图被压扁。
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      final resize = provider as ResizeImage;
      expect(resize.width! / resize.height!, closeTo(90 / 160, 0.01));
    });
  });

  group('Feed 多图', () {
    testWidgets('3 图一行三列同宽同高', (tester) async {
      await tester.pumpWidget(
        feedHost([asset('g1', 40, 30), asset('g2', 40, 30), asset('g3', 40, 30)]),
      );

      final size = tester.getSize(find.byType(PostMediaPreview));
      // tile = (360-12)/3 = 116，单行 + 10 padding
      expect(size.height, closeTo(126, 1.0));

      final tops = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(find.byType(Image).at(i)).dy,
      ];
      expect(tops[0], tops[1]);
      expect(tops[1], tops[2]);
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(find.byType(Image).at(i)).width, closeTo(116, 0.5));
      }
    });

    testWidgets('4 图 2×2 且全部顶部对齐', (tester) async {
      await tester.pumpWidget(
        feedHost([
          asset('q1', 40, 30),
          asset('q2', 40, 30),
          asset('q3', 40, 30),
          asset('q4', 40, 30),
        ]),
      );

      final size = tester.getSize(find.byType(PostMediaPreview));
      // tile = (360-6)/2 = 177，两行 = 177*2 + 6 + 10 padding
      expect(size.height, closeTo(370, 1.0));

      for (var i = 0; i < 4; i++) {
        final tile = find.byType(Image).at(i);
        expect(tester.getSize(tile).width, closeTo(177, 0.5));
        expect(tester.getSize(tile).height, closeTo(177, 0.5));
        expect(tester.widget<Image>(tile).alignment, Alignment.topCenter);
        expect(tester.widget<Image>(tile).fit, BoxFit.cover);
      }
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('5 图三列两行', (tester) async {
      await tester.pumpWidget(
        feedHost([
          asset('f1', 40, 30),
          asset('f2', 40, 30),
          asset('f3', 40, 30),
          asset('f4', 40, 30),
          asset('f5', 40, 30),
        ]),
      );

      expect(find.byType(Image), findsNWidgets(5));
      final size = tester.getSize(find.byType(PostMediaPreview));
      // tile = 116，两行 = 116*2 + 6 + 10 padding
      expect(size.height, closeTo(248, 1.0));
    });

    testWidgets('9 图 3×3 全部展示', (tester) async {
      await tester.pumpWidget(
        feedHost([
          asset('n1', 40, 30),
          asset('n2', 40, 30),
          asset('n3', 40, 30),
          asset('n4', 40, 30),
          asset('n5', 40, 30),
          asset('n6', 40, 30),
          asset('n7', 40, 30),
          asset('n8', 40, 30),
          asset('n9', 40, 30),
        ]),
      );

      expect(find.byType(AppNetworkImage), findsNWidgets(9));
      final size = tester.getSize(find.byType(PostMediaPreview));
      // tile = 116，三行 = 116*3 + 6*2 + 10 padding
      expect(size.height, closeTo(370, 1.0));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('12 图只显示 9 张，第 9 张叠加 +3', (tester) async {
      await tester.pumpWidget(
        feedHost([
          for (var i = 1; i <= 12; i++) asset('e$i', 40, 30),
        ]),
      );

      expect(find.byType(AppNetworkImage), findsNWidgets(9));
      expect(find.text('+3'), findsOneWidget);
      final size = tester.getSize(find.byType(PostMediaPreview));
      expect(size.height, closeTo(370, 1.0));
    });
  });

  group('Detail 回归', () {
    testWidgets('纵向真实比例全宽完整展示全部图片', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: PostMediaPreview(
                  mode: PostMediaPreviewMode.detail,
                  images: [asset('detail-tall', 90, 160), asset('detail-sq', 30, 30)],
                ),
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(PostMediaPreview));
      // 12 padding + 640 (360/0.5625) + 10 spacing + 360 (1:1)
      expect(size.height, closeTo(1022, 2.0));
      expect(tester.getSize(find.byType(Image).at(0)).width, closeTo(360, 0.5));
      expect(tester.getSize(find.byType(Image).at(1)).width, closeTo(360, 0.5));
    });
  });

  group('全屏查看器解码', () {
    testWidgets('已知比例：解码目标按原图比例展开，长边封顶后比例不变', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryScreen(
            images: [asset('viewer-9-16', 90, 160)],
          ),
        ),
      );
      await tester.pump();

      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(provider, isA<ResizeImage>());
      final resize = provider as ResizeImage;
      // 测试面 800×600、dpr 3 → zoomWidth = 4800，高度超 4096 封顶后
      // 按原图比例回推宽度，比例必须保持 90/160。
      expect(resize.width! / resize.height!, closeTo(90 / 160, 0.01));
    });

    testWidgets('缺失尺寸：只按宽度降采样，高度交给原图比例推断', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaGalleryScreen(
            images: [
              MediaAsset(
                id: 'viewer-mystery',
                type: MediaType.image,
                url: 'https://example.com/mystery.jpg',
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(provider, isA<ResizeImage>());
      final resize = provider as ResizeImage;
      expect(resize.width, 4800);
      expect(resize.height, isNull);
    });
  });
}
