import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;

import '../ui/palette.dart';

/// 行内公式 `$x$`。
///
/// 走 [fm.MathStyle.text]：行内公式要贴着正文的基线，用 display 样式
/// 会把行高撑起来，正文节奏就断了。
class InlineMath extends StatelessWidget {
  const InlineMath({super.key, required this.tex});

  final String tex;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return fm.Math.tex(
      tex,
      mathStyle: fm.MathStyle.text,
      textStyle: MdType.math(p, size: MdType.bodySize - 0.5),
      onErrorFallback: (_) => MathFallback(tex: tex),
    );
  }
}

/// 块级公式 `$$ … $$`。
class BlockMathView extends StatelessWidget {
  const BlockMathView({super.key, required this.tex, this.onTap});

  final String tex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final math = fm.Math.tex(
      tex,
      mathStyle: fm.MathStyle.display,
      textStyle: MdType.math(p, size: 17),
      onErrorFallback: (_) => MathFallback(tex: tex, block: true),
    );

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final avail =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: avail - 8),
            // Center 在宽度无界时会自动收缩，所以这里能「够宽就居中、
            // 不够宽就横向滚动」，不会因为 maxWidth 无穷而断言失败。
            child: Center(child: math),
          ),
        );
      },
    );

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: body,
      ),
    );

    if (onTap == null) return content;
    return MouseRegion(cursor: SystemMouseCursors.text, child: content);
  }
}

/// 公式解析失败时的降级展示。
///
/// 直接把原始 TeX 摆出来：读者一眼能看出「这里本来是个公式」，
/// 而不是看到一段莫名其妙的红字或一片空白。
class MathFallback extends StatelessWidget {
  const MathFallback({super.key, required this.tex, this.block = false});

  final String tex;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.codeBorder, width: 0.5),
      ),
      child: Text(
        block ? tex.trim() : tex,
        style: MdType.mono(p, size: block ? 13 : 13).copyWith(
          color: p.textMuted,
        ),
      ),
    );
  }
}
