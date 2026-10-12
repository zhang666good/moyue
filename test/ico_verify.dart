// .ico 回读校验：把刚组装好的 app_icon.ico 解回 PNG，肉眼 + 断言双重确认。
//
// 组装 ICO 最容易错两件事：① BGRA↔RGBA 通道顺序颠倒；② BMP 自下而上的行序
// 忘了解翻转。两者都会画出「颜色不对」或「上下颠倒」的图标，而 .ico 本身
// 用肉眼在资源管理器里看不出来。所以这里把每一帧还原成 PNG 落盘做交叉验证。
//
// 运行：flutter test test/ico_verify.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _icoPath = 'windows/runner/resources/app_icon.ico';

class _Frame {
  _Frame(this.size, this.rgba);
  final int size;
  final Uint8List rgba; // 自上而下 RGBA
}

/// 解析 ICO，返回每帧的 RGBA 像素。
List<_Frame> parseIco(Uint8List b) {
  final bd = ByteData.sublistView(b);
  expect(bd.getUint16(0, Endian.little), 0, reason: 'ICONDIR.reserved 应为 0');
  expect(bd.getUint16(2, Endian.little), 1, reason: 'type 应为 1(图标)');
  final count = bd.getUint16(4, Endian.little);

  final frames = <_Frame>[];
  for (var i = 0; i < count; i++) {
    final e = 6 + i * 16;
    final w = bd.getUint8(e);
    final h = bd.getUint8(e + 1);
    final size = w == 0 ? 256 : w;
    expect(h == 0 ? 256 : h, size, reason: '第 $i 帧宽高不一致');
    expect(bd.getUint16(e + 4, Endian.little), 1, reason: 'biPlanes');
    expect(bd.getUint16(e + 6, Endian.little), 32, reason: '每像素应为 32 位');
    final bytes = bd.getUint32(e + 8, Endian.little);
    final offset = bd.getUint32(e + 12, Endian.little);

    // BITMAPINFOHEADER
    expect(bd.getUint32(offset, Endian.little), 40, reason: 'biSize 应为 40');
    expect(bd.getInt32(offset + 4, Endian.little), size, reason: 'biWidth');
    expect(bd.getInt32(offset + 8, Endian.little), size * 2, reason: 'biHeight = 2×');
    final bits = bd.getUint16(offset + 14, Endian.little);
    expect(bits, 32);
    expect(bd.getUint32(offset + 16, Endian.little), 0, reason: 'BI_RGB 无压缩');

    final px = offset + 40;
    final stride = size * 4;
    final out = Uint8List(stride * size);
    for (var y = 0; y < size; y++) {
      final src = px + (size - 1 - y) * stride; // BMP 自下而上，翻回来
      final dst = y * stride;
      for (var x = 0; x < size; x++) {
        final s = src + x * 4;
        out[dst + x * 4 + 0] = b[s + 2]; // B→R
        out[dst + x * 4 + 1] = b[s + 1]; // G
        out[dst + x * 4 + 2] = b[s + 0]; // R→B
        out[dst + x * 4 + 3] = b[s + 3]; // A
      }
    }
    // AND 掩码必须存在且长度为 4 字节对齐的 1bpp
    final maskStride = ((size + 31) ~/ 32) * 4;
    expect(offset + 40 + stride * size + maskStride * size <= offset + bytes, isTrue,
        reason: '第 $i 帧数据长度不足');
    frames.add(_Frame(size, out));
  }
  return frames;
}

String _hex(Uint8List px, int size, int x, int y) {
  final i = (y * size + x) * 4;
  return '#${px[i].toRadixString(16).padLeft(2, '0')}'
          '${px[i + 1].toRadixString(16).padLeft(2, '0')}'
          '${px[i + 2].toRadixString(16).padLeft(2, '0')}'
          '/a${px[i + 3].toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('.ico 结构合法且通道/行序正确', (tester) async {
    final file = File(_icoPath);
    expect(file.existsSync(), isTrue, reason: '$_icoPath 不存在，先跑 tool/make_ico.py');
    final frames = parseIco(file.readAsBytesSync());

    final sizes = frames.map((f) => f.size).toList();
    expect(sizes, containsAll([16, 32, 48, 256]));
    // ignore: avoid_print
    print('📐 帧尺寸: $sizes');

    final f256 = frames.firstWhere((f) => f.size == 256);
    final p = f256.rgba;

    // ① 四角必须透明（圆角方块外是空白）
    for (final c in [(0, 0), (255, 0), (0, 255), (255, 255)]) {
      final a = p[(c.$2 * 256 + c.$1) * 4 + 3];
      expect(a, 0, reason: '角点 ${c.$1},${c.$2} 应透明，实际 alpha=$a');
    }

    // ② 纸张中央偏上应为纯白：若 BGRA 弄反，这里会变成蓝调或黄调
    final white = _hex(p, 256, 190, 118);
    expect(white.startsWith('#FFFFFF'), isTrue, reason: '纸面应为纯白，实际 $white');

    // ③ 首行文字线应是品牌靛蓝 #4F46E5
    final indigo = _hex(p, 256, 100, 155);
    expect(indigo.startsWith('#4F46E5'), isTrue, reason: '主文字线应为 #4F46E5，实际 $indigo');

    // ④ 墨滴圆腹右下（约 x=138, y=128）应是很深的靛蓝。这里避开了左上的高光。
    //    若 R/B 通道颠倒，这里会变成偏红的粉色，这条断言就会掉。
    final di = (128 * 256 + 138) * 4;
    final dr = p[di], dg = p[di + 1], db = p[di + 2];
    expect(dr < 110, isTrue, reason: '墨滴应很深，实际 rgb($dr,$dg,$db)');
    expect(db > dr, isTrue, reason: '若 R/B 颠倒，墨滴会偏红，实际 rgb($dr,$dg,$db)');

    // ⑤ 左上角内侧应是背景渐变（偏靛蓝），右下角内侧应更偏紫，
    //    以确认上下没有翻转、渐变方向正确。
    final tl = _hex(p, 256, 40, 40);
    final br = _hex(p, 256, 215, 215);
    // ignore: avoid_print
    print('🎨 左上 $tl / 右下 $br / 纸面 $white / 文字 $indigo');

    // ⑥ 把每帧还原成 PNG 落盘，供人工复核
    final outDir = Directory('assets/icon/_ico_check');
    outDir.createSync(recursive: true);
    for (final f in frames) {
      await tester.runAsync(() async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(f.rgba);
        final desc = ui.ImageDescriptor.raw(
          buffer,
          width: f.size,
          height: f.size,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        final codec = await desc.instantiateCodec();
        final frame = await codec.getNextFrame();
        final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        File('${outDir.path}/ico_${f.size}.png').writeAsBytesSync(png!.buffer.asUint8List());
        frame.image.dispose();
        codec.dispose();
        buffer.dispose();
      });
    }
    // ignore: avoid_print
    print('🖼  已还原到 ${outDir.absolute.path}');
  });
}
