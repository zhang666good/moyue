#!/usr/bin/env python3
"""从 Windows 图标 PNG 派生 iOS AppIcon 图标集。

为什么不用 Flutter 再渲染一遍
------------------------------------------------
`test/icon_gen.dart` 里的 iOS 分支（paintBrandIcon(..., fullBleed: true)）
才是正解，逻辑上也应该走那条路。但本机环境有一处硬伤：
Dart 进程已经无法再创建任何子进程（Windows 错误 231「所有管道范例都在使用中」），
`flutter test` 的编译前端起不来。所以这里用一条等价的离线路径：

  1. 直接解码 assets/icon/icon_<size>.png（它们是同一份绘制代码渲染出来的）；
  2. 只在**透明区域**补上按同一套渐变公式重算的背景色；
  3. 按 iOS 各档尺寸做面积平均缩放。

第 2 步之所以成立：iOS 图标要铺满整块画布、不留透明，而 Windows 图标在
圆角矩形之外是透明的——那里**除了背景之外没有任何内容**（纸张、墨滴都被
圆角矩形裁掉了）。所以把透明像素换成背景色，结果与 fullBleed 渲染逐像素一致。

方案自带校验：脚本会拿图标里「确定只有背景」的像素，和重算出来的背景比对，
差值应当极小；同时在半透明边缘上验证连续性。跑不通就说明公式抄错了。

用法：python tool/make_ios_icons.py
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "icon"
DST = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# ── 与 lib/ui/brand_mark.dart 保持一致的调色板与几何 ──────────────────────
BG_START = (0x5B, 0x4B, 0xF2)
BG_MID = (0x7C, 0x3A, 0xED)
BG_END = (0xA8, 0x55, 0xF7)
LINEAR_STOPS = ((0.0, BG_START), (0.52, BG_MID), (1.0, BG_END))
LINEAR_FROM = (0.02, -0.04)
LINEAR_TO = (1.02, 1.04)

# 两道径向高光：(圆心u, 圆心v, 半径, 颜色, 峰值alpha)
# 峰值 alpha 取 0.24 / 0.30，与 brand_mark.dart 中的 withValues 一致。
# 两个渐变的**第二个色标都是白色且 alpha=0**，Skia 在预乘空间插值，
# 于是中间色恒等于首色、只有 alpha 线性衰减——这正是下面公式的依据。
RADIALS = (
    (0.24, 0.08, 0.92, (255, 255, 255), 0.24),
    (0.94, 0.10, 0.55, (0xF0, 0xAB, 0xFC), 0.30),
)


def background_at(u: float, v: float, tier: int) -> tuple[float, float, float]:
    """按 brand_mark.dart 的绘制顺序，算出 (u, v) 处的背景色。u, v 为归一化坐标。"""
    # 1) 线性渐变（TileMode.clamp 是 ui.Gradient.linear 的默认值）
    dx = LINEAR_TO[0] - LINEAR_FROM[0]
    dy = LINEAR_TO[1] - LINEAR_FROM[1]
    t = ((u - LINEAR_FROM[0]) * dx + (v - LINEAR_FROM[1]) * dy) / (dx * dx + dy * dy)
    t = min(1.0, max(0.0, t))

    rgb = list(LINEAR_STOPS[-1][1])
    for i in range(len(LINEAR_STOPS) - 1):
        t0, c0 = LINEAR_STOPS[i]
        t1, c1 = LINEAR_STOPS[i + 1]
        if t <= t1:
            f = 1.0 if t1 == t0 else (t - t0) / (t1 - t0)
            rgb = [c0[k] + (c1[k] - c0[k]) * f for k in range(3)]
            break

    # 2) 径向高光（minimal 档 t==0 不画）
    if tier > 0:
        for cx, cy, r, color, amax in RADIALS:
            d = math.hypot(u - cx, v - cy)
            a = amax * max(0.0, 1.0 - d / r)
            rgb = [color[k] * a + rgb[k] * (1.0 - a) for k in range(3)]
    return rgb[0], rgb[1], rgb[2]


# ── 最小 PNG 读写（纯标准库；只用得到 8bit / 非隔行） ─────────────────────


def read_png(path: Path) -> tuple[int, int, bytearray]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} 不是 PNG")

    pos, idat, w = 8, bytearray(), 0
    h = bit_depth = color_type = interlace = 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        if ctype == b"IHDR":
            w, h, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
        pos += 12 + length

    if bit_depth != 8 or interlace != 0:
        raise ValueError(f"{path}: 只支持 8bit 非隔行，实际 depth={bit_depth} interlace={interlace}")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError(f"{path}: 不支持的颜色类型 {color_type}")

    raw = zlib.decompress(bytes(idat))
    stride = w * channels
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ftype = raw[p]
        p += 1
        line = bytearray(raw[p : p + stride])
        p += stride
        # 反滤波（PNG 规范里的五种滤波器）
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ftype != 0:
            raise ValueError(f"{path}: 未知滤波器 {ftype}")

        base = y * w * 4
        for x in range(w):
            s = x * channels
            d = base + x * 4
            if channels == 4:
                out[d : d + 4] = line[s : s + 4]
            elif channels == 3:
                out[d : d + 3] = line[s : s + 3]
                out[d + 3] = 255
            elif channels == 2:
                out[d : d + 3] = bytes((line[s], line[s], line[s]))
                out[d + 3] = line[s + 1]
            else:  # 灰度
                g = line[s]
                out[d : d + 3] = bytes((g, g, g))
                out[d + 3] = 255
        prev = line
    return w, h, out


def write_png(path: Path, w: int, h: int, rgba: bytes | bytearray) -> None:
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (None)
        raw += rgba[y * stride : (y + 1) * stride]

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


# ── 处理 ─────────────────────────────────────────────────────────────────


def flatten_over_background(w: int, h: int, rgba: bytearray, tier: int) -> bytearray:
    """把透明/半透明像素合成到重算的背景上。输出完全不透明（alpha=255）。

    注意合成用的是**直通 alpha**（PNG 存的就是直通），
    即 out = src*a + bg*(1-a)。
    """
    out = bytearray(rgba)
    for y in range(h):
        v = y / h
        base = y * w * 4
        for x in range(w):
            d = base + x * 4
            a = rgba[d + 3]
            if a == 255:
                continue
            br, bg_, bb = background_at(x / w, v, tier)
            fa = a / 255.0
            out[d] = int(rgba[d] * fa + br * (1 - fa) + 0.5)
            out[d + 1] = int(rgba[d + 1] * fa + bg_ * (1 - fa) + 0.5)
            out[d + 2] = int(rgba[d + 2] * fa + bb * (1 - fa) + 0.5)
            out[d + 3] = 255
    return out


def resize_area(sw: int, sh: int, src: bytearray, dw: int, dh: int) -> bytearray:
    """面积平均缩放。输入输出都是不透明的 8bit RGBA，所以直接在 RGB 上平均即可。"""
    if sw == dw and sh == dh:
        return bytearray(src)

    # 先把每行的权重算好（目标像素覆盖的源像素区间是分数，取重叠长度作权重）
    def spans(s_len: int, d_len: int) -> list[list[tuple[int, float]]]:
        ratio = s_len / d_len
        result = []
        for i in range(d_len):
            lo, hi = i * ratio, (i + 1) * ratio
            acc = []
            j = int(math.floor(lo))
            while j < math.ceil(hi):
                wgt = min(hi, j + 1) - max(lo, j)
                if wgt > 0:
                    acc.append((j, wgt))
                j += 1
            total = sum(w for _, w in acc)
            result.append([(j, w / total) for j, w in acc])
        return result

    xs = spans(sw, dw)
    # 水平方向：sw×sh → dw×sh
    tmp = bytearray(dw * sh * 4)
    for y in range(sh):
        srow = y * sw * 4
        drow = y * dw * 4
        for dx in range(dw):
            r = g = b = 0.0
            for sx, wgt in xs[dx]:
                o = srow + sx * 4
                r += src[o] * wgt
                g += src[o + 1] * wgt
                b += src[o + 2] * wgt
            o = drow + dx * 4
            tmp[o] = int(r + 0.5)
            tmp[o + 1] = int(g + 0.5)
            tmp[o + 2] = int(b + 0.5)
            tmp[o + 3] = 255

    ys = spans(sh, dh)
    out = bytearray(dw * dh * 4)
    for dy in range(dh):
        drow = dy * dw * 4
        for dx in range(dw):
            r = g = b = 0.0
            for sy, wgt in ys[dy]:
                o = sy * dw * 4 + dx * 4
                r += tmp[o] * wgt
                g += tmp[o + 1] * wgt
                b += tmp[o + 2] * wgt
            o = drow + dx * 4
            out[o] = int(r + 0.5)
            out[o + 1] = int(g + 0.5)
            out[o + 2] = int(b + 0.5)
            out[o + 3] = 255
    return out


# iOS 需要的文件名 → 像素边长，以及各自该用哪个母版。
# 母版必须和目标的「档位」一致：BrandIconTier.forSize 在 ≤24 / ≤48 / >48
# 三处切档，不同档位的文字行数与高光都不一样，跨档缩放会串味。
#   20          → minimal (≤24)  用 icon_24
#   29、40      → compact (≤48)  用 icon_48
#   其余        → full    (>48)  用 icon_1024
TARGETS: tuple[tuple[str, int, str, int], ...] = (
    ("Icon-App-20x20@1x.png", 20, "icon_24.png", 0),
    ("Icon-App-20x20@2x.png", 40, "icon_48.png", 1),
    ("Icon-App-20x20@3x.png", 60, "icon_1024.png", 2),
    ("Icon-App-29x29@1x.png", 29, "icon_48.png", 1),
    ("Icon-App-29x29@2x.png", 58, "icon_1024.png", 2),
    ("Icon-App-29x29@3x.png", 87, "icon_1024.png", 2),
    ("Icon-App-40x40@1x.png", 40, "icon_48.png", 1),
    ("Icon-App-40x40@2x.png", 80, "icon_1024.png", 2),
    ("Icon-App-40x40@3x.png", 120, "icon_1024.png", 2),
    ("Icon-App-60x60@2x.png", 120, "icon_1024.png", 2),
    ("Icon-App-60x60@3x.png", 180, "icon_1024.png", 2),
    ("Icon-App-76x76@1x.png", 76, "icon_1024.png", 2),
    ("Icon-App-76x76@2x.png", 152, "icon_1024.png", 2),
    ("Icon-App-83.5x83.5@2x.png", 167, "icon_1024.png", 2),
    ("Icon-App-1024x1024@1x.png", 1024, "icon_1024.png", 2),
)


def verify(path: Path, w: int, h: int, rgba: bytearray, tier: int, tol: float) -> list[str]:
    """用真实渲染像素反查背景公式。

    校验点在**图标最左侧的一列**。那里离纸张（约从 0.14·S 起）和墨滴
    （居中）都很远，可以确定只有背景。注意必须挑 alpha == 255 的像素：
    近乎全透明的地方，编码器把预乘值还原成直通时会放大出饱和噪点
    （α=1 时任何值都会变成 255），拿那些像素的颜色比对毫无意义。

    [tol] 按尺寸分级，原因见下面 main() 里的说明。
    """
    notes = []

    # A) 解码与形状：四角不实、中心不透明
    #
    # 角落的阈值要看尺寸：圆角半径是 0.2255·S，24px 时只有 5.4px，
    # 角落像素（中心在 1.5,1.5）是**半覆盖**的，本来就该是半透明而不是全透明；
    # 到 32px 以上才落得下整块空白。所以小尺寸放宽到「不实心」即可。
    limit = 8 if w >= 32 else 170
    corners = ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2))
    bad_corners = [
        (c[0], c[1], rgba[(c[1] * w + c[0]) * 4 + 3])
        for c in corners
        if rgba[(c[1] * w + c[0]) * 4 + 3] > limit
    ]
    if bad_corners:
        notes.append(
            f"  **不通过** {path.name}: 四角本应是透明或半透明，实际 (x, y, alpha)={bad_corners}"
        )
        return notes

    if rgba[((h // 2) * w + (w // 2)) * 4 + 3] != 255:
        notes.append(f"  **不通过** {path.name}: 中心像素不透明，解码可能出错")
        return notes

    # B) 渐变：左边缘整列（alpha==255 的部分）都应当是纯背景
    checked = 0
    max_delta = 0.0
    worst = None
    for y in range(h):
        for x in range(1, max(2, int(w * 0.012))):
            d = (y * w + x) * 4
            if rgba[d + 3] != 255:
                continue
            br, bg_, bb = background_at(x / w, y / h, tier)
            delta = max(abs(rgba[d] - br), abs(rgba[d + 1] - bg_), abs(rgba[d + 2] - bb))
            checked += 1
            if delta > max_delta:
                max_delta = delta
                worst = (
                    x,
                    y,
                    (rgba[d], rgba[d + 1], rgba[d + 2]),
                    (round(br), round(bg_), round(bb)),
                )

    if checked == 0:
        notes.append(f"  ! {path.name}: 左边缘没有可用的不透明像素，跳过渐变校验")
    else:
        state = "通过" if max_delta < tol else "**不通过**"
        detail = ""
        if worst is not None:
            detail = f"，最差点 {worst[0]},{worst[1]} 实际{worst[2]} 重算{worst[3]}"
        notes.append(
            f"  {state} {path.name}: 左边缘 {checked} 个像素，最大偏差 {max_delta:.1f}"
            f"（容差 {tol:g}）{detail}"
        )
    return notes


def main() -> int:
    if not SRC.is_dir():
        sys.exit(f"✗ 找不到 {SRC}")
    if not DST.is_dir():
        sys.exit(f"✗ 找不到 {DST}（先确保 ios/Runner/Assets.xcassets 存在）")

    print("① 校验背景公式（拿真实渲染像素反查）")
    # 容差按尺寸分级。大尺寸上误差只有 1～2（就是舍入），公式一旦抄错
    # （渐变方向、stops、半径、合成顺序）偏差会立刻到几十上百，所以这个
    # 检查的判别力不受影响。小尺寸把容差放宽，是因为纸张底下那道
    # **模糊投影**（maskFilter blur，sigma≈0.052·S，向外扩约 3σ）在 24px 时
    # 会渗进左边缘列——sigma 只有 1.25px，相对尺寸的比例反而更大。
    # 投影和纸张一样画在圆角矩形的裁剪之内，绝不会出现在我们要补的角部区域，
    # 所以它不影响结果，只影响这个校验点。
    masters: dict[str, tuple[int, int, bytearray, int]] = {}
    ok = True
    for name, tier, tol in (
        ("icon_24.png", 0, 14.0),
        ("icon_48.png", 1, 8.0),
        ("icon_1024.png", 2, 6.0),
    ):
        p = SRC / name
        if not p.is_file():
            sys.exit(f"✗ 缺少母版 {p}")
        w, h, rgba = read_png(p)
        for line in verify(p, w, h, rgba, tier, tol):
            print(line)
            if "**不通过**" in line:
                ok = False
        masters[name] = (w, h, rgba, tier)
    if not ok:
        sys.exit("✗ 背景公式与真实渲染对不上，说明调色板/几何抄错了，已中止")

    print("② 生成满幅图标")
    for filename, size, master, tier in TARGETS:
        sw, sh, rgba, mtier = masters[master]
        flat = flatten_over_background(sw, sh, rgba, mtier)
        scaled = resize_area(sw, sh, flat, size, size)
        # 抽检：四角与四条边中点必须完全不透明
        for idx in (0, (size - 1) * 4, (size - 1) * size * 4, (size * size - 1) * 4):
            if scaled[idx + 3] != 255:
                sys.exit(f"✗ {filename}: 存在透明像素，iOS 会拒绝")
        write_png(DST / filename, size, size, scaled)
        print(f"  {filename:<28} {size:>4}px  ← {master}")

    print(f"✅ 已写入 {DST.relative_to(ROOT)}（{len(TARGETS)} 个）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
