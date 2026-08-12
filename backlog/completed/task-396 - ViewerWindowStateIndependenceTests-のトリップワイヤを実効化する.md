---
id: TASK-396
title: ViewerWindowStateIndependenceTests のトリップワイヤを実効化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-09 13:34'
updated_date: '2026-08-10 00:34'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 650000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の CONFIRMED 指摘 2 件。BefoldApp/befoldTests/ViewerWindowStateIndependenceTests.swift のテストが、コメント・表示名で謳っている回帰を実際には検知しない。

1. **restoresStoredStateWhenReopening（131 行付近）**: 表示名と doc コメントは「ライブ値は窓と共に死ぬ」「提示開始は保存値を読む」の両方を検証すると謳うが、実際には窓を 1 回開くだけで close→reopen を行わない。閉じた窓のライブ zoom/scroll が次の窓へ漏れる回帰（controller や store のキャッシュ再利用など）が起きてもこのスイートは通る。

2. **keepsLiveZoomWhenStoredZoomChanges（87 行付近）**: トリップワイヤコメントは「ViewerContentView へ ZoomStore を渡す形に戻すと、ここが落ちる」と主張するが、アサーションは `store.zoom == 1.25` のみ。ZoomStore を body で読む形へ戻しても（まさに TASK-388 の回帰経路）store.zoom は 1.25 のままでテストは通る。keepsLiveScrollPositionWhenStoredPositionChanges（111 行付近）にも同じ穴がある。

ADR 0002 と CLAUDE.md の「決めたことには、破れたら落ちるものを付ける」の担保がこのテストの存在意義なので、実際に落ちる形へ直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 close→reopen を実際に実行し、閉じた窓のライブ値が再オープン後の窓へ漏れると落ちるテストがある
- [x] #2 ViewerContentView が ZoomStore/ScrollPositionStore を body で読む形へ戻ると落ちるテストがある（store のプロパティだけでなく描画へ渡る値を検証する）
- [x] #3 トリップワイヤコメントの主張とテストが実際に検知する範囲が一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. restoresStoredStateWhenReopening を close→reopen の実行へ書き換える。開いた窓のライブ zoom/scroll を保存値と異なる値へ動かし（保存はされない経路）、close→openViewer した新しい窓が保存値から始まることを検証する。ライブ値が漏れると落ちる。
2. ViewerContentView が ZoomStore/ScrollPositionStore を body で読む形へ戻ると落ちるトリップワイヤを追加する。SwiftUI の body は実行時に値を取り出せないため、FeatureGateEnumerationTests と同じソース走査方式で ViewerContentView.swift の非コメント行に ZoomStore / ScrollPositionStore / perFileState の参照が無いことを固定する。
3. keepsLiveZoom / keepsLiveScrollPosition のトリップワイヤコメントを、実際に検知する範囲（beginPresentingDocument の呼び直し）だけを主張する形へ直し、ZoomStore を渡す形の検知は 2 のテストへ委ねる旨を書く。
4. swift test で該当スイートを実行し、さらに各トリップワイヤを一時的に破って落ちることを実測で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

1. restoresStoredStateWhenReopening を実際の close→reopen へ書き換えた。1 窓目のライブ値を保存値と別の値（zoom 2.0 / scroll 0.9、保存値は 1.5 / 0.4）へ動かしてから close し、再オープンした窓が 1.5 / 0.4 から始まることを検証する。倍率・位置の永続化はレンダラ通知経路でしか起きないため、直接代入は保存値を汚さない（ViewerWindowController.swift:566/575 と windowWillClose を確認済み）。
2. ViewerContentViewStoreIsolationTests.swift を新設した。SwiftUI の body は opaque で組み立てた View から実引数を取り出せないため、FeatureGateEnumerationTests と同じソース走査方式で、ViewerContentView.swift の非コメント行が ZoomStore / ScrollPositionStore / PerFileStateStore / perFileState を参照しないことを固定する。空振り防止に「initialZoom: store.zoom」「scrollPositionToRestore: store.scrollPositionToRestore」の存在も併せて検査する。
3. keepsLiveZoom / keepsLiveScrollPosition のトリップワイヤコメントから、実際には検知しない「ViewerContentView へ ZoomStore を渡す形に戻すと落ちる」という主張を外し、そちらは新スイートが担保する旨へ書き換えた。

## 実測（変異テスト）

- 変異 A（TASK-388 の回帰そのもの）: ViewerContentView に let zoomStore: ZoomStore を足し initialZoom を zoomStore 経由へ戻す。
  - ViewerContentViewStoreIsolationTests → 2 件とも失敗（期待どおり検知）
  - ViewerWindowStateIndependenceTests → 6 件すべて成功（起票時の指摘 2 のとおり、旧スイートでは検知できないことを実測で確認）
- 変異 B（閉じた窓のライブ倍率が漏れる）: windowWillClose で store.zoom を static へ退避し、beginPresentingDocument でそれを優先する。
  - restoresStoredStateWhenReopening → 「reopened.store.zoom → 2.0 == 1.5」で失敗（漏れを検知）

## 検証

- swift test: 1243 tests / 183 suites すべて成功
- swiftlint（プラグイン同梱バイナリ）: 変更した 2 ファイルに指摘なし
- swiftformat: 差分なし
- 変異は両方とも git checkout で復元済み（git status で本文コードに差分が無いことを確認）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowStateIndependenceTests の 2 つのトリップワイヤを、コメントの主張どおり実際に落ちる形へ直した。(1) 再オープンのテストは close→reopen を実行し、閉じた窓のライブ倍率・位置が次の窓へ漏れると落ちる。(2) ViewerContentView が保存ストアを読む回帰は body が opaque で実行時に検証できないため、ソース走査のトリップワイヤ ViewerContentViewStoreIsolationTests を新設した。(3) 検知できない主張をコメントから外した。回帰を実際に注入する変異テストで両方が落ちること、および旧スイートでは (2) の回帰が検知できないことを実測で確認した。swift test 1243 件成功、swiftlint 指摘なし。
<!-- SECTION:FINAL_SUMMARY:END -->
