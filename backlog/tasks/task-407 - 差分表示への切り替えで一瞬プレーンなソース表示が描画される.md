---
id: TASK-407
title: 差分表示への切り替えで一瞬プレーンなソース表示が描画される
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 05:59'
updated_date: '2026-08-14 23:42'
labels:
  - bug
milestone: m-5
dependencies: []
priority: medium
type: bug
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
表示モードを差分表示 (.diff) に切り替えると、いったん差分なしのソースコード表示が描画されてから差分付きの表示に変わる。

原因（実測・コード参照）:
- `ViewerWindowController.setDisplayMode` (App/ViewerWindowController.swift:736) が `applyDisplayMode` で同期に `store.displayMode = .diff` を立てる (:787)。この時点で `store.diffText` は nil なので `ViewerContentView` (Viewer/ViewerContentView.swift:29) が渡す `diffState` は `.none`。
- `isSourceMode` が false→true に変わるため `ViewerRenderer` が「差分なしのソース表示」で全文描画する (BefoldRenderKit/ViewerRenderer+ContentUpdate.swift:212-226)。これが一瞬見えるプレーンなソース。
- その後 `refreshDiff()` (:761) が `GitDiffLoader.diff` を非同期に呼び、`store.diffText` 着地で 2 度目の全文再描画が走る (App/ViewerWindowController+Diff.swift:35-43)。

構造的な理由:
- `GitDiffLoader` は結果をキャッシュしない方針（App/GitDiffLoader.swift:3-8 の doc）で、切替時に即使える同期値が存在しない。
- 取得は `Task.detached` でサブプロセス `git` を起こすため (GitDiffLoader.swift:97)、`@MainActor` から同期に待てない。
- したがって `applyDisplayMode` と `refreshDiff` の呼び出し順を入れ替えても解消しない。

再現条件: `.rendered → .diff` の遷移でのみ発生する。`.source → .diff` は `isSourceMode` も `diffState` も変わらず 1 段目の再描画が `incoming != rendered` で弾かれる (ContentUpdate.swift:214) ため発生しない。

方針の候補（着手時に `/review-design` で確定する）:
(a) `ViewerRenderer.DiffState` (ViewerRenderer+ContentUpdate.swift:54-63) に未確定を表す状態を足し、diff 未着の間は 1 段目の描画を見送って前の表示を残す
(b) ViewerWebView 側で `store.diffText == nil && showsDiff` の間だけレンダリングを遅らせる（判定が View 層に散る）
(c) `GitDiffLoader` に短命キャッシュを持たせる（非キャッシュ方針に反するため非推奨）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `.rendered` から差分表示へ切り替えたとき、差分なしのプレーンなソース表示が中間状態として描画されない
- [x] #2 `.source` から差分表示への切り替えなど既存の遷移で余計な再描画が増えていない
- [x] #3 差分の取得に失敗した場合・差分が空の場合の表示が退行していない
- [x] #4 中間状態を描画しないことがユニットテストで担保されている（描画ミラーの遷移列を検証する形）
- [x] #5 着手前に `/review-design` を 1 回実行し、結果を Implementation Plan に反映している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
方針 (a) を現構造（#483 再編後）に写して実装する。Description の file:line は再編前のもので、実装点は ViewerDocumentPresenter / ViewerDiffPresenter / ContentUpdatePlanner に移っている（Explore 裏取り済み。因果の前提 6 件はすべて現在も成立）。

1. ViewerStore.diffText: String? を 3 状態 enum ViewerDiffContent（unavailable / pending / diff(String)）へ置き換える。「未着」と「確定差分なし」を型で区別する（現状はどちらも nil で不可分。AC #3 の要）。書き手 4 箇所を移行: openFile → .unavailable、applyDisplayMode（差分から離れる）→ .unavailable、ViewerDiffPresenter.refresh() の guard → .unavailable、着地 → .diff(text) または .unavailable
2. pending を立てるのは ViewerDiffPresenter.refresh() が取得を実際に登録した時点のみ（同期）。ただし現在値が .diff のときは降格しない（差分表示中のファイル変更再取得では従来どおり古い差分を出したまま待つ。新たな中間状態を作らない = AC #2）
3. BefoldRenderKit の DiffState（RenderValues.swift の struct）に isPending を追加し、static let pending を用意。生成は memberwise init では isPending を受けず、pending は static 経由のみ（text あり + pending の不正状態を作れなくする）。既定値 .none は据え置き（QuickLook の OneShotRenderer は DiffState 不参照で影響ゼロ・裏取り済み）
4. ContentUpdatePlanner.plan に skip 規則を追加: incoming.diffState.isPending かつ「isSourceMode / diffState 以外のフィールドが rendered と一致」なら .skip（前の表示を残す）。コンテンツ識別が異なる場合（初回描画・ファイル切替・内容更新）は従来どおり描画に進む（空白画面や旧ファイル残留を防ぐ）
5. ViewerContentView の diffState 導出を enum の写像へ: pending → .pending、unavailable → .none、diff(text) → DiffState(text:layout:)
6. テスト: (a) ContentUpdatePlannerTests を新設（直接テストは現状ゼロ）— pending+コンテンツ一致 → .skip、pending+filePath/revision 相違 → .render、pending+空ミラー → .render、既存フロー不変。(b) 統合テスト（ViewerRendererContentUpdateIntegrationTests 形式）— .rendered→.diff で中間の (isSourceMode:true, diffState:.none) がミラーに確定されず、diffRefreshTask 完了後に差分付きで確定する遷移列（AC #1/#4）。(c) 取得失敗・差分なし → .unavailable 着地でプレーンソース表示（AC #3）。(d) presenter の pending 遷移（登録時 pending・guard で unavailable・.diff からの再取得では降格しない）。修正を戻して落ちることを確認する
7. doc 追随: ViewerStore の diffText doc、ViewerDisplayMode.swift:11-14 の根拠記述、完了時に native-app-design.md
リスク注記: ViewerScriptDispatcher は applyRender 時に renderer.diffState をライブ再読するため、plan と送信の間の着地は「送った値がそのままミラーへ確定」で整合する（裏取り済み。pending が送信されるのはコンテンツ相違の描画経路のみで、nil text 送信 = 差分クリアで無害）

--- /review-design 実施結果（実装前レビュー・チェックリスト 10 項目）---
【設計修正 1（項目 3: 兄弟判断の全列挙）】skip 規則は通常経路の equality guard 直前ではなく、planner の先頭（direct HTML 分岐より前、incoming 組み立て直後）に置く。理由: HTML ファイルは .rendered が直接 HTML モード（isDirectHTMLActive）であり、.diff への切替が exitDirectThenRender 分岐（ContentUpdatePlanner.swift:57-61）を通って中間プレーン描画を起こすため。pending と directHTMLLoad(shouldEnter) は排他（pending は isSourceMode=true のときのみ生成され、shouldEnter は isSourceMode=false が条件。ContentUpdatePlanner.swift:47-52）なので先頭配置で directHTMLLoad を壊さない。
【確認済み（項目 3）】pendingAppend は plan(for:) が消費可否にかかわらず破棄し（ViewerRenderer+ContentUpdate.swift:44-46）、追記内容は input.content に含まれるため、skip しても行が失われず「次の描画契機まで遅延」になるだけ。canConsume はミラー丸ごと比較（RenderedStateMirror.swift:48-56）で pending ≠ 記録済みにより自動的に不成立 → 追記経路へ吸収されない（TASK-320 の構造が今回も効く）。dispatcher の送信判定（ViewerScriptDispatcher.swift:132-135）も同値比較で、pending が送信されるのはコンテンツ相違の描画経路のみ（nil text = 差分クリアで無害）。
【確認済み（項目 8: 世代管理）】pending を解消する書き手が全経路に存在: 着地（.diff/.unavailable）、refresh の guard（.unavailable）、モード離脱の applyDisplayMode（.unavailable）、ファイル切替の openFile（.unavailable）。着地タスクが guard で bail する 3 経路（self 消滅・URL 不一致・モード離脱）はいずれも上記の別の書き手が先行して解消している。
【確認済み（項目 5: 順序）】描画が 1 回に減ることで復元は isSwitch=true の永続化位置読み出しに一本化される。今日の 1 段目描画と同じ復元経路（切替先モードのキー）であり退行なし。
【注記（項目 4/6）】pending 中は前フレームを保持するため、git が遅いボリュームではツールバー選択と表示内容が乖離する時間が延びる（従来はプレーンソースが出ていた）。これはタスクの方針 (a) の意図どおり。pending 中に contentRevision が変わる更新（保存・loadMoreLines）は skip せずプレーン描画へ進む（表示の即応性優先。差分表示済み .diff からの再取得は pending に降格しないため、従来の「古い差分のまま待つ」挙動は保存される）。
【項目 10 実測】影響型グループ: ViewerStore 391 / ContentUpdatePlanner 119 / ViewerDiffPresenter 116 / ViewerContentView 100 / RenderValues 70 / RenderedStateMirror 68 / ViewerScriptDispatcher 140 行。いずれも閾値に遠く、プロトコル準拠・注入クロージャ・stored property の増加なし（ViewerStore の diffText を enum に置換するのみ）。ViewerDiffContent は Viewer/ViewerDiffContent.swift として新規ファイル化（xcodegen generate 必須）。
【破れたら落ちるもの（項目 9）】pending の不正生成（text あり + pending）は static let pending のみの生成経路で構造的に不能にする。planner の skip 規則・降格しないルールはそれぞれ ContentUpdatePlannerTests / presenter テストで固定する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（TASK-407）

採用した方針: 方針 (a) を現構造（#483 再編後）へ写した。単純化の検討結果、「取得が確定したか」という情報は既存のどの観測可能な状態にも存在しない（diffText == nil が「未着」と「確定差分なし」の両義）ため状態の追加は不可避と判断し、Bool の並走ではなく ViewerStore.diffText: String? を 3 状態 enum ViewerDiffContent（unavailable / pending / diff(String)）へ置き換えて不正な組を表現不能にした。

- 生成: ViewerDiffPresenter.refresh() が取得を登録した契機で .pending を立てる（確定差分を表示中の取り直しでは降格しない = 差分ハイライトが 1 サイクル消える中間状態を新設しない）。解消の書き手は着地・refresh guard・モード離脱・openFile の 4 経路で全 bail 経路をカバー
- レンダラ境界: DiffState（RenderKit の struct）へ isPending を追加。生成は static let pending のみ（text あり + 未確定を型で作れない）。QuickLook(OneShotRenderer) は DiffState 不参照で影響ゼロ
- 判定: ContentUpdatePlanner の先頭（direct HTML 分岐より前）に「pending かつ isSourceMode/diffState 以外がミラーと一致なら .skip」を追加（holdsPreviousFrame。ミラー丸ごと比較で TASK-320 と同型の列挙漏れを防ぐ）。direct HTML 分岐より前に置いたのは、HTML の .rendered（直接ロード）→.diff が exitDirectThenRender で同じ中間描画を起こすため（/review-design での設計修正 1）

検証（実測）:
- swift test: 1541 tests / 244 suites 全件成功。xcodebuild build 成功（xcodegen 済み）
- 修正を戻すと落ちる: planner の見送り規則を外すと 5 件失敗（ContentUpdatePlannerTests の skip 系 3 件 + 統合テスト「差分が未確定の間は前の描画を保持し、確定後に一度で差分付きへ遷移する」の 2 expect）。presenter の pending 設定を外すと 2 件失敗（「差分表示への切替は着地まで未確定として扱う」「差分なしの確定で未確定が解消される」の .pending 期待）
- swiftlint ベースライン差分: 真の新規ゼロ / 解消ゼロ（main 54 / head 54）。途中 ViewerWindowControllerDiffTests が file_length(405)/type_body_length(253) を超えたため、pending 系 3 テストを ViewerWindowControllerDiffPendingTests へ分割して解消（閾値は緩めていない）
- swiftformat: 0 files require formatting。markdownlint-cli2: 0 issues。scripts/check-doc-symbols.sh: 通過。scripts/check-type-group-size.sh --check: 閾値以内
- ContentUpdatePlanner の直接テストは従来存在しなかったため ContentUpdatePlannerTests を新設（8 件）

native-app-design.md へ反映済み: コンポーネント一覧に ViewerDiffContent の行を追加し、ViewerDiffPresenter の行に pending の記述を追記。ViewerDisplayMode の doc（「3 値を RenderKit へ渡さない」の根拠記述）も DiffState の 3 状態化に追随。

## 責務レビュー（responsibility-reviewer）の結果と対応

総評は「このまま進めてよい。分割の先行は不要」。指摘 2 件に同タスク内で対応した。

- M-1: pending 解消の不変条件（差分表示を離れたら未確定が解消される）に .pending 起点のテストが無い → ViewerWindowControllerDiffPendingTests に「取得飛行中に差分表示を離れると未確定が解消される」を追加。実測: この経路は applyDisplayMode と refresh() guard の 2 書き手で二重被覆されており、片方だけ外しても通る（setDisplayMode が両方を通すため）。両方外すと 2 expect が落ち、復元で通ることを確認した。テストの doc にこの二重被覆を明記
- L-1: ViewerDiffPresenter の doc コメント 2 箇所に廃止済み store.diffText への言及が残留 → diffContent へ同期
- Info として記録された覚え: DiffState.pending は layout を .inline に固定するが、text が nil のため表示に効かず、確定時にミラー不一致で再送されるため実害なし

対応後の最終検証: swift test 1542 tests / 244 suites 全件成功、swiftformat 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分表示への切替で一瞬プレーンなソース表示が描画される問題を、「未確定」を型で表現することで解消した。ViewerStore.diffText: String? を 3 状態 enum ViewerDiffContent（unavailable / pending / diff）へ置き換えて「未着」と「確定差分なし」を区別し、ViewerDiffPresenter が取得登録時に pending を立て（確定差分表示中は降格しない）、ContentUpdatePlanner が pending 中のモード切替だけの入力を .skip して前の表示を残す（direct HTML 分岐より前に配置し、HTML の .rendered→.diff も被覆）。QuickLook への影響はゼロ（DiffState 不参照を確認）。検証は swift test 1542 件 / 244 スイート成功、planner 直接テスト（ContentUpdatePlannerTests 新設 8 件）・描画ミラー遷移列の統合テスト・presenter の pending 遷移テスト 4 件で固定し、修正を戻すと planner 側 5 件・presenter 側 2 件・離脱経路 2 expect が落ちることを実測。swiftlint ベースライン差分ゼロ、xcodebuild 成功、native-app-design.md へ反映済み。
<!-- SECTION:FINAL_SUMMARY:END -->
