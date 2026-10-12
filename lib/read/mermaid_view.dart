import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/palette.dart';
import 'code_block_view.dart';
import 'mermaid.dart';

/// Mermaid 流程图的渲染入口。
///
/// 解析或布局失败时**降级成代码块**，而不是画一张半成品 ——
/// 画错的图比不画更容易误导读者。
class MermaidView extends StatelessWidget {
  const MermaidView({super.key, required this.source, this.language = 'mermaid'});

  final String source;
  final String language;

  @override
  Widget build(BuildContext context) {
    final graph = parseMermaid(source);
    if (!graph.isUsable) {
      return _Fallback(
        source: source,
        language: language,
        reason: graph.error,
      );
    }
    final layout = layoutMermaid(graph);
    return _MermaidCanvas(layout: layout);
  }
}

class _MermaidCanvas extends StatelessWidget {
  const _MermaidCanvas({required this.layout});

  final MermaidLayout layout;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final size = layout.size;
    final w = size.width + 24;
    final h = size.height + 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (layout.graph.unsupported.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Note(
              text: '图中使用了尚未支持的分组语法'
                  '（${layout.graph.unsupported.toSet().join("、")}），已按平铺渲染。',
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final avail = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : w;
              final fits = w <= avail;
              final canvas = CustomPaint(
                size: Size(w, h),
                painter: MermaidPainter(layout: layout, palette: p),
                isComplex: true,
              );
              if (fits) {
                return Center(child: canvas);
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: canvas,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 绘制整张图。等价于「几何 + 配色」的纯函数，没有状态。
class MermaidPainter extends CustomPainter {
  MermaidPainter({required this.layout, required this.palette});

  final MermaidLayout layout;
  final MdPalette palette;

  static const double _pad = 12;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(_pad, _pad);

    // 先画线，节点压在上面 —— 折线端点本来就贴在节点边界上，
    // 顺序反过来会在边框上留下毛刺。
    for (final e in layout.edges) {
      _drawEdge(canvas, e);
    }
    for (final node in layout.graph.nodes) {
      final rect = layout.rects[node.id];
      if (rect != null) _drawNode(canvas, node, rect);
    }

    canvas.restore();
  }

  // ------------------------------------------------------------------ 节点

  void _drawNode(Canvas canvas, MermaidNode node, Rect rect) {
    final fill = palette.isDark ? const Color(0xFF1C2330) : const Color(0xFFF3F6FB);
    final stroke = palette.isDark ? const Color(0xFF3A4553) : const Color(0xFFC4CEDC);
    final fillPaint = Paint()..color = fill;
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    switch (node.shape) {
      case MermaidShape.rect:
        final r = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(r, fillPaint);
        canvas.drawRRect(r, strokePaint);
      case MermaidShape.round:
        final r = RRect.fromRectAndRadius(rect, const Radius.circular(9));
        canvas.drawRRect(r, fillPaint);
        canvas.drawRRect(r, strokePaint);
      case MermaidShape.stadium:
        final r = RRect.fromRectAndRadius(
          rect,
          Radius.circular(rect.height / 2),
        );
        canvas.drawRRect(r, fillPaint);
        canvas.drawRRect(r, strokePaint);
      case MermaidShape.subroutine:
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
        // 子程序形状：两侧各有一条内缩的竖线
        canvas.drawLine(
          Offset(rect.left + 7, rect.top),
          Offset(rect.left + 7, rect.bottom),
          strokePaint,
        );
        canvas.drawLine(
          Offset(rect.right - 7, rect.top),
          Offset(rect.right - 7, rect.bottom),
          strokePaint,
        );
      case MermaidShape.circle:
        canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);
      case MermaidShape.diamond:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
    }

    _drawLabel(canvas, node.label, rect);
  }

  void _drawLabel(Canvas canvas, String label, Rect rect) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: kMermaidFontSize,
          height: 1.35,
          color: palette.text,
          fontFamily: kUiFont,
          fontFamilyFallback: kUiFallback,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(rect.width - 8, 10));

    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  // ------------------------------------------------------------------ 连线

  void _drawEdge(Canvas canvas, MermaidEdgeLayout e) {
    final color = palette.isDark
        ? const Color(0xFF7D8B9C)
        : const Color(0xFF8A97A8);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.edge.thick ? 2.4 : 1.3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    if (e.edge.dashed) {
      _dashedPolyline(canvas, e.points, paint);
    } else {
      final path = Path()..moveTo(e.points.first.dx, e.points.first.dy);
      for (var i = 1; i < e.points.length; i++) {
        path.lineTo(e.points[i].dx, e.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    _drawArrowHead(canvas, e.points[e.points.length - 2], e.points.last, paint);

    final anchor = e.labelAnchor;
    final label = e.edge.label;
    if (anchor != null && label != null && label.isNotEmpty) {
      _drawEdgeLabel(canvas, label, anchor);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final delta = to - from;
    final len = delta.distance;
    if (len < 0.5) return;
    final dir = delta / len;
    final normal = Offset(-dir.dy, dir.dx);
    const size = 7.0;

    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - dir.dx * size + normal.dx * size * 0.5,
        to.dy - dir.dy * size + normal.dy * size * 0.5,
      )
      ..lineTo(
        to.dx - dir.dx * size - normal.dx * size * 0.5,
        to.dy - dir.dy * size - normal.dy * size * 0.5,
      )
      ..close();

    canvas.drawPath(head, Paint()..color = paint.color);
  }

  void _drawEdgeLabel(Canvas canvas, String label, Offset anchor) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: kMermaidFontSize - 1.5,
          color: palette.textMuted,
          fontFamily: kUiFont,
          fontFamilyFallback: kUiFallback,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromCenter(
      center: anchor,
      width: painter.width + 10,
      height: painter.height + 5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = palette.bg,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = palette.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    painter.paint(
      canvas,
      Offset(rect.center.dx - painter.width / 2,
          rect.center.dy - painter.height / 2),
    );
  }

  void _dashedPolyline(Canvas canvas, List<Offset> pts, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final total = (b - a).distance;
      if (total < 0.01) continue;
      final dir = (b - a) / total;
      var t = 0.0;
      while (t < total) {
        final seg = math.min(dash, total - t);
        canvas.drawLine(a + dir * t, a + dir * (t + seg), paint);
        t += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant MermaidPainter old) =>
      !identical(old.layout, layout) || old.palette != palette;
}

/// 降级展示：说明原因 + 原始代码。
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.source,
    required this.language,
    required this.reason,
  });

  final String source;
  final String language;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Note(
          text: '这段 Mermaid 图未能渲染'
              '${reason == null ? "" : "：$reason"}，已按代码展示。',
        ),
        const SizedBox(height: 6),
        CodeBlockView(code: source, language: language),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline_rounded, size: 14, color: p.textMuted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: MdType.body(p).copyWith(
              fontSize: 13,
              color: p.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
