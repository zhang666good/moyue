import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../md/document.dart';
import '../ui/palette.dart';
import 'inline_render.dart';

/// Markdown 表格。
///
/// 列宽自己算，不用 [IntrinsicColumnWidth] —— 那个在「表格比正文窄」时会把
/// 表格缩在左边，而语雀这类文档里的表格是撑满正文宽度的。
class TableView extends StatelessWidget {
  const TableView({super.key, required this.table, this.onTap});

  final MdTable table;
  final VoidCallback? onTap;

  /// 单元格内边距。
  static const double cellPadH = 12;
  static const double cellPadV = 9;

  /// 单列宽度的上下限。下限保证再短的表头也不至于挤成一条，
  /// 上限避免某一列吃掉整行宽度。
  static const double minColumn = 68;
  static const double maxColumn = 340;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    if (table.headers.isEmpty) return const SizedBox.shrink();

    final headStyle = MdType.body(p).copyWith(fontWeight: FontWeight.w600);
    final cellStyle = MdType.body(p);

    return LayoutBuilder(
      builder: (context, constraints) {
        final avail =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 640.0;
        final widths = _columnWidths(headStyle, cellStyle, avail);
        final total = widths.fold<double>(0, (a, b) => a + b);

        final grid = SizedBox(
          width: total,
          child: Table(
            columnWidths: <int, TableColumnWidth>{
              for (var i = 0; i < widths.length; i++)
                i: FixedColumnWidth(widths[i]),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder(
              top: BorderSide(color: p.border, width: 0.5),
              right: BorderSide(color: p.border, width: 0.5),
              bottom: BorderSide(color: p.border, width: 0.5),
              left: BorderSide(color: p.border, width: 0.5),
              horizontalInside: BorderSide(color: p.border, width: 0.5),
              verticalInside: BorderSide(color: p.border, width: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(color: p.surface),
                children: <Widget>[
                  for (var c = 0; c < table.headers.length; c++)
                    _cell(table.headers[c], headStyle, _alignAt(c), p),
                ],
              ),
              for (final row in table.rows)
                TableRow(
                  children: <Widget>[
                    for (var c = 0; c < table.headers.length; c++)
                      _cell(
                        c < row.length ? row[c] : '',
                        cellStyle,
                        _alignAt(c),
                        p,
                      ),
                  ],
                ),
            ],
          ),
        );

        // 只有真的装不下时才横滚 —— 装得下的时候 total 就等于 avail，
        // 滚动视图自然不会有可滚动区间。
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: grid,
          ),
        );
      },
    );
  }

  MdAlign _alignAt(int column) =>
      column < table.aligns.length ? table.aligns[column] : MdAlign.left;

  TextAlign _textAlign(MdAlign a) => switch (a) {
        MdAlign.left => TextAlign.left,
        MdAlign.center => TextAlign.center,
        MdAlign.right => TextAlign.right,
      };

  Widget _cell(
    String source,
    TextStyle style,
    MdAlign align,
    MdPalette p,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: cellPadH,
        vertical: cellPadV,
      ),
      child: Text.rich(
        renderInlineText(source, style, p),
        style: style,
        textAlign: _textAlign(align),
      ),
    );
  }

  /// 先量出每列的自然宽度，装得下就摊开铺满，装不下就保持自然宽度让外层横滚。
  List<double> _columnWidths(
    TextStyle headStyle,
    TextStyle cellStyle,
    double avail,
  ) {
    final n = table.headers.length;
    final widths = List<double>.filled(n, minColumn);

    for (var c = 0; c < n; c++) {
      var w = _measure(table.headers[c], headStyle);
      for (final row in table.rows) {
        if (c < row.length) {
          w = math.max(w, _measure(row[c], cellStyle));
        }
      }
      widths[c] = (w + cellPadH * 2) .clamp(minColumn, maxColumn);
    }

    final total = widths.fold<double>(0, (a, b) => a + b);
    if (total > 0 && total < avail) {
      // 均匀分掉富余宽度，而不是按比例放大 —— 按比例会让本来就最宽的
      // 那一列更宽，窄列反而没变化，视觉上很不均衡。
      final share = (avail - total) / n;
      for (var i = 0; i < n; i++) {
        widths[i] += share;
      }
    }
    return widths;
  }

  double _measure(String source, TextStyle style) {
    // 用渲染后的纯文本量宽：语法标记（`**`、`` ` ``）不占位置，
    // 拿原文量会把列撑宽。
    final painter = TextPainter(
      text: TextSpan(text: plainInlineText(source), style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}
