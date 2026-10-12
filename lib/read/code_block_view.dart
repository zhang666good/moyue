import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/palette.dart';
import 'code_highlight.dart';
import 'code_spans.dart';
import 'code_theme.dart';

/// 代码块是否自动换行。
///
/// 做成全局开关而不是每块一个：语雀、GitHub 都是这么做的 ——
/// 读文档时「要不要换行」是读者的习惯，不是每段代码自己的属性。
/// 用 ValueNotifier 是为了让所有已挂载的代码块立刻同步，
/// 不必把回调一层层往下传。
final ValueNotifier<bool> codeWrapPreference = ValueNotifier<bool>(true);

/// 带行号、语法高亮、指定行高亮、一键复制的代码块。
///
/// 布局上要解决一个矛盾：行号槽和代码列是两个独立的列，却必须逐行对齐。
/// 关键是把每一行的高度完全钉死 —— 见 [MdCodeTheme.strut]。
class CodeBlockView extends StatefulWidget {
  const CodeBlockView({
    super.key,
    required this.code,
    required this.language,
    this.highlightSpec = '',
    this.onTapAt,
    this.compact = false,
  });

  /// 代码正文（不含围栏）。
  final String code;

  /// 语言标记。空串表示未指定，此时按纯文本处理。
  final String language;

  /// 行高亮标注原文，例如 `1,3-5`。
  final String highlightSpec;

  /// 点击代码区时回调，参数是**代码正文内**的字符偏移。
  ///
  /// 只有自动换行模式能给准偏移（宽度有界，TextPainter 才排得出来）；
  /// 横向滚动模式下宽度无界，一律给 -1，由调用方兜底。
  final ValueChanged<int>? onTapAt;

  /// 编辑态下用紧凑一点的内边距，免得代码块在文档里显得过重。
  final bool compact;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    codeWrapPreference.addListener(_onWrapChanged);
  }

  @override
  void dispose() {
    codeWrapPreference.removeListener(_onWrapChanged);
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _onWrapChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
    } catch (_) {
      // 剪贴板在个别环境不可用，静默失败总好过让阅读器崩掉
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final theme = MdCodeTheme.of(p);
    final lines = highlightToLines(widget.code, widget.language);
    final marked = parseHighlightSpec(widget.highlightSpec);
    final wrap = codeWrapPreference.value;

    // 空代码块也要占一行，否则整块会缩成一条线
    final effective = lines.isEmpty ? <List<CodeSpan>>[<CodeSpan>[]] : lines;
    final gutterWidth = _gutterWidth(effective.length, theme);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: p.codeBg,
          border: Border.all(color: p.codeBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(p, theme),
            Padding(
              padding: EdgeInsets.only(
                top: widget.compact ? 6 : 10,
                bottom: widget.compact ? 8 : 12,
              ),
              child: wrap
                  ? _buildWrapped(effective, theme, marked, gutterWidth)
                  : _buildUnwrapped(effective, theme, marked, gutterWidth),
            ),
          ],
        ),
      ),
    );
  }

  /// 行号槽宽度随位数增长 —— 2 位数和 4 位数不能共用一个宽度。
  double _gutterWidth(int count, MdCodeTheme t) {
    final digits = count.toString().length;
    final size = t.base.fontSize ?? 13;
    // 等宽字体下 0.62em 是可靠的经验值，再加左右各 8px 内边距
    return digits * size * 0.62 + 18;
  }

  Widget _header(MdPalette p, MdCodeTheme t) {
    final label = widget.language.isEmpty ? '纯文本' : widget.language;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0x14FFFFFF) : const Color(0x06000000),
        border: Border(bottom: BorderSide(color: p.codeBorder, width: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: MdType.mono(p, size: 11.5)
                .copyWith(color: p.textMuted, letterSpacing: 0.6),
          ),
          const Spacer(),
          _ActionButton(
            icon: codeWrapPreference.value
                ? Icons.wrap_text
                : Icons.notes_outlined,
            tooltip: codeWrapPreference.value ? '关闭自动换行' : '开启自动换行',
            visible: _hovered,
            onTap: () => codeWrapPreference.value = !codeWrapPreference.value,
          ),
          const SizedBox(width: 2),
          _ActionButton(
            icon: _copied ? Icons.check_rounded : Icons.content_copy_outlined,
            tooltip: _copied ? '已复制' : '复制代码',
            visible: _hovered || _copied,
            tint: _copied ? const Color(0xFF2EA043) : null,
            onTap: _copy,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 换行

  Widget _buildWrapped(
    List<List<CodeSpan>> lines,
    MdCodeTheme t,
    Set<int> marked,
    double gutterWidth,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < lines.length; i++)
          Container(
            color: marked.contains(i + 1) ? t.lineHighlight : null,
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _lineNumber(i + 1, t, gutterWidth),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 0.0;
                      final child = _codeText(lines[i], t, wrap: true);
                      final handler = widget.onTapAt;
                      if (handler == null) return child;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => handler(
                          _offsetAt(lines[i], t, d.localPosition, maxWidth),
                        ),
                        child: child,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 用与显示完全一致的文本、样式和宽度跑一次 [TextPainter]，
  /// 把点击位置换算成正文内的字符偏移。
  int _offsetAt(
    List<CodeSpan> spans,
    MdCodeTheme t,
    Offset local,
    double maxWidth,
  ) {
    if (maxWidth <= 0) return -1;
    try {
      final painter = TextPainter(
        text: TextSpan(text: spans.map((s) => s.text).join(), style: t.base),
        textDirection: TextDirection.ltr,
        strutStyle: t.strut,
      )..layout(maxWidth: maxWidth);
      return painter.getPositionForOffset(local).offset;
    } catch (_) {
      return -1;
    }
  }

  // ---------------------------------------------------------------- 不换行

  Widget _buildUnwrapped(
    List<List<CodeSpan>> lines,
    MdCodeTheme t,
    Set<int> marked,
    double gutterWidth,
  ) {
    // 行号槽留在滚动区之外，横滚时不会跟着跑掉。
    //
    // 左右两列的对齐靠「每行高度被 strut 钉死」：不换行时每行必定只占一行字，
    // 所以两个 Column 的第 i 行必然等高。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: gutterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < lines.length; i++)
                _lineNumber(i + 1, t, gutterWidth),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final avail =
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: avail),
                  // IntrinsicWidth 把宽度钉成「最长那一行」，短行的底色因此
                  // 也能铺满，而长行不会被挤到折行。
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (var i = 0; i < lines.length; i++)
                          Container(
                            color: marked.contains(i + 1)
                                ? t.lineHighlight
                                : null,
                            padding: const EdgeInsets.only(right: 14),
                            child: _tapWholeLine(
                              _codeText(lines[i], t, wrap: false),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 横向滚动模式下的点击：宽度无界，算不出准确偏移，只报「点了代码区」。
  Widget _tapWholeLine(Widget child) {
    final handler = widget.onTapAt;
    if (handler == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => handler(-1),
      child: child,
    );
  }

  // ------------------------------------------------------------------ 公共

  Widget _lineNumber(int number, MdCodeTheme t, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          '$number',
          textAlign: TextAlign.right,
          softWrap: false,
          style: t.base.copyWith(color: t.lineNumber),
          strutStyle: t.strut,
        ),
      ),
    );
  }

  Widget _codeText(List<CodeSpan> spans, MdCodeTheme t, {required bool wrap}) {
    final children = <TextSpan>[
      for (final s in spans)
        TextSpan(text: s.text, style: t.styleFor(s.className)),
    ];
    if (children.isEmpty) {
      children.add(TextSpan(text: '', style: t.base));
    }
    return Text.rich(
      TextSpan(children: children),
      style: t.base,
      softWrap: wrap,
      strutStyle: t.strut,
      overflow: TextOverflow.clip,
    );
  }
}

/// 头部的小图标按钮。悬停或状态变化时淡入，避免常驻干扰阅读。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.visible,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String tooltip;
  final bool visible;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      child: IgnorePointer(
        ignoring: !visible,
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: InkResponse(
            onTap: onTap,
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 15, color: tint ?? p.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
