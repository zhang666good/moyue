import 'package:flutter_test/flutter_test.dart';
import 'package:moread/md/document.dart';
import 'package:moread/md/inline.dart';

/// 文件名沿用 flutter create 生成的 widget_test.dart，避免它被模板覆盖。
/// 这里放的是纯逻辑测试：不依赖 GUI，跑得快，也最容易发现问题。
void main() {
  group('文档解析必须无损往返', () {
    test('常见结构', () {
      const src = '# 一级标题\n'
          '\n'
          '普通段落，含 **粗体** 和 `代码`。\n'
          '\n'
          '- 列表项 A\n'
          '- 列表项 B\n'
          '\n'
          '1. 第一项\n'
          '2. 第二项\n'
          '\n'
          '> 引用内容\n'
          '\n'
          '```dart\n'
          'void main() {}\n'
          '```\n'
          '\n'
          '---\n'
          '\n'
          '结尾没有换行';
      expect(MdDocument.parse(src).source, src);
    });

    test('空文档与纯空行', () {
      expect(MdDocument.parse('').source, '');
      expect(MdDocument.parse('\n').source, '\n');
      expect(MdDocument.parse('\n\n\n').source, '\n\n\n');
    });

    test('未闭合的代码块', () {
      const src = '```\n没有结束围栏';
      expect(MdDocument.parse(src).source, src);
    });

    test('空代码块', () {
      const src = '```dart\n```';
      expect(MdDocument.parse(src).source, src);
    });

    test('行尾换行', () {
      const src = 'a\n';
      expect(MdDocument.parse(src).source, src);
    });
  });

  group('块类型识别', () {
    test('标题层级', () {
      final doc = MdDocument.parse('## 二级\n### 三级');
      expect(doc.blocks[0].type, BlockType.heading);
      expect(doc.blocks[0].level, 2);
      expect(doc.blocks[0].content, '二级');
      expect(doc.blocks[1].level, 3);
      expect(doc.headings.length, 2);
    });

    test('分割线不会被误判成列表', () {
      final doc = MdDocument.parse('- - -');
      expect(doc.blocks.length, 1);
      expect(doc.blocks[0].type, BlockType.divider);
    });

    test('有序列表取序号', () {
      final doc = MdDocument.parse('7. 第七项');
      expect(doc.blocks[0].type, BlockType.ordered);
      expect(MdDocument.orderedIndex(doc.blocks[0]), 7);
      expect(doc.blocks[0].content, '第七项');
    });
  });

  group('行内分词', () {
    test('令牌覆盖全部字符且可还原原文', () {
      const samples = <String>[
        '',
        '纯文本',
        '**粗体** 和 *斜体*',
        '`code` 与 ~~删除~~',
        '[链接](https://flutter.dev) 和 ![图](a.png)',
        'file_name_should_not_be_italic',
        '2 * 3 = 6',
        '未闭合 **标记',
        r'转义 \*不是斜体\*',
      ];
      for (final s in samples) {
        final tokens = tokenizeInline(s);
        expect(
          tokens.map((t) => t.text).join(),
          s,
          reason: '分词后必须能拼回原文：$s',
        );
      }
    });

    test('隐藏标记后能得到干净的纯文本', () {
      final tokens = tokenizeInline('前 **中** 后');
      expect(renderedPlainText(tokens), '前 中 后');
    });

    test('下划线不误伤 snake_case', () {
      final tokens = tokenizeInline('file_name_here');
      expect(
        tokens.every((t) => t.kind == InlineKind.text),
        isTrue,
        reason: '下划线应遵守词边界规则',
      );
    });

    test('渲染偏移能映射回原文偏移', () {
      // "**abc**" 渲染成 "abc"，第 0 个渲染字符对应原文第 2 个字符
      final tokens = tokenizeInline('**abc**');
      expect(renderedOffsetToRaw(tokens, 0), 2);
      expect(renderedOffsetToRaw(tokens, 3), 5);
    });
  });
}
