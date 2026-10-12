import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../md/document.dart';
import '../md/inline.dart';
import '../ui/palette.dart';
import 'callout_view.dart';
import 'code_block_view.dart';
import 'code_spans.dart';
import 'image_figure.dart';
import 'inline_render.dart';
import 'math_view.dart';
import 'mermaid_view.dart';
import 'table_view.dart';

/// 渲染一个块时需要的、来自文档整体的东西。
@immutable
class ReadContext {
  const ReadContext({
    this.baseDir,
    this.images = const <ImageRef>[],
    this.imageIndex = const <String, int>{},
    this.onOpenUrl,
  });

  /// 文档所在目录，用来解析图片的相对路径。
  final String? baseDir;

  /// 文档里的全部图片，供灯箱左右切换。
  final List<ImageRef> images;

  /// 图片原始地址 → 在 [images] 里的下标。
  final Map<String, int> imageIndex;

  final ValueChanged<String>? onOpenUrl;

  static const ReadContext empty = ReadContext();

  ReadContext copyWith({
    String? baseDir,
    List<ImageRef>? images,
    Map<String, int>? imageIndex,
    ValueChanged<String>? onOpenUrl,
  }) {
    return ReadContext(
      baseDir: baseDir ?? this.baseDir,
      images: images ?? this.images,
      imageIndex: imageIndex ?? this.imageIndex,
      onOpenUrl: onOpenUrl ?? this.onOpenUrl,
    );
  }
}

/// 块渲染器。
///
/// 阅读模式和编辑器的「非活动块」共用这一份实现：
/// - 编辑模式传入 [onTapOffset]，点哪儿就把光标放到哪儿；
/// - 阅读模式传 null，图片灯箱、折叠块等交互才生效。
///
/// 保持一份实现是有意的 —— 同一个块在两种模式下长得不一样，
/// 是很显眼的质量问题。
class BlockRenderer extends StatelessWidget {
  const BlockRenderer({
    super.key,
    required this.block,
    required this.read,
    this.onTapOffset,
    this.depth = 0,
  });

  final MdBlock block;
  final ReadContext read;

  /// 编辑模式下点中某处时回调（参数是块内**原文**偏移，-1 表示落到块尾）。
  final ValueChanged<int>? onTapOffset;

  /// 嵌套深度。容器块内部又是一段文档，必须设上限防止构造出无限深的树。
  final int depth;

  static const int maxDepth = 4;

  /// 块与块之间的垂直间距。编辑器和阅读模式共用，保证切换视图时版面不跳。
  static EdgeInsets paddingFor(MdBlock b) {
    switch (b.type) {
      case BlockType.heading:
        return const EdgeInsets.only(top: 16, bottom: 6);
      case BlockType.divider:
        return const EdgeInsets.symmetric(vertical: 8);
      case BlockType.code:
      case BlockType.table:
      case BlockType.callout:
      case BlockType.details:
      case BlockType.mathBlock:
        return const EdgeInsets.symmetric(vertical: 6);
      case BlockType.paragraph:
      case BlockType.quote:
      case BlockType.bullet:
      case BlockType.ordered:
        return const EdgeInsets.symmetric(vertical: 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    switch (block.type) {
      case BlockType.heading:
        return _inline(block.content, MdType.heading(p, block.level), p);
      case BlockType.divider:
        return _divider(p);
      case BlockType.code:
        return _code();
      case BlockType.quote:
        return _quote(p);
      case BlockType.bullet:
      case BlockType.ordered:
        return _list(p);
      case BlockType.table:
        return _table();
      case BlockType.callout:
        return _callout();
      case BlockType.details:
        return _details();
      case BlockType.mathBlock:
        return _math();
      case BlockType.paragraph:
        return _paragraph(p);
    }
  }

  // ---------------------------------------------------------------- 行内块

  /// 行内文本 + 点击定位。空块渲染成一个空格以保证行高与可点区域。
  Widget _inline(String content, TextStyle style, MdPalette p) {
    final tokens = tokenizeInline(content);
    final plain = renderedPlainText(tokens);

    final text = plain.trim().isEmpty
        ? Text(' ', style: style)
        : Text.rich(renderInline(tokens, style, p));

    final boxed = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 26),
      child: Align(alignment: Alignment.centerLeft, child: text),
    );

    if (onTapOffset == null) return boxed;

    return _TapArea(
      tokens: tokens,
      baseStyle: style,
      palette: p,
      onOffset: onTapOffset!,
      child: boxed,
    );
  }

  Widget _paragraph(MdPalette p) {
    // 独占一行的图片渲染成「图 + 图注」，而不是塞在段落里
    final lone = _loneImage(block.content);
    if (lone != null) {
      final url = lone.url ?? '';
      return _figure(ImageRef(source: url, alt: lone.text, baseDir: read.baseDir), url);
    }
    return _inline(block.content, MdType.body(p), p);
  }

  Widget _figure(ImageRef ref, String url) {
    return ImageFigure(
      image: ref,
      // 编辑模式下点图片应该激活块去改文本，所以不挂灯箱
      gallery: onTapOffset == null ? read.images : null,
      index: read.imageIndex[url] ?? 0,
      onTap: () => onTapOffset?.call(-1),
    );
  }

  /// 整块就是一个图片语法时返回那个图片令牌。
  InlineToken? _loneImage(String content) {
    InlineToken? found;
    var count = 0;
    for (final t in tokenizeInline(content)) {
      if (t.isMarker) continue;
      if (t.kind == InlineKind.text && t.text.trim().isEmpty) continue;
      count++;
      if (count > 1) return null;
      found = t;
    }
    return (count == 1 && found!.kind == InlineKind.image) ? found : null;
  }

  Widget _divider(MdPalette p) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onTapOffset?.call(-1),
      child: SizedBox(
        height: 26,
        child: Center(child: Container(height: 1.5, color: p.border)),
      ),
    );
  }

  Widget _quote(MdPalette p) {
    final style = MdType.body(p).copyWith(color: p.textMuted);
    const borderWidth = 3.0;
    const pad = EdgeInsets.fromLTRB(12, 8, 12, 8);

    return Container(
      decoration: BoxDecoration(
        color: p.quoteBg,
        border: Border(
          left: BorderSide(color: p.quoteBar, width: borderWidth),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: pad,
      child: _inline(block.content, style, p),
    );
  }

  Widget _list(MdPalette p) {
    final style = MdType.body(p);
    final label = block.type == BlockType.bullet
        ? '•'
        : '${MdDocument.orderedIndex(block)}.';
    const gutter = 30.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: gutter,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(label, style: style.copyWith(color: p.textMuted)),
          ),
        ),
        Expanded(child: _inline(block.content, style, p)),
      ],
    );
  }

  // ------------------------------------------------------------------ 代码

  Widget _code() {
    final lang = block.lang;
    if (lang.toLowerCase() == 'mermaid') {
      return MermaidView(source: block.content, language: lang);
    }
    final tap = onTapOffset;
    return CodeBlockView(
      code: block.content,
      language: lang,
      highlightSpec: fenceHighlightSpec(block.prefix),
      compact: tap != null,
      onTapAt: tap == null
          ? null
          : (offsetInCode) => tap(
                offsetInCode < 0 ? -1 : block.prefix.length + offsetInCode,
              ),
    );
  }

  // ------------------------------------------------------------------ 表格

  Widget _table() {
    return TableView(
      table: MdTable.parse(block.content),
      onTap: () => onTapOffset?.call(-1),
    );
  }

  // -------------------------------------------------------------- 容器块

  Widget _callout() {
    return CalloutView(
      kind: block.variant,
      title: block.title,
      body: block.body,
      blocksBuilder: _nested,
    );
  }

  Widget _details() {
    return DetailsView(
      title: block.title,
      body: block.body,
      blocksBuilder: _nested,
    );
  }

  /// 容器块内部再是一段 Markdown。
  ///
  /// 不往下传 [onTapOffset]：在编辑器里，内层内容属于外层块的一部分，
  /// 点它应该激活**外层**块去改原文，而不是去激活一个不存在的内层块。
  Widget _nested(BuildContext context, String markdown) {
    final p = MdPalette.of(context);
    if (depth >= maxDepth || markdown.trim().isEmpty) {
      return Text(
        markdown,
        style: MdType.body(p).copyWith(color: p.textMuted),
      );
    }
    final doc = MdDocument.parse(markdown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final b in doc.blocks)
          Padding(
            padding: paddingFor(b),
            child: BlockRenderer(block: b, read: read, depth: depth + 1),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ 公式

  Widget _math() {
    return BlockMathView(
      tex: block.content,
      onTap: onTapOffset == null ? null : () => onTapOffset!(-1),
    );
  }
}

/// 点击命中测试：把点击位置换算成「原文偏移」。
///
/// 用与显示一致的文本和样式跑一次 [TextPainter]，再取
/// [TextPainter.getPositionForOffset]，最后把「隐藏标记后的偏移」映射回
/// 「含标记的原文偏移」。这样光标落在用户真正点到的字符上，
/// 而不是粗暴地跳到块尾。
class _TapArea extends StatelessWidget {
  const _TapArea({
    required this.child,
    required this.tokens,
    required this.baseStyle,
    required this.palette,
    required this.onOffset,
  });

  final Widget child;
  final List<InlineToken> tokens;
  final TextStyle baseStyle;
  final MdPalette palette;
  final ValueChanged<int> onOffset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            var raw = -1;
            try {
              final painter = TextPainter(
                // 量宽时用不带控件的版本：公式和图片在显示时是 WidgetSpan，
                // 宽度对不上 TextPainter。分词层给这类令牌留的 layoutLength
                // 是 1，renderedOffsetToRaw 会把落点吸附到令牌开头。
                text: buildRenderedInline(tokens, baseStyle, palette),
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: maxWidth);
              final pos = painter.getPositionForOffset(details.localPosition);
              raw = renderedOffsetToRaw(tokens, pos.offset);
            } catch (_) {
              raw = -1;
            }
            onOffset(raw);
          },
          child: child,
        );
      },
    );
  }
}

/// 用系统默认程序打开外链。
///
/// 只放行几个明确安全的 scheme：`javascript:`、`file:` 这类交给外部程序
/// 处理并不合适，直接忽略。
Future<void> openExternalLink(String raw) async {
  final url = raw.trim();
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  const allowed = <String>{'http', 'https', 'mailto'};
  if (!allowed.contains(uri.scheme.toLowerCase())) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // 打不开就打不开，阅读器不该因此中断
  }
}
