import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moread/io/file_service.dart';
import 'package:path/path.dart' as p;

/// 复刻 `file_selector_ios` 内部对类型组的校验。
///
/// 源码（file_selector_ios.dart）逐字是：
///
/// ```dart
/// if (typeGroup.allowsAny) return allowAny;
/// if (typeGroup.uniformTypeIdentifiers?.isEmpty ?? true) {
///   throw ArgumentError('The provided type group $typeGroup should either '
///       'allow all files, or have a non-empty "uniformTypeIdentifiers"');
/// }
/// ```
///
/// 本机跑不了 iOS，所以把这个判定抄下来单独测。抄漏了没关系 ——
/// 这个测试的价值就是「哪天有人删掉 uniformTypeIdentifiers，这里会红」。
void _iosAccepts(XTypeGroup g) {
  if (g.allowsAny) return;
  if (g.uniformTypeIdentifiers?.isEmpty ?? true) {
    throw ArgumentError('iOS 会拒绝这个类型组：$g');
  }
}

void main() {
  group('类型组（iOS 打开文件的前提）', () {
    final g = FileService.markdownTypeGroup;

    test('iOS 侧能接受：UTI 非空', () {
      expect(() => _iosAccepts(g), returnsNormally);
      expect(g.uniformTypeIdentifiers, isNotNull);
      expect(g.uniformTypeIdentifiers, isNotEmpty);
    });

    test('含 Markdown 官方 UTI，并带 public.plain-text 兜底', () {
      expect(g.uniformTypeIdentifiers, contains('net.daringfireball.markdown'));
      // .md 本身 conform public.plain-text，加它可兜住「扩展名没被正确
      // 推断成 md UTI」的文件（网络盘、下载来的压缩包解出来的等）。
      expect(g.uniformTypeIdentifiers, contains('public.plain-text'));
    });

    test('extensions 也必须在：Windows / Linux 只看这个', () {
      expect(g.extensions, isNotNull);
      expect(g.extensions, contains('md'));
      expect(g.extensions, contains('txt'));
    });

    test('不允许退化成「所有文件」', () {
      // allowsAny 为 true 会让 iOS 跳过校验，但同时也意味着
      // Windows 上的文件选择框不再按扩展名过滤。
      expect(g.allowsAny, isFalse);
    });

    test('extensions 不带前导点', () {
      for (final ext in g.extensions!) {
        expect(ext.startsWith('.'), isFalse, reason: '写 md 而不是 .md：$ext');
      }
    });
  });

  group('readPath', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('moread_fs_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('按 basename 取文件名，不把整条路径当名字', () async {
      final f = File(p.join(tmp.path, 'note.md'));
      await f.writeAsString('# 标题\n');
      final opened = await FileService.readPath(f.path);
      expect(opened.name, 'note.md');
      expect(opened.path, f.path);
      expect(opened.content, '# 标题\n');
    });

    test('去掉 UTF-8 BOM', () async {
      final f = File(p.join(tmp.path, 'bom.md'));
      await f.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...'正文'.codeUnits]);
      final opened = await FileService.readPath(f.path);
      expect(opened.content.codeUnitAt(0), isNot(0xFEFF));
      expect(opened.content.startsWith('正文'), isTrue);
    });

    test('空文件也不炸', () async {
      final f = File(p.join(tmp.path, 'empty.md'));
      await f.writeAsString('');
      final opened = await FileService.readPath(f.path);
      expect(opened.content, isEmpty);
    });
  });
}
