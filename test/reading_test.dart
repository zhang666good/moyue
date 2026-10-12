import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:moread/md/document.dart';
import 'package:moread/read/code_highlight.dart';
import 'package:moread/read/code_spans.dart';
import 'package:moread/read/image_figure.dart';
import 'package:moread/read/mermaid.dart';
import 'package:moread/read/reading_view.dart';

void main() {
  // -------------------------------------------------------------------------
  group('新块类型必须无损往返', () {
    const samples = <String>[
      // 表格
      '| a | b |\n| --- | --- |\n| 1 | 2 |\n',
      '| 左 | 中 | 右 |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |\n',
      '| 单 |\n| --- |\n',
      '| a \\| b | c |\n| --- | --- |\n',
      '  | 缩进表格 |\n  | --- |\n',
      // 提示卡片：容器式
      ':::info\n内容\n:::\n',
      ':::warning 小心\n第一行\n\n第二行\n:::\n',
      ':::tip\n\n:::\n',
      ':::info 没闭合\n内容\n',
      ':::danger\n:::\n',
      // 折叠块
      ':::details 点开\n里面\n:::\n',
      ':::details\n:::\n',
      // 容器嵌套
      ':::details 外\n:::tip 内\n内容\n:::\n:::\n',
      ':::info a\n:::warning b\n:::tip c\nx\n:::\n:::\n:::\n',
      // 公式
      r'$$E = mc^2$$',
      r'  $$ x $$  ',
      '\$\$\n\\frac{a}{b}\n\$\$\n',
      '\$\$\n\$\$\n',
      '\$\$\n未闭合\n',
      // 引用式提示卡片
      '> [!NOTE]\n> 内容\n',
      '> [!WARNING] 标题\n> 第一行\n> 第二行\n',
      '> [!CAUTION]\n> caution 会归一到 warning\n',
      '> [!note]\n> 小写也认\n',
      // 混合
      '# 标题\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\n:::warning 注意\n内容\n:::\n\n\$\$\nx^2\n\$\$\n',
      ':::details 外\n| a |\n| --- |\n| 1 |\n:::\n',
      // Mermaid 围栏（就是普通代码块）
      '```mermaid\ngraph TD\n  A --> B\n```\n',
      // 行高亮标注
      '```dart {1,3-5}\nvoid main() {}\n```\n',
    ];

    for (var i = 0; i < samples.length; i++) {
      test('#$i ${_preview(samples[i])}', () {
        final src = samples[i];
        expect(
          MdDocument.parse(src).source,
          src,
          reason: '解析后拼回的文本必须与原文逐字节相同',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  group('表格解析', () {
    test('表头 / 对齐 / 缺列补齐', () {
      final t = MdTable.parse('| 左 | 中 | 右 |\n| :-- | :-: | --: |\n| 1 | 2 |\n');
      expect(t.headers, <String>['左', '中', '右']);
      expect(t.aligns, <MdAlign>[MdAlign.left, MdAlign.center, MdAlign.right]);
      expect(t.rows.length, 1);
      expect(t.rows.first.length, 3);
      expect(t.rows.first[2], '');
    });

    test('多列会被裁到表头列数', () {
      final t = MdTable.parse('| a | b |\n| --- | --- |\n| 1 | 2 | 3 | 4 |');
      expect(t.rows.first.length, 2);
    });

    test('单元格内含行内标记时原样保留', () {
      final t = MdTable.parse('| a |\n| --- |\n| `code` **b** |');
      expect(t.rows.first.first, '`code` **b**');
    });

    test('转义的竖线不参与切分', () {
      expect(MdTable.splitRow(r'| a \| b | c |'), <String>[r'a | b', 'c']);
    });

    test('分割线不会被当成表格对齐行', () {
      expect(MdTable.isDelimiter('---'), isFalse);
      expect(MdTable.isDelimiter('| --- |'), isTrue);
    });

    test('表格被识别成一个块而不是多行段落', () {
      final doc = MdDocument.parse('| a |\n| --- |\n| 1 |\n| 2 |');
      expect(doc.blocks.length, 1);
      expect(doc.blocks.single.type, BlockType.table);
    });
  });

  // -------------------------------------------------------------------------
  group('容器块', () {
    test('嵌套的容器各自配对，不会提前闭合', () {
      final doc = MdDocument.parse(':::details 外\n:::tip 内\n内容\n:::\n:::');
      expect(doc.blocks.single.type, BlockType.details);
      // 外层内容里应完整包含内层容器
      expect(doc.blocks.single.content, contains(':::tip 内'));
      expect(doc.blocks.single.content, contains('内容'));
    });

    test('caution 归一到 warning', () {
      final doc = MdDocument.parse(':::caution\nx\n:::');
      expect(doc.blocks.single.variant, 'warning');
    });

    test('容器标题被解析出来', () {
      final doc = MdDocument.parse(':::info 我的标题\nx\n:::');
      expect(doc.blocks.single.title, '我的标题');
      expect(doc.blocks.single.variant, 'info');
    });

    test('引用式提示卡片吞掉连续引用行并剥掉 >', () {
      final doc = MdDocument.parse('> [!NOTE] 标题\n> 一\n> 二\n\n普通段落');
      final b = doc.blocks.first;
      expect(b.type, BlockType.callout);
      expect(b.variant, 'note');
      expect(b.title, '标题');
      expect(b.body, '一\n二');
    });

    test('大写种类名会归一成小写', () {
      expect(MdDocument.parse('> [!IMPORTANT]\n> x').blocks.first.variant,
          'important');
    });
  });

  // -------------------------------------------------------------------------
  group('块级公式', () {
    test('单行写法', () {
      final b = MdDocument.parse(r'$$E = mc^2$$').blocks.single;
      expect(b.type, BlockType.mathBlock);
      expect(b.content, 'E = mc^2');
    });

    test('围栏写法', () {
      final b = MdDocument.parse('\$\$\n\\frac{a}{b}\n\$\$').blocks.single;
      expect(b.type, BlockType.mathBlock);
      expect(b.content, r'\frac{a}{b}');
    });

    test('未闭合的围栏公式按到文件末尾', () {
      final b = MdDocument.parse('\$\$\nx\n').blocks.single;
      expect(b.type, BlockType.mathBlock);
      // 与代码块同规则：未闭合时后面所有行都属于该块，
      // 末尾那个空行也在内 —— 这样拼回去才和原文一模一样。
      expect(b.content, 'x\n');
    });
  });

  // -------------------------------------------------------------------------
  group('代码高亮', () {
    test('压平后字符与原文完全一致', () async {
      const dart = 'class A {\n'
          '  // 注释\n'
          '  final String s = "x";\n'
          '  int n = 42;\n'
          '  void f() {}\n'
          '}\n';
      for (final lang in <String>['dart', 'javascript', 'python', 'json']) {
        final src = lang == 'json' ? '{"a": 1, "b": [true, null]}' : dart;
        final lines = highlightToLines(src, lang);
        expect(
          lines.map((l) => l.map((s) => s.text).join()).join('\n'),
          src,
          reason: '$lang 的高亮结果必须能拼回原文',
        );
      }
    });

    test('行数等于源码行数', () {
      const src = 'a\nb\nc';
      expect(highlightToLines(src, 'dart').length, 3);
    });

    test('未知语言退化成纯文本但仍有行', () {
      const src = 'aaa\nbbb';
      final lines = highlightToLines(src, 'nosuchlangatall');
      expect(lines.map((l) => l.map((s) => s.text).join()).join('\n'), src);
    });

    test('空语言不报错', () {
      expect(highlightToLines('x', '').length, 1);
    });

    test('叶子片段带上了 class 名', () {
      final lines = highlightToLines('// hi', 'dart');
      final names = lines
          .expand((l) => l)
          .map((s) => s.className)
          .whereType<String>()
          .toSet();
      expect(names, contains('comment'));
    });
  });

  group('行高亮标注', () {
    test('从围栏行取标注', () {
      expect(fenceHighlightSpec('```dart {1,3-5}\n'), '1,3-5');
      expect(fenceHighlightSpec('```dart\n'), '');
      expect(fenceHighlightSpec('```\n'), '');
    });

    test('解析单个与区间', () {
      expect(parseHighlightSpec('1,3,5'), <int>{1, 3, 5});
      expect(parseHighlightSpec('3-6'), <int>{3, 4, 5, 6});
      expect(parseHighlightSpec('1, 4-5'), <int>{1, 4, 5});
      expect(parseHighlightSpec(''), isEmpty);
      expect(parseHighlightSpec('abc'), isEmpty);
      expect(parseHighlightSpec('0,-2'), isEmpty);
    });

    test('超大区间会被拒绝，避免把内存撑爆', () {
      expect(parseHighlightSpec('1-99999999'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('Mermaid 流程图', () {
    test('方向识别', () {
      expect(parseMermaid('graph TD\nA-->B').direction,
          MermaidDirection.topDown);
      expect(parseMermaid('graph LR\nA-->B').direction,
          MermaidDirection.leftRight);
      expect(parseMermaid('flowchart RL\nA-->B').direction,
          MermaidDirection.rightLeft);
      expect(parseMermaid('graph BT\nA-->B').direction,
          MermaidDirection.bottomTop);
    });

    test('节点与形状', () {
      final g = parseMermaid('graph TD\n'
          'A[方]\n'
          'B(圆角)\n'
          'C{菱形}\n'
          'D((圆))\n'
          'E[[子程序]]\n'
          'F([体育场])\n');
      expect(g.nodes.length, 6);
      expect(g.nodeOf('A')!.shape, MermaidShape.rect);
      expect(g.nodeOf('B')!.shape, MermaidShape.round);
      expect(g.nodeOf('C')!.shape, MermaidShape.diamond);
      expect(g.nodeOf('D')!.shape, MermaidShape.circle);
      expect(g.nodeOf('E')!.shape, MermaidShape.subroutine);
      expect(g.nodeOf('F')!.shape, MermaidShape.stadium);
      expect(g.nodeOf('A')!.label, '方');
    });

    test('箭头上的标签', () {
      final g = parseMermaid('graph TD\nA -->|是| B\nC -- 否 --> D');
      expect(g.edges.length, 2);
      expect(g.edges[0].label, '是');
      expect(g.edges[1].label, '否');
    });

    test('虚线箭头', () {
      final g = parseMermaid('graph TD\nA -.-> B\nC ==> D');
      expect(g.edges[0].dashed, isTrue);
      expect(g.edges[1].thick, isTrue);
    });

    test('链式写法拆成多条边', () {
      final g = parseMermaid('graph TD\nA --> B --> C');
      expect(g.nodes.length, 3);
      expect(g.edges.length, 2);
    });

    test('裸 id 自己当标签', () {
      final g = parseMermaid('graph TD\nA --> B');
      expect(g.nodeOf('A')!.label, 'A');
    });

    test('引号与 <br/> 处理', () {
      final g = parseMermaid('graph TD\nA["带引号"]\nB[两行<br/>文本]');
      expect(g.nodeOf('A')!.label, '带引号');
      expect(g.nodeOf('B')!.label, '两行\n文本');
    });

    test('忽略样式指令行', () {
      final g = parseMermaid('graph TD\n'
          'A --> B\n'
          'style A fill:#f9f\n'
          'classDef x fill:#000\n'
          '%% 注释\n');
      expect(g.nodes.length, 2);
      expect(g.error, isNull);
    });

    test('subgraph 记为不支持但继续解析', () {
      final g = parseMermaid('graph TD\nsubgraph 组\nA --> B\nend');
      expect(g.isUsable, isTrue);
      expect(g.unsupported, contains('subgraph'));
    });

    test('其它图类型明确报错而不是硬画', () {
      final g = parseMermaid('sequenceDiagram\nA->>B: hi');
      expect(g.error, isNotNull);
      expect(g.isUsable, isFalse);
    });

    test('空输入报错', () {
      expect(parseMermaid('').error, isNotNull);
    });

    test('分层：链式结构每级一层', () {
      final g = parseMermaid('graph TD\nA --> B\nB --> C');
      final l = layoutMermaid(g);
      final a = l.rects['A']!;
      final b = l.rects['B']!;
      final c = l.rects['C']!;
      expect(a.top, lessThan(b.top));
      expect(b.top, lessThan(c.top));
    });

    test('分层：同层节点并排不重叠', () {
      final g = parseMermaid('graph TD\nA --> B\nA --> C\nA --> D');
      final l = layoutMermaid(g);
      final rects = <Rect>[l.rects['B']!, l.rects['C']!, l.rects['D']!];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('LR 方向沿 x 铺开', () {
      final g = parseMermaid('graph LR\nA --> B');
      final l = layoutMermaid(g);
      expect(l.rects['A']!.left, lessThan(l.rects['B']!.left));
      expect(l.size.width, greaterThan(l.size.height));
    });

    test('环不会让分层卡死', () {
      final g = parseMermaid('graph TD\nA --> B\nB --> A');
      final l = layoutMermaid(g);
      expect(l.rects.length, 2);
      expect(l.size.width, greaterThan(0));
    });

    test('每条边都有折线且终点非空', () {
      final g = parseMermaid('graph TD\nA --> B\nB --> C\nC --> A');
      final l = layoutMermaid(g);
      expect(l.edges.length, 3);
      for (final e in l.edges) {
        expect(e.points.length, greaterThanOrEqualTo(2));
      }
    });

    test('节点尺寸随文字增长，且不小于下限', () {
      final small = nodeSize(
        const MermaidNode(id: 'a', label: 'x', shape: MermaidShape.rect),
      );
      final big = nodeSize(
        const MermaidNode(
          id: 'a',
          label: '很长很长很长的一段节点文字用来测试',
          shape: MermaidShape.rect,
        ),
      );
      expect(big.width, greaterThan(small.width));
      expect(small.width, greaterThanOrEqualTo(kMermaidMinW));
      expect(small.height, greaterThanOrEqualTo(kMermaidMinH));
    });

    test('中文宽度估算大于等长英文', () {
      // 同样 4 个字符，中文比西文宽
      expect(
        estimateTextWidth('中文中文'),
        greaterThan(estimateTextWidth('abcd')),
      );
      expect(estimateTextWidth('中'), greaterThan(estimateTextWidth('a')));
    });
  });

  // -------------------------------------------------------------------------
  group('文档统计', () {
    test('中英混排字数', () {
      final s = docStats('hello world 你好世界');
      // 2 个英文词 + 4 个汉字
      expect(s.words, 6);
    });

    test('字符按码点算，行数按换行算', () {
      final s = docStats('ab\ncd\nef');
      expect(s.chars, 8);
      expect(s.lines, 3);
    });

    test('空文档', () {
      final s = docStats('');
      expect(s.words, 0);
      expect(s.chars, 0);
      expect(s.lines, 0);
    });

    test('emoji 不会被拆成两半', () {
      expect(docStats('😀').chars, 1);
    });
  });

  group('图片收集', () {
    test('扫出正文里的图片并保留 alt', () {
      final imgs = collectImages(
        '文字 ![图注](a.png) 更多\n\n![](b/c.jpg)\n\n[链接](x.md)',
        null,
      );
      expect(imgs.length, 2);
      expect(imgs[0].source, 'a.png');
      expect(imgs[0].alt, '图注');
      expect(imgs[1].source, 'b/c.jpg');
    });

    test('相对路径按文档目录解析，绝对路径与 URL 原样', () {
      expect(
        ImageRef(source: 'img/a.png', alt: '', baseDir: r'C:\docs').resolved,
        contains('img'),
      );
      expect(
        ImageRef(source: 'https://x.com/a.png', alt: '').resolved,
        'https://x.com/a.png',
      );
      // 没有文档目录时，相对路径解析不出来
      expect(ImageRef(source: 'a.png', alt: '').resolved, isNull);
    });
  });
}

String _preview(String s) {
  final flat = s.replaceAll('\n', r'\n');
  return flat.length <= 34 ? flat : '${flat.substring(0, 34)}…';
}
