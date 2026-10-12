import 'package:flutter/foundation.dart';

/// 块类型。
enum BlockType {
  paragraph,
  heading,
  code,
  quote,
  bullet,
  ordered,
  divider,

  /// 表格（表头 + 对齐行 + 数据行），整段保存在 [MdBlock.content] 里。
  table,

  /// 提示卡片。两套写法都支持：
  /// 容器式 `:::info 标题` … `:::`，以及引用式 `> [!NOTE]` …（连续引用行）。
  callout,

  /// 折叠块：`:::details 标题` … `:::`。
  details,

  /// 块级公式。`$$` 独占一行的围栏写法，或单行 `$$E=mc^2$$`。
  mathBlock,
}

/// 表格列对齐。
enum MdAlign { left, center, right }

/// 提示卡片的种类（引用式写法的类型名会先小写化，`caution` 归一到 `warning`）。
const Set<String> kCalloutKinds = <String>{
  'note',
  'info',
  'tip',
  'success',
  'warning',
  'caution',
  'danger',
  'important',
};

/// 一个块。
///
/// 设计要点：`raw == prefix + content + suffix`，且 [MdDocument.source]
/// 把各块的 raw 用 "\n" 拼回去后必须与原始文本**逐字节相同**。
/// 编辑器只改块的边界，永远不重排、不丢字符，这样「编辑 → 保存」不会悄悄改写用户的文件。
@immutable
class MdBlock {
  const MdBlock({
    required this.type,
    this.level = 0,
    this.prefix = '',
    this.content = '',
    this.suffix = '',
    this.lang = '',
    this.variant = '',
    this.title = '',
  });

  final BlockType type;

  /// 标题层级 1-6，其它类型为 0。
  final int level;

  /// 块前缀，例如 "# "、"- "、"> "、"1. "、代码块的开始围栏行 + 换行。
  final String prefix;

  /// 主体内容（不含前缀/后缀）。
  final String content;

  /// 块后缀，目前只有代码块的结束围栏会用到。
  final String suffix;

  /// 代码块语言标记。
  final String lang;

  /// 变体标记。提示卡片存种类名（`info` / `warning` …），其它块为空。
  final String variant;

  /// 容器标题。折叠块的标题、带标题的提示卡片标题。
  final String title;

  String get raw => '$prefix$content$suffix';

  bool get isCode => type == BlockType.code;

  /// 正文（去掉容器自身的行首标记，供渲染使用）。
  ///
  /// 引用式提示卡片 `> [!NOTE]` 的后续行仍带 `>`，这个标记必须留在原文里
  /// （否则破坏 `raw` 的无损性），所以这里在渲染前按行剥掉。
  String get body {
    if (!prefix.trimLeft().startsWith('>')) return content;
    return content
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*>\s?'), ''))
        .join('\n');
  }

  /// 单行块的块标记长度（代码块是围栏，不适用）。
  int get markerLength => prefix.length;

  MdBlock copyWith({
    BlockType? type,
    int? level,
    String? prefix,
    String? content,
    String? suffix,
    String? lang,
    String? variant,
    String? title,
  }) {
    return MdBlock(
      type: type ?? this.type,
      level: level ?? this.level,
      prefix: prefix ?? this.prefix,
      content: content ?? this.content,
      suffix: suffix ?? this.suffix,
      lang: lang ?? this.lang,
      variant: variant ?? this.variant,
      title: title ?? this.title,
    );
  }
}

/// 大纲条目。
@immutable
class MdHeading {
  const MdHeading({
    required this.blockIndex,
    required this.level,
    required this.text,
  });

  final int blockIndex;
  final int level;
  final String text;
}

/// 表格的解析结果。
///
/// 刻意不依赖 Flutter —— 只产出纯数据，对齐方式用 [MdAlign] 表示，
/// 这样表格解析能在独立 Dart 进程里被测试。
@immutable
class MdTable {
  const MdTable({
    required this.headers,
    required this.rows,
    required this.aligns,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<MdAlign> aligns;

  int get columnCount => headers.length;

  /// 按 `|` 切分一行，尊重 `\|` 转义。
  static List<String> splitRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) {
      s = s.substring(0, s.length - 1);
    }
    final cells = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length && s[i + 1] == '|') {
        buf.write('|');
        i++;
        continue;
      }
      if (c == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  static final RegExp _delimiterRe =
      RegExp(r'^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$');

  /// 判断 [line] 是否是表格的对齐行（`| --- | :--: |`）。
  ///
  /// 必须含 `|`：否则 `---` 这类分割线也会匹配上，
  /// 让「上一行恰好含竖线的标题 + 分割线」被误判成表格。
  static bool isDelimiter(String line) =>
      line.contains('|') && _delimiterRe.hasMatch(line);

  /// 从块的原始正文解析表格。首行表头、次行对齐、其余为数据。
  static MdTable parse(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty) {
      return const MdTable(
        headers: <String>[],
        rows: <List<String>>[],
        aligns: <MdAlign>[],
      );
    }

    final headers = splitRow(lines[0]);
    final aligns = <MdAlign>[];
    if (lines.length > 1) {
      for (final c in splitRow(lines[1])) {
        final left = c.startsWith(':');
        final right = c.endsWith(':');
        aligns.add(left && right
            ? MdAlign.center
            : (right ? MdAlign.right : MdAlign.left));
      }
    }
    while (aligns.length < headers.length) {
      aligns.add(MdAlign.left);
    }

    final rows = <List<String>>[];
    for (var i = 2; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final cells = splitRow(lines[i]);
      while (cells.length < headers.length) {
        cells.add('');
      }
      rows.add(cells.length > headers.length
          ? cells.sublist(0, headers.length)
          : cells);
    }

    return MdTable(
      headers: headers,
      rows: rows,
      aligns: aligns.sublist(0, headers.length),
    );
  }
}

/// 文档 = 块列表。raw 是唯一真相来源。
class MdDocument {
  MdDocument(this.blocks);

  final List<MdBlock> blocks;

  String get source => blocks.map((b) => b.raw).join('\n');

  List<MdHeading> get headings {
    final out = <MdHeading>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.type == BlockType.heading) {
        out.add(MdHeading(blockIndex: i, level: b.level, text: b.content));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // 解析
  // ---------------------------------------------------------------------

  static final RegExp _fenceRe = RegExp(r'^(\s*)(`{3,}|~{3,})\s*([^\s`]*)');
  static final RegExp _headingRe = RegExp(r'^(#{1,6})(\s+)(.*)$');
  static final RegExp _headingBareRe = RegExp(r'^(#{1,6})\s*$');
  static final RegExp _quoteRe = RegExp(r'^(\s*>\s?)(.*)$');
  static final RegExp _bulletRe = RegExp(r'^(\s*[-*+]\s+)(.*)$');
  static final RegExp _orderedRe = RegExp(r'^(\s*\d+[.)]\s+)(.*)$');
  static final RegExp _dividerRe = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');

  /// 容器块开始：`:::info 标题`、`:::details 标题`。
  static final RegExp _containerOpenRe = RegExp(r'^\s*:::(\w+)\s*(.*)$');

  /// 容器块结束：独占一行的 `:::`。
  static final RegExp _containerCloseRe = RegExp(r'^\s*:::\s*$');

  /// 单行块级公式：`$$E = mc^2$$`。
  /// 首尾空白也要捕获 —— 否则 `  $$ x $$` 的前导空格会在拼回时丢失。
  static final RegExp _mathInlineRe = RegExp(r'^(\s*)\$\$(.+?)\$\$(\s*)$');

  /// 围栏式块级公式的开始/结束行：独占一行的 `$$`。
  static final RegExp _mathFenceRe = RegExp(r'^\s*\$\$\s*$');

  /// 引用式提示卡片的类型标记：`[!NOTE]` 或 `[!NOTE] 标题`。
  static final RegExp _alertRe = RegExp(r'^\[!(\w+)\]\s*(.*)$');

  /// 表格行必须含 `|`。
  static bool _looksLikeTableRow(String line) => line.contains('|');

  static MdDocument parse(String source) {
    final lines = source.split('\n');
    final blocks = <MdBlock>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // 1) 代码块
      final fm = _fenceRe.firstMatch(line);
      if (fm != null) {
        final fence = fm.group(2)!;
        final lang = (fm.group(3) ?? '').trim();
        final isLastLine = i == lines.length - 1;
        final prefix = isLastLine ? line : '$line\n';

        final body = <String>[];
        var j = i + 1;
        var closed = false;
        final closer = RegExp(
          '^\\s*${RegExp.escape(fence[0])}{${fence.length},}\\s*\$',
        );
        while (j < lines.length) {
          if (closer.hasMatch(lines[j])) {
            closed = true;
            break;
          }
          body.add(lines[j]);
          j++;
        }

        final content = body.join('\n');
        final suffix = closed
            ? (body.isEmpty ? lines[j] : '\n${lines[j]}')
            : '';

        blocks.add(MdBlock(
          type: BlockType.code,
          prefix: prefix,
          content: content,
          suffix: suffix,
          lang: lang,
        ));
        i = closed ? j + 1 : j;
        continue;
      }

      // 2) 块级公式
      final mathOne = _mathInlineRe.firstMatch(line);
      if (mathOne != null) {
        blocks.add(MdBlock(
          type: BlockType.mathBlock,
          prefix: '${mathOne.group(1)!}\$\$',
          content: mathOne.group(2)!,
          suffix: '\$\$${mathOne.group(3)!}',
        ));
        i++;
        continue;
      }
      if (_mathFenceRe.hasMatch(line)) {
        final isLastLine = i == lines.length - 1;
        final prefix = isLastLine ? line : '$line\n';
        final body = <String>[];
        var j = i + 1;
        var closed = false;
        while (j < lines.length) {
          if (_mathFenceRe.hasMatch(lines[j])) {
            closed = true;
            break;
          }
          body.add(lines[j]);
          j++;
        }
        final content = body.join('\n');
        final suffix = closed
            ? (body.isEmpty ? lines[j] : '\n${lines[j]}')
            : '';
        blocks.add(MdBlock(
          type: BlockType.mathBlock,
          prefix: prefix,
          content: content,
          suffix: suffix,
        ));
        i = closed ? j + 1 : j;
        continue;
      }

      // 3) 容器块：:::info / :::details … :::
      final cm = _containerOpenRe.firstMatch(line);
      if (cm != null) {
        final kind = cm.group(1)!.toLowerCase();
        final isLastLine = i == lines.length - 1;
        final prefix = isLastLine ? line : '$line\n';
        final body = <String>[];
        var j = i + 1;
        var closed = false;

        // 容器可以嵌套。只看「第一个 ::: 就收尾」的话，内层的收尾符号会把
        // 外层一起关掉，剩下的裸 ::: 还会掉到段落里去。这里用深度计数配对。
        var depth = 1;
        while (j < lines.length) {
          if (_containerOpenRe.hasMatch(lines[j])) {
            depth++;
          } else if (_containerCloseRe.hasMatch(lines[j])) {
            depth--;
            if (depth == 0) {
              closed = true;
              break;
            }
          }
          body.add(lines[j]);
          j++;
        }
        final content = body.join('\n');
        final suffix = closed
            ? (body.isEmpty ? lines[j] : '\n${lines[j]}')
            : '';
        final isDetails = kind == 'details';
        blocks.add(MdBlock(
          type: isDetails ? BlockType.details : BlockType.callout,
          prefix: prefix,
          content: content,
          suffix: suffix,
          variant: isDetails ? '' : _normalizeCallout(kind),
          title: (cm.group(2) ?? '').trim(),
        ));
        i = closed ? j + 1 : j;
        continue;
      }

      // 4) 分割线（必须在列表之前判断，否则 "- - -" 会被当成列表项）
      if (_dividerRe.hasMatch(line)) {
        blocks.add(MdBlock(type: BlockType.divider, content: line));
        i++;
        continue;
      }

      // 5) 表格：本行含竖线、且下一行是对齐行
      if (_looksLikeTableRow(line) &&
          i + 1 < lines.length &&
          MdTable.isDelimiter(lines[i + 1])) {
        var j = i + 2;
        while (j < lines.length &&
            _looksLikeTableRow(lines[j]) &&
            lines[j].trim().isNotEmpty) {
          j++;
        }
        blocks.add(MdBlock(
          type: BlockType.table,
          content: lines.sublist(i, j).join('\n'),
        ));
        i = j;
        continue;
      }

      // 3) 标题
      final hm = _headingRe.firstMatch(line);
      if (hm != null) {
        final hashes = hm.group(1)!;
        blocks.add(MdBlock(
          type: BlockType.heading,
          level: hashes.length,
          prefix: '$hashes${hm.group(2)}',
          content: hm.group(3) ?? '',
        ));
        i++;
        continue;
      }
      final hb = _headingBareRe.firstMatch(line);
      if (hb != null) {
        final hashes = hb.group(1)!;
        blocks.add(MdBlock(
          type: BlockType.heading,
          level: hashes.length,
          prefix: hashes,
        ));
        i++;
        continue;
      }

      // 6) 引用 / 引用式提示卡片 `> [!NOTE]`
      final qm = _quoteRe.firstMatch(line);
      if (qm != null) {
        final inner = qm.group(2) ?? '';
        final alert = _alertRe.firstMatch(inner.trimLeft());
        if (alert != null &&
            kCalloutKinds.contains(alert.group(1)!.toLowerCase())) {
          // 引用式提示卡片会一直吃到「连续引用行」为止。
          // 注意这里的 prefix 不能用 isLastLine 判断：正文为空时本块就只有
          // 这一行，若仍补上 '\n' 会让拼回的文档多出一个空行。
          final body = <String>[];
          var j = i + 1;
          while (j < lines.length && _quoteRe.hasMatch(lines[j])) {
            body.add(lines[j]);
            j++;
          }
          blocks.add(MdBlock(
            type: BlockType.callout,
            prefix: body.isEmpty ? line : '$line\n',
            content: body.join('\n'),
            variant: _normalizeCallout(alert.group(1)!),
            title: (alert.group(2) ?? '').trim(),
          ));
          i = j;
          continue;
        }
        blocks.add(MdBlock(
          type: BlockType.quote,
          prefix: qm.group(1)!,
          content: inner,
        ));
        i++;
        continue;
      }

      // 7) 无序列表
      final bm = _bulletRe.firstMatch(line);
      if (bm != null) {
        blocks.add(MdBlock(
          type: BlockType.bullet,
          prefix: bm.group(1)!,
          content: bm.group(2) ?? '',
        ));
        i++;
        continue;
      }

      // 8) 有序列表
      final om = _orderedRe.firstMatch(line);
      if (om != null) {
        blocks.add(MdBlock(
          type: BlockType.ordered,
          prefix: om.group(1)!,
          content: om.group(2) ?? '',
        ));
        i++;
        continue;
      }

      // 9) 段落（含空行）
      blocks.add(MdBlock(type: BlockType.paragraph, content: line));
      i++;
    }

    if (blocks.isEmpty) {
      blocks.add(const MdBlock(type: BlockType.paragraph));
    }
    return MdDocument(blocks);
  }

  /// 解析单块的 raw，通常返回 1 个块；若用户粘贴了多行内容则可能返回多个。
  static List<MdBlock> parseFragment(String raw) => parse(raw).blocks;

  /// 列表项序号（用于有序列表自动续号）。
  static int orderedIndex(MdBlock block) {
    final m = RegExp(r'^(\d+)').firstMatch(block.prefix.trim());
    if (m == null) return 1;
    return int.tryParse(m.group(1)!) ?? 1;
  }

  /// 归一提示卡片种类：`caution` 与 `warning` 同义，统一成后者，
  /// 免得渲染层要为一个含义相同的种类写两套颜色。
  static String _normalizeCallout(String raw) {
    final k = raw.toLowerCase();
    return k == 'caution' ? 'warning' : k;
  }
}
