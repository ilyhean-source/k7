#!/usr/bin/env python3
"""Render Kindle EPDC framebuffer dumps (documents/k7diag/fb_*.raw) to PNG
so the address-bar region can be inspected visually, plus a row-darkness
profile of the bottom of the screen (where the Kindle address bar lives).

Assumptions (from /sys/class/graphics/fb0): 8bpp grayscale, stride 608,
visible area = top 600x800 of a 608x5376 buffer. If the layout differs the
profile numbers will look wrong and the script can be adapted.
"""
import os
import struct
import sys
import zlib

DIR = r"C:/Users/skgx2/WorkBuddy/2026-10-24-19-46-58/k7/db/fb"
STRIDE = 608
VIS_W, VIS_H = 600, 800


def write_png(path, w, h, pixels):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(pixels[y * w:(y + 1) * w]) for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def analyze(path):
    with open(path, "rb") as f:
        data = f.read()
    name = os.path.basename(path)
    n = len(data)
    full_h = n // STRIDE
    h = min(VIS_H, full_h)
    w = min(VIS_W, STRIDE)
    px = bytearray(w * h)
    for y in range(h):
        row = data[y * STRIDE:y * STRIDE + w]
        px[y * w:(y + 1) * w] = row
    out = os.path.join(os.path.dirname(path), name.replace(".raw", ".png"))
    write_png(out, w, h, px)

    # row darkness profile (mean of inverted intensity) for the last 120 rows
    prof = []
    for y in range(h - 120, h):
        row = px[y * w:(y + 1) * w]
        dark = sum(255 - b for b in row) / len(row)
        prof.append((y, round(dark, 1)))
    print(f"{name}: {n} bytes -> {w}x{h}, png={out}")
    # summary of the address-bar band (bottom 60 px)
    band = [d for _, d in prof[60:120]]
    print(f"   bottom-60px mean darkness: {sum(band)/len(band):.1f}  min={min(band)} max={max(band)}")
    return out


if __name__ == "__main__":
    targets = sys.argv[1:]
    if not targets:
        os.makedirs(DIR, exist_ok=True)
        targets = [os.path.join(DIR, f) for f in sorted(os.listdir(DIR)) if f.endswith(".raw")]
    for t in targets:
        analyze(t)
