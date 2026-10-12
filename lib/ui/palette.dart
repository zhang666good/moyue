import 'package:flutter/material.dart';

import '../md/document.dart';

/// 界面字体回退链。Windows 上 Segoe UI 不含中文，必须补 CJK 回退，
/// 否则中文会渲染成方框。
const List<String> kUiFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans SC',
  'Segoe UI',
];

const String kUiFont = 'Segoe UI';

const List<String> kMonoFallback = <String>[
  'Consolas',
  'Courier New',
  'Microsoft YaHei',
];

/// 数学排版字体。Windows 自带 Cambria Math，缺了就往衬线字体退。
const String kMathFont = 'Cambria Math';

const List<String> kMathFallback = <String>[
  'Cambria Math',
  'Latin Modern Math',
  'Times New Roman',
  'Microsoft YaHei',
];

/// 编辑器用到的全部颜色与字体。刻意不用 ThemeExtension，
/// 免得在 Theme.of(context) 链路里多一层类型转换。
@immutable
class MdPalette {
  const MdPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.marker,
    required this.link,
    required this.codeBg,
    required this.codeBorder,
    required this.quoteBg,
    required this.quoteBar,
    required this.accent,
  });

  /// 是否是深色主题。给那些只在明暗之间换色、不需要进调色板的
  /// 局部样式（提示卡片、语法高亮）用，省得层层推 Theme.of。
  final bool isDark;

  final Color bg;
  final Color surface;
  final Color border;
  final Color text;
  final Color textMuted;

  /// 语法标记的颜色（比正文淡，让用户能看见但不干扰阅读）。
  final Color marker;
  final Color link;
  final Color codeBg;
  final Color codeBorder;
  final Color quoteBg;
  final Color quoteBar;
  final Color accent;

  String get monoFont => 'Consolas';

  static const MdPalette light = MdPalette(
    isDark: false,
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F8FA),
    border: Color(0xFFE3E7EC),
    text: Color(0xFF1B1F24),
    textMuted: Color(0xFF6B7684),
    marker: Color(0xFFB3BCC7),
    link: Color(0xFF2F6FEB),
    codeBg: Color(0xFFF3F5F8),
    codeBorder: Color(0xFFE3E7EC),
    quoteBg: Color(0xFFF1F5FF),
    quoteBar: Color(0xFF9DBBF5),
    accent: Color(0xFF2F6FEB),
  );

  static const MdPalette dark = MdPalette(
    isDark: true,
    bg: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    border: Color(0xFF272E37),
    text: Color(0xFFE6EDF3),
    textMuted: Color(0xFF8B949E),
    marker: Color(0xFF5C6673),
    link: Color(0xFF5B9BFF),
    codeBg: Color(0xFF161B22),
    codeBorder: Color(0xFF272E37),
    quoteBg: Color(0x1F4D8DFB),
    quoteBar: Color(0xFF3D6DB5),
    accent: Color(0xFF5B9BFF),
  );

  static MdPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 排版规格。
class MdType {
  static const double bodySize = 15.5;

  static const List<double> _headingSizes = <double>[
    30, 24.5, 20, 17.5, 16, 15,
  ];

  static TextStyle body(MdPalette p) => TextStyle(
        fontSize: bodySize,
        height: 1.7,
        color: p.text,
        fontFamily: kUiFont,
        fontFamilyFallback: kUiFallback,
      );

  static TextStyle heading(MdPalette p, int level) {
    final idx = (level - 1).clamp(0, _headingSizes.length - 1);
    return TextStyle(
      fontSize: _headingSizes[idx],
      height: 1.35,
      color: p.text,
      fontWeight: idx <= 2 ? FontWeight.w700 : FontWeight.w600,
      fontFamily: kUiFont,
      fontFamilyFallback: kUiFallback,
    );
  }

  static TextStyle mono(MdPalette p, {double size = 13.5}) => TextStyle(
        fontFamily: p.monoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: size,
        height: 1.6,
        color: p.text,
      );

  static TextStyle math(MdPalette p, {double size = bodySize}) => TextStyle(
        fontFamily: kMathFont,
        fontFamilyFallback: kMathFallback,
        fontSize: size,
        height: 1.7,
        color: p.text,
      );

  /// 每种块类型的编辑样式，供 TextField 与 buildTextSpan 共用，
  /// 保证编辑态和只读态的字号一致（光标不跳）。
  static TextStyle forBlock(MdPalette p, BlockType type, int level) {
    switch (type) {
      case BlockType.heading:
        return heading(p, level);
      case BlockType.code:
        return mono(p);
      case BlockType.quote:
        return body(p).copyWith(color: p.textMuted);
      case BlockType.divider:
        return body(p).copyWith(color: p.marker, letterSpacing: 1.5);
      case BlockType.table:
        // 表格编辑时用等宽字体，竖线更容易对齐
        return mono(p, size: 13);
      case BlockType.mathBlock:
        return math(p);
      case BlockType.callout:
      case BlockType.details:
        return body(p);
      case BlockType.paragraph:
      case BlockType.bullet:
      case BlockType.ordered:
        return body(p);
    }
  }
}
