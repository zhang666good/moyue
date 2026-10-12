import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// 行内令牌类型。[marker] 是语法标记（`**`、`[`、`](url)` 等），
/// 只读渲染时隐藏、编辑时淡化。
enum InlineKind {
  text,
  marker,
  bold,
  italic,
  boldItalic,
  code,
  strike,
  link,
  image,

  /// 行内公式，[InlineToken.text] 是 `$` 之间的 TeX 源码。
  math,
}

@immutable
class InlineToken {
  const InlineToken({
    required this.start,
    required this.end,
    required this.text,
    required this.kind,
    this.url,
    this.renderedLength = -1,
  });

  final int start;
  final int end;
  final String text;
  final InlineKind kind;
  final String? url;

  /// 该令牌在**只读渲染**布局里占多少字符位；-1 表示等于 [text] 的长度。
  ///
  /// 只有行内公式需要它：只读态渲染成公式控件，在文本布局里只占 1 个
  /// 占位字符（U+FFFC），但原文有 `$…$` 那么长。不区分这两个长度，
  /// 点击定位就会在公式之后整体偏移。
  final int renderedLength;

  bool get isMarker => kind == InlineKind.marker;

  /// 只读渲染时的字符宽度。
  int get layoutLength => renderedLength < 0 ? text.length : renderedLength;

  InlineToken shift(int delta) => InlineToken(
        start: start + delta,
        end: end + delta,
        text: text,
        kind: kind,
        url: url,
        renderedLength: renderedLength,
      );
}

final RegExp _wordChar = RegExp(r'[A-Za-z0-9\u4e00-\u9fff]');

class _LinkMatch {
  const _LinkMatch(this.textEnd, this.end, this.url);
  final int textEnd;
  final int end;
  final String url;
}

class _Emph {
  const _Emph(this.openLen, this.closeStart, this.kind);
  final int openLen;
  final int closeStart;
  final InlineKind kind;
}

/// 在 [open]（必须是 `[`）处匹配 `[text](url)`。
_LinkMatch? _matchLink(String s, int open) {
  if (open >= s.length || s[open] != '[') return null;
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
      if (depth == 0) break;
    }
    i++;
  }
  if (i >= s.length) return null;
  if (i + 1 >= s.length || s[i + 1] != '(') return null;
  final close = s.indexOf(')', i + 2);
  if (close < 0) return null;
  return _LinkMatch(i, close + 1, s.substring(i + 2, close));
}

/// 行内公式匹配结果。
class _MathMatch {
  const _MathMatch(this.openLen, this.innerEnd);
  final int openLen;

  /// 内部文本结束位置（= 收尾 `$` 的起点）。
  final int innerEnd;
}

final RegExp _digitRe = RegExp(r'\d');

/// 从位置 [i]（必须是 `$`）尝试匹配行内公式。
///
/// 刻意收得比较紧，宁可漏判也不要把价格当公式：
/// - 内侧不能为空、不能跨行，首尾不留空白（`$5 到 $10` 因此不会误判）；
/// - 单 `$` 形式额外要求收尾 `$` 后面不是数字（挡住 `$5$元` 这类写法）；
/// - `$$…$$` 是行内展示公式，同样支持。
_MathMatch? _matchMath(String s, int i) {
  if (i >= s.length || s[i] != r'$') return null;
  final doubled = i + 1 < s.length && s[i + 1] == r'$';
  final openLen = doubled ? 2 : 1;
  final delim = doubled ? r'$$' : r'$';

  final closeAt = s.indexOf(delim, i + openLen);
  if (closeAt < 0) return null;

  final inner = s.substring(i + openLen, closeAt);
  if (inner.isEmpty) return null;
  if (inner.contains('\n')) return null;
  if (inner != inner.trim()) return null;
  if (!doubled) {
    final after = closeAt + 1;
    if (after < s.length && _digitRe.hasMatch(s[after])) return null;
  }
  return _MathMatch(openLen, closeAt);
}

/// 从位置 [i] 尝试匹配强调标记。按 3 → 2 → 1 个字符的优先级。
/// 下划线版本要求词边界，避免把 `file_name` 误判为斜体。
_Emph? _matchEmphasis(String s, int i) {
  final c = s[i];
  if (c != '*' && c != '_') return null;

  for (final len in const [3, 2, 1]) {
    if (i + len > s.length) continue;
    final d = s.substring(i, i + len);
    var allSame = true;
    for (var k = 0; k < len; k++) {
      if (s[i + k] != c) {
        allSame = false;
        break;
      }
    }
    if (!allSame) continue;
    if (c == '_' && i > 0 && _wordChar.hasMatch(s[i - 1])) continue;

    final close = s.indexOf(d, i + len);
    if (close < 0 || close == i + len) continue;
    if (c == '_') {
      final after = close + len;
      if (after < s.length && _wordChar.hasMatch(s[after])) continue;
    }

    final kind = len == 3
        ? InlineKind.boldItalic
        : (len == 2 ? InlineKind.bold : InlineKind.italic);
    return _Emph(len, close, kind);
  }
  return null;
}

/// 把一段 Markdown 行内文本切成令牌。
///
/// 不变式：所有字符被精确覆盖一次，无遗漏、无重复，
/// 因此 `tokens.map((t) => t.text).join()` 恒等于 `s`。
/// [offset] 用于把结果整体平移到宿主字符串的坐标系（例如块的 prefix 之后）。
List<InlineToken> tokenizeInline(String s, {int offset = 0}) {
  final out = <InlineToken>[];
  final buf = StringBuffer();
  var bufStart = -1;
  final n = s.length;

  void flush(int end) {
    if (bufStart >= 0) {
      out.add(InlineToken(
        start: bufStart,
        end: end,
        text: buf.toString(),
        kind: InlineKind.text,
      ));
      buf.clear();
      bufStart = -1;
    }
  }

  void plain(int index, String text) {
    if (bufStart < 0) bufStart = index;
    buf.write(text);
  }

  void marker(int start, int end, String text) {
    flush(start);
    out.add(InlineToken(
      start: start,
      end: end,
      text: text,
      kind: InlineKind.marker,
    ));
  }

  void spanFrom(int openStart, int openLen, int closeStart, int closeLen,
      InlineKind kind, String? url) {
    final delim = s.substring(openStart, openStart + openLen);
    marker(openStart, openStart + openLen, delim);
    out.add(InlineToken(
      start: openStart + openLen,
      end: closeStart,
      text: s.substring(openStart + openLen, closeStart),
      kind: kind,
      url: url,
    ));
    marker(closeStart, closeStart + closeLen,
        s.substring(closeStart, closeStart + closeLen));
  }

  var i = 0;
  while (i < n) {
    final c = s[i];

    // 转义：\x 原样保留
    if (c == r'\' && i + 1 < n) {
      plain(i, s.substring(i, i + 2));
      i += 2;
      continue;
    }

    // 行内代码 `code`
    if (c == '`') {
      final close = s.indexOf('`', i + 1);
      if (close > i + 1) {
        spanFrom(i, 1, close, 1, InlineKind.code, null);
        i = close + 1;
        continue;
      }
    }

    // 行内公式 $x$ / $$x$$
    if (c == r'$') {
      final mm = _matchMath(s, i);
      if (mm != null) {
        marker(i, i + mm.openLen, s.substring(i, i + mm.openLen));
        out.add(InlineToken(
          start: i + mm.openLen,
          end: mm.innerEnd,
          text: s.substring(i + mm.openLen, mm.innerEnd),
          kind: InlineKind.math,
          renderedLength: 1,
        ));
        marker(
          mm.innerEnd,
          mm.innerEnd + mm.openLen,
          s.substring(mm.innerEnd, mm.innerEnd + mm.openLen),
        );
        i = mm.innerEnd + mm.openLen;
        continue;
      }
    }

    // 图片 ![alt](url)
    if (c == '!' && i + 1 < n && s[i + 1] == '[') {
      final lm = _matchLink(s, i + 1);
      if (lm != null) {
        marker(i, i + 2, '![');
        out.add(InlineToken(
          start: i + 2,
          end: lm.textEnd,
          text: s.substring(i + 2, lm.textEnd),
          kind: InlineKind.image,
          url: lm.url,
        ));
        marker(lm.textEnd, lm.end, s.substring(lm.textEnd, lm.end));
        i = lm.end;
        continue;
      }
    }

    // 链接 [text](url)
    if (c == '[') {
      final lm = _matchLink(s, i);
      if (lm != null) {
        marker(i, i + 1, '[');
        out.add(InlineToken(
          start: i + 1,
          end: lm.textEnd,
          text: s.substring(i + 1, lm.textEnd),
          kind: InlineKind.link,
          url: lm.url,
        ));
        marker(lm.textEnd, lm.end, s.substring(lm.textEnd, lm.end));
        i = lm.end;
        continue;
      }
    }

    // 删除线 ~~x~~
    if (s.startsWith('~~', i)) {
      final close = s.indexOf('~~', i + 2);
      if (close > i + 2) {
        spanFrom(i, 2, close, 2, InlineKind.strike, null);
        i = close + 2;
        continue;
      }
    }

    // 强调
    final em = _matchEmphasis(s, i);
    if (em != null) {
      spanFrom(i, em.openLen, em.closeStart, em.openLen, em.kind, null);
      i = em.closeStart + em.openLen;
      continue;
    }

    plain(i, c);
    i++;
  }

  flush(n);
  return offset == 0 ? out : out.map((t) => t.shift(offset)).toList();
}

// ---------------------------------------------------------------------------
// 样式与 Span 构建
// ---------------------------------------------------------------------------

TextStyle inlineStyleFor(InlineKind kind, TextStyle base, MdPalette p) {
  switch (kind) {
    case InlineKind.bold:
      return base.copyWith(fontWeight: FontWeight.w700);
    case InlineKind.boldItalic:
      return base.copyWith(
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
      );
    case InlineKind.italic:
      return base.copyWith(fontStyle: FontStyle.italic);
    case InlineKind.code:
      return base.copyWith(
        fontFamily: p.monoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: (base.fontSize ?? 15.5) * 0.88,
        backgroundColor: p.codeBg,
      );
    case InlineKind.strike:
      return base.copyWith(decoration: TextDecoration.lineThrough);
    case InlineKind.link:
      return base.copyWith(
        color: p.link,
        decoration: TextDecoration.underline,
        decorationColor: p.link.withValues(alpha: 0.35),
      );
    case InlineKind.image:
      return base.copyWith(
        color: p.link,
        backgroundColor: p.codeBg,
        fontFamily: p.monoFont,
        fontFamilyFallback: kMonoFallback,
        fontSize: (base.fontSize ?? 15.5) * 0.9,
      );
    case InlineKind.math:
      // 编辑态公式以文本出现（TextField 里不能放控件），
      // 用衬线斜体让它和正文区分开；只读态会换成真正的公式控件。
      return base.copyWith(
        color: p.link,
        fontStyle: FontStyle.italic,
        fontFamily: kMathFont,
        fontFamilyFallback: kMathFallback,
      );
    case InlineKind.text:
    case InlineKind.marker:
      return base;
  }
}

/// 只读渲染：丢弃语法标记。
///
/// [mathBuilder] 用来把行内公式换成真正的公式控件；传 null 时公式退化成文本，
/// 这样 [inline] 层不必依赖任何公式渲染库。
TextSpan buildRenderedInline(
  List<InlineToken> tokens,
  TextStyle base,
  MdPalette p, {
  Widget Function(String tex)? mathBuilder,
}) {
  final children = <InlineSpan>[];
  for (final t in tokens) {
    if (t.isMarker) continue;
    if (t.kind == InlineKind.math && mathBuilder != null) {
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: mathBuilder(t.text),
      ));
      continue;
    }
    children.add(TextSpan(
      text: t.text,
      style: inlineStyleFor(t.kind, base, p),
    ));
  }
  if (children.isEmpty) children.add(const TextSpan(text: ''));
  return TextSpan(style: base, children: children);
}

/// 编辑渲染：保留全部字符。
///
/// TextField 的选区偏移量与文本严格对应，所以**绝不能**删除或把标记降为字号 0
/// ——那会让中文输入法的 composing 区域和光标位置错位。这里只把标记改成淡色。
TextSpan buildEditingInline(
  List<InlineToken> tokens,
  TextStyle base,
  MdPalette p,
  TextRange composing,
) {
  final composingActive = composing.isValid && !composing.isCollapsed;
  final children = <TextSpan>[];
  for (final t in tokens) {
    var style = t.isMarker
        ? base.copyWith(color: p.marker)
        : inlineStyleFor(t.kind, base, p);
    if (composingActive && t.start < composing.end && t.end > composing.start) {
      style = style.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: p.marker,
      );
    }
    children.add(TextSpan(text: t.text, style: style));
  }
  if (children.isEmpty) children.add(const TextSpan(text: ''));
  return TextSpan(style: base, children: children);
}

/// 把「隐藏标记后的渲染偏移」映射回「含标记的原文偏移」。
/// 点击非活动块时用它把光标放到用户真正点到的位置。
int renderedOffsetToRaw(List<InlineToken> tokens, int renderedOffset) {
  var cursor = 0;
  for (final t in tokens) {
    if (t.isMarker) continue;
    final len = t.layoutLength;
    if (renderedOffset < cursor + len) {
      // 公式是控件令牌：内部没有逐字符对应的位置，一律落到它的开头。
      if (len != t.text.length) return t.start;
      return t.start + (renderedOffset - cursor);
    }
    cursor += len;
  }
  for (var i = tokens.length - 1; i >= 0; i--) {
    if (!tokens[i].isMarker) return tokens[i].end;
  }
  return 0;
}

/// 隐藏标记后的纯文本（字数统计、点击命中测试用）。
String renderedPlainText(List<InlineToken> tokens) {
  final buf = StringBuffer();
  for (final t in tokens) {
    if (t.isMarker) continue;
    buf.write(t.text);
  }
  return buf.toString();
}
