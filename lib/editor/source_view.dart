import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// 源码模式：整篇文档一个普通 TextField，作为所见即所得模式的兜底
/// （复杂结构出问题时用户仍能直接改源码）。
class SourceView extends StatefulWidget {
  const SourceView({
    super.key,
    required this.source,
    required this.revision,
    required this.palette,
    required this.onChanged,
  });

  final String source;
  final int revision;
  final MdPalette palette;
  final ValueChanged<String> onChanged;

  @override
  State<SourceView> createState() => _SourceViewState();
}

class _SourceViewState extends State<SourceView> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.source);

  @override
  void didUpdateWidget(covariant SourceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision &&
        _controller.text != widget.source) {
      _controller.value = TextEditingValue(
        text: widget.source,
        selection:
            TextSelection.collapsed(offset: widget.source.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return ColoredBox(
      color: p.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 18, 30, 30),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          autofocus: false,
          style: MdType.mono(p),
          cursorColor: p.accent,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
