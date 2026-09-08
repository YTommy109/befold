#!/usr/bin/env bash
set -euo pipefail

# BefoldKit(コアロジック層)がプラットフォーム依存のモジュールを import しないことを
# 確認する(TASK-594)。
#
# なぜ機械で止めるか:
# BefoldKit は本体アプリ・QuickLook 拡張・CLI が共有するコア層で、AppKit / SwiftUI /
# WebKit が存在しない環境へ持っていける唯一の部分になりうる。依存は 1 つ入るたびに
# 外すコストが上がる(TASK-594 の時点で AppKit 依存は 47 ファイル中 1 ファイルだった)。
# 「気をつける」では守れないので、import の一覧そのものを固定する。
#
# なぜ denylist ではなく allowlist か:
# 「AppKit / Cocoa / WebKit / SwiftUI が無いこと」を見る形だと、名前を挙げていない
# プラットフォーム依存(Carbon・CoreGraphics・UIKit・Quartz など)が素通りする。
# 実際 TASK-594 の着手時、AppKit を外しても PDFKit が残っていた(TASK-598 で除去)。
# 許可する側を列挙すれば、新しい依存は必ずこのファイルの編集(= 明示的な判断)を伴う。
#
# 検査するのは BefoldKit だけ。上の層(befold / BefoldCLI / BefoldRenderKit)と、
# PDFKit を隔離するための BefoldPDFProbe は対象外で、それが意図した設計である
# (プラットフォーム依存はそちらへ寄せる)。
#
# grep で検索する(rg は GitHub Actions の ubuntu ランナーに入っていない。
# scripts/check-no-detached-blocking.sh が同じ理由で grep を使っている)。

ROOT="$(git rev-parse --show-toplevel)"

# BefoldKit が import してよいモジュール。
# どちらもプラットフォーム非依存(swift-corelibs 側にも実装がある)。
#
# ここへ足すのは最後の手段。PDF の判定(PDFKit)は TASK-598 で BefoldPDFProbe へ
# 隔離し、BefoldKit へは `@Sendable (Data) -> Bool` として注入する形にした。
# 同じ形が使えないか先に検討すること。
ALLOWED_MODULES=(
  Foundation
  CryptoKit
)

# import 行からモジュール名(最初の "." より前)を取り出す。
# `@testable import Foo` / `@_exported import Foo` / `import class AppKit.NSEvent` の
# いずれの形でも AppKit を拾えるようにする(修飾つき import を見落とすと、
# 「1 つの型だけ借りる」形で依存が静かに戻る)。
extract_modules() {
  local target="$1"
  grep -rhE --include='*.swift' --exclude-dir='.build' \
    '^[[:space:]]*(@[_a-zA-Z]+[[:space:]]+)*import[[:space:]]' "$target" 2>/dev/null \
    | sed -E 's/^[[:space:]]*(@[_a-zA-Z]+[[:space:]]+)*import[[:space:]]+//' \
    | sed -E 's/^(typealias|struct|class|enum|protocol|func|var|let)[[:space:]]+//' \
    | sed -E 's/[[:space:]]*(\/\/.*)?$//' \
    | cut -d. -f1 \
    | grep -v '^$' \
    | sort -u
}

# 許可一覧に無いモジュールだけを返す。
find_violations() {
  local target="$1"
  local module
  while IFS= read -r module; do
    local allowed=0
    local permitted
    for permitted in "${ALLOWED_MODULES[@]}"; do
      if [[ "$module" == "$permitted" ]]; then
        allowed=1
        break
      fi
    done
    if [[ $allowed -eq 0 ]]; then
      echo "$module"
    fi
  done < <(extract_modules "$target")
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # 1. 素の import を検知できるか。
  printf 'import AppKit\n' > "$tmp/Plain.swift"
  if [[ "$(find_violations "$tmp")" != "AppKit" ]]; then
    echo "self-test 失敗: 素の 'import AppKit' を検知できていない" >&2
    exit 1
  fi

  # 2. 修飾つき import を検知できるか(型 1 つだけ借りる形で依存が戻る経路)。
  rm "$tmp/Plain.swift"
  printf 'import class AppKit.NSEvent\n' > "$tmp/Qualified.swift"
  if [[ "$(find_violations "$tmp")" != "AppKit" ]]; then
    echo "self-test 失敗: 'import class AppKit.NSEvent' を検知できていない" >&2
    exit 1
  fi

  # 3. 許可されたモジュールで誤検知しないか。
  rm "$tmp/Qualified.swift"
  printf 'import Foundation\n@testable import CryptoKit\n' > "$tmp/Allowed.swift"
  if [[ -n "$(find_violations "$tmp")" ]]; then
    echo "self-test 失敗: 許可モジュールを違反として報告している" >&2
    exit 1
  fi

  echo "self-test OK: 素の import・修飾つき import を検知し、許可モジュールでは鳴らない"
  exit 0
fi

TARGET="$ROOT/BefoldApp/BefoldKit"
violations="$(find_violations "$TARGET")"

if [[ -n "$violations" ]]; then
  echo "BefoldKit はプラットフォーム非依存のコア層です。許可されていない import があります:" >&2
  while IFS= read -r module; do
    echo "  $module" >&2
    grep -rnE --include='*.swift' --exclude-dir='.build' \
      "^[[:space:]]*(@[_a-zA-Z]+[[:space:]]+)*import[[:space:]]+([a-zA-Z]+[[:space:]]+)?${module}\b" \
      "$TARGET" >&2 || true
  done <<< "$violations"
  echo "" >&2
  echo "AppKit / SwiftUI / WebKit などが要る処理は BefoldRenderKit か befold へ置いてください" >&2
  echo "(前例: BefoldApp/BefoldRenderKit/OpenDisposition+NSEvent.swift)。" >&2
  echo "本当に BefoldKit へ必要な依存なら scripts/check-befoldkit-platform-free.sh の" >&2
  echo "ALLOWED_MODULES へ理由つきで追記してください。" >&2
  exit 1
fi

echo "OK: BefoldKit の import は許可一覧のみ"
