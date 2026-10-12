import 'package:highlight/highlight_core.dart' show Node;

/// 语法高亮后的一段叶子文本。`className` 是 highlight.js 的 class 名。
///
/// 刻意不依赖 Flutter —— 压平、切行、行号标注解析这些逻辑都能在
/// 独立 Dart 进程里被测试。
class CodeSpan {
  const CodeSpan({this.className, required this.text});

  final String? className;
  final String text;

  @override
  String toString() => 'CodeSpan($className, ${text.replaceAll('\n', r'\n')})';
}

/// 只起分组作用、本身不带配色的作用域。
///
/// highlight.js 的 class 是**沿着节点树继承**的：`// 注释` 这种片段，
/// `comment` 挂在父节点上，叶子节点的 `className` 是 null。所以压平必须
/// 把祖先的 class 传下来，否则注释、字符串这类彩色片段会全部变成默认色。
///
/// 但也不能无条件继承：`hljs-function`、`hljs-class`、`hljs-params`
/// 在配色表里没有颜色（纯粹是结构壳），继承下来会给普通文字错误上色。
const Set<String> _structuralScopes = <String>{
  'function',
  'class',
  'params',
};

/// 把 highlight 的节点树压平成叶子文本序列，并解析出每个叶子生效的 class。
///
/// 节点树是嵌套的：有子节点的节点只起「作用域」作用，文本全在叶子上。
List<CodeSpan> flattenCodeNodes(List<Node>? nodes) {
  final out = <CodeSpan>[];

  void walk(List<Node>? list, String? inherited) {
    if (list == null) return;
    for (final n in list) {
      final raw = n.className;
      final own = (raw == null || raw.isEmpty) ? null : raw;
      // 结构壳不往下传，其余按「就近优先」继承
      final effective =
          (own != null && _structuralScopes.contains(own)) ? inherited : (own ?? inherited);

      final children = n.children;
      if (children != null && children.isNotEmpty) {
        walk(children, effective);
      } else {
        final value = n.value;
        if (value != null && value.isNotEmpty) {
          out.add(CodeSpan(className: effective, text: value));
        }
      }
    }
  }

  walk(nodes, null);
  return out;
}

/// 按换行把叶子序列切成「一行一组」。
///
/// 叶子内部可能含换行（比如多行注释、模板字符串），必须拆开 ——
/// 否则行号会和内容错位，行高亮也会亮错行。
List<List<CodeSpan>> splitCodeLines(List<CodeSpan> spans) {
  final lines = <List<CodeSpan>>[<CodeSpan>[]];
  for (final s in spans) {
    final parts = s.text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) lines.add(<CodeSpan>[]);
      if (parts[i].isNotEmpty) {
        lines.last.add(CodeSpan(className: s.className, text: parts[i]));
      }
    }
  }
  return lines;
}

/// 仅用于换行的叶子序列（不做语法分析时的兜底）。
List<List<CodeSpan>> plainCodeLines(String source) =>
    splitCodeLines(<CodeSpan>[CodeSpan(text: source)]);

final RegExp _specRe = RegExp(r'\{([\d\s,\-]*)\}\s*$');

/// 从代码围栏行里取出行高亮标注，例如 ```` ```dart {1,3-5} ```` 里的 `1,3-5`。
///
/// 取不到时返回空串。围栏行本身仍完整保留在块的 prefix 里，
/// 所以这个动作不影响文档的无损性。
String fenceHighlightSpec(String fenceLine) {
  final m = _specRe.firstMatch(fenceLine.trimRight());
  return m?.group(1)?.trim() ?? '';
}

/// 解析行高亮标注，返回 1 基行号集合。
///
/// 支持 `1`、`1,3`、`3-5` 及其组合。区间有上限保护，
/// 免得 `1-99999999` 这种标注把展开撑爆。
Set<int> parseHighlightSpec(String spec) {
  const maxSpread = 2000;
  final out = <int>{};
  for (final part in spec.split(',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final dash = t.indexOf('-');
    if (dash > 0) {
      final a = int.tryParse(t.substring(0, dash).trim());
      final b = int.tryParse(t.substring(dash + 1).trim());
      if (a == null || b == null) continue;
      if (b - a >= maxSpread) continue;
      for (var i = a; i <= b; i++) {
        if (i > 0) out.add(i);
      }
    } else {
      final n = int.tryParse(t);
      if (n != null && n > 0) out.add(n);
    }
  }
  return out;
}
