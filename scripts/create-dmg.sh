#!/bin/bash
# リリース用 DMG を作成する。release.yml(本番)と verify-dmg.yml(検証)の両方から呼ぶことで、
# create-dmg のオプションを 1 箇所に保つ。
# 使い方: create-dmg.sh <app-path> <output-dmg>
set -euo pipefail

app_path=$1
output_dmg=$2

create-dmg \
  --volname "mmdview" \
  --window-size 600 400 \
  --icon "mmdview.app" 150 200 \
  --app-drop-link 450 200 \
  "$output_dmg" \
  "$app_path"
