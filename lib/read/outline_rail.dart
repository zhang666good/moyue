import 'package:flutter/material.dart';

import '../md/document.dart';
import '../ui/palette.dart';
import 'inline_render.dart';

/// 右侧悬浮目录。
///
/// 语雀的目录是「跟随滚动高亮 + 可点击跳转」，而且当前项一旦变化就自动
/// 滚进可视区 —— 长文档里目录本身就是一屏，不自动跟随等于没有。
class OutlineRail extends StatefulWidget {
  const OutlineRail({
    super.key,
    required this.headings,
    required this.activeIndex,
    required this.onJump,
    this.width = 210,
  });

  final List<MdHeading> headings;

  /// 当前高亮项的**下标**（不是块下标）。没有匹配时传 -1。
  final int activeIndex;

  /// 参数是 [headings] 里的下标。
  final ValueChanged<int> onJump;

  final double width;

  @override
  State<OutlineRail> createState() => _OutlineRailState();
}

class _OutlineRailState extends State<OutlineRail> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(covariant OutlineRail old) {
    super.didUpdateWidget(old);
    if (old.headings.length != widget.headings.length) _syncKeys();
    if (old.activeIndex != widget.activeIndex) _followActive();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys() {
    _keys.clear();
    for (var i = 0; i < widget.headings.length; i++) {
      _keys[i] = GlobalKey();
    }
  }

  void _followActive() {
    final i = widget.activeIndex;
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.42,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    if (widget.headings.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text(
              '目录',
              style: MdType.body(p).copyWith(
                fontSize: 12,
                letterSpacing: 1.2,
                color: p.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 40),
                itemCount: widget.headings.length,
                itemBuilder: (context, i) => _item(i, p),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(int i, MdPalette p) {
    final h = widget.headings[i];
    final active = i == widget.activeIndex;
    // 层级缩进收敛到 3 级，再深就没地方放文字了
    final indent = ((h.level - 1).clamp(0, 2)) * 11.0;
    final label = outlineLabel(h.text);

    return Padding(
      key: _keys[i],
      padding: const EdgeInsets.only(bottom: 1),
      child: InkWell(
        onTap: () => widget.onJump(i),
        child: Container(
          decoration: BoxDecoration(
            color: active
                ? p.accent.withValues(alpha: p.isDark ? 0.16 : 0.09)
                : null,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              left: BorderSide(
                color: active ? p.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(9 + indent, 6, 8, 6),
          child: Text(
            label.isEmpty ? '(空标题)' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MdType.body(p).copyWith(
              fontSize: 13,
              height: 1.35,
              color: active ? p.accent : p.textMuted,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 目录里显示的标题文字。
///
/// 直接复用分词层的纯文本提取：它会丢掉语法标记，但保留 `code` 的内容、
/// 链接和图片的 alt —— 正是目录想要的。再手写一遍剥壳逻辑只会多一份
/// 会过时的实现。
String outlineLabel(String raw) => plainInlineText(raw).trim();
