#!/usr/bin/env bash
# BefoldApp/AppIcon/icon.svg から AppIcon.icns を生成する。
#
# **手作業で書き出さないこと。** 以前の AppIcon.icns は SVG の透明な角が白地へ
# 合成された状態で入っており（全ピクセル α=255、四隅が純白）、macOS 26 未満の Dock で
# 四隅が白く見えていた（TASK-582）。macOS 26 は旧来のアイコンを角丸へ自動マスクする
# ため、手元の環境では気づけない。再発を防ぐにはこのスクリプトを通す。
#
# 依存: rsvg-convert（`nix profile install nixpkgs#librsvg` 等）と iconutil（macOS 標準）。
# rsvg-convert は SVG の透明部分をそのまま RGBA の α=0 として書き出す。
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
SVG="$ROOT/BefoldApp/AppIcon/icon.svg"
OUT="$ROOT/BefoldApp/befold/Resources/AppIcon.icns"

command -v rsvg-convert >/dev/null || {
    echo "rsvg-convert が必要です（例: nix profile install nixpkgs#librsvg）" >&2
    exit 1
}
[ -f "$SVG" ] || { echo "元データが見つかりません: $SVG" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"

# iconutil が要求する 10 種類。名前は固定で、1 つでも欠けると icns にならない。
render() {
    local px=$1 name=$2
    rsvg-convert --width "$px" --height "$px" --background-color=none \
        --output "$SET/$name" "$SVG"
}
render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

# 透過が保たれているかをここで落とす。書き出し系はオプション 1 つで無音に
# 白マットへ倒れるので、生成の直後に検査してから icns へ固める。
python3 "$ROOT/scripts/check-icon-alpha.py" "$SET"

iconutil --convert icns --output "$OUT" "$SET"
echo "生成しました: $OUT"
