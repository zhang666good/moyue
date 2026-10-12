import 'package:flutter/material.dart';

import '../md/document.dart';
import '../ui/palette.dart';
import 'block_renderer.dart';
import 'image_figure.dart';
import 'outline_rail.dart';

/// 文档统计。
///
/// 中文按字算、西文按词算 —— 只按空格分词的话，一整段中文会被算成 1 个词，
/// 数字会离谱到没人信。
({int words, int chars, int lines}) docStats(String source) {
  final cjk = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')
      .allMatches(source)
      .length;
  final latin =
      RegExp(r"[A-Za-z0-9_']+").allMatches(source).length;
  return (
    words: cjk + latin,
    chars: source.runes.length,
    lines: source.isEmpty ? 0 : source.split('\n').length,
  );
}

final RegExp _imageRe = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)');

/// 把整篇文档里的图片地址扫出来，供灯箱左右切换。
List<ImageRef> collectImages(String source, String? baseDir) {
  final out = <ImageRef>[];
  for (final m in _imageRe.allMatches(source)) {
    out.add(ImageRef(
      source: m.group(2)!,
      alt: m.group(1) ?? '',
      baseDir: baseDir,
    ));
  }
  return out;
}

/// 阅读模式。
///
/// 与编辑模式的区别不只是「不能编辑」：这里有右侧目录、阅读进度、
/// 文档信息，块也全部渲染成最终形态（公式、图表、灯箱）。
class ReadingView extends StatefulWidget {
  const ReadingView({
    super.key,
    required this.source,
    this.baseDir,
    this.onOpenUrl,
    this.showOutline = true,
  });

  final String source;

  /// 文档所在目录，用于解析图片相对路径。
  final String? baseDir;

  final ValueChanged<String>? onOpenUrl;

  final bool showOutline;

  /// 正文最大宽度。太宽的行会让眼睛在换行处找不着下一行的开头。
  static const double bodyWidth = 860;

  /// 目录显示的宽度阈值：窗口更窄时直接收起来，正文优先。
  static const double outlineBreakpoint = 1040;

  @override
  State<ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<ReadingView> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();

  List<MdHeading> _headings = <MdHeading>[];
  Map<int, GlobalKey> _headingKeys = <int, GlobalKey>{};
  ReadContext _read = ReadContext.empty;
  int _active = -1;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ReadingView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source ||
        old.baseDir != widget.baseDir ||
        old.onOpenUrl != widget.onOpenUrl) {
      setState(_load);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    final doc = MdDocument.parse(widget.source);
    _headings = doc.headings;
    _headingKeys = <int, GlobalKey>{
      for (final h in _headings) h.blockIndex: GlobalKey(),
    };
    final images = collectImages(widget.source, widget.baseDir);
    _read = ReadContext(
      baseDir: widget.baseDir,
      images: images,
      imageIndex: <String, int>{
        for (var i = 0; i < images.length; i++) images[i].source: i,
      },
      onOpenUrl: widget.onOpenUrl,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final max = pos.maxScrollExtent;
    final progress = max <= 0 ? 0.0 : (pos.pixels / max).clamp(0.0, 1.0);

    final active = _activeHeading();
    if (active == _active && (progress - _progress).abs() < 0.002) return;
    setState(() {
      _active = active;
      _progress = progress;
    });
  }

  /// 视口顶部往下 96px 处为界，最后一个越过这条线的标题就是当前项。
  int _activeHeading() {
    final viewport = _viewportKey.currentContext;
    if (viewport == null || _headings.isEmpty) return -1;
    final vBox = viewport.findRenderObject();
    if (vBox is! RenderBox || !vBox.hasSize) return -1;
    final top = vBox.localToGlobal(Offset.zero).dy;

    var found = -1;
    for (var i = 0; i < _headings.length; i++) {
      final ctx = _headingKeys[_headings[i].blockIndex]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy - top;
      if (y <= 96) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  void _jumpTo(int headingIndex) {
    final blockIndex = _headings[headingIndex].blockIndex;
    final ctx = _headingKeys[blockIndex]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.02,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final doc = MdDocument.parse(widget.source);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= ReadingView.outlineBreakpoint;
        final showRail = widget.showOutline && wide && _headings.length >= 2;

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ProgressBar(value: _progress, palette: p),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        key: _viewportKey,
                        controller: _scroll,
                        padding: const EdgeInsets.only(top: 26, bottom: 120),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: ReadingView.bodyWidth,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: SelectionArea(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    for (var i = 0; i < doc.blocks.length; i++)
                                      _block(i, doc.blocks[i]),
                                    _footer(doc, p),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showRail)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 16, 0),
                      child: OutlineRail(
                        headings: _headings,
                        activeIndex: _active,
                        onJump: _jumpTo,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

        return content;
      },
    );
  }

  Widget _block(int index, MdBlock b) {
    final child = BlockRenderer(block: b, read: _read);
    final key = _headingKeys[index];
    final padded = Padding(padding: BlockRenderer.paddingFor(b), child: child);
    if (key == null) return padded;
    return KeyedSubtree(key: key, child: padded);
  }

  Widget _footer(MdDocument doc, MdPalette p) {
    final s = docStats(widget.source);
    final images = _read.images.length;
    final parts = <String>[
      '${s.words} 字',
      '${s.chars} 字符',
      '${s.lines} 行',
      if (images > 0) '$images 张图片',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(height: 1, color: p.border),
          const SizedBox(height: 12),
          Text(
            parts.join(' · '),
            textAlign: TextAlign.center,
            style: MdType.body(p).copyWith(
              fontSize: 12.5,
              color: p.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部阅读进度条。细到 2px —— 它的作用是「扫一眼知道还剩多少」，
/// 不该抢正文的注意力。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.palette});

  final double value;
  final MdPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          // heightFactor 必须给：Align 会把约束放宽，只给 widthFactor 的话
          // 高度会退化成 0，整条进度条就看不见了。
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: palette.accent),
        ),
      ),
    );
  }
}
