import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../ui/palette.dart';

/// 一张可展示的图片。
class ImageRef {
  const ImageRef({required this.source, required this.alt, this.baseDir});

  /// Markdown 里写的原始地址。
  final String source;

  final String alt;

  /// 文档所在目录，用于解析相对路径。
  final String? baseDir;

  /// 解析成可加载的路径 / URL。解析不出来时返回 null。
  String? get resolved {
    final s = source.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('data:')) return s;
    if (s.startsWith('file://')) return s;

    final decoded = Uri.decodeComponent(s).replaceAll('/', Platform.pathSeparator);
    if (p.isAbsolute(decoded)) return decoded;
    if (baseDir == null || baseDir!.isEmpty) return null;
    return p.normalize(p.join(baseDir!, decoded));
  }

  bool get isRemote =>
      source.startsWith('http://') || source.startsWith('https://');

  String get displayName =>
      alt.trim().isNotEmpty ? alt.trim() : p.basename(source);
}

/// 正文里的图片。
///
/// 图注（caption）取 alt 文本 —— 这是语雀和 GitHub 都遵循的约定，
/// 读者本来就会把 alt 当描述来写。
class ImageFigure extends StatelessWidget {
  const ImageFigure({
    super.key,
    required this.image,
    this.gallery,
    this.index = 0,
    this.onTap,
  });

  final ImageRef image;

  /// 同一篇文档里的所有图片。非空时点击可打开灯箱并左右切换。
  final List<ImageRef>? gallery;

  final int index;

  /// 兜底点击（编辑器用它来激活所在块）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    final resolved = image.resolved;

    Widget content;
    if (resolved == null) {
      content = _Missing(path: image.source, note: '相对路径，但不知道文档所在目录');
    } else {
      content = _image(resolved, p);
    }

    final canOpen = gallery != null && gallery!.length > 0 && resolved != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        MouseRegion(
          cursor: canOpen ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (canOpen) {
                _openLightbox(context, gallery!, index);
              } else {
                onTap?.call();
              }
            },
            child: content,
          ),
        ),
        if (image.alt.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              image.alt.trim(),
              textAlign: TextAlign.center,
              style: MdType.body(p).copyWith(
                fontSize: 13,
                color: p.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _image(String resolved, MdPalette p) {
    final frame = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: p.border, width: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: image.isRemote
            ? Image.network(
                resolved,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _Placeholder(
                    path: '加载中 ${(progress.expectedTotalBytes ?? 0) == 0 ? "" : "${(100 * (progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1))).toStringAsFixed(0)}%" }',
                  );
                },
                errorBuilder: (context, error, stack) =>
                    _Missing(path: image.source, note: '加载失败'),
              )
            : Image.file(
                File(resolved),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    _Missing(path: image.source, note: '文件不存在或无法读取'),
              ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 560),
      child: frame,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 90),
      padding: const EdgeInsets.all(20),
      color: p.surface,
      child: Center(
        child: Text(
          path,
          style: MdType.mono(p, size: 12.5).copyWith(color: p.textMuted),
        ),
      ),
    );
  }
}

/// 图片缺失时的占位。
///
/// 直接画出地址而不是留白：读者一眼就知道是「图挂了」还是「本来就没图」，
/// 顺带能看出路径对不对。
class _Missing extends StatelessWidget {
  const _Missing({required this.path, required this.note});

  final String path;
  final String note;

  @override
  Widget build(BuildContext context) {
    final p = MdPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 96, minWidth: 220),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.broken_image_outlined, size: 26, color: p.textMuted),
          const SizedBox(height: 7),
          Text(
            note,
            textAlign: TextAlign.center,
            style: MdType.body(p).copyWith(fontSize: 13, color: p.textMuted),
          ),
          const SizedBox(height: 3),
          Text(
            path,
            textAlign: TextAlign.center,
            style: MdType.mono(p, size: 12).copyWith(color: p.marker),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 灯箱
// ---------------------------------------------------------------------------

Future<void> _openLightbox(
  BuildContext context,
  List<ImageRef> images,
  int index,
) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xE6000000),
    builder: (context) => _Lightbox(images: images, initialIndex: index),
  );
}

class _Lightbox extends StatefulWidget {
  const _Lightbox({required this.images, required this.initialIndex});

  final List<ImageRef> images;
  final int initialIndex;

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late int _index = widget.initialIndex;
  final TransformationController _zoom = TransformationController();
  bool _showChrome = true;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  ImageRef get _current => widget.images[_index];

  void _step(int delta) {
    if (widget.images.length < 2) return;
    setState(() {
      _index = (_index + delta) % widget.images.length;
      if (_index < 0) _index += widget.images.length;
      _zoom.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _showChrome = true),
                  onHover: (_) {
                    if (!_showChrome) setState(() => _showChrome = true);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Center(
                      child: InteractiveViewer(
                        transformationController: _zoom,
                        minScale: 0.4,
                        maxScale: 8,
                        child: _preview(_current),
                      ),
                    ),
                  ),
                ),
              ),
              if (_showChrome) ...<Widget>[
                Positioned(
                  top: 12,
                  right: 14,
                  child: Row(
                    children: <Widget>[
                      if (total > 1)
                        _chromeText('${_index + 1} / $total'),
                      const SizedBox(width: 10),
                      _RoundIcon(
                        icon: Icons.close_rounded,
                        tooltip: '关闭 (Esc)',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                if (total > 1) ...<Widget>[
                  Positioned(
                    left: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _RoundIcon(
                        icon: Icons.chevron_left_rounded,
                        tooltip: '上一张 (←)',
                        onTap: () => _step(-1),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _RoundIcon(
                        icon: Icons.chevron_right_rounded,
                        tooltip: '下一张 (→)',
                        onTap: () => _step(1),
                      ),
                    ),
                  ),
                ],
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(child: _caption(_current)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(ImageRef ref) {
    const size = 40.0;
    final resolved = ref.resolved;
    if (resolved == null) {
      return const SizedBox.shrink();
    }
    if (ref.isRemote) {
      return Image.network(
        resolved,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) =>
            _chromeText('无法加载 ${ref.source}'),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      );
    }
    return Image.file(
      File(resolved),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          _chromeText('无法加载 ${ref.source}'),
    );
  }

  Widget _caption(ImageRef ref) {
    final name = ref.displayName;
    return Container(
      constraints: const BoxConstraints(maxWidth: 620),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13),
      ),
    );
  }

  Widget _chromeText(String text) => Text(
        text,
        style: const TextStyle(color: Color(0xCCE6EDF3), fontSize: 13),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x66000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 20, color: const Color(0xFFE6EDF3)),
          ),
        ),
      ),
    );
  }
}
