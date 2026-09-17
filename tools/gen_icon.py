# -*- coding: utf-8 -*-
"""生成 1024x1024 的 App 图标（纯 Python，无第三方依赖）。

用法: python gen_icon.py <输出路径>
默认输出到本文件同级的 AppIcon.png。
"""
import sys
import struct
import zlib

W = 1024
SS = 2          # 2x 超采样做简单抗锯齿
WW = W * SS

# 三角形顶点（归一化坐标，顺时针）
AX, AY = 0.34, 0.28
BX, BY = 0.34, 0.72
CX, CY = 0.72, 0.50


def main(out_path: str) -> None:
    big = []
    for y in range(WW):
        t = y / WW
        br = int(8 + 118 * t)
        bg = int(128 + 66 * t)
        bb = int(252 - 28 * t)
        row = bytearray()
        for x in range(WW):
            px = x / WW
            py = y / WW
            d1 = (px - BX) * (AY - BY) - (AX - BX) * (py - BY)
            d2 = (px - CX) * (BY - CY) - (BX - CX) * (py - CY)
            d3 = (px - AX) * (CY - AY) - (CX - AX) * (py - AY)
            has_neg = d1 < 0 or d2 < 0 or d3 < 0
            has_pos = d1 > 0 or d2 > 0 or d3 > 0
            if has_neg and has_pos:
                row += bytes((br, bg, bb))   # 背景（蓝色渐变）
            else:
                row += b"\xff\xff\xff"       # 白色播放三角
        big.append(row)

    rows = []
    for y in range(W):
        row = bytearray()
        top = big[y * 2]
        bottom = big[y * 2 + 1]
        for x in range(W):
            i = x * 2 * 3
            r = top[i] + top[i + 3] + bottom[i] + bottom[i + 3]
            g = top[i + 1] + top[i + 4] + bottom[i + 1] + bottom[i + 4]
            b = top[i + 2] + top[i + 5] + bottom[i + 2] + bottom[i + 5]
            row += bytes((r // 4, g // 4, b // 4))
        rows.append(b"\x00" + bytes(row))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, W, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")

    with open(out_path, "wb") as f:
        f.write(png)
    print("OK:", out_path, len(png), "bytes")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
    main(out)
