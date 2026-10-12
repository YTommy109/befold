#!/usr/bin/env bash
set -euo pipefail

# 本体アプリ(befold)と BefoldRenderKit が BefoldCLI / ArgumentParser に依存しないことを
# 確認する(TASK-698)。
#
# なぜ機械で止めるか:
# 本体が CLI 実装と ArgumentParser を抱えると、本体の変更が CLI のビルドを巻き込み、
# 共有すべき型(CLIRequest など)の置き場が BefoldCLI に引っ張られる。共有型は
# BefoldKit、CLIInstaller は本体に置くのが現在の構造で、依存方向は
# befold-cli → BefoldCLI → BefoldKit の一方向。「気をつける」では戻るので、次の 3 点を固定する。
#   (a) befold / BefoldRenderKit の *.swift に import BefoldCLI / ArgumentParser が無い
#   (b) BefoldApp/Package.swift の befold ターゲットの dependencies に BefoldCLI / ArgumentParser が無い
#   (c) BefoldApp/project.yml の befold(application)ブロックに target: BefoldCLI が無い
#
# grep / awk で検索する(rg は GitHub Actions の ubuntu ランナーに入っていない)。

ROOT="$(git rev-parse --show-toplevel)"
FORBIDDEN='(BefoldCLI|ArgumentParser)'

# (a) `@testable import X` / `import class X.Y` の形も拾う。
find_import_violations() {
  grep -rnE --include='*.swift' --exclude-dir='.build' \
    "^[[:space:]]*(@[_a-zA-Z]+[[:space:]]+)*import[[:space:]]+([a-z]+[[:space:]]+)?${FORBIDDEN}\b" \
    "$@" 2>/dev/null || true
}

# (b) Package.swift から name: "befold", のターゲットブロックだけを切り出し、コメント行を除く。
package_block() {
  awk '
    /\.(executableTarget|target|testTarget|plugin|binaryTarget|systemLibrary)\(/ { in_block = 0 }
    /name:[[:space:]]*"befold",/ { in_block = 1 }
    in_block && $0 !~ /^[[:space:]]*\/\// { print }
  ' "$1"
}

# (c) project.yml のトップレベル targets 直下 `  befold:` のうち type: application のブロック。
yml_app_block() {
  awk '
    function flush() { if (buf ~ /type:[[:space:]]*application/) printf "%s", buf; buf = "" }
    /^  [^ #]/ { flush(); in_block = ($0 ~ /^  befold:[[:space:]]*$/) }
    /^[^ #]/ { flush(); in_block = 0 }
    in_block && $0 !~ /^[[:space:]]*#/ { buf = buf $0 "\n" }
    END { flush() }
  ' "$1"
}

find_manifest_violations() {
  local pkg="$1" yml="$2"
  package_block "$pkg" | grep -E "\"${FORBIDDEN}\"|package:[[:space:]]*\"swift-argument-parser\"" \
    | sed 's/^/Package.swift: /' || true
  yml_app_block "$yml" | grep -E "target:[[:space:]]*BefoldCLI\b|package:[[:space:]]*ArgumentParser\b" \
    | sed 's/^/project.yml: /' || true
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  fail() { echo "self-test 失敗: $1" >&2; exit 1; }

  # (a) 違反: 素の import / @testable / 修飾つき。許可: 無関係な import とコメント。
  for line in 'import BefoldCLI' '@testable import BefoldCLI' 'import ArgumentParser' 'import struct BefoldCLI.CLIRequest'; do
    printf '%s\n' "$line" > "$tmp/V.swift"
    [[ -n "$(find_import_violations "$tmp")" ]] || fail "'$line' を検知できていない"
  done
  printf 'import Foundation\nimport BefoldKit\n// import BefoldCLI\nimport BefoldCLIFoo\n' > "$tmp/V.swift"
  [[ -z "$(find_import_violations "$tmp")" ]] || fail "許可ケースの import で鳴っている"

  # (b)(c) 違反ケース。befold 以外のブロックにある BefoldCLI は許可。
  cat > "$tmp/bad-Package.swift" <<'EOP'
        .target(name: "BefoldCLI", dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "befold",
            dependencies: [
                "BefoldKit",
                "BefoldCLI",
            ]
        ),
        .executableTarget(
            name: "befold-cli",
            dependencies: ["BefoldCLI"]
        ),
EOP
  cat > "$tmp/bad-project.yml" <<'EOP'
schemes:
  befold:
    build:
      targets:
        befold: all
targets:
  befold:
    type: application
    dependencies:
      - target: BefoldKit
      - target: BefoldCLI
  befold-cli:
    type: tool
    dependencies:
      - target: BefoldCLI
EOP
  cat > "$tmp/ok-Package.swift" <<'EOP'
        .executableTarget(
            name: "befold",
            dependencies: [
                "BefoldKit",
                // BefoldCLI には依存しない
            ]
        ),
        .executableTarget(
            name: "befold-cli",
            dependencies: ["BefoldCLI"]
        ),
EOP
  cat > "$tmp/ok-project.yml" <<'EOP'
schemes:
  befold:
    build:
      targets:
        befold: all
targets:
  befold:
    type: application
    dependencies:
      - target: BefoldKit
  befold-cli:
    type: tool
    dependencies:
      - target: BefoldCLI
EOP
  out="$(find_manifest_violations "$tmp/bad-Package.swift" "$tmp/bad-project.yml")"
  grep -q '^Package.swift:' <<< "$out" || fail "Package.swift の BefoldCLI 依存を検知できていない"
  grep -q '^project.yml:' <<< "$out" || fail "project.yml の BefoldCLI 依存を検知できていない"
  [[ -z "$(find_manifest_violations "$tmp/ok-Package.swift" "$tmp/ok-project.yml")" ]] \
    || fail "許可ケース(befold-cli や他ブロックの BefoldCLI)で鳴っている"

  echo "self-test OK: import・Package.swift・project.yml の違反を検知し、許可ケースでは鳴らない"
  exit 0
fi

violations="$(find_import_violations "$ROOT/BefoldApp/befold" "$ROOT/BefoldApp/BefoldRenderKit")"
manifest="$(find_manifest_violations "$ROOT/BefoldApp/Package.swift" "$ROOT/BefoldApp/project.yml")"

if [[ -n "$violations$manifest" ]]; then
  echo "本体アプリ(befold)と BefoldRenderKit は BefoldCLI / ArgumentParser に依存しません:" >&2
  [[ -z "$violations" ]] || printf '%s\n' "$violations" >&2
  [[ -z "$manifest" ]] || printf '%s\n' "$manifest" >&2
  echo "" >&2
  echo "本体と CLI が共有する型は BefoldKit へ置いてください(前例: CLIRequest / CLIOpenOptions)。" >&2
  echo "CLIInstaller は本体側の実装です。ArgumentParser への適合は BefoldCLI 側に残します。" >&2
  exit 1
fi

echo "OK: 本体と BefoldRenderKit は BefoldCLI / ArgumentParser に依存していない"
