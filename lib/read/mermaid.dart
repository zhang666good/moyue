import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Mermaid 流程图的方向。
enum MermaidDirection { topDown, bottomTop, leftRight, rightLeft }

/// 节点形状。
enum MermaidShape { rect, round, stadium, subroutine, diamond, circle }

class MermaidNode {
  const MermaidNode({
    required this.id,
    required this.label,
    required this.shape,
  });

  final String id;
  final String label;
  final MermaidShape shape;
}

class MermaidEdge {
  const MermaidEdge({
    required this.from,
    required this.to,
    this.label,
    this.dashed = false,
    this.thick = false,
  });

  final String from;
  final String to;
  final String? label;
  final bool dashed;
  final bool thick;
}

/// 解析结果。
class MermaidGraph {
  const MermaidGraph({
    required this.direction,
    required this.nodes,
    required this.edges,
    this.error,
    this.unsupported = const <String>[],
  });

  final MermaidDirection direction;
  final List<MermaidNode> nodes;
  final List<MermaidEdge> edges;

  /// 解析失败原因。非空时调用方应降级成代码块。
  final String? error;

  /// 认识但没实现的行（比如 `subgraph`），渲染时在图上给个提示。
  final List<String> unsupported;

  bool get isUsable => error == null && nodes.isNotEmpty;

  MermaidNode? nodeOf(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

final RegExp _headerRe =
    RegExp(r'^\s*(?:graph|flowchart)\s+(TD|TB|BT|LR|RL)\b', caseSensitive: false);

/// `A -- 文字 --> B` 归一成 `A -->|文字| B`，后面的解析就只需处理一种形式。
final RegExp _midLabelRe = RegExp(r'--\s+([^>|]+?)\s+-->');

/// 箭头。按「长的优先」排列，否则 `-->` 会被 `--` 先吃掉。
final RegExp _arrowRe = RegExp(
  r'-\.-+>|={2,}>|--+>|--+[ox]|--+|-\.-+|={2,}',
);

/// 节点定义：`A[文字]`、`B{判断}`、`C((圆))` …
final RegExp _nodeRe = RegExp(r'^([A-Za-z0-9_\u4e00-\u9fff.@-]+)\s*(.*)$');

/// 解析 Mermaid 源码。
///
/// 只实现 flowchart。其它图（`sequenceDiagram`、`classDiagram` …）会返回
/// [MermaidGraph.error]，由调用方降级成代码块并给出提示 —— 半吊子渲染
/// 比不渲染更糟，读者会误以为图本来就是那样的。
MermaidGraph parseMermaid(String source) {
  final lines = source.split('\n');
  var direction = MermaidDirection.topDown;
  var headerSeen = false;

  final order = <String>[];
  final nodes = <String, MermaidNode>{};
  final edges = <MermaidEdge>[];
  final unsupported = <String>[];

  void declare(String id, String? label, MermaidShape? shape) {
    if (id.isEmpty) return;
    final existing = nodes[id];
    if (existing == null) {
      order.add(id);
      nodes[id] = MermaidNode(
        id: id,
        label: label ?? id,
        shape: shape ?? MermaidShape.rect,
      );
      return;
    }
    if (label != null) {
      nodes[id] = MermaidNode(
        id: id,
        label: label,
        shape: shape ?? existing.shape,
      );
    } else if (shape != null) {
      nodes[id] = MermaidNode(id: id, label: existing.label, shape: shape);
    }
  }

  for (var raw in lines) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('%%')) continue;

    if (!headerSeen) {
      final hm = _headerRe.firstMatch(line);
      if (hm != null) {
        switch (hm.group(1)!.toUpperCase()) {
          case 'TD':
          case 'TB':
            direction = MermaidDirection.topDown;
          case 'BT':
            direction = MermaidDirection.bottomTop;
          case 'LR':
            direction = MermaidDirection.leftRight;
          case 'RL':
            direction = MermaidDirection.rightLeft;
        }
        headerSeen = true;
        continue;
      }
      // 第一行就是 diagram 关键字却又不认识 → 明确告知不支持
      final first = RegExp(r'^\s*([A-Za-z]+)').firstMatch(line);
      if (first != null && _knownDiagramKeywords.contains(first.group(1))) {
        return MermaidGraph(
          direction: direction,
          nodes: const <MermaidNode>[],
          edges: const <MermaidEdge>[],
          error: '暂不支持 ${first.group(1)} 图，仅支持 flowchart',
        );
      }
      headerSeen = true;
    }

    // 明确忽略的指令行
    if (_ignoredPrefixes.any(line.startsWith)) continue;

    if (line.startsWith('subgraph') ||
        line == 'end' ||
        line.startsWith('direction')) {
      if (line.startsWith('subgraph')) unsupported.add('subgraph');
      continue;
    }

    line = line.replaceAllMapped(_midLabelRe, (m) => '-->|${m.group(1)!.trim()}|');

    final matches = _arrowRe.allMatches(line).toList();
    if (matches.isEmpty) {
      final def = _parseNodeDef(line);
      if (def != null) declare(def.id, def.label, def.shape);
      continue;
    }

    final segments = <String>[];
    var last = 0;
    for (final m in matches) {
      segments.add(line.substring(last, m.start));
      last = m.end;
    }
    segments.add(line.substring(last));

    // 箭头后面的 `|文字|` 归到这条边上
    final labels = List<String?>.filled(matches.length, null);
    for (var i = 1; i < segments.length; i++) {
      var s = segments[i].trimLeft();
      if (s.startsWith('|')) {
        final close = s.indexOf('|', 1);
        if (close > 0) {
          labels[i - 1] = s.substring(1, close).trim();
          segments[i] = s.substring(close + 1);
        }
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final leftDef = _parseNodeDef(segments[i]);
      final rightDef = _parseNodeDef(segments[i + 1]);
      if (leftDef == null || rightDef == null) continue;
      declare(leftDef.id, leftDef.label, leftDef.shape);
      declare(rightDef.id, rightDef.label, rightDef.shape);

      final arrow = matches[i].group(0)!;
      final label = labels[i];
      edges.add(MermaidEdge(
        from: leftDef.id,
        to: rightDef.id,
        label: (label == null || label.isEmpty) ? null : label,
        dashed: arrow.startsWith('-.'),
        thick: arrow.startsWith('='),
      ));
    }
  }

  if (nodes.isEmpty) {
    return MermaidGraph(
      direction: direction,
      nodes: const <MermaidNode>[],
      edges: const <MermaidEdge>[],
      error: '没有解析出任何节点',
    );
  }

  return MermaidGraph(
    direction: direction,
    nodes: <MermaidNode>[for (final id in order) nodes[id]!],
    edges: edges,
    unsupported: unsupported,
  );
}

const Set<String> _knownDiagramKeywords = <String>{
  'sequenceDiagram',
  'classDiagram',
  'stateDiagram',
  'erDiagram',
  'journey',
  'gantt',
  'pie',
  'gitGraph',
  'mindmap',
  'timeline',
  'quadrantChart',
  'requirementDiagram',
  'C4Context',
};

const List<String> _ignoredPrefixes = <String>[
  'style ',
  'classDef ',
  'class ',
  'click ',
  'linkStyle ',
  'accTitle',
  'accDescr',
  '%%{',
];

class _NodeDef {
  const _NodeDef(this.id, this.label, this.shape);
  final String id;
  final String? label;
  final MermaidShape? shape;
}

/// 解析一段可能带形状的节点定义。`A` 这种裸 id 返回 label 为 null。
_NodeDef? _parseNodeDef(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  // 去掉行尾多余的分号
  if (s.endsWith(';')) s = s.substring(0, s.length - 1).trim();
  if (s.isEmpty) return null;

  final m = _nodeRe.firstMatch(s);
  if (m == null) return null;
  final id = m.group(1)!;
  final rest = m.group(2)!.trim();
  if (rest.isEmpty) return _NodeDef(id, null, null);

  final shape = _shapeOf(rest);
  if (shape == null) return _NodeDef(id, null, null);

  final open = shape.open;
  final close = shape.close;
  if (rest.length < open.length + close.length) return _NodeDef(id, null, null);
  if (!rest.startsWith(open) || !rest.endsWith(close)) {
    return _NodeDef(id, null, null);
  }
  final inner = rest.substring(open.length, rest.length - close.length);
  return _NodeDef(id, _cleanLabel(inner), _shapeKind(open));
}

/// 按「长的符号优先」判断形状，否则 `((` 会被当成 `(`。
({String open, String close})? _shapeOf(String rest) {
  const pairs = <({String open, String close})>[
    (open: '((', close: '))'),
    (open: '([', close: '])'),
    (open: '[[', close: ']]'),
    (open: '[', close: ']'),
    (open: '(', close: ')'),
    (open: '{', close: '}'),
  ];
  for (final p in pairs) {
    if (rest.startsWith(p.open) && rest.endsWith(p.close)) return p;
  }
  return null;
}

MermaidShape _shapeKind(String open) => switch (open) {
      '((' => MermaidShape.circle,
      '([' => MermaidShape.stadium,
      '[[' => MermaidShape.subroutine,
      '{' => MermaidShape.diamond,
      '(' => MermaidShape.round,
      _ => MermaidShape.rect,
    };

String _cleanLabel(String raw) {
  var s = raw.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    s = s.substring(1, s.length - 1);
  }
  // <br/> 是 Mermaid 的换行写法，这里换成真换行
  return s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
}

// ---------------------------------------------------------------------------
// 布局
// ---------------------------------------------------------------------------

/// 一条已经排好位置的边。
class MermaidEdgeLayout {
  const MermaidEdgeLayout({
    required this.edge,
    required this.points,
    this.labelAnchor,
  });

  final MermaidEdge edge;

  /// 折线顶点，至少两个。末点贴着目标节点边界。
  final List<Offset> points;

  /// 标签中心位置。
  final Offset? labelAnchor;
}

/// 排好版的一张图。
class MermaidLayout {
  const MermaidLayout({
    required this.size,
    required this.rects,
    required this.edges,
    required this.graph,
  });

  final Size size;
  final Map<String, Rect> rects;
  final List<MermaidEdgeLayout> edges;
  final MermaidGraph graph;
}

/// 节点内边距与字号（绘制端必须用同一套数值，否则文字会和框对不上）。
const double kMermaidFontSize = 13.5;
const double kMermaidPadH = 14;
const double kMermaidPadV = 9;
const double kMermaidMinW = 54;
const double kMermaidMinH = 34;

/// 层间距与同层节点间距。
const double kMermaidRankGap = 46;
const double kMermaidNodeGap = 26;

/// 估算文本宽度。
///
/// 布局层不依赖 Flutter 的排版引擎，所以用一个够准的估算：
/// CJK 按一个全角宽算，其它按 0.56 个。绘制端用的是同一套数值，
/// 因此框和文字始终一致 —— 估算的偏差只影响「框比文字宽多少」，不会错位。
double estimateTextWidth(String text, {double fontSize = kMermaidFontSize}) {
  var w = 0.0;
  var widest = 0.0;
  for (final rune in text.runes) {
    if (rune == 0x0A) {
      widest = math.max(widest, w);
      w = 0;
      continue;
    }
    w += rune > 0x2E80 ? fontSize : fontSize * 0.56;
  }
  return math.max(widest, w);
}

int _lineCount(String text) =>
    text.isEmpty ? 1 : text.split('\n').length;

Size nodeSize(MermaidNode node) {
  final lines = _lineCount(node.label);
  final textW = estimateTextWidth(node.label);
  return Size(
    math.max(kMermaidMinW, textW + kMermaidPadH * 2),
    math.max(kMermaidMinH, lines * kMermaidFontSize * 1.35 + kMermaidPadV * 2),
  );
}

/// 分层 + 定位。
MermaidLayout layoutMermaid(MermaidGraph graph) {
  final sizes = <String, Size>{
    for (final n in graph.nodes) n.id: nodeSize(n),
  };

  final horizontal = graph.direction == MermaidDirection.leftRight ||
      graph.direction == MermaidDirection.rightLeft;

  // ---- 1) 定层号：反复松弛，直到不再变化。
  //
  // 有环时这个循环不会自然收敛，所以加了「最多 N 轮」的硬上限 ——
  // 图里出现 A→B→A 是常见的写法（用户想表达「互相调用」），不能让程序卡住。
  final rank = <String, int>{for (final n in graph.nodes) n.id: 0};
  for (var pass = 0; pass <= graph.nodes.length; pass++) {
    var changed = false;
    for (final e in graph.edges) {
      if (!rank.containsKey(e.from) || !rank.containsKey(e.to)) continue;
      final want = rank[e.from]! + 1;
      if (want > rank[e.to]!) {
        rank[e.to] = want;
        changed = true;
      }
    }
    if (!changed) break;
  }

  final layers = <int, List<String>>{};
  for (final n in graph.nodes) {
    layers.putIfAbsent(rank[n.id]!, () => <String>[]).add(n.id);
  }
  final layerKeys = layers.keys.toList()..sort();

  double mainExtent(Size s) => horizontal ? s.width : s.height;
  double crossExtent(Size s) => horizontal ? s.height : s.width;

  // ---- 2) 主轴位置：逐层累加。
  final mainPos = <String, double>{};
  final crossPos = <String, double>{};
  final layerCrossSize = <int, double>{};
  var mainCursor = 0.0;
  var maxLayerCross = 0.0;

  for (final key in layerKeys) {
    final ids = layers[key]!;
    var layerMain = 0.0;
    for (final id in ids) {
      layerMain = math.max(layerMain, mainExtent(sizes[id]!));
    }

    var cross = 0.0;
    for (final id in ids) {
      // 层内居中对齐：高度不一的节点在同一条带上更整齐
      mainPos[id] = mainCursor + (layerMain - mainExtent(sizes[id]!)) / 2;
      crossPos[id] = cross;
      cross += crossExtent(sizes[id]!) + kMermaidNodeGap;
    }
    if (ids.isNotEmpty) cross -= kMermaidNodeGap;

    layerCrossSize[key] = cross;
    maxLayerCross = math.max(maxLayerCross, cross);
    mainCursor += layerMain + kMermaidRankGap;
  }
  final totalMain =
      mainCursor > 0 ? mainCursor - kMermaidRankGap : 0.0;

  // ---- 3) 交叉轴：每层整体居中，避免短层贴在左边。
  final rects = <String, Rect>{};
  for (final key in layerKeys) {
    final ids = layers[key]!;
    final offset = (maxLayerCross - layerCrossSize[key]!) / 2;
    for (final id in ids) {
      final s = sizes[id]!;
      final cross = crossPos[id]! + offset;
      final main = mainPos[id]!;

      double x, y;
      switch (graph.direction) {
        case MermaidDirection.topDown:
          x = cross;
          y = main;
        case MermaidDirection.bottomTop:
          x = cross;
          y = totalMain - main - s.height;
        case MermaidDirection.leftRight:
          x = main;
          y = cross;
        case MermaidDirection.rightLeft:
          x = totalMain - main - s.width;
          y = cross;
      }
      rects[id] = Rect.fromLTWH(x, y, s.width, s.height);
    }
  }

  final totalCross = maxLayerCross;
  final size = horizontal
      ? Size(totalMain, totalCross)
      : Size(totalCross, totalMain);

  // ---- 4) 连线路由
  final edgeLayouts = <MermaidEdgeLayout>[];
  for (final e in graph.edges) {
    final a = rects[e.from];
    final b = rects[e.to];
    if (a == null || b == null) continue;
    edgeLayouts.add(_route(e, a, b, horizontal, rank[e.from]!, rank[e.to]!));
  }

  return MermaidLayout(
    size: size,
    rects: rects,
    edges: edgeLayouts,
    graph: graph,
  );
}

MermaidEdgeLayout _route(
  MermaidEdge e,
  Rect a,
  Rect b,
  bool horizontal,
  int rankA,
  int rankB,
) {
  final forward = rankB > rankA || (rankB == rankA && _after(a, b, horizontal));

  if (forward) {
    if (horizontal) {
      final start = Offset(a.right, a.center.dy);
      final end = Offset(b.left, b.center.dy);
      final midX = (start.dx + end.dx) / 2;
      return MermaidEdgeLayout(
        edge: e,
        points: <Offset>[
          start,
          Offset(midX, start.dy),
          Offset(midX, end.dy),
          end,
        ],
        labelAnchor: Offset(midX, (start.dy + end.dy) / 2),
      );
    }
    final start = Offset(a.center.dx, a.bottom);
    final end = Offset(b.center.dx, b.top);
    final midY = (start.dy + end.dy) / 2;
    return MermaidEdgeLayout(
      edge: e,
      points: <Offset>[
        start,
        Offset(start.dx, midY),
        Offset(end.dx, midY),
        end,
      ],
      labelAnchor: Offset((start.dx + end.dx) / 2, midY),
    );
  }

  // 同层或回边：绕到侧面走一条通道，避免压在节点上。
  const channel = 22.0;
  if (horizontal) {
    final lane = math.max(a.right, b.right) + channel;
    final start = Offset(a.right, a.center.dy);
    final end = Offset(b.right, b.center.dy);
    return MermaidEdgeLayout(
      edge: e,
      points: <Offset>[
        start,
        Offset(lane, start.dy),
        Offset(lane, end.dy),
        end,
      ],
      labelAnchor: Offset(lane, (start.dy + end.dy) / 2),
    );
  }
  final lane = math.max(a.bottom, b.bottom) + channel;
  final start = Offset(a.center.dx, a.bottom);
  final end = Offset(b.center.dx, b.bottom);
  return MermaidEdgeLayout(
    edge: e,
    points: <Offset>[
      start,
      Offset(start.dx, lane),
      Offset(end.dx, lane),
      end,
    ],
    labelAnchor: Offset((start.dx + end.dx) / 2, lane),
  );
}

bool _after(Rect a, Rect b, bool horizontal) =>
    horizontal ? a.center.dx <= b.center.dx : a.center.dy <= b.center.dy;
