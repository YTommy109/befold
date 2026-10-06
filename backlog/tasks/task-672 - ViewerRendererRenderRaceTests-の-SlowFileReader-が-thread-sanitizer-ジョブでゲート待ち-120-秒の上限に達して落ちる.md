---
id: TASK-672
title: >-
  ViewerRendererRenderRaceTests の SlowFileReader が thread-sanitizer ジョブでゲート待ち
  120 秒の上限に達して落ちる
status: To Do
assignee: []
created_date: '2026-10-06 02:54'
updated_date: '2026-10-06 04:47'
labels:
  - bug
  - test
dependencies: []
references:
  - TASK-665
  - TASK-629
priority: medium
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-10-06、main push（PR #713 のマージコミット 0807c484）の CI run 37401520728 で thread-sanitizer ジョブだけが落ちた。`ViewerRendererRenderRaceTests.swift:251` で「SlowFileReader.readData: 同期待機が 120.0 秒で上限に達した（解放されないまま協調スレッドを塞いでいる）」が 1 件記録された（テスト名は «unknown» で、SlowFileReader を使う 3 テストのどれかは特定できていない）。プロセスは死んでおらず、総括行「Test run with 1997 tests in 329 suites failed ... with 1 issue」が出ている。DEADLYSIGNAL / SEGV は 0 件で、TASK-629（SEGV でプロセスごと落ちる）とは別の障害。同系統は TASK-665（並列時のゲート待ち上限超過。別テストで async の境界へ移して解消済み）。同じ run では全体が 363 秒かかり、多くのテストが 360 秒前後で完了しており、TSan 下の極端な混雑だった。同じ run の build-and-test（default / strict）は pass で、PR #713 は Swift に触れていない。未確認: 原因が混雑だけか（ゲートが塞ぐ協調スレッドが待ち先の進行を止めていないか）、再現率、TSan でしか出ないのか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 落ちたテストがどれかと、上限超過の条件（混雑だけか、塞いだ協調スレッドが待ち先の進行を止めているか）を実測で特定している
- [ ] #2 ゲートの上限を延ばす形ではなく、待ちの構造（TASK-665 と同じく async の境界へ移す等）で直っている
- [ ] #3 swift test --sanitize=thread を同一ツリーで複数回まわし、当該テストが再発しないことを実測している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
測定（2026-10-06、手元 10 コア。全実験 BEFOLD_TEST_TIMEOUT_SECONDS=120 + --sanitize=thread。ログは .tmp/ の t672-* と t672b-*、リポジトリには含まれない）:
- 無負荷: スイート単体 0/20、全体（--skip befoldCLITests）0/3（123〜132 秒）。CI は 363 秒かかっており、混雑の再現ができていなかった。
- 協調プール幅 1（LIBDISPATCH_COOPERATIVE_POOL_STRICT=1）: スイート単体 0/10、全体 0/3。TASK-665 と同じく「協調スレッドが塞がれている」説は支持されない。
- CPU 負荷（yes 20 本）: 全体 0/1（229 秒）。1 回なので「出ない」とは言えない。
- CPU 負荷（yes 40 本）: 全体 3/3 で何らかの失敗。内訳は (1) ThreadSanitizer の SEGV（libsystem_malloc。166 秒で落ち、総括行なし。TASK-629 の署名に近いが別物かは未調査）、(2) ViewerRendererOneShotIntegrationTests の WKWebView エラー（別の失敗）、(3) TASK-672 の issue そのもの（ViewerRendererRenderRaceTests.swift:251、「同期待機が 120.0 秒で上限に達した」、Test «unknown»、462.993 秒、プロセス生存、スイート自体は pass）。
- 結論（実測）: 再現は 3 回中 1 回（C40-3）。全体が 400 秒前後まで伸びる混雑と結びつく。CI の 363 秒に近い条件。
- 未確認（推定）: 終了後の再描画が同じフェイクをもう一度呼び、誰も解放しない待機が上限に達した形（BlockingGate の doc にある TASK-427 の型）に見える。根拠は «unknown» への帰属とスイート自体が pass していること。確かめるには diffStateIsNotConfirmedBeforeRender 等でゲートを開く前にテストが抜ける経路を読み、ゲートを開く直前の主キュー遅延を測る。
- 未確認: 負荷 40 本は CI（コア数の少ないランナー）と構造が同じとは限らない。再現率を比べるなら同じ負荷で 10 回程度の追加が要る。CI のコア数と並列度は未確認（gh run view 37401520728 --log で見られる）。
- 着手の手がかり: AC#1 のうち「落ちたテストの特定」は未達（«unknown» のまま）。「協調スレッドが塞がれているか」は否定できた。
<!-- SECTION:NOTES:END -->
