#!/usr/bin/env python3
"""把 assets/icon/icon_<size>.rgba 组装成 Windows .ico。

ICO 内每帧用标准 BMP(BITMAPINFOHEADER) 封装 32bpp BGRA + 全零 AND 掩码，
这是兼容性最好的写法（PNG 压缩帧虽被 Vista+ 支持，但个别旧 shell 会忽略）。

用法：
    python tool/make_ico.py
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "assets" / "icon"
OUTS = [
    ROOT / "assets" / "icon" / "app_icon.ico",
    ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
]

# 按 Windows 惯例由小到大；24 与 48 是资源管理器/工具栏常用档
FRAMES = [16, 24, 32, 48, 64, 128, 256]


def bmp_frame(rgba: bytes, size: int) -> bytes:
    """把自上而下的 RGBA 数据转成一帧 ICO 图像（BMP 格式）。"""
    expected = size * size * 4
    if len(rgba) != expected:
        raise ValueError(f"{size}: 期望 {expected} 字节 RGBA，实际 {len(rgba)}")

    # BITMAPINFOHEADER：高度写 2 倍，因为后面还要跟 AND 掩码
    header = struct.pack(
        "<IiiHHIIiiII",
        40,          # biSize
        size,        # biWidth
        size * 2,    # biHeight = XOR + AND
        1,           # biPlanes
        32,          # biBitCount
        0,           # biCompression = BI_RGB
        0,           # biSizeImage（下填）
        0, 0,        # 分辨率
        0, 0,        # 调色板
    )

    # BGRA 且自下而上
    rows = bytearray()
    stride = size * 4
    for y in range(size - 1, -1, -1):
        row = rgba[y * stride:(y + 1) * stride]
        for x in range(0, stride, 4):
            r, g, b, a = row[x], row[x + 1], row[x + 2], row[x + 3]
            rows += bytes((b, g, r, a))

    # AND 掩码：32bpp 下由 alpha 决定透明，全零即可；每行补到 4 字节对齐
    mask_stride = ((size + 31) // 32) * 4
    and_mask = bytes(mask_stride * size)

    payload = bytes(rows) + and_mask
    header = header[:20] + struct.pack("<I", len(payload)) + header[24:]
    return header + payload


def main() -> int:
    frames: list[tuple[int, bytes]] = []
    for size in FRAMES:
        path = ICON_DIR / f"icon_{size}.rgba"
        if not path.exists():
            print(f"✗ 缺少 {path.name}，请先跑 flutter test test/icon_gen.dart")
            return 1
        frames.append((size, bmp_frame(path.read_bytes(), size)))

    count = len(frames)
    directory = struct.pack("<HHH", 0, 1, count)
    offset = 6 + 16 * count

    entries = bytearray()
    blobs = bytearray()
    for size, blob in frames:
        dim = 0 if size >= 256 else size  # 256 在 ICO 里记作 0
        entries += struct.pack(
            "<BBBBHHII",
            dim, dim, 0, 0, 1, 32, len(blob), offset,
        )
        blobs += blob
        offset += len(blob)

    ico = directory + bytes(entries) + bytes(blobs)

    for out in OUTS:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(ico)
        print(f"✅ {out.relative_to(ROOT)}  ({len(ico)} 字节, {count} 个尺寸)")

    print("   尺寸: " + ", ".join(f"{s}×{s}" for s, _ in frames))
    return 0


if __name__ == "__main__":
    sys.exit(main())
