import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/all.dart' show allLanguages;

import 'code_spans.dart';

/// 语言注册是一次性的全局动作。
///
/// `registerLanguage` 只是往 map 里塞对象（真正的正则编译在 parse 时才做），
/// 所以这里一次性注册全部语言是廉价的；换成「用哪门注册哪门」反而没意义 ——
/// `allLanguages` 本身是个字面量映射，只要碰一下就全构造出来了。
bool _registered = false;

void ensureLanguagesRegistered() {
  if (_registered) return;
  _registered = true;
  highlight.registerLanguages(allLanguages);
}

/// 提前把语言表热起来。
///
/// 第一次高亮时才会真正构造 190 份语言定义，如果恰好发生在滚动或打字中间，
/// 会掉一帧。启动后主动调用一次，把这份开销挪到用户还没在看内容的时候。
void warmUpHighlighter() {
  ensureLanguagesRegistered();
}

/// 高亮结果缓存。
///
/// 每次 rebuild 都重新跑一遍分词对长代码块来说太贵了（编辑别的块也会触发
/// 整个文档重建），所以按「语言 + 源码」缓存，容量满了按插入顺序淘汰最早的。
const int _cacheLimit = 48;
final Map<String, List<List<CodeSpan>>> _cache =
    <String, List<List<CodeSpan>>>{};

/// 把 [source] 高亮成「每行的片段列表」。
///
/// 语言未知时 highlight 自己会退化成纯文本；这里再兜一层 try/catch ——
/// 阅读器不该因为某段代码块的高亮失败就崩掉。
List<List<CodeSpan>> highlightToLines(String source, String language) {
  if (language.isEmpty) return plainCodeLines(source);

  final key = '$language\u0000$source';
  final cached = _cache[key];
  if (cached != null) return cached;

  List<List<CodeSpan>> lines;
  try {
    ensureLanguagesRegistered();
    final result = highlight.parse(source, language: language);
    final spans = flattenCodeNodes(result.nodes);
    lines = spans.isEmpty ? plainCodeLines(source) : splitCodeLines(spans);
  } catch (_) {
    lines = plainCodeLines(source);
  }

  if (_cache.length >= _cacheLimit) {
    _cache.remove(_cache.keys.first);
  }
  _cache[key] = lines;
  return lines;
}
