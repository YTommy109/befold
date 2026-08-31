#!/usr/bin/env python3
"""iconset の各 PNG で、角丸の外側が透明のままかを検査する。

以前の AppIcon.icns は全ピクセル α=255 で四隅が純白だった（TASK-582）。
アルファ「チャンネル」は RGBA として存在していたので、色形式を見るだけでは
気づけない。**実際の α 値**を見る必要がある。

PIL には依存しない（この環境に入っていないため）。8bit RGBA・非インターレースの
PNG だけを対象にした最小のデコーダを持つ。iconutil へ渡す前段の検査なので、
入力は自分たちで書き出した PNG に限られる。
"""
import glob
import os
import struct
import sys
import zlib


def decode_rgba(path):
    """8bit RGBA / 非インターレースの PNG を (幅, 高さ, bytearray) で返す。"""
    data = open(path, "rb").read()
    pos, idat, width, height = 8, b"", None, None
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if (depth, colour, interlace) != (8, 6, 0):
                raise SystemExit(f"{path}: 8bit RGBA・非インターレースではない: {(depth, colour, interlace)}")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
        pos += 12 + length

    raw = zlib.decompress(idat)
    bpp, stride = 4, width * 4
    out, prev, i = bytearray(height * stride), bytearray(stride), 0
    for y in range(height):
        filter_type = raw[i]
        i += 1
        line = bytearray(raw[i : i + stride])
        i += stride
        for x in range(stride):
            left = line[x - bpp] if x >= bpp else 0
            up = prev[x]
            upleft = prev[x - bpp] if x >= bpp else 0
            if filter_type == 1:
                line[x] = (line[x] + left) & 255
            elif filter_type == 2:
                line[x] = (line[x] + up) & 255
            elif filter_type == 3:
                line[x] = (line[x] + ((left + up) >> 1)) & 255
            elif filter_type == 4:
                estimate = left + up - upleft
                da, db, dc = abs(estimate - left), abs(estimate - up), abs(estimate - upleft)
                nearest = left if (da <= db and da <= dc) else (up if db <= dc else upleft)
                line[x] = (line[x] + nearest) & 255
        out[y * stride : (y + 1) * stride] = line
        prev = line
    return width, height, out


def check(path):
    """1 枚を検査する。問題があれば説明の文字列を返し、無ければ None。"""
    width, height, pixels = decode_rgba(path)

    def alpha(x, y):
        return pixels[(y * width + x) * 4 + 3]

    corners = {
        "左上": alpha(0, 0),
        "右上": alpha(width - 1, 0),
        "左下": alpha(0, height - 1),
        "右下": alpha(width - 1, height - 1),
    }
    opaque = {name: value for name, value in corners.items() if value != 0}
    if opaque:
        return f"四隅が透明でない: {opaque}（角丸の外側は α=0 であるべき）"

    # 16px では角丸が 3px 程度しかないため、割合の下限は緩く取る。
    transparent = sum(1 for a in pixels[3::4] if a == 0)
    ratio = transparent * 100.0 / (width * height)
    if ratio < 1.0:
        return f"透明なピクセルが {ratio:.1f}% しかない（角丸の外側が潰れている疑い）"
    return None


def main():
    if len(sys.argv) != 2:
        raise SystemExit("使い方: check-icon-alpha.py <iconset ディレクトリ>")
    target = sys.argv[1]
    files = sorted(glob.glob(os.path.join(target, "*.png")))
    if not files:
        raise SystemExit(f"PNG が見つかりません: {target}")

    failures = []
    for path in files:
        problem = check(path)
        name = os.path.basename(path)
        if problem:
            failures.append(f"  {name}: {problem}")
            print(f"NG {name}: {problem}")
        else:
            print(f"OK {name}")
    if failures:
        raise SystemExit("アイコンの透過が失われています:\n" + "\n".join(failures))
    print(f"透過の検査を通過しました（{len(files)} 枚）")


if __name__ == "__main__":
    main()
