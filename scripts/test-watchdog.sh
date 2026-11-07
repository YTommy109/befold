#!/usr/bin/env bash
# コマンドの出力が一定時間止まったら、止まった時点の状態を保存してからプロセスを止める。
# テストのハングは再現が稀で、CI のタイムアウトで打ち切られると何を待っていたかが残らない
# （TASK-907。同型の TASK-424 / TASK-607 / TASK-673 でも止まった時点の情報が無かった）。
#
# 使い方: scripts/test-watchdog.sh [--quiet-seconds N] --diagnostics DIR -- コマンド...
#   --quiet-seconds : 出力が止まったと見なす秒数（既定 300）
#   --diagnostics   : 診断の保存先。止まったときだけ作る
#   --self-test     : 検知が働くことを確認する（CI 用）
# 終了コード: コマンドの終了コード。止まって打ち切ったときは 124。
#
# 保存するもの: output.log / unfinished-tests.txt（始まったが終わっていないテスト）/
# ps.txt / sample-<名前>-<pid>.txt（コマンドの子孫と WebKit のプロセス）。
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 2; }

HUNG_EXIT=124
SAMPLE_SECONDS=5
MAX_SAMPLED_PROCESSES=12

QUIET_SECONDS=300
DIAGNOSTICS=""
SELF_TEST=false
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet-seconds) QUIET_SECONDS="${2:?--quiet-seconds に秒数が要ります}"; shift 2 ;;
    --diagnostics) DIAGNOSTICS="${2:?--diagnostics に保存先が要ります}"; shift 2 ;;
    --self-test) SELF_TEST=true; shift ;;
    --) shift; break ;;
    *) err "不明な引数: '$1'（--quiet-seconds | --diagnostics | --self-test | -- コマンド）" ;;
  esac
done

POLL_SECONDS=1

descendants() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null || true); do
    echo "$child"
    descendants "$child"
  done
}

# Swift Testing の出力から、始まったが終わっていないテストを出す。パラメータ付きテストの
# ケースごとの行（Test case passing ...）と全体の行（Test run ...）は数えない。
unfinished_tests() {
  perl -ne '
    s/\e\[[0-9;]*[A-Za-z]//g;
    next if /Test case passing/ || /Test run /;
    if (/ Test (.+?) started\.\s*$/) { $started{$1} = $.; }
    elsif (/ Test (.+?)(?: with \d+ test cases?)? (?:passed|failed) /) { delete $started{$1}; }
    END { print "$_\n" for sort { $started{$a} <=> $started{$b} } keys %started; }
  ' "$1"
}

# コマンドの子孫と WebKit の補助プロセスを、同時刻の状態になるよう並行に sample する。
# WebContent は launchd の子なので親子関係では辿れない（TASK-673 で必要だった情報）。
capture_diagnostics() {
  local root="$1" log="$2" pids pid name
  mkdir -p "$DIAGNOSTICS"
  ps -axo pid,ppid,stat,etime,%cpu,rss,command > "$DIAGNOSTICS/ps.txt"
  unfinished_tests "$log" > "$DIAGNOSTICS/unfinished-tests.txt"
  # WebKit は新しい順にする。手元では Safari などの古いプロセスが上限を埋めてしまう。
  pids="$(descendants "$root"; pgrep -U "$(id -u)" -f 'com\.apple\.WebKit\.' 2>/dev/null | sort -rn || true)"
  # pipefail の下で head にパイプを閉じさせない（SIGPIPE でスクリプトごと落ちる。実測）。
  for pid in $(printf '%s\n' "$pids" | awk -v max="$MAX_SAMPLED_PROCESSES" 'NR <= max'); do
    name="$(basename "$(ps -o comm= -p "$pid" 2>/dev/null || echo unknown)")"
    sample "$pid" "$SAMPLE_SECONDS" -file "$DIAGNOSTICS/sample-$name-$pid.txt" >/dev/null 2>&1 &
  done
  wait_for_samples
  cp "$log" "$DIAGNOSTICS/output.log"
}

# 本体のコマンドと tail を待たないよう、sample の分だけを待つ。
wait_for_samples() {
  local job
  for job in $(jobs -p); do
    [ "$job" = "$COMMAND_PID" ] || [ "$job" = "$TAIL_PID" ] || wait "$job" 2>/dev/null || true
  done
}

terminate_tree() {
  local root="$1" pids
  pids="$(descendants "$root")"
  # shellcheck disable=SC2086 # pid の並びを別々の引数として渡す
  kill -TERM "$root" $pids 2>/dev/null || true
  sleep 2
  # shellcheck disable=SC2086
  kill -KILL "$root" $pids 2>/dev/null || true
}

# テスト本体のメインスレッドのスタックを、artifact を開かずに読めるようログへ出す。
report_hang() {
  local file
  echo "::error::出力が ${QUIET_SECONDS} 秒止まったので打ち切りました（TASK-907）。診断: $DIAGNOSTICS"
  echo "--- 未完了のテスト: $(wc -l < "$DIAGNOSTICS/unfinished-tests.txt" | tr -d ' ') 件（先頭 40 件）"
  head -n 40 "$DIAGNOSTICS/unfinished-tests.txt"
  for file in "$DIAGNOSTICS"/sample-swiftpm-testing-helper-*.txt "$DIAGNOSTICS"/sample-xctest-*.txt; do
    [ -f "$file" ] || continue
    echo "--- メインスレッド（$(basename "$file")）"
    sed -n '/^Call graph:/,/^$/p' "$file" | awk 'NR == 1 || /^ +[0-9]+ Thread_/ { n++ } n <= 2 && ++shown <= 120'
  done
}

run_with_watchdog() {
  local log last_size=-1 size quiet=0 status=0
  log="$(mktemp)"
  # 擬似端末を通す。swift test は出力先がファイルやパイプだとブロックバッファになり、
  # 止まったときに最後の数 KB が失われて、未完了のテストが分からなくなる（実測）。
  # macOS の script は子の終了コードをそのまま返す。
  script -q -F /dev/null "$@" > "$log" 2>&1 < /dev/null &
  COMMAND_PID=$!
  tail -n +1 -f "$log" &
  TAIL_PID=$!
  trap 'terminate_tree "$COMMAND_PID"; kill "$TAIL_PID" 2>/dev/null || true; rm -f "$log"' TERM INT

  while kill -0 "$COMMAND_PID" 2>/dev/null; do
    sleep "$POLL_SECONDS"
    size="$(wc -c < "$log")"
    if [ "$size" = "$last_size" ]; then
      quiet=$((quiet + POLL_SECONDS))
    else
      quiet=0
      last_size="$size"
    fi
    if [ "$quiet" -ge "$QUIET_SECONDS" ]; then
      capture_diagnostics "$COMMAND_PID" "$log"
      terminate_tree "$COMMAND_PID"
      wait "$COMMAND_PID" 2>/dev/null || true
      kill "$TAIL_PID" 2>/dev/null || true
      wait "$TAIL_PID" 2>/dev/null || true
      report_hang
      rm -f "$log"
      trap - TERM INT
      return "$HUNG_EXIT"
    fi
  done

  wait "$COMMAND_PID" || status=$?
  sleep 1 # tail が最後の出力を流し切るのを待つ
  kill "$TAIL_PID" 2>/dev/null || true
  wait "$TAIL_PID" 2>/dev/null || true
  rm -f "$log"
  trap - TERM INT
  return "$status"
}

run_self_test() {
  local self tmp fail=0 status
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT

  # (a) 止まったら 124 で打ち切り、未完了のテストだけを残し、子孫を止める
  cat > "$tmp/hang.sh" <<'EOF'
echo '◇ Test "done" started.'
echo '✔ Test "done" passed after 0.1 seconds.'
echo '◇ Test "param" started.'
echo '◇ Test case passing 1 argument x → 1 to "param"'
echo '✔ Test "param" with 2 test cases passed after 0.1 seconds.'
echo '◇ Test "stuck" started.'
sleep 317
EOF
  status=0
  bash "$self" --quiet-seconds 2 --diagnostics "$tmp/hung" -- bash "$tmp/hang.sh" > "$tmp/hung.out" 2>&1 || status=$?
  [ "$status" -eq "$HUNG_EXIT" ] || { echo "self-test 失敗: 止まったのに終了コードが $status" >&2; fail=1; }
  [ "$(cat "$tmp/hung/unfinished-tests.txt" 2>/dev/null)" = '"stuck"' ] \
    || { echo "self-test 失敗: 未完了のテストが '\"stuck\"' だけになっていない" >&2; fail=1; }
  [ -s "$tmp/hung/ps.txt" ] || { echo "self-test 失敗: ps.txt が無い" >&2; fail=1; }
  grep -q 'Test "stuck" started' "$tmp/hung/output.log" 2>/dev/null \
    || { echo "self-test 失敗: output.log に出力が残っていない" >&2; fail=1; }
  grep -q '::error::' "$tmp/hung.out" || { echo "self-test 失敗: ログに打ち切りの理由が出ない" >&2; fail=1; }
  if pgrep -f 'sleep 317' >/dev/null 2>&1; then
    echo "self-test 失敗: 打ち切ったコマンドの子孫が残っている" >&2
    pkill -f 'sleep 317' || true
    fail=1
  fi

  # (b) 出力が続く間は、閾値より長く動いても打ち切らない
  status=0
  bash "$self" --quiet-seconds 2 --diagnostics "$tmp/busy" -- \
    bash -c 'for i in 1 2 3 4 5; do echo "$i"; sleep 1; done' > "$tmp/busy.out" 2>&1 || status=$?
  [ "$status" -eq 0 ] || { echo "self-test 失敗: 出力が続くのに終了コードが $status" >&2; fail=1; }
  [ ! -e "$tmp/busy" ] || { echo "self-test 失敗: 止まっていないのに診断を作った" >&2; fail=1; }
  [ "$(grep -c . "$tmp/busy.out")" -eq 5 ] || { echo "self-test 失敗: 出力が欠けている" >&2; fail=1; }

  # (c) コマンドの終了コードをそのまま返す
  status=0
  bash "$self" --diagnostics "$tmp/fail" -- bash -c 'exit 7' > /dev/null 2>&1 || status=$?
  [ "$status" -eq 7 ] || { echo "self-test 失敗: 終了コード 7 が $status になった" >&2; fail=1; }

  [ "$fail" -eq 0 ] && echo "self-test OK: 止まれば診断を残して打ち切り、動いている間と終了コードには干渉しない"
  return "$fail"
}

if $SELF_TEST; then run_self_test; exit; fi

[ -n "$DIAGNOSTICS" ] || err "--diagnostics が必要です"
[ $# -gt 0 ] || err "実行するコマンドがありません（-- の後に書きます）"
run_with_watchdog "$@"
