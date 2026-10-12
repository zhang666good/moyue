import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'editor/block_editor.dart';
import 'editor/source_view.dart';
import 'io/file_service.dart';
import 'md/document.dart';
import 'read/block_renderer.dart';
import 'read/reading_view.dart';
import 'ui/brand_mark.dart';
import 'ui/outline_panel.dart';
import 'ui/palette.dart';

enum ViewMode {
  /// 所见即所得编辑。
  wysiwyg,

  /// 纯阅读：无光标，公式/图表/灯箱全部生效。
  reading,

  /// 源码模式，结构出问题时的兜底。
  source,
}

// 用原始字符串：正文里有 `$` 公式和 `\`，普通字符串会被当成插值和转义。
const String kWelcomeDoc = r'''# 墨阅 MoRead

> 墨落于纸，阅见所想。

用 **Flutter 原生实现**的 Markdown 编辑器与阅读器。既能像 Typora 那样所见即所得地写，
也能像语雀那样把文档读得舒服——代码块、公式、图表、表格、提示卡片全都在。

## 三种视图

工具栏中间的三段开关可以在三者之间切换：

- **编辑** —— 光标落在哪个块，哪个块就露出源码，语法标记用淡灰色显示
- **阅读** —— 没有光标，公式、图表、代码块、图片灯箱全部生效
- **源码** —— 兜底开关，复杂结构出问题时直接改原文

> 编辑模式下点击任意文字，光标会落到你真正点到的那个字符上。

## 快捷键

| 按键 | 作用 |
| :--- | :--- |
| `Ctrl+O` | 打开文件 |
| `Ctrl+S` | 保存 |
| `Ctrl+Shift+S` | 另存为 |
| `Ctrl+N` | 新建 |
| `Ctrl+\` | 展开／收起大纲 |
| `Ctrl+Shift+/` | 在编辑／阅读／源码之间轮换 |

## 代码块

行号、语法高亮、指定行高亮、一键复制、换行开关：

```dart {1,7}
class Greeter {
  final String name;
  Greeter(this.name);

  String greet() {
    // 第 7 行会被高亮
    return 'Hello there!';
  }
}
```

把鼠标移到代码块上，右上角会出现「换行」和「复制」两个按钮。

## 表格

| 能力 | 编辑 | 阅读 | 说明 |
| :--- | :-: | :-: | ---: |
| 语法高亮 | ✓ | ✓ | GitHub 明暗两套配色 |
| 行号 | — | ✓ | 阅读模式显示 |
| 图片灯箱 | — | ✓ | 点击放大 |
| 公式 | ✓ | ✓ | 块级与行内 |

## 提示卡片

:::info 两种写法都支持
容器式 `:::info 标题` … `:::`，以及引用式 `> [!NOTE]`。
解析层把它们归一成同一个块，渲染出来完全一致。
:::

:::tip 小技巧
块级公式用 `$$` 独占一行，行内公式用单个 `$`。
:::

:::warning 注意
表格、容器块是新增的解析分支，别的扩展语法不一定认识。
:::

:::danger 危险
源码模式下改坏了结构，目前还没有撤销栈可以救你。
:::

> [!NOTE] 引用式提示卡片
> 这种写法会一直吃到「连续的引用行」为止，所以它可以有好几行。
> 缩进的引用行也照样吞进去。

## 折叠块

:::details 点开看折叠块内部
折叠块内部是一段完整的 Markdown：

- 列表
- **粗体**、`行内代码`
- 还能再套一层：

:::tip 嵌套的提示卡片
容器块支持嵌套，内部递归渲染（有深度上限）。
:::
:::

## 公式

行内写作 $E = mc^2$，或者带上下标的 $a_1^2 + a_2^2 = a_3^2$。

块级公式：

$$
\frac{1}{\pi} = \frac{2\sqrt{2}}{9801} \sum_{k=0}^{\infty} \frac{(4k)!\,(1103 + 26390k)}{(k!)^4\,396^{4k}}
$$

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

渲染不出来时不会留白，而是把原始 TeX 摆出来 —— 至少能看出这里本来是个公式。

## 流程图

```mermaid
graph TD
    A[读取 .md 文件] --> B{解析成块}
    B -->|成功| C[按块渲染]
    B -->|失败| D[降级为段落]
    C --> E{光标在哪}
    E -->|有光标| F[TextField 编辑]
    E -->|无光标| G[只读富文本]
    F --> H[回传源码]
    G --> H
    H --> I[保存]
```

只支持 flowchart。碰到 `sequenceDiagram` 之类的图会降级成代码块并说明原因 ——
画错的图比不画更容易误导人。

## 阅读模式

切到阅读模式之后：

- 右侧悬浮目录，跟随滚动高亮，点击可跳转
- 顶部一条 2px 的阅读进度条
- 底部文档信息（字数 / 字符 / 行数 / 图片数）
- 图片点击放大，支持滚轮缩放、拖拽平移、左右切换、Esc 关闭

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开文件 | Ctrl + O |
| 保存 | Ctrl + S |
| 另存为 | Ctrl + Shift + S |
| 新建 | Ctrl + N |
| 切换大纲 | Ctrl + 反斜杠 |
| 循环切换视图 | Ctrl + Shift + 斜杠 |

---

拖拽打开文件还没做，先用工具栏的「打开」按钮。
''';

class TyporaFlowApp extends StatefulWidget {
  const TyporaFlowApp({super.key});

  @override
  State<TyporaFlowApp> createState() => _TyporaFlowAppState();
}

class _TyporaFlowAppState extends State<TyporaFlowApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  ThemeData _buildTheme(Brightness brightness) {
    final palette =
        brightness == Brightness.dark ? MdPalette.dark : MdPalette.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ),
      fontFamily: kUiFont,
      fontFamilyFallback: kUiFallback,
      scaffoldBackgroundColor: palette.bg,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨阅 MoRead',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: WorkspacePage(
        isDark: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  String _source = kWelcomeDoc;
  int _revision = 0;
  ViewMode _mode = ViewMode.wysiwyg;
  bool _showOutline = false;
  String? _path;
  String _fileName = '欢迎.md';
  bool _dirty = false;

  List<MdHeading> _headings = const <MdHeading>[];
  Map<int, GlobalKey> _headingKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _keyCache = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _refreshOutline();
  }

  // ------------------------------------------------------------------ 文档

  /// 重建大纲与标题锚点。GlobalKey 按块下标缓存复用，
  /// 否则每次打字都会换一批 key，标题块会被反复重建。
  void _refreshOutline() {
    final doc = MdDocument.parse(_source);
    final headings = doc.headings;
    final keys = <int, GlobalKey>{};
    for (final h in headings) {
      keys[h.blockIndex] =
          _keyCache.putIfAbsent(h.blockIndex, () => GlobalKey());
    }
    _headings = headings;
    _headingKeys = keys;
  }

  void _onSourceChanged(String s) {
    // 内容没变就什么都不做。除了省掉一次全文重新解析（_refreshOutline 会
    // 整篇 parse 一遍），也顺手挡掉了「子组件回传了和父级相同的内容」这类
    // 无意义重建 —— 那正是 build 阶段调用 setState 的高发场景。
    if (s == _source) return;
    setState(() {
      _source = s;
      _dirty = true;
      _refreshOutline();
    });
  }

  void _replaceDocument(String content, {String? path, String? name}) {
    setState(() {
      _source = content;
      _path = path;
      _fileName = name ??
          (path == null
              ? '未命名.md'
              : path.split(RegExp(r'[\\/]')).last);
      _revision++;
      _dirty = false;
      _refreshOutline();
    });
  }

  // ------------------------------------------------------------------ 动作

  Future<void> _open() async {
    try {
      final file = await FileService.openMarkdown();
      if (file == null) return;
      _replaceDocument(file.content, path: file.path, name: file.name);
      _toast('已打开 ${file.name}');
    } catch (e) {
      _toast('打开失败：$e');
    }
  }

  Future<void> _save() async {
    if (_path == null) {
      await _saveAs();
      return;
    }
    try {
      await FileService.write(_path!, _source);
      if (!mounted) return;
      setState(() => _dirty = false);
      _toast('已保存 $_fileName');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _saveAs() async {
    try {
      final path = await FileService.saveAs(
        _source,
        suggestedName: _fileName.isEmpty ? 'untitled.md' : _fileName,
      );
      if (path == null) return;
      if (!mounted) return;
      setState(() {
        _path = path;
        _fileName = path.split(RegExp(r'[\\/]')).last;
        _dirty = false;
      });
      _toast('已保存 $_fileName');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  void _newDocument() {
    _replaceDocument('', name: '未命名.md');
    _toast('已新建空白文档');
  }

  void _toggleOutline() => setState(() => _showOutline = !_showOutline);

  /// Ctrl+Shift+/ 在三者之间循环，而不是只做两态切换。
  void _cycleMode() => setState(() {
        _mode = switch (_mode) {
          ViewMode.wysiwyg => ViewMode.reading,
          ViewMode.reading => ViewMode.source,
          ViewMode.source => ViewMode.wysiwyg,
        };
      });

  /// 文档所在目录。图片的相对路径按它解析。
  String? get _baseDir => _path == null ? null : path.dirname(_path!);

  /// 打开外链。用系统浏览器，不在应用内开网页。
  void _openUrl(String url) {
    // 内部锚点（`#标题`）暂不处理，直接忽略比弹个错要好
    if (url.startsWith('#')) return;
    openExternalLink(url);
  }

  void _jumpToHeading(MdHeading h) {
    final ctx = _headingKeys[h.blockIndex]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      alignment: 0.05,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ------------------------------------------------------------------ 统计

  ({int words, int chars, int lines, int minutes}) _stats() {
    final s = docStats(_source);
    final minutes = s.words == 0 ? 1 : (s.words / 300).ceil();
    return (
      words: s.words,
      chars: s.chars,
      lines: s.lines,
      minutes: minutes,
    );
  }

  /// 三种视图的切换。用图标分段控件而不是图标按钮：
  /// 两态可以用一个按钮来回切，三态就必须能直接看到「现在在哪一档」。
  Widget _modeSelector(MdPalette p) {
    return SegmentedButton<ViewMode>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<ViewMode>>[
        ButtonSegment<ViewMode>(
          value: ViewMode.wysiwyg,
          icon: Icon(Icons.edit_note_outlined, size: 16),
          tooltip: '编辑模式',
        ),
        ButtonSegment<ViewMode>(
          value: ViewMode.reading,
          icon: Icon(Icons.menu_book_outlined, size: 16),
          tooltip: '阅读模式',
        ),
        ButtonSegment<ViewMode>(
          value: ViewMode.source,
          icon: Icon(Icons.code, size: 16),
          tooltip: '源码模式',
        ),
      ],
      selected: <ViewMode>{_mode},
      onSelectionChanged: (selection) =>
          setState(() => _mode = selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStatePropertyAll<Color?>(p.bg),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: p.border),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 构建

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onPressed) {
    final p = MdPalette.of(context);
    return IconButton(
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      color: p.textMuted,
      hoverColor: p.border,
      onPressed: onPressed,
    );
  }

  Widget _statusText(String text, MdPalette p) => Text(
        text,
        style: TextStyle(fontSize: 11.5, color: p.textMuted),
      );

  PreferredSizeWidget _appBar(MdPalette p) {
    return AppBar(
      toolbarHeight: 54,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 18,
      title: Row(
        children: <Widget>[
          const BrandMark(size: 22),
          const SizedBox(width: 9),
          Text(
            '墨阅',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: p.text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              _fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.textMuted),
            ),
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: p.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        _iconButton(Icons.note_add_outlined, '新建 (Ctrl+N)', _newDocument),
        _iconButton(Icons.folder_open_outlined, '打开 (Ctrl+O)', _open),
        _iconButton(Icons.save_outlined, '保存 (Ctrl+S)', _save),
        _iconButton(Icons.save_as_outlined, '另存为 (Ctrl+Shift+S)', _saveAs),
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: p.border,
        ),
        _iconButton(
          _showOutline ? Icons.toc : Icons.toc_outlined,
          '大纲 (Ctrl+反斜杠)',
          _toggleOutline,
        ),
        const SizedBox(width: 4),
        _modeSelector(p),
        const SizedBox(width: 10),
        _iconButton(
          widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          '切换主题',
          widget.onToggleTheme,
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: p.border),
      ),
    );
  }

  Widget _editorArea(MdPalette p) {
    // 阅读模式自带右侧目录与进度条，左侧大纲就不重复显示了。
    final showSideOutline = _showOutline && _mode != ViewMode.reading;

    return Row(
      children: <Widget>[
        if (showSideOutline)
          OutlinePanel(
            headings: _headings,
            palette: p,
            onJump: _jumpToHeading,
          ),
        Expanded(child: _body(p)),
      ],
    );
  }

  Widget _body(MdPalette p) {
    switch (_mode) {
      case ViewMode.wysiwyg:
        return BlockEditor(
          source: _source,
          revision: _revision,
          palette: p,
          onChanged: _onSourceChanged,
          headingKeys: _headingKeys,
          baseDir: _baseDir,
        );
      case ViewMode.reading:
        return ReadingView(
          source: _source,
          baseDir: _baseDir,
          onOpenUrl: _openUrl,
        );
      case ViewMode.source:
        return SourceView(
          source: _source,
          revision: _revision,
          palette: p,
          onChanged: _onSourceChanged,
        );
    }
  }

  String get _modeLabel => switch (_mode) {
        ViewMode.wysiwyg => '编辑模式',
        ViewMode.reading => '阅读模式',
        ViewMode.source => '源码模式',
      };

  Widget _statusBar(MdPalette p) {
    final s = _stats();
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          _statusText('${s.words} 字', p),
          const SizedBox(width: 16),
          _statusText('${s.chars} 字符', p),
          const SizedBox(width: 16),
          _statusText('${s.lines} 行', p),
          const SizedBox(width: 16),
          _statusText('${s.minutes} 分钟阅读', p),
          const Spacer(),
          _statusText(_modeLabel, p),
          const SizedBox(width: 16),
          _statusText(
            _mode == ViewMode.reading ? '只读' : (_dirty ? '未保存' : '已保存'),
            p,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): _saveAs,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _newDocument,
        const SingleActivator(LogicalKeyboardKey.backslash, control: true):
            _toggleOutline,
        const SingleActivator(
          LogicalKeyboardKey.slash,
          control: true,
          shift: true,
        ): _cycleMode,
      },
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: _appBar(p),
        body: Column(
          children: <Widget>[
            Expanded(child: _editorArea(p)),
            _statusBar(p),
          ],
        ),
      ),
    );
  }
}
