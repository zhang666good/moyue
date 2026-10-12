import 'package:flutter/material.dart';

import '../md/document.dart';
import '../md/inline.dart';
import '../ui/palette.dart';

/// 大纲侧栏。条目文本会先去掉行内语法标记（`**`、`` ` `` 等）再显示。
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({
    super.key,
    required this.headings,
    required this.palette,
    required this.onJump,
  });

  final List<MdHeading> headings;
  final MdPalette palette;
  final ValueChanged<MdHeading> onJump;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Text(
              '大纲',
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
                color: p.textMuted,
              ),
            ),
          ),
          Expanded(
            child: headings.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      '还没有标题',
                      style: TextStyle(fontSize: 12.5, color: p.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 40),
                    itemCount: headings.length,
                    itemBuilder: (context, i) {
                      final h = headings[i];
                      final indent = 16.0 + (h.level - 1) * 12.0;
                      final label = renderedPlainText(
                        tokenizeInline(h.text),
                      ).trim();
                      return InkWell(
                        onTap: () => onJump(h),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(indent, 6, 12, 6),
                          child: Text(
                            label.isEmpty ? '(空标题)' : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: h.level <= 2 ? 13.5 : 12.5,
                              fontWeight: h.level <= 2
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: p.text,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
