import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../md/document.dart';
import '../read/block_renderer.dart';
import '../ui/palette.dart';
import 'markdown_editing_controller.dart';

/// 块级所见即所得编辑器。
///
/// 架构：文档 = 块列表，每块保存自己的原始 Markdown（raw）。
/// - 光标所在的块渲染成真正的 [TextField]，显示原始源码、语法标记淡化；
/// - 其它块渲染成只读富文本，语法标记完全隐藏。
///
/// 这样做的关键收益：**活动块就是一个普通 TextField**，中文输入法不用做任何特殊处理。
/// 如果改用「单个 TextField + 隐藏标记字符」，就必须把 `**` 这类字符压成零宽，
/// 而零宽字符会让 IME 的 composing 区间和光标定位错乱 —— 那是个填不完的坑。
class BlockEditor extends StatefulWidget {
  const BlockEditor({
    super.key,
    required this.source,
    required this.revision,
    required this.palette,
    required this.onChanged,
    this.headingKeys = const <int, GlobalKey>{},
    this.baseDir,
  });

  /// 文档源码。仅在 [revision] 变化时才会被采纳（避免与内部编辑互相打架）。
  final String source;

  /// 外部替换文档的版本号。打开文件 / 撤销时 +1。
  final int revision;

  final MdPalette palette;
  final ValueChanged<String> onChanged;

  /// 标题块的下标 → GlobalKey，供大纲跳转使用。
  final Map<int, GlobalKey> headingKeys;

  /// 文档所在目录，用于解析图片相对路径。
  final String? baseDir;

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockSlot {
  _BlockSlot(this.block, MdPalette palette)
      : controller = MarkdownEditingController(
          text: block.raw,
          palette: palette,
          type: block.type,
          level: block.level,
          prefix: block.prefix,
        ),
        focusNode = FocusNode(debugLabel: 'md-block');

  MdBlock block;
  final MarkdownEditingController controller;
  final FocusNode focusNode;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _BlockEditorState extends State<BlockEditor> {
  final List<_BlockSlot> _slots = <_BlockSlot>[];
  int _active = -1;
  int _rebuild = 0;

  @override
  void initState() {
    super.initState();
    _loadBlocks(widget.source);
    _active = _slots.isEmpty ? -1 : 0;
    _scheduleFocus(0, 0);
  }

  @override
  void didUpdateWidget(covariant BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      // notify: false 是必须的，有两个原因：
      // 1) didUpdateWidget 是在父节点 Expanded 的 performRebuild 里被同步调用的
      //    （framework.dart:5854 的 updateChild），此刻对祖先 WorkspacePage
      //    调用 setState 会抛 "setState() called during build"；
      // 2) 外部换文档时 widget.source 就是权威值，回传只会把刚打开的文件标成「未保存」。
      _reloadAt(widget.source, 0, notify: false);
    } else if (oldWidget.palette != widget.palette) {
      for (final s in _slots) {
        s.controller.palette = widget.palette;
      }
    }
  }

  @override
  void dispose() {
    _disposeSlots();
    super.dispose();
  }

  // ---------------------------------------------------------------- 文档装载

  void _disposeSlots() {
    for (final s in _slots) {
      s.dispose();
    }
    _slots.clear();
  }

  void _loadBlocks(String source) {
    _disposeSlots();
    final doc = MdDocument.parse(source);
    for (final b in doc.blocks) {
      _slots.add(_BlockSlot(b, widget.palette));
    }
    if (_slots.isEmpty) {
      _slots.add(_BlockSlot(
        const MdBlock(type: BlockType.paragraph),
        widget.palette,
      ));
    }
  }

  String get _sourceNow => _slots.map((s) => s.block.raw).join('\n');

  /// 第 [index] 块之前的所有字符数（含块之间的换行）。
  int _globalOffsetOf(int index) {
    var acc = 0;
    for (var i = 0; i < index; i++) {
      acc += _slots[i].block.raw.length + 1;
    }
    return acc;
  }

  /// 全局偏移 → (块下标, 块内偏移)。
  ({int index, int offset}) _locate(List<MdBlock> blocks, int global) {
    var acc = 0;
    for (var i = 0; i < blocks.length; i++) {
      final len = blocks[i].raw.length;
      if (global <= acc + len) {
        return (index: i, offset: global - acc);
      }
      acc += len + 1;
    }
    final last = blocks.length - 1;
    return (index: last, offset: blocks[last].raw.length);
  }

  /// 用新源码整体重建文档，并把光标落到全局偏移 [globalCaret] 处。
  ///
  /// 拆块、合并、粘贴多行全部走这一条路径 —— 只保留一个结构性变更入口，
  /// 就不容易出现「某条分支忘了同步下标」这类 bug。
  ///
  /// [notify] 为 false 表示不回传父级。外部换文档（revision 变化）时必须传 false。
  void _reloadAt(String source, int globalCaret, {bool notify = true}) {
    final doc = MdDocument.parse(source);
    _disposeSlots();
    for (final b in doc.blocks) {
      _slots.add(_BlockSlot(b, widget.palette));
    }
    if (_slots.isEmpty) {
      _slots.add(_BlockSlot(
        const MdBlock(type: BlockType.paragraph),
        widget.palette,
      ));
    }

    final at = _locate(doc.blocks, globalCaret);
    _active = at.index.clamp(0, _slots.length - 1);
    _rebuild++;
    setState(() {});
    _scheduleFocus(_active, at.offset);
    if (notify) {
      _notifyParent(source);
    }
  }

  /// 回传文档给父级。
  ///
  /// 父级 [WorkspacePage] 是当前构建元素的**祖先**，在 build 阶段对它调用
  /// setState 会直接抛 "setState() or markNeedsBuild() called during build" ——
  /// 框架只允许标记「当前构建目标的后代」（framework.dart:5363 的
  /// `_debugIsDescendantOf`）。本组件自己的 setState 在 build 阶段是合法的，
  /// 父级不是，所以这里检测到正处于 build / layout / paint 阶段时推迟到帧末；
  /// 届时重新取一遍最新内容，避免推一份过期快照给父级。
  ///
  /// 所有回传都走这一个入口，和多处结构变更统一走 [_reloadAt] 是同一个思路。
  void _notifyParent(String source) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onChanged(_sourceNow);
      });
      return;
    }
    widget.onChanged(source);
  }

  // ------------------------------------------------------------------ 焦点

  void _scheduleFocus(int index, int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusSlotAt(index, offset);
    });
  }

  void _focusSlotAt(int index, int offset) {
    if (index < 0 || index >= _slots.length) return;
    final slot = _slots[index];
    final len = slot.controller.text.length;
    final off = offset < 0 ? len : offset.clamp(0, len);
    slot.controller.selection = TextSelection.collapsed(offset: off);
    slot.focusNode.requestFocus();
  }

  void _activate(int index, int rawOffset) {
    if (index < 0 || index >= _slots.length) return;
    if (_active == index) {
      _focusSlotAt(index, rawOffset);
      return;
    }
    setState(() => _active = index);
    _scheduleFocus(index, rawOffset);
  }

  void _moveFocus(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _slots.length) return;
    setState(() => _active = to);
    _scheduleFocus(to, delta < 0 ? _slots[to].controller.text.length : 0);
  }

  // ------------------------------------------------------------------ 编辑

  void _onBlockChanged(int index) {
    final slot = _slots[index];
    final raw = slot.controller.text;
    final fragments = MdDocument.parseFragment(raw);

    if (fragments.length == 1) {
      // 常规打字：只更新本块，控制器不重建，输入手感不受影响
      slot.block = fragments.first;
      slot.controller.syncBlock(fragments.first, widget.palette);
      _notifyParent(_sourceNow);
      return;
    }

    // 回车 / 粘贴多行导致块被撑破 → 结构性重建
    final caretInBlock = slot.controller.selection.baseOffset.clamp(0, raw.length);
    final parts = <String>[
      ..._slots.sublist(0, index).map((s) => s.block.raw),
      raw,
      ..._slots.sublist(index + 1).map((s) => s.block.raw),
    ];
    _reloadAt(parts.join('\n'), _globalOffsetOf(index) + caretInBlock);
  }

  void _splitAtCursor(int index) {
    final slot = _slots[index];
    final block = slot.block;
    final sel = slot.controller.selection;
    var raw = slot.controller.text;
    var at = raw.length;

    if (sel.isValid && !sel.isCollapsed) {
      raw = raw.replaceRange(sel.start, sel.end, '');
      at = sel.start;
    } else if (sel.isValid) {
      at = sel.baseOffset.clamp(0, raw.length);
    }

    // 空列表项上回车 = 退出列表
    final isListItem =
        block.type == BlockType.bullet || block.type == BlockType.ordered;
    if (isListItem && block.content.trim().isEmpty) {
      final parts = <String>[
        ..._slots.sublist(0, index).map((s) => s.block.raw),
        '',
        ..._slots.sublist(index + 1).map((s) => s.block.raw),
      ];
      _reloadAt(parts.join('\n'), _globalOffsetOf(index));
      return;
    }

    final head = raw.substring(0, at);
    final rest = raw.substring(at);

    // 新块继承列表 / 引用的块标记，让连续输入不用重复敲 "- "
    var tail = rest;
    var inherited = false;
    if (tail.isEmpty) {
      if (block.type == BlockType.bullet) {
        tail = block.prefix;
        inherited = true;
      } else if (block.type == BlockType.ordered) {
        tail = '${MdDocument.orderedIndex(block) + 1}. ';
        inherited = true;
      } else if (block.type == BlockType.quote) {
        tail = block.prefix;
        inherited = true;
      }
    }

    final parts = <String>[
      ..._slots.sublist(0, index).map((s) => s.block.raw),
      head,
      tail,
      ..._slots.sublist(index + 1).map((s) => s.block.raw),
    ];
    var caret = _globalOffsetOf(index) + head.length + 1;
    if (inherited) caret += tail.length;
    _reloadAt(parts.join('\n'), caret);
  }

  void _mergeWithPrevious(int index) {
    if (index <= 0) return;
    final prev = _slots[index - 1];
    final cur = _slots[index];

    // 用 cur.content 而不是 cur.raw：避免把当前块的标记（比如 "## "）一起拼进去
    final merged = prev.block.raw + cur.block.content;
    final caret = prev.block.raw.length;

    final parts = <String>[
      ..._slots.sublist(0, index - 1).map((s) => s.block.raw),
      merged,
      ..._slots.sublist(index + 1).map((s) => s.block.raw),
    ];
    _reloadAt(parts.join('\n'), _globalOffsetOf(index - 1) + caret);
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final slot = _slots[index];
    final key = event.logicalKey;
    final sel = slot.controller.selection;

    if (key == LogicalKeyboardKey.backspace) {
      if (sel.isCollapsed && sel.baseOffset == 0 && index > 0) {
        _mergeWithPrevious(index);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // 代码块里的回车应该换行，不拆块
      if (slot.block.type == BlockType.code) return KeyEventResult.ignored;
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _splitAtCursor(index);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (sel.isCollapsed && sel.baseOffset == 0 && index > 0) {
        _moveFocus(index, -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final len = slot.controller.text.length;
      if (sel.isCollapsed &&
          sel.baseOffset >= len &&
          index < _slots.length - 1) {
        _moveFocus(index, 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------ 构建

  Widget _editable(int index, _BlockSlot slot, MdPalette p) {
    final block = slot.block;
    final controller = slot.controller;
    controller.palette = p;

    final field = TextField(
      controller: controller,
      focusNode: slot.focusNode,
      maxLines: null,
      style: controller.baseStyle,
      cursorColor: p.accent,
      cursorWidth: 2,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      scrollPadding: const EdgeInsets.only(top: 60, bottom: 220),
      decoration: const InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (_) => _onBlockChanged(index),
    );

    // 包裹一层 Focus 来拦截按键。它位于 TextField 自己的 FocusNode 之上、
    // 应用级 DefaultTextEditingShortcuts 之下，所以能先拿到按键；
    // 返回 ignored 时事件照常继续下传，方向键等默认行为不受影响。
    final focused = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleKey(index, event),
      child: field,
    );

    if (block.type == BlockType.code) {
      return Container(
        decoration: BoxDecoration(
          color: p.codeBg,
          border: Border.all(color: p.codeBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: focused,
      );
    }
    return focused;
  }

  Widget _buildBlock(int index, MdPalette p) {
    final slot = _slots[index];
    final block = slot.block;
    final isActive = index == _active;

    final Widget child = isActive
        ? _editable(index, slot, p)
        : BlockRenderer(
            block: block,
            read: ReadContext(baseDir: widget.baseDir),
            onTapOffset: (offset) => _activate(index, offset),
          );

    Widget padded = Padding(
      padding: BlockRenderer.paddingFor(block),
      child: child,
    );

    if (block.type == BlockType.heading) {
      final key = widget.headingKeys[index];
      if (key != null) {
        padded = KeyedSubtree(key: key, child: padded);
      }
    }

    return KeyedSubtree(
      key: ValueKey<String>('blk-$index-$_rebuild'),
      child: padded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 900.0;
        final bodyWidth = width > 900 ? 900.0 : width;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: 18, bottom: 260),
          child: Center(
            child: SizedBox(
              width: bodyWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < _slots.length; i++) _buildBlock(i, p),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
