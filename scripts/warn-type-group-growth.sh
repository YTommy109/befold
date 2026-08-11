#!/usr/bin/env bash
set -uo pipefail

# 型グループの行数がベースラインを超えて増えたことを、コミット時点で「警告だけ」する。
#
# 段階を分ける理由(TASK-428.2): 作業の途中段階でコミットが止まると `--no-verify` を使う
# 圧力がかかり、フック自体が形骸化する。手元では気づけるだけにして、外に出る手前
# （CI, TASK-428.3）で確実に止める。
#
# したがってこのスクリプトは検知しても終了コードで落とさない。set -e を付けないのも同じ理由。

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-type-group-size.sh"

# 検知そのものが壊れた状態でグリーンになるのを防ぐため、毎回 self-test を通す。
if ! "$SCRIPT" --self-test > /dev/null 2>&1; then
  echo "警告: check-type-group-size.sh の self-test が失敗しています（判定が壊れている可能性）" >&2
fi

"$SCRIPT" --check > /dev/null || true

exit 0
