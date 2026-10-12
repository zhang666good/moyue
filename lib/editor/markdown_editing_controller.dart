import 'package:flutter/material.dart';

import '../md/document.dart';
import '../md/inline.dart';
import '../ui/palette.dart';

/// 活动块的文本控制器。
///
/// 与只读渲染最大的区别：**一个字符都不能少**。TextField 的选区偏移量
/// 必须与文本严格一一对应，所以标记只能用淡色区分，绝不能删掉或者设成
/// fontSize:0 —— 那会让中文输入法的 composing 区域和光标位置错位。
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({
    required String text,
    required this.palette,
    required this.type,
    required this.level,
    required this.prefix,
  }) : super(text: text);

  MdPalette palette;
  BlockType type;
  int level;
  String prefix;

  /// 编辑态与只读态必须使用**同一个**样式，否则光标进入时字体会跳。
  TextStyle get baseStyle => MdType.forBlock(palette, type, level);

  /// 块类型可能在打字过程中变化（例如行首敲下 "# "）。
  /// 这里只更新字段，不主动通知 —— 文本变化本身会触发上层 rebuild，
  /// buildTextSpan 会跟着用上新样式。
  void syncBlock(MdBlock b, MdPalette p) {
    type = b.type;
    level = b.level;
    prefix = b.prefix;
    palette = p;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = baseStyle;
    final s = text;

    if (s.isEmpty) {
      return TextSpan(style: base, text: '');
    }

    if (type == BlockType.code) {
      return _codeSpan(base, s);
    }

    final markerLen = prefix.length <= s.length ? prefix.length : 0;
    final content = s.substring(markerLen);
    final tokens = tokenizeInline(content, offset: markerLen);
    final composing = withComposing ? value.composing : TextRange.empty;

    final children = <InlineSpan>[];
    if (markerLen > 0) {
      children.add(TextSpan(
        text: prefix,
        style: base.copyWith(color: palette.marker),
      ));
    }
    final inner = buildEditingInline(tokens, base, palette, composing);
    final innerChildren = inner.children;
    if (innerChildren != null) {
      children.addAll(innerChildren);
    }
    return TextSpan(style: base, children: children);
  }

  /// 代码块：围栏行淡化，正文用等宽字体。
  ///
  /// 注意：所有字符必须原样进入 span，包括行尾的空行 —— 少一个字符
  /// 就会让光标偏移量整体错位。
  TextSpan _codeSpan(TextStyle base, String s) {
    final lines = s.split('\n');
    final children = <TextSpan>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLast = i == lines.length - 1;
      final trimmed = line.trimLeft();
      final isFence = i == 0 ||
          (isLast &&
              (trimmed.startsWith('```') || trimmed.startsWith('~~~')));

      children.add(TextSpan(
        text: isLast ? line : '$line\n',
        style: isFence ? base.copyWith(color: palette.marker) : base,
      ));
    }

    if (children.isEmpty) children.add(const TextSpan(text: ''));
    return TextSpan(style: base, children: children);
  }
}
