---
id: TASK-353.2
title: 差分の比較基準を窓ごとに切り替える UI を足す
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-08 02:00'
updated_date: '2026-10-08 04:52'
labels: []
milestone: m-11
dependencies:
  - TASK-353.1
parent_task_id: TASK-353
priority: medium
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-353 の仕様のうち、差分ビューア側を担う。現状は何との差分かが画面に出ず、基準も変えられない（基準は `GitComparisonBaseResolver` が返す merge-base で固定、`GitDiffReader.diff(forFileAt:in:)` は解決できなければ HEAD へ縮退）。

3 基準（このブランチ／スタック全体／作業中）と、選択肢の出し分け・粒度・永続化しないことは TASK-353 の Description を参照。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 差分モードの間、現在の基準をラベルで表示し、そこから基準を切り替えられる
- [x] #2 「スタック全体の変更」は、親ブランチがデフォルトブランチと異なるときだけ選択肢に出る
- [x] #3 基準は窓ごとに独立し、別の窓の基準を変えても影響しない。窓ごとであることが破れたら落ちるテストがある
- [x] #4 新しい窓は常に「このブランチの変更」から始まる（永続化しない）
- [x] #5 選んだ基準で差分が空になるファイルでは、差分モードの選択可否が基準に合わせて変わる
- [x] #6 メニュー・ラベルの文字列が en/ja で揃っている
- [x] #7 GitStatusStore / GitDiffLoader の合流とキャッシュが比較基準をキーに含み、基準の違う窓同士が結果を共有しない（テストで担保）
- [x] #8 差分取得の着地時に取得開始時の基準と窓の現在の基準を照合し、基準切替直後に旧基準の差分が着地しない（テストで担保）
- [x] #9 ラベルは解決された基準ブランチ名（縮退時はデフォルトブランチ名）を表示する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（2026-10-08）

### 窓ごとの値の置き場（チェック 9・10）
- `ViewerStore.comparisonTarget: GitComparisonTarget = .parentBranch`（371/400 行、`displayMode` / `diffContent` と同じ窓ごとのライブ値）。永続化しない。`WindowPresentationMemory` には載せない（基準は窓の設定でファイルの設定ではない）
- 書き込み口は `ViewerDocumentPresenter.setComparisonTarget(_:)` の 1 本（253 行、`setDisplayMode` と並べる）。やることは store へ書く → `sidebar.refreshGitStatuses(policy: .always)` の 1 つだけ。再描画・差分取り直し・capabilities 再同期は既存の `applyGitStatus → gitContextDidChange → refreshDiff / refreshUIState` が運ぶ（新しい経路を増やさない。チェック 3）
- `ViewerWindowController` グループは 921/931 行で余裕 10 行。メニューのアクションを `+MenuActions` に足さない。ラベル兼ポップアップは `HistoryButtonView` と同じく自分で NSMenu/SwiftUI Menu を組み、presenter を直接呼ぶ

### 共有キャッシュの衝突（チェック 3・5・9、最重要）
基準を窓ごとにすると、次の 3 つの app 全体共有が「同じルート／同じファイルなら同じ結果」を前提にしているため破れる。**すべてキーに target を含める。**
- `GitStatusStore.cache` / `inFlight`（キー = rootKey）→ rootKey + target。`.onlyIfIndexChanged` の再利用判定（index fingerprint）も target が同じときだけ
- `GitDiffLoader` の合流（キー = ファイルの normalizedPathKey）→ + target。窓 A（parent）と窓 B（head）が同じファイルを開くと互いの差分を受け取る
- `GitStatusReading.status(forRepositoryAt:)` / `GitDiffReading.diff(forFileAt:in:)` に `target:` を必須引数で足す（既定引数にしない。渡し忘れが黙って既定基準になる = TASK-319 型）
- 担保: `foldsConcurrentRequestsForSameRoot` の逆（target が違えば合流しない）、`skipsGitWhenIndexFingerprintIsUnchanged` の逆（target が変われば取り直す）、`ViewerWindowManagerDiffTests` に「基準は窓ごと」（2 窓で切り替え → もう一方の store.comparisonTarget と diffContent が動かない）

### 着地時の照合（チェック 8）
- `ViewerDiffPresenter.refresh` の着地 guard は `currentURL() == url && isDiffShown` だけ。**`store.comparisonTarget == 取得時の target` を足す**。無いと切替直後に旧基準の差分が着地する
- 開始時: 基準を変えたら `diffContent` は `.pending` に落とす（TASK-407 の「確定差分を表示中は降格しない」は保存による取り直し向け。基準が変わったのに旧差分を新ラベルの下に出す方が誤り）
- バッジ側: `GitStatusResult` / `SidebarGitStatus` に `GitComparisonResolution`（353.1）を載せ、`SidebarGitStatusCoordinator` は snapshot の target が窓の現在値と違えば捨てる（既存の sequence ゲートと同じ場所）

### 表示（チェック 4）
- ラベルは 353.1 の `GitComparisonResolution.baseBranchName` を出す（「このブランチの変更」の抽象名ではなく "main から" / "feature-a から" / "HEAD から"）。縮退して main に落ちたことが利用者に見える
- 「スタック全体の変更」の出し分けは snapshot の `parentDiffersFromDefault` を読む。メニューを開く瞬間に git を触らない
- 基準を変えて現在ファイルの差分が空になると、既存どおり `.unavailable` → 通常のソース表示へ黙って戻る（`DocumentSurfaceStack` の `.none`）。新しい状態は作らず、ラベルに「(変更なし)」を付ける（`showsDiff && diffContent == .unavailable` から導出、新しい stored property は無し）
- 基準メニュー自体は `GitDiffAvailability` でゲートしない（窓の設定なので現在ファイルが unchanged でも切り替えられる）

### UI の置き場（決定事項）
- 既存の差分専用領域は無い（ツールバー 5 項目＋View メニューのみ）。**ツールバー項目**として足し、差分モード以外は `isHidden`。本文内のバー（viewer.html）は `BefoldRenderKit` 経由で QuickLook まで波及するので採らない
- 文字列: `Localizable.xcstrings` の `toolbar.mode.diff*` の直後に挿入（ソートしない）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装メモ(2026-10-08)
- 実装: store.comparisonTarget(既定 .parentBranch、非永続)、書き込み口は ViewerDocumentPresenter.setComparisonTarget。GitStatusReading.status / GitDiffReading.diff / SidebarGitReading.statuses に target: 必須引数。GitStatusStore の cache/inFlight と GitDiffLoader の合流キーに target を含めた(Key 構造体)。GitStatusSnapshot/GitStatusResult/SidebarGitStatus に GitComparisonResolution を載せ、ツールバーのポップアップ(ComparisonTargetPresentation)が読む。
- バッジ側の照合は GitStatusResult に target を持たせず、StatusRequest が発行時の target を持ち、apply で窓の現在値(SidebarNavigatorHost.comparisonTarget)と照合する形にした(結果側に載せるより状態が増えない)。
- 実測(修正を戻すと落ちること): GitStatusStore のキーから target を外す → doesNotFoldRequestsWithDifferentTargets / refetchesWhenTargetChangedDespiteSameFingerprint が落ちる。GitDiffLoader のキーから外す → doesNotFoldRequestsWithDifferentTargets と comparisonTargetIsPerWindow が落ちる。着地 guard の store.comparisonTarget == target を外す → oldTargetDiffDoesNotLand が落ちる。comparisonTarget を静的共有にする → newWindowStartsFromParentBranch / comparisonTargetIsPerWindow が落ちる。
- 全 swift test: 2027 件 pass(既知の known issue 1 件は BlockingWaitTests の既存)。swiftformat --lint ゼロ、swiftlint は HEAD との差分ゼロ、xcodebuild build -scheme befold 成功。
- 未確認: AC#1(ツールバーのラベル表示と切替)と AC#5(基準ごとの選択可否)は実機の GUI で目視していない。AC#5 は status が target 付きで取られ GitDiffAvailability がその snapshot を読む構造に依存しており、基準を変えて unchanged になる専用テストは無い。

AC#5 の専用テストを追加(GitStatusBranchDiffIntegrationTests.diffAvailabilityFollowsComparisonTarget: ブランチでコミット済みのファイルが defaultBranch で .changed、head で .unchanged になり選択不可)。Reader が target を無視する変異で落ちることを確認。AC#5 を達成とする。AC#1 は未確認のまま: xcodebuild build(-derivedDataPath .build/xcode)は成功したが、ツールバーのポップアップ操作を自動化できず目視していない。ラベル表示と切替の GUI 確認は人手で要実施。
<!-- SECTION:NOTES:END -->
