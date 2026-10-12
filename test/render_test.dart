import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moread/app.dart';
import 'package:moread/md/document.dart';
import 'package:moread/read/block_renderer.dart';
import 'package:moread/read/code_block_view.dart';
import 'package:moread/read/mermaid_view.dart';
import 'package:moread/read/reading_view.dart';
import 'package:moread/ui/palette.dart';

/// 包里所有示例块。渲染测试逐个真跑一遍布局 ——
/// 「分析通过」和「真的能画出来」之间差着一整类断言错误。
const Map<String, String> _samples = <String, String>{
  '段落': '普通段落，带 **粗体**、*斜体*、`代码`、~~删除线~~ 和 [链接](https://x.com)。',
  '标题': '## 二级标题',
  '空段落': '',
  '分割线': '---',
  '引用': '> 引用里的一段话',
  '无序列表': '- 列表项',
  '有序列表': '3. 第三项',
  '代码': '```dart {1,3}\nclass A {\n  // 注释\n  final String s = "x";\n}\n```',
  '无语言代码': '```\nplain text\n```',
  '空代码': '```\n```',
  '超长行代码':
      '```dart\nfinal x = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";\n```',
  '表格': '| 左 | 中 | 右 |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |\n| 4 | 5 |',
  '单列表格': '| 只有一列 |\n| --- |\n| 值 |',
  '宽表格': '| c0 | c1 | c2 | c3 | c4 | c5 | c6 | c7 |\n'
      '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
      '| 内容0 | 内容1 | 内容2 | 内容3 | 内容4 | 内容5 | 内容6 | 内容7 |',
  'info 卡片': ':::info 标题\n卡片内容\n:::',
  'warning 卡片': ':::warning\n注意\n:::',
  '无标题卡片': ':::tip\n内容\n:::',
  '折叠块': ':::details 点开\n里面一段话\n:::',
  '嵌套容器': ':::details 外\n:::tip 内\n内容\n:::\n:::',
  '行内公式': r'质能方程 $E = mc^2$ 就在这里。',
  '块级公式': '\$\$\n\\frac{a}{b} = c\n\$\$',
  '坏公式': r'$$ \frac{  $$',
  'mermaid':
      '```mermaid\ngraph TD\n  A[开始] --> B{判断}\n  B -->|是| C[处理]\n  B -->|否| D[结束]\n  C --> D\n```',
  'mermaid LR': '```mermaid\ngraph LR\n  X((圆)) --> Y[[子程序]]\n```',
  'mermaid 不支持': '```mermaid\nsequenceDiagram\n  A->>B: hi\n```',
  'mermaid 空': '```mermaid\n```',
  '图片（缺目录）': '![图注](missing.png)',
  '行内图片': '前面 ![alt](a.png) 后面',
  '空引用': '>',
  '列表空项': '- ',
  '多行引用卡片': '> [!NOTE] 标题\n> 第一行\n> 第二行',
};

Widget _wrap(Widget child, {double width = 900, bool dark = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  );
}

void main() {
  // 每个块在所有宽度上都必须能排版出来，且不抛异常
  for (final entry in _samples.entries) {
    for (final width in <double>[320, 760, 1200]) {
      testWidgets('块渲染 ${entry.key} @${width.toInt()}',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final doc = MdDocument.parse(entry.value);
        expect(doc.source, entry.value, reason: '样本必须无损往返');

        await tester.pumpWidget(_wrap(
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final b in doc.blocks)
                  Padding(
                    padding: BlockRenderer.paddingFor(b),
                    child: BlockRenderer(block: b, read: ReadContext.empty),
                  ),
              ],
            ),
          ),
          width: width,
        ));
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} 在宽度 $width 下排版抛异常',
        );
      });
    }
  }

  // 深色主题下同样要能排出来
  testWidgets('块渲染 深色主题', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final src in _samples.values)
              for (final b in MdDocument.parse(src).blocks)
                BlockRenderer(block: b, read: ReadContext.empty),
          ],
        ),
      ),
      dark: true,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------- 代码块

  testWidgets('代码块：换行开 / 关两种布局都能排出来', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => codeWrapPreference.value = true);

    const code = '```dart {2}\n'
        'void main() {\n'
        '  final veryLongVariableName = "一段相当长的内容用来逼出横向滚动而不是折行的情况";\n'
        '}\n'
        '```';

    final block = MdDocument.parse(code).blocks.single;

    for (final wrap in <bool>[true, false]) {
      codeWrapPreference.value = wrap;
      await tester.pumpWidget(_wrap(
        BlockRenderer(block: block, read: ReadContext.empty),
        width: 700,
      ));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '换行=${wrap ? "开" : "关"} 时排版抛异常',
      );
      expect(find.byType(CodeBlockView), findsOneWidget);
    }
  });

  testWidgets('代码块：行号数量与代码行数一致', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final block = MdDocument.parse('```\n1\n2\n3\n4\n```').blocks.single;
    await tester.pumpWidget(_wrap(
      BlockRenderer(block: block, read: ReadContext.empty),
      width: 700,
    ));
    await tester.pump();

    for (final n in <String>['1', '2', '3', '4']) {
      expect(find.text(n), findsWidgets, reason: '缺少行号 $n');
    }
  });

  // ---------------------------------------------------------------- Mermaid

  testWidgets('Mermaid：能画出节点与折线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      const SingleChildScrollView(
        child: MermaidView(source: 'graph TD\nA[开始] --> B[结束]'),
      ),
      width: 900,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('Mermaid：不支持的图降级成代码块', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      const SingleChildScrollView(
        child: MermaidView(source: 'sequenceDiagram\nA->>B: hi'),
      ),
      width: 900,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CodeBlockView), findsOneWidget);
    expect(find.textContaining('未能渲染'), findsOneWidget);
  });

  // -------------------------------------------------------------- 阅读模式

  testWidgets('阅读模式：欢迎文档能完整排出来', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      ReadingView(source: kWelcomeDoc),
      width: 1400,
    ));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('目录'), findsOneWidget);
  });

  testWidgets('阅读模式：窄窗口收起目录且不报错', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      ReadingView(source: kWelcomeDoc),
      width: 640,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('目录'), findsNothing);
  });

  testWidgets('阅读模式：空文档不崩', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const ReadingView(source: ''), width: 900));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('阅读模式：只有正文没有标题时不显示目录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(const ReadingView(source: '一段没有标题的正文。'), width: 1400),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('目录'), findsNothing);
  });

  // ---------------------------------------------------------------- 整体

  testWidgets('应用外壳：三种模式都能渲染', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const TyporaFlowApp());
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 切到阅读模式
    await tester.tap(find.byIcon(Icons.menu_book_outlined).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '切到阅读模式抛异常');

    // 切到源码模式
    await tester.tap(find.byIcon(Icons.code).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '切到源码模式抛异常');

    // 切回编辑模式
    await tester.tap(find.byIcon(Icons.edit_note_outlined).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '切回编辑模式抛异常');
  });

  testWidgets('应用外壳：深色主题', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const TyporaFlowApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.dark_mode_outlined).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.menu_book_outlined).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('调色板：明暗两套字段齐全', (tester) async {
    expect(MdPalette.light.isDark, isFalse);
    expect(MdPalette.dark.isDark, isTrue);
    expect(MdPalette.light.bg, isNot(MdPalette.dark.bg));
  });
}
