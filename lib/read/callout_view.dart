import 'package:flutter/material.dart';

import '../ui/palette.dart';
import 'inline_render.dart';

/// 一种提示卡片的外观规格。
class _CalloutKind {
  const _CalloutKind(this.icon, this.light, this.dark, this.fallbackTitle);

  final IconData icon;
  final Color light;
  final Color dark;

  /// 用户没写标题时显示的名字。
  final String fallbackTitle;
}

const Map<String, _CalloutKind> _kinds = <String, _CalloutKind>{
  'note': _CalloutKind(
    Icons.sticky_note_2_outlined,
    Color(0xFF5B6B7C),
    Color(0xFF9AA7B4),
    '说明',
  ),
  'info': _CalloutKind(
    Icons.info_outline_rounded,
    Color(0xFF2F6FEB),
    Color(0xFF6EA8FF),
    '信息',
  ),
  'tip': _CalloutKind(
    Icons.lightbulb_outline_rounded,
    Color(0xFF2EA043),
    Color(0xFF56D364),
    '提示',
  ),
  'success': _CalloutKind(
    Icons.check_circle_outline_rounded,
    Color(0xFF2EA043),
    Color(0xFF56D364),
    '成功',
  ),
  'warning': _CalloutKind(
    Icons.warning_amber_rounded,
    Color(0xFFBF8700),
    Color(0xFFE3B341),
    '注意',
  ),
  'danger': _CalloutKind(
    Icons.dangerous_outlined,
    Color(0xFFCF222E),
    Color(0xFFFF7B72),
    '危险',
  ),
  'important': _CalloutKind(
    Icons.priority_high_rounded,
    Color(0xFF8250DF),
    Color(0xFFB083F0),
    '重要',
  ),
};

_CalloutKind _kindOf(String name) =>
    _kinds[name.toLowerCase()] ?? _kinds['info']!;

/// 语雀式提示卡片。
///
/// 同时吃两种写法：容器式 `:::info 标题 … :::` 和引用式 `> [!NOTE] 标题`。
/// 解析层已经把它们归一成同一个块，这里不必再区分。
class CalloutView extends StatelessWidget {
  const CalloutView({
    super.key,
    required this.kind,
    required this.title,
    required this.body,
    required this.blocksBuilder,
  });

  /// 种类名（`info` / `warning` …），未知种类按 `info` 处理。
  final String kind;

  /// 用户写的标题，可能为空。
  final String title;

  /// 卡片正文（Markdown 源码）。
  final String body;

  final MarkdownBlocksBuilder blocksBuilder;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final k = _kindOf(kind);
    final accent = p.isDark ? k.dark : k.light;
    final label = title.trim().isEmpty ? k.fallbackTitle : title.trim();
    final hasBody = body.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: p.isDark ? 0.11 : 0.07),
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(k.icon, size: 17, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: MdType.body(p).copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (hasBody)
            Padding(
              padding: const EdgeInsets.only(left: 25, top: 5),
              child: blocksBuilder(context, body),
            ),
        ],
      ),
    );
  }
}

/// 折叠块 `:::details 标题 … :::`。
class DetailsView extends StatefulWidget {
  const DetailsView({
    super.key,
    required this.title,
    required this.body,
    required this.blocksBuilder,
    this.initiallyExpanded = false,
  });

  final String title;
  final String body;
  final MarkdownBlocksBuilder blocksBuilder;
  final bool initiallyExpanded;

  @override
  State<DetailsView> createState() => _DetailsViewState();
}

class _DetailsViewState extends State<DetailsView> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final title = widget.title.trim().isEmpty ? '详情' : widget.title.trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              child: Row(
                children: <Widget>[
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: p.textMuted,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: MdType.body(p).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
              child: widget.blocksBuilder(context, widget.body),
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}
