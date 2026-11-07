---
id: TASK-907
title: CI の build-and-test (default) がテスト実行中に固まり、30 分のタイムアウトで打ち切られる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T04:18:00Z'
updated_date: '2026-11-07T05:44:00Z'
labels:
  - test
  - bug
  - ci
  - test-infra
dependencies: []
references:
  - TASK-675
  - https://github.com/YTommy109/befold/actions/runs/42333763789
  - https://github.com/YTommy109/befold/pull/756
priority: medium
type: bug
ordinal: 873000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI が通常 6〜8 分のジョブで 30 分待たされ、失敗の情報も残らない。再実行すれば通るので、原因が分からないまま再実行で済ませる運用になりやすい。

観測（1 回のみ）: PR #756 の run 42333763789（attempt 1）、build-and-test (default)。Swift のテストは 03:28:34 に始まり、失敗 0 件のまま 03:29:34 を最後に出力が止まり、03:53 に timeout-minutes: 30 で打ち切られた。この時点で未完了は 20 スイート、最後の出力の直前には約 60 秒で終わったテストが続いていた（CI の BEFOLD_TEST_TIMEOUT_SECONDS は 60）。未完了には ViewerRendererRenderRaceTests、ViewerCanvasPixelTests、ViewerStoreFileGoneTests、ViewerWindowControllerDiffTests などがある。同じコミットの strict は成功し、再実行（attempt 2）は 6 分半で成功した。同じ変更を含む PR #757 も両方成功したので、PR #756 の変更が原因とは考えにくいが断定はできない。

未特定: どのテストが何を待って止まったか。今回のログにはプロセスの状態が無く、未完了のテストは並列実行のため大量に出る。TASK-675（TSan + CPU 負荷で実 WKWebView の didFinish が来ない）と同じ原因の可能性はあるが、未確認。あちらは負荷をかけた条件で、今回は通常の CI ジョブ。

手元での再現は flaky-test-investigator サブエージェントが使える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 固まった回に、どのテストが何を待っているかを後から確認できる情報が CI に残る
- [ ] #2 実際に固まった回の情報で原因が特定され、TASK-675 と同じか別かが Notes に記録されている
- [ ] #3 直せる原因なら直し、複数回の全体実行で再発しないことを実測している。直せないなら根拠と回避策が記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. scripts/test-watchdog.sh を追加する: コマンドを実行し、出力が一定時間止まったら sample（テスト本体・WebContent）、未完了テスト、ps を保存してからプロセスを止め、終了コード 124 で失敗する
2. --self-test を足し、CI で実行する（CI の実行条件にも追加）
3. CI のテスト実行をこのスクリプト経由にし、診断結果を artifact へ、メインスレッドのスタックをログへ出す
4. メインスレッドを塞ぐテストで、手元と CI の両方で診断が取れることを確認する（確認用のコミットは残さない）
5. 完了条件 2・3 は実際に固まった回の情報が要る。手元での再現を試み、再現しなければ着手条件を Notes に残す

設計の根拠: 未完了 108 件に待つものの無い軽いテストが含まれるので、メインスレッドまたはメインアクターが止まっている形。所要時間が 60 秒で揃っていたのは経過時間と同じなだけで、BEFOLD_TEST_TIMEOUT_SECONDS とは無関係（成功した回は全体で 90 秒）。発生は直近 200 回の CI で数回。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測 1（手元で再現）: test-watchdog を通した全体実行で 2 回ハングを捉えた。どちらも本体のスレッド 145 本のうち 130 本が PDFKit の解析で止まっていた（-[PDFView visiblePagesChanged:] → PDFPageAnalyzerV2 → VNImageRequestHandler が 66〜74 本、VNRequest performInContext の semaphore_wait が 64 本）。Dispatch Thread Soft Limit: 64 に全サンプルで到達。実 WKWebView の面は loadFileURL のあと didFinish が 0 件で、abortedRenderDoesNotLeaveOptionsInJS が isReady を待ち続け、loadOneShot は #diagram-wrap が null で失敗した。

実測 2（因果）: 成功した回の途中の sample では解析スレッドは 0〜6 本で、弁別材料になる（TASK-673 の NSAnimation と違う）。ワーカーを塞ぐ一時テスト: 0 本で 0.10 秒、30 本で 0.10 秒、80 本で 39.7 秒（塞いだスレッドの 40 秒後に解放と一致）。

実測 3（A/B、空のユーザーキャッシュ CFFIXED_USER_HOME）: 全テスト 5/6 でハング、PDF を除く 0/3、PDF だけ 0/3。修正後の CI と同じ 3 プロセス構成: 0/6（1963 + 103 + 83 件すべて成功）。

外れた仮説（記録）: 60 秒の揃いは BEFOLD_TEST_TIMEOUT_SECONDS と無関係（所要時間 ≒ 経過時間）。メインスレッドの停止ではない（ランループは回っている）。リビルド直後も打ち切り直後も再現しない（各 3/3 で成功）。

CI のログの限界: swift test の出力はパイプだとブロックバッファになり、止まると末尾が失われる。CI で見えた「未完了 108 件」は実際より多い。元の CI の回に sample は無いので、同じ原因という判断は、未完了に同じテストがあること・実 WebView の待ちであること・CI のランナーがキャッシュの無い環境であることからの推定。

CI での確認（一時コミットでメインスレッドを塞いだ run 42343123345）: 300 秒で打ち切り、ログにメインスレッドのスタック、artifact に診断が残ることを default / strict とも確認。一時コミットは取り除いた。self-test は macOS 専用なので build-and-test へ置いた（Linux の type-group-size では落ちた）。

TASK-675 との関係: 同じ原因と考える。TSan ジョブも同じ分離にした。TSan + 負荷での再発なしは未測定なので、TASK-675 は閉じていない。

native-app-design.md への反映は不要（CI とテストの構成のみ）。
<!-- SECTION:NOTES:END -->
