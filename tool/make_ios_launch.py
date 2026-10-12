#!/usr/bin/env python3
"""从 assets/icon/icon_1024.png 派生 iOS 启动图（LaunchImage）。

为什么是「把图标当作一枚居中方块」
------------------------------------------------
启动图这一层只有静态资源可用，画不了自定义矢量。而品牌标识的绘制
逻辑（lib/ui/brand_mark.dart）跑在本机跑不了（Dart 子进程已废，见
tool/make_ios_icons.py 的说明），所以这里沿用同一条离线路径：拿 1024
母版做面积平均缩放。

母版 icon_1024.png 本身就是**已经带好圆角、圆角外透明的**那一版
（BrandIconTier.full，即窗口标题栏 / exe 用的那版）。所以：

  · 保留 alpha 直接缩放 → 得到一枚圆角方块，圆角外透明；
  · 放进 LaunchScreen.storyboard 的白底上 → 就是「白纸上落一枚品牌方块」。

这里**不要**走 flatten_over_background（那是给 iOS 主屏图标用的，主屏
图标不允许带透明通道）；启动图恰恰需要透明，否则白底上会出现一个
紫色方块的硬边。

缩放的坑
------------------------------------------------
PNG 存的是**直通 alpha**。如果对 RGB 直接求平均，圆角边缘那些近乎
全透明的像素会把它们的 RGB（预乘编码残留，接近 0）混进来，圆角上
就会挂一圈脏边。所以先把 RGB 乘 alpha 变成预乘、平均、再除回去。

用法：python tool/make_ios_launch.py
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))

from make_ios_icons import read_png, write_png  # noqa: E402

SRC = ROOT / "assets" / "icon" / "icon_1024.png"
DST = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"

# 启动图上这枚方块的显示边长（pt）。storyboard 里 imageView 是
# contentMode="center" + 居中约束，所以渲染尺寸 = 图片像素 / scale。
# 128pt 大致是 iPhone 上「一眼能看清但不喧宾夺主」的尺度。
BASE_PT = 128

SCALES = ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png"))


def resize_area_alpha(
    sw: int, sh: int, src: bytes | bytearray, dw: int, dh: int
) -> bytearray:
    """面积平均缩放，**alpha 感知**（在预乘空间里平均）。

    输入输出都是直通 alpha 的 8bit RGBA。
    """
    if sw == dw and sh == dh:
        return bytearray(src)

    # 目标像素覆盖到的源像素区间是分数的，取重叠长度作权重
    def spans(s_len: int, d_len: int) -> list[list[tuple[int, float]]]:
        ratio = s_len / d_len
        out = []
        for i in range(d_len):
            lo, hi = i * ratio, (i + 1) * ratio
            acc = []
            j = math.floor(lo)
            while j < math.ceil(hi):
                wgt = min(hi, j + 1) - max(lo, j)
                if wgt > 0:
                    acc.append((j, wgt))
                j += 1
            total = sum(w for _, w in acc)
            out.append([(j, w / total) for j, w in acc])
        return out

    xs = spans(sw, dw)
    # 每一步都带着 (预乘 R, 预乘 G, 预乘 B, A) 四通道
    tmp = bytearray(dw * sh * 4)
    for y in range(sh):
        srow = y * sw * 4
        drow = y * dw * 4
        for dx in range(dw):
            pr = pg = pb = pa = 0.0
            for sx, wgt in xs[dx]:
                o = srow + sx * 4
                a = src[o + 3]
                pr += src[o] * a * wgt
                pg += src[o + 1] * a * wgt
                pb += src[o + 2] * a * wgt
                pa += a * wgt
            o = drow + dx * 4
            tmp[o] = min(255, int(pr / 255.0 + 0.5))
            tmp[o + 1] = min(255, int(pg / 255.0 + 0.5))
            tmp[o + 2] = min(255, int(pb / 255.0 + 0.5))
            tmp[o + 3] = int(pa + 0.5)

    ys = spans(sh, dh)
    out = bytearray(dw * dh * 4)
    for dy in range(dh):
        drow = dy * dw * 4
        for dx in range(dw):
            pr = pg = pb = pa = 0.0
            for sy, wgt in ys[dy]:
                o = sy * dw * 4 + dx * 4
                pr += tmp[o] * wgt
                pg += tmp[o + 1] * wgt
                pb += tmp[o + 2] * wgt
                pa += tmp[o + 3] * wgt
            o = drow + dx * 4
            # 除回直通；pa 极小时颜色已不可见，取 0 免得除爆
            out[o] = 0 if pa < 0.5 else min(255, int(pr * 255.0 / pa + 0.5))
            out[o + 1] = 0 if pa < 0.5 else min(255, int(pg * 255.0 / pa + 0.5))
            out[o + 2] = 0 if pa < 0.5 else min(255, int(pb * 255.0 / pa + 0.5))
            out[o + 3] = min(255, int(pa + 0.5))
    return out


def main() -> int:
    if not SRC.is_file():
        sys.exit(f"✗ 缺少母版 {SRC}")
    if not DST.is_dir():
        sys.exit(f"✗ 找不到 {DST}")

    sw, sh, rgba = read_png(SRC)
    print(f"母版 {SRC.name}: {sw}×{sh}")

    for scale, filename in SCALES:
        size = BASE_PT * scale
        out = resize_area_alpha(sw, sh, rgba, size, size)

        # 校验 A：中心必须不透明（缩放没把 alpha 吃掉）
        if out[((size // 2) * size + size // 2) * 4 + 3] != 255:
            sys.exit(f"✗ {filename}: 中心像素透明，缩放出错")
        # 校验 B：四角必须接近全透明（圆角保留，白底才透得出来）
        worst = max(
            out[(y * size + x) * 4 + 3]
            for x, y in ((0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1))
        )
        if worst > 4:
            sys.exit(f"✗ {filename}: 角部 alpha={worst}，圆角丢了（母版用错？）")
        # 校验 C：圆角边缘不能出现脏边——半透明像素不该比中心暗太多
        #         取「预乘后」的亮度比，直通比较会被 alpha 干扰。
        edge = []
        for y in range(size):
            d = (y * size) * 4
            a = out[d + 3]
            if 40 < a < 215:
                edge.append((out[d] * a / 255.0, out[d + 1] * a / 255.0, out[d + 2] * a / 255.0))
        if not edge:
            sys.exit(f"✗ {filename}: 找不到圆角过渡像素，形状可疑")
        lum = sum(0.299 * r + 0.587 * g + 0.114 * b for r, g, b in edge) / len(edge)
        if lum < 20:
            sys.exit(f"✗ {filename}: 圆角边缘预乘亮度 {lum:.1f} 过暗，出现脏边")
        print(f"  {filename:<22} {size:>4}px  角部alpha≤{worst}  过渡像素{len(edge)}个  预乘亮度{lum:.1f}")

        write_png(DST / filename, size, size, out)

    print(f"✅ 已写入 {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
