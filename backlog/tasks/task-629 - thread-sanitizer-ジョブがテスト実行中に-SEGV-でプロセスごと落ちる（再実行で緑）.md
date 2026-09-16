---
id: TASK-629
title: thread-sanitizer ジョブがテスト実行中に SEGV でプロセスごと落ちる（再実行で緑）
status: To Do
assignee: []
created_date: '2026-09-16 02:32'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 826000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
main push の CI（run 35046463664 / commit 4b8e2de7）で thread-sanitizer ジョブだけが落ちた。テストの失敗は 1 件も無く（✘ 0 件、総括行 `Test run with N tests` も出ない）、✔ 1083 件／全 2062 件を出したところでプロセスが死んでいる。多数の suite が in-flight のまま巻き添えで終了した。

クラッシュ署名:

```
✔ Suite GitCommandFileIndexTests passed after 22.863 seconds.
ThreadSanitizer:DEADLYSIGNAL
==12681==ERROR: ThreadSanitizer: SEGV on unknown address 0x30009cbb2000 (pc 0x000102fb01bc bp 0x00016d77d070 sp 0x00016d77d060 T44873)
==12681==The signal is caused by a READ memory access.
```

TSan 自身がバックトレースを出し切る前に死んでおり、スタックが 1 フレームも残っていない。**この署名のまま再発しても原因を追えないのが、いま最大の障害。** スレッド ID が T44873（テスト実行 23 秒で約 4.5 万スレッド生成）なのは、TSan 下での libdispatch スレッド爆発を疑う手がかりになる（このリポジトリは BlockingWorkTests / BlockingGateTests / FileWatcherSlowOpenTests のように意図的にキューを塞ぐテストを持つ）。ただし未確認の仮説であり、TSan 内部の資源枯渇か実コードの use-after-free かも切り分けられていない。

再現性の実測:
- ローカル `swift test --sanitize=thread` を同一コミットで 2 回 → どちらも exit 0（2402 件パス）
- CI の同ジョブを再実行 → success（run 全体も completed success）
- 直近の main push / nightly 7 回はすべて success

過去の nightly 失敗 2 件（34708873857 / 33327874435）はクラッシュではなく期待値不一致・予算切れで、別物。全件パス直後のクラッシュという点では TASK-515（signal 6 / unowned 逆参照）が近いが、あちらは signal 6 でスタックも取れており署名が違うため同型の 2 件目とは数えていない。TASK-515 の申し送りにある「同じ unowned 逆参照が ViewerScriptDispatcher / BridgeMessageRouter / DirectHTMLModeController / PageZoomProjector / ViewerWindowSessionSync に残っている」は、原因候補として参照する価値がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 再発時にクラッシュ地点が特定できる（TSAN_OPTIONS 等で TSan にスタックを出させる、またはクラッシュレポートを artifact として保全する設定が CI に入っている）
- [ ] #2 TSan 実行中のスレッド生成数が実測され、スレッド爆発が原因かどうかが肯定または否定されている
- [ ] #3 原因が特定できた場合は修正し、swift test --sanitize=thread を複数回まわして再発しないことを実測している
- [ ] #4 原因が特定できない場合は、何が観測できれば着手できるかを Notes に明記して閉じている
<!-- AC:END -->
