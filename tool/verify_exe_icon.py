"""校验 exe 里内嵌的图标确实是我们生成的「墨阅」图标（改完即可删除）。

判据：Flutter 默认的 app_icon.ico 只含 16/32/48/256 四个尺寸；我们生成的是
16/24/32/48/64/128/256 七个。rc.exe 会把 .ico 拆成 RT_ICON 资源写入 exe，
每个资源的开头就是一段 BITMAPINFOHEADER——只要能在 exe 里找到 24×24 与
128×128 的头部，就说明嵌进去的是我们这份，而不是模板默认图标。
"""
import struct
from pathlib import Path

EXE = Path("build/windows/x64/runner/Release/MoRead.exe")
EXE_BAK = Path("build/windows/x64/runner/Release/data/app.so")  # 仅用于对比体积
SIZES = [16, 24, 32, 48, 64, 128, 256]

blob = EXE.read_bytes()
print(f"exe 体积: {len(blob):,} 字节")

found = []
for s in SIZES:
    # biSize, biWidth, biHeight(=2×，因为 DIB 里 XOR+AND 是一张图), planes, bitCount, compression
    head = struct.pack("<IiiHHI", 40, s, s * 2, 1, 32, 0)
    hit = blob.find(head)
    found.append((s, hit))
    print(f"  {s:>3}×{s:<3} BITMAPINFOHEADER {'命中 @0x%X' % hit if hit >= 0 else '未找到'}")

ok = all(h >= 0 for _, h in found)
missing = [s for s, h in found if h < 0]
print()
if ok:
    print("✅ exe 内嵌图标含全部 7 个尺寸 —— 包含模板默认图标没有的 24/64/128，确认是我们的图标")
else:
    print(f"❌ 缺少尺寸: {missing}")
    raise SystemExit(1)
