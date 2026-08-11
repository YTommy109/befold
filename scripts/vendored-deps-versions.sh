#!/usr/bin/env bash
# 同梱している JS/CSS ライブラリの版を 1 箇所で出力し、記録とのずれを検出する。
#
# 棚卸し手順（.claude/commands/check-vendored-deps.md /
# .claude/agents/vendored-deps-auditor.md）はこのスクリプトを呼ぶ。
#
# TASK-432.5 でベンダーは npm 依存になった。版の正は
# BefoldApp/package.json の devDependencies と、実際に入っている node_modules で、
# 同梱ファイルからバナーや内部リテラルを grep して版を推定する必要はもう無い
# （その推定は TASK-433 で 6 件中 5 件のパスが壊れていた）。実体は Node 側の
# BefoldApp/scripts/check-third-party-licenses.mjs にあり、ここは入口。
#
# 出力: "<Component>\t<版>\t<ライセンス>\t<同梱のしかた>" のタブ区切り。
# 記録（THIRD_PARTY_LICENSES.md / package.json）と食い違う場合は非ゼロで終了する。
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

if [[ ! -d BefoldApp/node_modules ]]; then
  printf 'ERROR: BefoldApp/node_modules が無い。先に `cd BefoldApp && npm ci` を実行する\n' >&2
  exit 1
fi

exec node BefoldApp/scripts/check-third-party-licenses.mjs
