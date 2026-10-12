#!/usr/bin/env python3
"""把 Windows Release 产物打成一个可直接分发的 zip。

产物布局（解压即用，不再需要 Flutter）：

    墨阅 MoRead-1.0.0-windows-x64.zip
      └─ 墨阅 MoRead-1.0.0-windows-x64/
           ├─ MoRead.exe
           ├─ 使用说明.txt
           ├─ data/                     ← Flutter 资源与 Dart AOT 产物
           ├─ flutter_windows.dll
           ├─ file_selector_windows_plugin.dll
           └─ url_launcher_windows_plugin.dll

用法：python tool/package_win.py
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "build" / "windows" / "x64" / "runner" / "Release"
DIST = ROOT / "dist"

# exe 之外还必须一起走的文件，缺一个就打不开
REQUIRED = [
    "MoRead.exe",
    "flutter_windows.dll",
    "file_selector_windows_plugin.dll",
    "url_launcher_windows_plugin.dll",
    "data/app.so",
    "data/icudtl.dat",
]

README = """墨阅 MoRead {ver}
{bar}

用 Flutter 原生实现的 Markdown 编辑器与阅读器。
写的时候像 Typora，读的时候像语雀。

——— 怎么跑 ———
双击 MoRead.exe 就行，免安装，不写注册表。

  注意：MoRead.exe 依赖同一个文件夹里的 data\\ 目录和三个 .dll，
        它们是一个整体，别把 exe 单独拷出去。
        整个文件夹可以随意改名、挪动、拷到 U 盘。

如果 Windows 弹出「已保护你的电脑」：
  点「更多信息」→「仍要运行」。这是没有代码签名证书的软件的正常提示。

——— 首次启动 ———
会载入一份示例文档，演示了代码块（行号／高亮／复制）、数学公式、
Mermaid 流程图、表格、四种提示卡片和图片灯箱。看完直接删掉即可。

——— 快捷键 ———
  Ctrl+O           打开文件
  Ctrl+S           保存
  Ctrl+Shift+S     另存为
  Ctrl+N           新建
  Ctrl+\\           展开 / 收起大纲
  Ctrl+Shift+/     在 编辑 / 阅读 / 源码 之间轮换

——— 卸载 ———
删掉整个文件夹即可，系统里不会残留任何东西。
"""


def pubspec_version() -> str:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*(\S+)", text, re.M)
    if not m:
        sys.exit("✗ pubspec.yaml 里找不到 version")
    return m.group(1).split("+")[0]  # 1.0.0+1 → 1.0.0


def main() -> int:
    if not RELEASE.is_dir():
        sys.exit(f"✗ 找不到 {RELEASE}\n  先跑：flutter build windows --release")

    missing = [f for f in REQUIRED if not (RELEASE / f).is_file()]
    if missing:
        sys.exit("✗ Release 目录不完整，缺少：\n   " + "\n   ".join(missing))

    ver = pubspec_version()
    name = f"墨阅 MoRead-{ver}-windows-x64"

    DIST.mkdir(exist_ok=True)
    stage_parent = DIST / "_stage"
    if stage_parent.exists():
        shutil.rmtree(stage_parent)
    stage = stage_parent / name
    shutil.copytree(RELEASE, stage)

    (stage / "使用说明.txt").write_text(
        README.format(ver=ver, bar="=" * 40), encoding="utf-8"
    )

    zip_path = DIST / f"{name}.zip"
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(stage.rglob("*")):
            if f.is_file():
                # 相对路径以顶层文件夹开头，解压不会散落一地
                z.write(f, Path(name) / f.relative_to(stage))

    shutil.rmtree(stage_parent)

    raw = sum(f.stat().st_size for f in RELEASE.rglob("*") if f.is_file())
    print(f"✅ {zip_path.relative_to(ROOT)}")
    print(f"   版本   : {ver}")
    print(f"   解压后 : {raw / 1048576:.1f} MB")
    print(f"   压缩包 : {zip_path.stat().st_size / 1048576:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
