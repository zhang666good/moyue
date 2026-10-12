import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// 语义角色。
///
/// highlight.js 的 class 名有一百多种，直接为每个名字写一套颜色，
/// 加一门语言就要补几行。这里先归到十几个语义角色上，配色表只需维护一份，
/// 未收录的语言也能落到合理颜色上。
enum CodeRole {
  comment,
  keyword,
  string,
  number,
  title,
  type,
  builtin,
  tag,
  attr,
  meta,
  variable,
  symbol,
  deletion,
  addition,
  emphasis,
  strong,
}

/// highlight.js 的裸 class 名 → 语义角色。
///
/// 键是**不带 `hljs-` 前缀**的名字 —— [Node.className] 返回的就是裸名
/// （`hljs-` 前缀只在 `toHtml()` 里拼上）。
const Map<String, CodeRole> _classRoles = <String, CodeRole>{
  // 注释
  'comment': CodeRole.comment,
  'quote': CodeRole.comment,
  'doctag': CodeRole.comment,

  // 关键字
  'keyword': CodeRole.keyword,
  'selector-tag': CodeRole.keyword,
  'template-tag': CodeRole.keyword,
  'subst': CodeRole.keyword,
  'meta-keyword': CodeRole.keyword,

  // 字符串
  'string': CodeRole.string,
  'regexp': CodeRole.string,
  'meta-string': CodeRole.string,
  'link': CodeRole.string,

  // 数字与字面量
  'number': CodeRole.number,
  'literal': CodeRole.number,
  'char': CodeRole.number,
  'escape': CodeRole.number,
  'template-variable': CodeRole.number,

  // 标识符 / 函数名 / 类名
  'title': CodeRole.title,
  'function': CodeRole.title,
  'class': CodeRole.title,
  'selector-id': CodeRole.title,
  'selector-class': CodeRole.title,
  'section': CodeRole.title,

  // 类型与内建
  'type': CodeRole.type,
  'built_in': CodeRole.type,
  'builtin-name': CodeRole.type,

  // 标签（HTML/XML）
  'tag': CodeRole.tag,
  'name': CodeRole.tag,

  // 属性
  'attr': CodeRole.attr,
  'attribute': CodeRole.attr,
  'selector-attr': CodeRole.attr,
  'property': CodeRole.attr,

  // 元信息
  'meta': CodeRole.meta,
  'selector-pseudo': CodeRole.meta,

  // 变量与参数
  'variable': CodeRole.variable,
  'params': CodeRole.variable,

  // 符号
  'symbol': CodeRole.symbol,
  'bullet': CodeRole.symbol,
  'formula': CodeRole.symbol,
  'code': CodeRole.symbol,

  // diff
  'deletion': CodeRole.deletion,
  'addition': CodeRole.addition,

  // 强调
  'emphasis': CodeRole.emphasis,
  'strong': CodeRole.strong,
};

/// 一个角色在明暗两套主题下的颜色与字形。
class _RoleStyle {
  const _RoleStyle(
    this.light,
    this.dark, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
  });

  final Color light;
  final Color dark;
  final bool bold;
  final bool italic;
  final bool strike;
}

/// 取 GitHub 明/暗两套配色的近似值。
///
/// 读者对代码块的配色最敏感 —— 代码块是唯一「外来品」，
/// 偏离主流方案一眼就能看出来，所以这里刻意贴着 GitHub 走，不自己发挥。
const Map<CodeRole, _RoleStyle> _roleStyles = <CodeRole, _RoleStyle>{
  CodeRole.comment: _RoleStyle(
    Color(0xFF6A737D),
    Color(0xFF8B949E),
    italic: true,
  ),
  CodeRole.keyword: _RoleStyle(Color(0xFFD73A49), Color(0xFFFF7B72)),
  CodeRole.string: _RoleStyle(Color(0xFF032F62), Color(0xFFA5D6FF)),
  CodeRole.number: _RoleStyle(Color(0xFF005CC5), Color(0xFF79C0FF)),
  CodeRole.title: _RoleStyle(Color(0xFF6F42C1), Color(0xFFD2A8FF)),
  CodeRole.type: _RoleStyle(Color(0xFF005CC5), Color(0xFFFFA657)),
  CodeRole.builtin: _RoleStyle(Color(0xFFE36209), Color(0xFFFFA657)),
  CodeRole.tag: _RoleStyle(Color(0xFF22863A), Color(0xFF7EE787)),
  CodeRole.attr: _RoleStyle(Color(0xFF6F42C1), Color(0xFF79C0FF)),
  CodeRole.meta: _RoleStyle(Color(0xFF005CC5), Color(0xFF79C0FF)),
  CodeRole.variable: _RoleStyle(Color(0xFFE36209), Color(0xFFFFA657)),
  CodeRole.symbol: _RoleStyle(Color(0xFF005CC5), Color(0xFF79C0FF)),
  CodeRole.deletion: _RoleStyle(
    Color(0xFFB31D28),
    Color(0xFFFFA198),
    strike: true,
  ),
  CodeRole.addition: _RoleStyle(Color(0xFF22863A), Color(0xFF7EE787)),
  CodeRole.emphasis: _RoleStyle(
    Color(0xFF24292E),
    Color(0xFFE6EDF3),
    italic: true,
  ),
  CodeRole.strong: _RoleStyle(
    Color(0xFF24292E),
    Color(0xFFE6EDF3),
    bold: true,
  ),
};

/// 代码块的配色与字体规格。
@immutable
class MdCodeTheme {
  const MdCodeTheme({
    required this.base,
    required this.lineNumber,
    required this.lineHighlight,
    required Map<CodeRole, TextStyle> styles,
  }) : _styles = styles;

  /// 不带任何语法角色的基础样式（也是未知 class 的兜底）。
  final TextStyle base;

  /// 行号颜色。
  final Color lineNumber;

  /// 指定行高亮的底色。
  final Color lineHighlight;

  final Map<CodeRole, TextStyle> _styles;

  /// 强制统一行高。
  ///
  /// 行号槽和代码列是两个独立的 Column，要逐行对齐就必须保证每一行的
  /// 高度完全一致。仅靠 `height: 1.6` 不够 —— 一旦某个 span 用了不同字号，
  /// 行高就会漂移。`forceStrutHeight` 把「决定行高的那一行字」固定住，
  /// 字号变化也不会再影响行高。
  static const double lineHeightFactor = 1.6;

  static MdCodeTheme of(
    MdPalette p, {
    double size = 13.0,
  }) {
    final base = MdType.mono(p, size: size).copyWith(
      height: lineHeightFactor,
      color: p.text,
    );
    final styles = <CodeRole, TextStyle>{};
    for (final entry in _roleStyles.entries) {
      final s = entry.value;
      styles[entry.key] = base.copyWith(
        color: p.isDark ? s.dark : s.light,
        fontWeight: s.bold ? FontWeight.w700 : null,
        fontStyle: s.italic ? FontStyle.italic : null,
        decoration: s.strike ? TextDecoration.lineThrough : null,
      );
    }
    return MdCodeTheme(
      base: base,
      lineNumber: p.isDark ? const Color(0xFF6E7681) : const Color(0xFF8C959F),
      lineHighlight: p.isDark
          ? const Color(0x2EFFD33D)
          : const Color(0x33FFF3B0),
      styles: styles,
    );
  }

  /// 保证行高与 [base] 一致的 strut，供 RichText 使用。
  StrutStyle get strut => StrutStyle(
        fontFamily: base.fontFamily,
        fontFamilyFallback: base.fontFamilyFallback,
        fontSize: base.fontSize,
        height: base.height,
        forceStrutHeight: true,
      );

  /// 按 class 名取样式。
  ///
  /// class 名理论上可能是 `title class_` 这种复合名（highlight.js 的
  /// 作用域拼接），所以按空格逐段试；都命中不了就回退到基础样式。
  TextStyle styleFor(String? className) {
    if (className == null || className.isEmpty) return base;
    final first = _lookup(className);
    if (first != null) return first;
    if (className.contains(' ')) {
      for (final part in className.split(' ')) {
        final s = _lookup(part);
        if (s != null) return s;
      }
    }
    return base;
  }

  TextStyle? _lookup(String raw) {
    final key = raw.endsWith('_') ? raw.substring(0, raw.length - 1) : raw;
    final role = _classRoles[key];
    if (role == null) return null;
    return _styles[role];
  }
}
