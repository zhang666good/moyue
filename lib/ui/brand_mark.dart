// 「墨阅 · MoRead」品牌标识 —— 图标绘制逻辑的唯一来源。
//
// 同一份绘制代码服务两个场景：
//   ① Windows exe / 任务栏图标（test/icon_gen.dart 调它导出 PNG，再由
//      tool/make_ico.py 打包成 .ico）；
//   ② 应用内标题栏的小 Logo（BrandMark 组件）。
// 这样图标改一次，两处同时生效，不会各画各的跑偏。
//
// 构图：深靛蓝→紫罗兰渐变圆角方块，其上落一张白色纸张（右下折角），
// 纸面中央一滴饱满的墨，墨下方是几行靛蓝文字线。
// 小尺寸自动降级：去掉文字线与高光、放大墨滴，保证 16px 仍可辨识。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 图标绘制档位。
enum BrandIconTier {
  /// ≤24px：只留纸张与墨滴，笔画加粗。
  minimal,

  /// 32–48px：两行文字。
  compact,

  /// ≥64px：三行文字 + 墨滴高光。
  full;

  /// 按目标像素尺寸挑档位。
  static BrandIconTier forSize(double size) {
    if (size <= 24) return BrandIconTier.minimal;
    if (size <= 48) return BrandIconTier.compact;
    return BrandIconTier.full;
  }
}

// ── 调色板 ────────────────────────────────────────────────────────────
const _bgStart = Color(0xFF5B4BF2); // 靛蓝
const _bgMid = Color(0xFF7C3AED); // 紫罗兰
const _bgEnd = Color(0xFFA855F7); // 紫
const _inkTop = Color(0xFF6D28D9); // 墨·上（带一点紫调，避免死黑）
const _inkBot = Color(0xFF1E1B4B); // 墨·下
const _lineStrong = Color(0xFF4F46E5); // 主文字线
const _lineSoft = Color(0xFFC7D2FE); // 次文字线
const _foldFlap = Color(0xFFDDD6FE); // 折角翻面
const _paper = Color(0xFFFFFFFF);

/// 把图标画进一块 [S]×[S] 的画布。
///
/// [tier] 见 [BrandIconTier]，可用 [BrandIconTier.forSize] 按尺寸自动挑。
/// [fullBleed] 为 true 时铺满整块画布、不画圆角。iOS 主屏图标走这个模式：
/// 系统会统一裁圆角，且图标不允许带透明通道，留圆角反而会露黑边。
void paintBrandIcon(
  Canvas c,
  double S,
  BrandIconTier tier, {
  bool fullBleed = false,
}) {
  final t = tier.index;
  // ── 1. 背景：圆角方块 + 渐变 + 左上高光 ────────────────────────────
  final full = Rect.fromLTWH(0, 0, S, S);
  c.save();
  if (fullBleed) {
    c.clipRect(full);
  } else {
    c.clipRRect(RRect.fromRectAndRadius(full, Radius.circular(S * 0.2255)));
  }
  c.drawRect(
    full,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(S * 0.02, -S * 0.04),
        Offset(S * 1.02, S * 1.04),
        const [_bgStart, _bgMid, _bgEnd],
        const [0.0, 0.52, 1.0],
      ),
  );
  if (t > 0) {
    c.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(S * 0.24, S * 0.08),
          S * 0.92,
          [Colors.white.withValues(alpha: 0.24), Colors.white.withValues(alpha: 0)],
          const [0.0, 1.0],
        ),
    );
    // 右上角一点点暖紫，让渐变更透气
    c.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(S * 0.94, S * 0.10),
          S * 0.55,
          [const Color(0xFFF0ABFC).withValues(alpha: 0.30), Colors.white.withValues(alpha: 0)],
          const [0.0, 1.0],
        ),
    );
  }
  c.restore();

  // ── 尺寸档位配置 ─────────────────────────────────────────────────
  //  0 = 极简（≤24px，只留纸 + 墨滴）
  //  1 = 紧凑（32–48px，两行文字）
  //  2 = 完整（≥64px，三行文字 + 墨滴高光）
  final pw = S * (t == 0 ? 0.740 : (t == 1 ? 0.700 : 0.636));
  final ph = S * (t == 0 ? 0.740 : (t == 1 ? 0.700 : 0.620));
  final rad = S * (t == 0 ? 0.105 : (t == 1 ? 0.092 : 0.080));
  final fold = S * (t == 0 ? 0.175 : (t == 1 ? 0.180 : 0.176));

  final dr = S * (t == 0 ? 0.160 : (t == 1 ? 0.108 : 0.092));
  final dtail = S * (t == 0 ? 0.290 : (t == 1 ? 0.200 : 0.176));
  // minimal 档没有文字，墨滴在纸面上居中；其余档位让出下方空间给文字行。
  final dcy = S * (t == 0 ? 0.065 : (t == 1 ? -0.100 : -0.102));
  final pcy = S * (t == 0 ? 0.520 : (t == 1 ? 0.530 : 0.535));

  // ── 2. 纸张（含右下折角） ─────────────────────────────────────────
  c.save();
  c.translate(S * 0.5, pcy);
  c.rotate(-4 * math.pi / 180);

  final page = Rect.fromCenter(center: Offset.zero, width: pw, height: ph);
  final pagePath = _pagePath(page, rad, fold);

  // 投影
  c.drawPath(
    pagePath.shift(Offset(0, S * 0.024)),
    Paint()
      ..color = const Color(0xFF2E1065).withValues(alpha: 0.42)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, S * 0.052),
  );
  c.drawPath(pagePath, Paint()..color = _paper);

  // 折角翻面
  final br = page.bottomRight;
  final flap = Path()
    ..moveTo(br.dx - fold, br.dy)
    ..lineTo(br.dx, br.dy - fold)
    ..lineTo(br.dx - fold, br.dy - fold)
    ..close();
  c.drawPath(flap, Paint()..color = _foldFlap);
  c.drawPath(
    Path()
      ..moveTo(br.dx - fold, br.dy)
      ..lineTo(br.dx, br.dy - fold),
    Paint()
      ..color = _lineSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = S * 0.011,
  );

  // ── 3. 墨滴 ───────────────────────────────────────────────────────
  final dropCenter = Offset(0, dcy);
  final drop = _dropPath(dropCenter, dr, dtail);
  c.drawPath(
    drop,
    Paint()
      ..shader = ui.Gradient.linear(
        dropCenter + Offset(-dr * 0.9, -dtail),
        dropCenter + Offset(dr * 0.9, dr),
        const [_inkTop, _inkBot],
      ),
  );
  if (t > 1) {
    // 墨滴上一道细高光，暗示湿润的表面
    c.save();
    c.clipPath(drop);
    c.drawOval(
      Rect.fromCenter(
        center: dropCenter + Offset(-dr * 0.40, -dr * 0.30),
        width: dr * 0.40,
        height: dr * 0.80,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.36)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, S * 0.005),
    );
    c.restore();
  }

  // ── 4. 文字线 ─────────────────────────────────────────────────────
  if (t > 0) {
    final lines = t > 1
        ? [
            (y: 0.068, x0: -0.212, x1: 0.052, h: 0.048, color: _lineStrong),
            (y: 0.152, x0: -0.212, x1: 0.152, h: 0.036, color: _lineSoft),
            (y: 0.228, x0: -0.212, x1: 0.020, h: 0.036, color: _lineSoft),
          ]
        : [
            (y: 0.108, x0: -0.245, x1: 0.060, h: 0.058, color: _lineStrong),
            (y: 0.215, x0: -0.245, x1: 0.145, h: 0.046, color: _lineSoft),
          ];
    for (final l in lines) {
      final yy = l.y * S;
      final rect = Rect.fromLTRB(l.x0 * S, yy - l.h * S / 2, l.x1 * S, yy + l.h * S / 2);
      c.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(l.h * S / 2)),
        Paint()..color = l.color,
      );
    }
  }

  c.restore();
}

/// 纸张轮廓：三个圆角 + 右下斜切。
Path _pagePath(Rect r, double rad, double fold) {
  final l = r.left, t = r.top, rr = r.right, b = r.bottom;
  return Path()
    ..moveTo(l + rad, t)
    ..lineTo(rr - rad, t)
    ..arcToPoint(Offset(rr, t + rad), radius: Radius.circular(rad))
    ..lineTo(rr, b - fold)
    ..lineTo(rr - fold, b)
    ..lineTo(l + rad, b)
    ..arcToPoint(Offset(l, b - rad), radius: Radius.circular(rad))
    ..lineTo(l, t + rad)
    ..arcToPoint(Offset(l + rad, t), radius: Radius.circular(rad))
    ..close();
}

/// 尖头朝上的墨滴。[center] 是圆腹圆心，[r] 圆腹半径，[tail] 尖端到圆心的距离。
///
/// 用「一段 240° 的圆弧 + 两条由尖端引出的微凹侧边」构造。
/// 这里刻意不用 `arcToPoint(clockwise:)`——它对「哪条弧」的判定依赖两点的相对
/// 位置，实测会把 240° 的圆腹选成 120° 的短弧，墨滴被压成一枚叶子。
/// `arcTo(rect, startAngle, sweepAngle)` 的角度是显式的，没有歧义。
Path _dropPath(Offset center, double r, double tail) {
  final tip = Offset(center.dx, center.dy - tail);
  final rect = Rect.fromCircle(center: center, radius: r);
  const a0 = -math.pi / 6; // -30°：圆腹右上缘
  const sweep = math.pi * 4 / 3; // +240°，顺时针途经正下方
  final p0 = Offset(center.dx + r * math.cos(a0), center.dy + r * math.sin(a0));
  final p1 = Offset(
    center.dx + r * math.cos(a0 + sweep),
    center.dy + r * math.sin(a0 + sweep),
  );
  // 侧边取「尖端↔切点」的中点作控制点，并向中轴收 10%，做出腰身
  final cR = Offset.lerp(tip, p0, 0.5)!;
  final cL = Offset.lerp(tip, p1, 0.5)!;
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..quadraticBezierTo(center.dx + (cR.dx - center.dx) * 0.90, cR.dy, p0.dx, p0.dy)
    ..arcTo(rect, a0, sweep, false)
    ..quadraticBezierTo(center.dx + (cL.dx - center.dx) * 0.90, cL.dy, tip.dx, tip.dy)
    ..close();
}


/// 应用内的小号品牌标识，用在标题栏等位置。
///
/// [size] 与图标生成用的是同一套几何，只是换了个渲染入口，
/// 所以界面里的 Logo 和 exe 图标永远长一样。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BrandMarkPainter(BrandIconTier.forSize(size)),
        isComplex: true,
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.tier);

  final BrandIconTier tier;

  @override
  void paint(Canvas canvas, Size size) {
    paintBrandIcon(canvas, size.shortestSide, tier);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.tier != tier;
}
