---
id: TASK-673
title: >-
  ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS
  が thread-sanitizer + 高負荷で 600 秒の time limit まで終わらないことがある
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-06 06:00'
updated_date: '2026-10-07 00:50'
labels:
  - bug
  - test
dependencies: []
references:
  - TASK-672
priority: medium
ordinal: 858000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-672 の修正後の検証（2026-10-06、TSan + CPU 負荷 yes 40 本 + 全体実行 6 回、ログは .tmp/t672c-C40-3.log）で、6 回中 1 回（run3）、このテストだけが `Time limit was exceeded: 600.000 seconds` で落ちた（754 秒）。他のテストは約 445 秒で pass しており、単なる全体の混雑では説明できない。「SlowFileReader.readData の同期待機が」issue は出ていない。実 WKWebView を使い、waitForWebViewLoad（isReady / entered / rendered.contentRevision の 3 つの待ち）と evaluateJavaScript を持つ唯一の SlowFileReader 利用テスト。修正前の負荷実行（3 回）ではこの失敗は出ていないが標本が小さく、TASK-672 の修正（SlowFileReader の上限なし化）由来か、元からある別の flaky かは判定できていない。修正前の負荷実行では同じ型の WKWebView 系の別の失敗（ViewerRendererOneShotIntegrationTests、`document.getElementById(diagram-wrap)` が null）も 1 回出ている。未確認: どの await で止まったか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 このテストが止まる await が特定されている（診断ログで 3 回中 3 回とも waitForWebViewLoad の最初の待ち isReady）
- [x] #2 TASK-672 の上限なし化が原因かが判定されている（止まる位置が SlowFileReader のゲートを作る前なので、原因ではない）
- [ ] #3 isReady が 600 秒以上来ない原因が特定され、同じ負荷・複数回の全体実行で再発しないことを実測している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-674 / 674.1 との関係（2026-10-06）: (1) 674 の実測で、開け忘れは「結果を待つテストが .timeLimit まで終わらない」形で出る。本タスクの症状（600 秒で time limit、754 秒）と一致するため、原因は WKWebView の待ちでなくゲートが開かれないまま上限なしで待ち続けた可能性がある（推定、未確認）。上限付きの時代は 120 秒で issue になっていたはずの状態が、TASK-672 の上限なし化で「終わらない」に変わった、という仮説。(2) TASK-674.1 の検査（塞いではいけないスレッドでの待機）は withBlockingWork の専用 Thread 上では発火しないため、この状態は検査で捕まらない。(3) ADR 0012「再検討する条件」は『開け忘れによる終わらない run が CI で起きたら自己解放を足す』。本件は手元の TSan + 負荷での観測で CI ではないが、条件を前倒しで判断する材料になる。(4) AC#2 の比較対象を『TASK-672 の修正を含まないツリー』から『674.1 を含むツリーと上限付きだった修正前』へ更新した。

実測 1（2026-10-06、TASK-674.1 を含むツリー。手元 10 コア、TSan、yes 40 本、BEFOLD_TEST_TIMEOUT_SECONDS=120。ログは .tmp/t673/、リポジトリには含まれない）: テストに一時的な診断ログ（待ちごとのラベル。コミットしない）を入れて回した。
- スイート単体 + 負荷 40 本: 0/40（1 回 16〜18 秒）。全体実行（--skip befoldCLITests）+ 負荷 40 本: 2/8 で同じ失敗を再現（run3 1114 秒、run7 1162 秒。どちらも「Time limit was exceeded: 600 seconds」）。単体では出ず、全体実行の混雑の中でだけ出る。
- 止まった待ちは 2 回とも最初の await、つまり waitForWebViewLoad の isReady（実 WKWebView の viewer.html ロード完了待ち）。その後の 2 回目の描画・ゲート・evaluateJavaScript には到達していない（isReady が解放されたあとで js1 / js2 の診断が出る順）。成功した 6 回でも isReady は 30 秒を超えて待っている。
- 結論（実測）: 『TASK-672 の上限なし化で、ゲートが開かれないまま待ち続けた』という仮説は否定。止まった時点では SlowFileReader のゲートはまだ作られていない。AC#2 の『修正前との比較』は、このテストが止まる場所がゲートの手前なので前提ごと外れる。
- 関連（コード・文書参照）: TASK-607 が同じ型（isReady が来ない）を扱い、真因は『Task.sleep 系ではメインランループが回らず実 WKWebView のロードが前進しない。並列実行では他のテストの Task.yield がたまたまランループを回すので、通るか来ないかの二極になる』だった。本テストの waitForWebViewLoad も同じ前提（yield スピンがランループを回す）に依存している。他のテストが終わった後（約 445 秒以降）も 650 秒以上来なかったので、単なる混雑ではなく『ロードが前進しない状態』の疑い。
- 未確認: なぜ前進しないか（WebContent プロセスの状態、didFinish が来ない/ナビゲーションの失敗、メインランループが回らない）。次は BEFOLD_RENDER_DIAGNOSTICS=1（TASK-607 の診断）と、650 秒止まった時点の sample / WebContent プロセス一覧で切り分ける。

実測 2（2026-10-06、診断ログと sample。ログは .tmp/t673/、リポジトリには含まれない。診断コードは revert 済み）:
- 追加の全体実行 + 負荷 40 本: 再現は通算 3 件目（G40 run7）。run7 は isReady で止まったまま alarm 1500 秒で打ち切られた。止まった待ちは 3 件とも最初の await の isReady（AC#1 達成）。AC#2: ゲートは isReady の後に作るので、TASK-672 の上限なし化は原因ではない（達成）。
- 再現率（実測）: 全体実行で 3/22 前後（最初の 8 回で 2、二重実行で捨てた 8 回を除く次の 8 回で 0、次の 10 回で 1）。標本ごとにばらつく。スイート単体 + 負荷 40 本では 0/40。
- 650 秒止まった時点の sample（run7）: メインスレッドは CFRunLoop を回している（1001 サンプル中 734 が mach_msg 待ち、107 が主キューの処理）。つまり『ランループが回らずロードが進まない』（TASK-607 の型）ではない。
- 同じ sample で、libdispatch のワーカースレッド 53 本が -[NSAnimation _runBlocking] の入れ子ランループに入ったまま残り、『Dispatch Thread Soft Limit: 64 reached in 998 of 1001 samples』と出ている。ただし**成功した回でも同じ**だった: 通常の全体実行で 5 秒時点から 54 本（開始 5〜360 秒で増減なし、soft limit の警告も毎回出る）。したがって 54 本は止まった回の弁別材料ではない。常に上限 64 の近くで動いていて、残りは約 10 本という背景条件にすぎず、これが止まる原因だとは言えない（未確認）。
- 発生源（未確認）: この NSAnimation スレッドを残すテスト・処理がどれかは特定できていない。全テストがほぼ同時に始まるため、時系列では絞れなかった。
- 結論: 『止まる場所』は特定、『止まる理由』は未特定。AC#3 は未達。
- 同じ実行で出た別の失敗（本タスクとは別。起票はしていない）: ViewerRendererOneShotIntegrationTests の『loadOneShot は描画完了まで待ってから返る』が WKWebView の JavaScript 例外で 2 回（G40 run2 / run7。TASK-672 の Notes にある修正前の同じ型の失敗と同一）、SidebarNavigatorGitStatusTests の『取得結果の .git/index を監視し…』が 1 回（E40 run4）、TSan の SEGV（libsystem_malloc。TASK-629 の型）が 1 回（E40 run8）。
- 次の手（案。着手はユーザーの指示待ち）: (a) 止まった時点の WKWebView 側を見る（BEFOLD_RENDER_DIAGNOSTICS=1 の出力が G40 run7 のログにある。TASK-607 の診断の分岐のどこで止まったかを読む）、(b) NSAnimation スレッドの発生源を、PDF 系・ウィンドウ表示系のスイートを単独で回して sample で数えて絞る、(c) 3/22 の再現率では検証に 1 件あたり 1 時間以上かかるため、isReady に上限と診断ダンプを付けて『止まったことを即座に失敗として記録する』形（TASK-607 と同じ型）にする。

実測 3（2026-10-06、ユーザーの提案: yes の代わりに taskpolicy で負荷をかける）:
- taskpolicy -b（バックグラウンド）+ 全体実行 1 回: 1151 秒で終了し、59 テストが .timeLimit（600 秒）で落ちた。全体が極端に遅くなるだけで『1 テストだけが isReady で止まる』形ではない。再現条件としては強すぎる。
- taskpolicy -c utility + 全体実行 4 回: 129〜142 秒（無負荷の 123〜132 秒と同等）、.timeLimit 0 件、失敗 0 件。混雑にならない。
- 結論（実測）: taskpolicy は『効かない』か『全体が崩れる』の二択で、yes N 本のように強度を刻めない（クランプは utility / background / maintenance の 3 段のみ）。再現率を調整できる負荷は yes N 本のまま（40 本で 3/22 前後）。マシン全体を使い切る点は残る。taskpolicy を負荷の置き換えにはしない。
- 止まった回（G40 run7）の診断ログの読み（実測）: loadFileURL は 7 面で呼ばれたが didFinish は 0 件（成功した回は 2 件）。遮断ポリシー完了（WKContentRuleList のコンパイル）に 120〜141 秒かかった面が 3 つあり、その後 loadFileURL に進んでいるが、以後 1300 秒以上 didFinish が来ない。didFail / webContentProcessDidTerminate も無い。つまり『ロードは始まったが完了通知が一度も来ない』。同じ run の ViewerRendererOneShotIntegrationTests が WKWebView の JavaScript 例外で落ちているのも、ページが未ロードのまま JS を評価した形として説明がつく（推定）。
- 未確認: 完了通知が来ない理由（WebContent プロセスの起動・応答、dispatch ワーカースレッドの上限 64 の逼迫との関係）。次に必要なのは、止まった時点でテストプロセスの子の WebContent を sample すること。再現が 3/22 前後なので、1 件の検証に 1 時間以上かかる。

実測 4（2026-10-07。NSAnimation スレッドの漏れの除去と、その効果の検証。コミット 9a184df9）:
- 発生源を特定（実測）: 全体実行の開始 5 秒時点で libdispatch のワーカースレッド 54 本が -[NSAnimation _runBlocking] で塞がれたまま残り（全体 145 スレッド前後、『Dispatch Thread Soft Limit: 64 reached』）、ViewerSplitViewController.toggleSidebar の super.toggleSidebar（AppKit のアニメーション付き開閉）を、画面に出ていない窓で呼ぶと 1 回ごとに 1 本残る。toggleSidebar をアニメーションなしにすると 54 本 → 0 本、全体 約 20〜30 スレッド、警告も消えた。
- 対処（コミット 9a184df9）: 画面に出ていない窓ではアニメーションなしで確定させる（ViewerSplitViewController.shouldAnimateSidebarToggle(in:)）。窓が無い・出ている場合は従来どおり。回帰テスト ViewerSplitViewControllerAnimationTests を追加（判定を『常に true』に戻すと落ちることを確認）。無負荷の全体実行は 2002 件 pass。
- 重要（実測）: この対処は TASK-673 の停止を直さなかった。停止の率: 修正前は有効な全体実行 + 負荷 40 本で 4/34（F40 2/8、E40 0/7、G40 1/10、H40 1/9）、修正後は 1/22（V40 run1〜10 で 0/10、最終コードの F4 run1〜12 で 1/12）。F4 run10 で TASK-673 と同じ症状（対象テストが 600 秒の time limit、678 秒で終了）が、NSAnimation スレッドの漏れを除去した状態で出た。差は有意でない（標本が小さい）。したがって『スレッド上限の逼迫が isReady の来ない原因』という仮説は裏づけられなかった。
- 追加の事実（F4 run10 の診断ログ、実測）: 対象テストの面は loadFileURL が開始 70 秒、didFinish が開始 670 秒で、ロード完了まで約 10 分かかっている。他のテストは約 428 秒で全部終わっており、そこから約 4 分、ロードだけが残った。同じ run の別の面は loadFileURL から didFinish まで 80 秒。成功した回でも didFinish は実行の最後（他のテストが終わるころ）に届く。止まった回（H40 run8、G40 run7）では、メインスレッドはランループを回しており、テストが起動した WebContent と Networking は mach_msg で完全にアイドルだった（UI 側・WebContent 側のどちらも何もしていない）。
- 未確認の候補（いずれも仮説）: (1) 画面に出ていない WKWebView の WebContent が OS に低優先度として扱われ、CPU 負荷 40 本の下で数分〜永久に走らせてもらえない、(2) UI プロセスと WebContent の間の通知が、特定のタイミングで届かないまま両側がアイドルになる（止まった回の観測と整合）。(1) は CPU 負荷の強さに依存するはずで、taskpolicy（弱い設定では混雑にならず、強い設定では全体が崩れる）と整合する。いずれも本タスクの範囲では裏づけを取れていない。
- 実験の注意（私の運用ミス、記録）: 実験の実行中に別のビルド・テスト・変異テストを走らせたため、V40 run11/12 と F2 の 7 回は無効（二重実行・並走。ログに 945 秒の時刻の飛び、止め忘れた swift test が 1 時間以上並走）。有効なのは V40 run1〜10 と F4 の 12 回。計測中は、ビルド・テストを一切走らせず、止め忘れを pgrep で確認すること。
- AC#3 は未達（原因の特定と再発しないことの実測）。状態は In Progress のまま。選択肢（ユーザー判断）: (a) 実 WKWebView のロード完了待ちを持つテストを、TASK-607 と同じく実 WebView 依存を外して Swift 側の状態で測る形へ変える（このテストは JS 側の _mmdViewOptions を直接読むので、外せるかの検討が要る）、(b) isReady に上限と診断ダンプを付けて、止まったことを即座に失敗として記録する（原因は残る）、(c) 本件を『負荷下で実 WKWebView のロードが数分遅れる既知の flaky』として記録して止め、原因探索は別タスクに切り出す。
<!-- SECTION:NOTES:END -->
