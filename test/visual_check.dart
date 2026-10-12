// 可视化检查：把界面真渲染成 PNG，用来人眼看效果。
//
// 刻意**不**叫 `*_test.dart`：`flutter test` 只收集 `*_test.dart`，
// 所以它不会进默认测试集。golden 图依赖本机字体，换台机器必然不匹配，
// 放进主测试套件只会制造无意义的失败。手动运行：
//
//   flutter test test/visual_check.dart --update-goldens
//
// 产出在 test/goldens/ 下。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:moread/app.dart';
import 'package:moread/md/document.dart';
import 'package:moread/read/block_renderer.dart';
import 'package:moread/read/code_block_view.dart';
import 'package:moread/read/reading_view.dart';
import 'package:moread/ui/palette.dart';

/// 测试环境默认用一套占位字体（所有字都画成方块），
/// 所以必须把系统字体真正装进来，产出的图才有可读性。
Future<void> _register(String family, List<String> paths) async {
  final existing = paths.where((p) => File(p).existsSync()).toList();
  if (existing.isEmpty) {
    // ignore: avoid_print
    print('!! 字体缺失，$family 将退化为占位字体');
    return;
  }
  final loader = FontLoader(family);
  for (final p in existing) {
    loader.addFont(
      File(p).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 西文正文
    await _register('Segoe UI', <String>[r'C:\Windows\Fonts\segoeui.ttf']);
    // 中文回退链。Segoe UI 不含汉字，缺了会全是方框。
    for (final name in <String>[
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans SC',
    ]) {
      await _register(name, <String>[r'C:\Windows\Fonts\simhei.ttf']);
    }
    await _register('Consolas', <String>[r'C:\Windows\Fonts\consola.ttf']);

    // 图标字体。测试环境不会自动带进来，不装的话所有 Icons 都是空方框 ——
    // 那会让截图完全没法看。真实 app 里它是被 uses-material-design 打进去的。
    await _register('MaterialIcons', <String>[
      r'D:\aiitem\k_md\flutter_app\build\flutter_assets\fonts\MaterialIcons-Regular.otf',
      r'D:\software\flutter_sdk\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    ]);

    // 数学字体。Cambria Math 在 cambria.ttc 里，能否装上取决于
    // TTC 的支持情况；装不上公式会退化成方框，这是截图环境的限制。
    await _register('Cambria Math', <String>[r'C:\Windows\Fonts\cambria.ttc']);
    await _register('Latin Modern Math', <String>[r'C:\Windows\Fonts\georgia.ttf']);
    await _register('Times New Roman', <String>[r'C:\Windows\Fonts\times.ttf']);
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget body, {
    Size size = const Size(1500, 950),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(body);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
    await tester.binding.setSurfaceSize(null);
  }

  // ---------------------------------------------------------------- 编辑态

  testWidgets('01 编辑模式', (tester) async {
    await shoot(tester, '01_edit_light', const TyporaFlowApp());
  });

  testWidgets('02 编辑模式 深色', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    await tester.pumpWidget(const TyporaFlowApp());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.dark_mode_outlined).first);
    await tester.pump();
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/02_edit_dark.png'),
    );
    await tester.binding.setSurfaceSize(null);
  });

  // ---------------------------------------------------------------- 阅读态

  Future<void> shootDoc(
    WidgetTester tester,
    String name,
    String source, {
    bool dark = false,
    double width = 1400,
    double height = 950,
  }) async {
    final palette = dark ? MdPalette.dark : MdPalette.light;
    await shoot(
      tester,
      name,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: kUiFont,
          fontFamilyFallback: kUiFallback,
        ),
        home: Scaffold(
          backgroundColor: palette.bg,
          body: ReadingView(source: source),
        ),
      ),
      size: Size(width, height),
    );
  }

  testWidgets('03 阅读 代码块', (tester) async {
    await shootDoc(
      tester,
      '03_read_code',
      '## 代码块\n\n'
      '```dart {2,6-7}\n'
      'class Greeter {\n'
      '  final String name;\n'
      '  Greeter(this.name);\n'
      '\n'
      '  String greet() {\n'
      '    // 高亮行\n'
      "    return 'Hello, \$name!';\n"
      '  }\n'
      '}\n'
      '```\n\n'
      '```json\n'
      '{"name": "k_md", "stars": 42, "tags": ["markdown", "flutter"]}\n'
      '```\n',
      height: 820,
    );
  });

  testWidgets('04 阅读 表格与提示卡片', (tester) async {
    await shootDoc(
      tester,
      '04_read_table_callout',
      '## 表格\n\n'
      '| 能力 | 编辑 | 阅读 | 说明 |\n'
      '| :--- | :-: | :-: | ---: |\n'
      '| 语法高亮 | ✓ | ✓ | GitHub 配色 |\n'
      '| 行号 | — | ✓ | 阅读模式显示 |\n'
      '| 图片灯箱 | — | ✓ | 点击放大 |\n\n'
      '## 提示卡片\n\n'
      ':::info 两种写法都支持\n'
      '容器式和引用式会归一成同一个块。\n'
      ':::\n\n'
      ':::tip 小技巧\n'
      '块级公式用 `\$\$` 独占一行。\n'
      ':::\n\n'
      ':::warning 注意\n'
      '这是警告样式。\n'
      ':::\n\n'
      ':::danger 危险\n'
      '这是危险样式。\n'
      ':::\n',
      height: 980,
    );
  });

  testWidgets('05 阅读 公式与流程图', (tester) async {
    await shootDoc(
      tester,
      '05_read_math_mermaid',
      '## 公式\n\n'
      '行内 \$E = mc^2\$ 与 \$a_1^2 + a_2^2 = a_3^2\$。\n\n'
      '\$\$\n'
      '\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}\n'
      '\$\$\n\n'
      '## 流程图\n\n'
      '```mermaid\n'
      'graph TD\n'
      '    A[读取 .md 文件] --> B{解析成块}\n'
      '    B -->|成功| C[按块渲染]\n'
      '    B -->|失败| D[降级为段落]\n'
      '    C --> E{光标在哪}\n'
      '    E -->|有光标| F[TextField 编辑]\n'
      '    E -->|无光标| G[只读富文本]\n'
      '    F --> H[回传源码]\n'
      '    G --> H\n'
      '```\n',
      height: 1020,
    );
  });

  testWidgets('06 阅读 折叠块与引用卡片', (tester) async {
    await shootDoc(
      tester,
      '06_read_details',
      '## 折叠块\n\n'
      ':::details 点开看折叠块内部\n'
      '折叠块内部是一段完整的 Markdown：\n\n'
      '- 列表\n'
      '- **粗体**、`行内代码`\n'
      ':::\n\n'
      '## 引用式提示卡片\n\n'
      '> [!NOTE] 引用式写法\n'
      '> 这种写法会一直吃到连续的引用行为止。\n'
      '> 所以它可以有好几行。\n\n'
      '## 引用块\n\n'
      '> 普通引用和提示卡片是两个块类型。\n',
      height: 700,
    );
  });

  testWidgets('07 阅读 深色主题', (tester) async {
    await shootDoc(
      tester,
      '07_read_dark',
      '## 深色主题\n\n'
      '| 列 A | 列 B |\n'
      '| :--- | ---: |\n'
      '| 值 | 值 |\n\n'
      ':::warning 注意\n'
      '深色下的卡片配色。\n'
      ':::\n\n'
      '```dart {2}\n'
      'void main() {\n'
      '  // 注释\n'
      "  print('hello');\n"
      '}\n'
      '```\n\n'
      '行内公式 \$x^2 + y^2 = z^2\$。\n',
      dark: true,
      height: 900,
    );
  });

  testWidgets('08 阅读 图片缺失占位', (tester) async {
    await shootDoc(
      tester,
      '08_read_missing_image',
      '## 图片\n\n'
      '独占一行的图片会渲染成「图 + 图注」：\n\n'
      '![这是一张不存在的图片的图注](images/demo.png)\n\n'
      '行内图片则贴在文字中间：前面 ![alt](a.png) 后面。\n',
      height: 520,
    );
  });

  testWidgets('09 阅读 不换行的代码块', (tester) async {
    codeWrapPreference.value = false;
    addTearDown(() => codeWrapPreference.value = true);
    await shootDoc(
      tester,
      '09_read_code_nowrap',
      '## 关闭自动换行\n\n'
      '```dart\n'
      'final veryLongVariableName = "一段相当长的内容，用来逼出横向滚动条而不是折行";\n'
      'short();\n'
      '```\n',
      height: 400,
      width: 900,
    );
  });

  testWidgets('10 阅读 目录跟随', (tester) async {
    await shootDoc(
      tester,
      '10_read_outline',
      List<String>.generate(
        14,
        (i) => '## 第 $i 节\n\n这是第 $i 节的内容，用来把目录撑长。\n',
      ).join('\n'),
      height: 900,
    );
  });

  // 各块类型的密集对照表，方便一次性比对
  testWidgets('11 块类型总览', (tester) async {
    const samples = <String>[
      '# 一级标题',
      '## 二级标题',
      '### 三级标题',
      '',
      '普通段落，带 **粗体**、*斜体*、`行内代码`、~~删除线~~ 和 [链接](https://x.com)。',
      '',
      '> 引用块，左侧有一条竖线。',
      '',
      '- 无序列表项',
      '- 第二项',
      '',
      '1. 有序列表项',
      '2. 第二项',
      '',
      '---',
      '',
      r'行内公式 $E = mc^2$ 混在文字里。',
    ];
    final doc = MdDocument.parse(samples.join('\n'));
    await shoot(
      tester,
      '11_block_gallery',
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: kUiFont,
          fontFamilyFallback: kUiFallback,
        ),
        home: Scaffold(
          backgroundColor: MdPalette.light.bg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
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
        ),
      ),
      size: const Size(820, 900),
    );
  });
}
