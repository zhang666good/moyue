// 应用图标导出器 —— 「墨阅 · MoRead」
//
// 绘制逻辑在 lib/ui/brand_mark.dart（与应用内 Logo 共用同一份代码），
// 这里只负责按各档尺寸渲染、落盘 PNG 与裸 RGBA。
//
// 运行：flutter test test/icon_gen.dart
// 产物：
//   ① assets/icon/icon_<size>.png / .rgba
//      随后：python tool/make_ico.py  → windows/runner/resources/app_icon.ico
//   ② ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png（满幅、无圆角）
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moread/ui/brand_mark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('生成应用图标 PNG', (tester) async {
    final outDir = Directory('assets/icon');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    const sizes = [1024, 512, 256, 128, 64, 48, 32, 24, 16];
    for (final s in sizes) {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        paintBrandIcon(canvas, s.toDouble(), BrandIconTier.forSize(s.toDouble()));
        final picture = recorder.endRecording();
        final image = await picture.toImage(s, s);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${outDir.path}/icon_$s.png').writeAsBytesSync(png!.buffer.asUint8List());
        // 同时落一份裸 RGBA，供 tool/make_ico.py 免解 PNG 直接组装 .ico。
        // 必须用 rawStraightRgba——rawRgba 是预乘 alpha 的，直接塞进 ICO 会在
        // 抗锯齿边缘留下发黑的一圈毛边。
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        File('${outDir.path}/icon_$s.rgba').writeAsBytesSync(raw!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
    }
    // ignore: avoid_print
    print('✅ 图标已输出到 ${outDir.absolute.path}');
  });

  testWidgets('生成 iOS AppIcon 图标集', (tester) async {
    final outDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    // 文件名 → 像素边长。同一像素尺寸会以不同文件名出现两次
    // （如 40 = 20@2x = 40@1x），这是 iOS contents.json 的要求，照写即可。
    const entries = <(String, int)>[
      ('Icon-App-20x20@1x.png', 20),
      ('Icon-App-20x20@2x.png', 40),
      ('Icon-App-20x20@3x.png', 60),
      ('Icon-App-29x29@1x.png', 29),
      ('Icon-App-29x29@2x.png', 58),
      ('Icon-App-29x29@3x.png', 87),
      ('Icon-App-40x40@1x.png', 40),
      ('Icon-App-40x40@2x.png', 80),
      ('Icon-App-40x40@3x.png', 120),
      ('Icon-App-60x60@2x.png', 120),
      ('Icon-App-60x60@3x.png', 180),
      ('Icon-App-76x76@1x.png', 76),
      ('Icon-App-76x76@2x.png', 152),
      ('Icon-App-83.5x83.5@2x.png', 167),
      ('Icon-App-1024x1024@1x.png', 1024),
    ];

    for (final (name, s) in entries) {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        // fullBleed：铺满画布不留圆角，iOS 会自行裁圆角且不接受透明通道。
        paintBrandIcon(
          canvas,
          s.toDouble(),
          BrandIconTier.forSize(s.toDouble()),
          fullBleed: true,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(s, s);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${outDir.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
    }
    // ignore: avoid_print
    print('✅ iOS 图标已输出到 ${outDir.absolute.path}（${entries.length} 个）');
  });
}
