import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

class OpenedFile {
  const OpenedFile({
    required this.path,
    required this.name,
    required this.content,
  });

  final String path;
  final String name;
  final String content;
}

/// 文件读写。
///
/// 桌面与移动端的差异全部收敛在这个类里：
///
/// * **打开** —— 两端都走 `file_selector` 的 `openFile`。iOS 上会拉起
///   「文件」App 的文档选择器，拿到的路径是系统拷进沙盒的副本。
/// * **另存为** —— **iOS 根本没有「另存为」对话框**，`file_selector_ios`
///   也没有实现 `getSaveLocation`，直接调用会抛 `UnimplementedError`。
///   所以移动端降级成「写进 App 沙盒的 Documents 目录」，配合 Info.plist 里的
///   `UIFileSharingEnabled`，用户在「文件」App 的「我的 iPhone → 墨阅 MoRead」
///   里就能看到文件、可以拷进拷出。
/// * **保存**（已有路径）—— 两端一致，直接覆写。
///
/// 说明：`extensions` 里**不要带前导点**（写 `md` 而不是 `.md`），
/// 包内部会自己做 `_removeLeadingDots`，带了也能跑，但语义上不干净。
class FileService {
  /// 「打开 / 另存为」允许的文件类型。
  ///
  /// 这里**必须同时给 `uniformTypeIdentifiers`**，否则 iOS 上一点「打开」
  /// 就抛：
  ///
  /// ```
  /// Invalid argument(s): The provided type group Instance of 'XTypeGroup'
  /// should either allow all files, or have a non-empty "uniformTypeIdentifiers"
  /// ```
  ///
  /// 因为 `XTypeGroup` 的各字段是**按平台各取所需**的，不是互相兜底：
  /// `file_selector_ios` 只看 UTI（源码里 `extensions` 连读都没读，
  /// 直接 `ArgumentError`），`file_selector_windows` / `_linux` 只看
  /// `extensions` / `mimeTypes`，`file_selector_macos` 两者都收。
  /// 所以一份组里把三样都写全，各平台自己挑。
  ///
  /// UTI 挑这两个：
  /// * `net.daringfireball.markdown` —— 系统为 `.md` / `.markdown` 声明的官方 UTI；
  /// * `public.plain-text` —— 兜底。`.md` 本身 conform 它，所以即使某个
  ///   `.md` 文件的 UTI 没被正确推断（网络盘、下载来的包等），也仍然可选。
  ///
  /// 注意 **不能只留 UTI 而删掉 `extensions`**：Windows / Linux 侧拿不到
  /// 任何过滤条件，文件选择框就变成「所有文件」了。
  static const XTypeGroup markdownTypeGroup = XTypeGroup(
    label: 'Markdown',
    extensions: <String>['md', 'markdown', 'mdown', 'txt'],
    uniformTypeIdentifiers: <String>[
      'net.daringfireball.markdown',
      'public.plain-text',
    ],
  );

  /// 当前平台是否有系统级的「另存为」对话框。
  ///
  /// 只有桌面端有；iOS / Android 上 `getSaveLocation` 不可用，
  /// 调用会抛异常，必须走 [saveAs] 里的降级分支。
  static bool get hasSaveDialog =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<OpenedFile?> openMarkdown() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[markdownTypeGroup],
    );
    if (file == null) return null;
    return readPath(file.path);
  }

  static Future<OpenedFile> readPath(String path) async {
    var content = await File(path).readAsString();
    // 去掉 UTF-8 BOM，否则首个字符会变成不可见字符
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    return OpenedFile(
      path: path,
      name: p.basename(path),
      content: content,
    );
  }

  static Future<String?> saveAs(
    String content, {
    String? suggestedName,
  }) async {
    final name = _safeName(suggestedName ?? 'untitled.md');

    if (!hasSaveDialog) {
      final dir = _mobileDocumentsDir();
      final target = File(p.join(dir.path, name));
      await target.writeAsString(content);
      return target.path;
    }

    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const <XTypeGroup>[markdownTypeGroup],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(content);
    return location.path;
  }

  static Future<void> write(String path, String content) async {
    await File(path).writeAsString(content);
  }

  /// 把建议文件名压成一个纯文件名，去掉任何目录成分。
  /// 调用方可能把整条路径当名字传进来，直接 join 会跑到沙盒外面去。
  static String _safeName(String raw) {
    final base = p.basename(raw.replaceAll('\\', '/'));
    return base.isEmpty ? 'untitled.md' : base;
  }

  /// 移动端「另存为」的落点：App 沙盒里的 Documents 目录。
  ///
  /// 刻意不引 path_provider——iOS 上 `Directory.systemTemp` 就是 `<沙盒>/tmp`，
  /// 父目录即沙盒根，`Documents` 就在它下面，一行就能拿到，
  /// 省掉一个原生插件（少一个 pod，云端构建也快些）。
  static Directory _mobileDocumentsDir() {
    final docs =
        Directory(p.join(Directory.systemTemp.parent.path, 'Documents'));
    if (docs.existsSync()) return docs;

    // 拿不到沙盒结构（例如 Android）时退到临时目录下的子目录，
    // 至少保证「另存为」不会直接崩掉。
    final fallback = Directory(p.join(Directory.systemTemp.path, 'MoRead'));
    if (!fallback.existsSync()) fallback.createSync(recursive: true);
    return fallback;
  }
}
