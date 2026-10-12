import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../md/inline.dart';
import '../ui/palette.dart';
import 'math_view.dart';

/// 统一的「行内 Markdown → TextSpan」入口。
///
/// 单独抽出来是为了收敛一个跨层依赖：行内公式要换成真正的公式控件，
/// 但 [inline] 层（分词）刻意不依赖任何公式库。这里把两者接上，
/// 表格、提示卡片、引用等渲染器统一调这几个函数，不必各自拼一遍。
TextSpan renderInline(
  List<InlineToken> tokens,
  TextStyle style,
  MdPalette p, {
  List<InlineSpan> Function(InlineToken token)? imageBuilder,
}) {
  if (imageBuilder == null) {
    return buildRenderedInline(
      tokens,
      style,
      p,
      mathBuilder: (tex) => InlineMath(tex: tex),
    );
  }
  final children = <InlineSpan>[];
  for (final t in tokens) {
    if (t.isMarker) continue;
    if (t.kind == InlineKind.math) {
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: InlineMath(tex: t.text),
      ));
      continue;
    }
    if (t.kind == InlineKind.image) {
      children.addAll(imageBuilder(t));
      continue;
    }
    children.add(TextSpan(
      text: t.text,
      style: inlineStyleFor(t.kind, style, p),
    ));
  }
  if (children.isEmpty) children.add(const TextSpan(text: ''));
  return TextSpan(style: style, children: children);
}

/// 直接从字符串渲染行内 Markdown。
TextSpan renderInlineText(String source, TextStyle style, MdPalette p) =>
    renderInline(tokenizeInline(source), style, p);

/// 行内 Markdown 的纯文本内容（隐藏标记后）。
String plainInlineText(String source) =>
    renderedPlainText(tokenizeInline(source));

/// 把一段 Markdown 渲染成块序列。
///
/// 提示卡片和折叠块的内部又是一段 Markdown，需要递归渲染。这里用注入而不是
/// 直接 import 块渲染器 —— 否则 [block_renderer] 与容器组件就互相依赖了，
/// 这种环在小工程里看不出问题，一旦要单独测试某一层就很别扭。
typedef MarkdownBlocksBuilder = Widget Function(
  BuildContext context,
  String markdown,
);

/// 行内 Markdown 的可交互渲染。
///
/// 用 StatefulWidget 而不是纯函数，是因为链接需要 [TapGestureRecognizer]，
/// 而它必须被显式释放 —— 放在 build 里现建现丢会稳定泄漏。
class RichInlineText extends StatefulWidget {
  const RichInlineText({
    super.key,
    required this.source,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.onOpenUrl,
    this.imageBuilder,
  });

  final String source;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;

  /// 点击链接时的回调。为空时链接只做样式，不可点。
  final ValueChanged<String>? onOpenUrl;

  /// 自定义行内图片的渲染。为空时图片退化成 alt 文本。
  final List<InlineSpan> Function(InlineToken token)? imageBuilder;

  @override
  State<RichInlineText> createState() => _RichInlineTextState();
}

class _RichInlineTextState extends State<RichInlineText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    // 上一帧的 recognizer 到这里就没用了，先释放再重建
    _release();

    final p = MdPalette.of(context);
    final tokens = tokenizeInline(widget.source);
    final children = <InlineSpan>[];

    for (final t in tokens) {
      if (t.isMarker) continue;

      if (t.kind == InlineKind.math) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InlineMath(tex: t.text),
        ));
        continue;
      }
      if (t.kind == InlineKind.image) {
        final custom = widget.imageBuilder;
        if (custom != null) {
          children.addAll(custom(t));
          continue;
        }
      }

      var style = inlineStyleFor(t.kind, widget.style, p);
      TapGestureRecognizer? recognizer;
      final url = t.url;
      if (t.kind == InlineKind.link &&
          url != null &&
          url.isNotEmpty &&
          widget.onOpenUrl != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onOpenUrl!(url);
        _recognizers.add(recognizer);
        style = style.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: p.link.withValues(alpha: 0.5),
        );
      }

      children.add(TextSpan(
        text: t.text,
        style: style,
        recognizer: recognizer,
      ));
    }

    if (children.isEmpty) children.add(const TextSpan(text: ''));

    return Text.rich(
      TextSpan(style: widget.style, children: children),
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
    );
  }
}
