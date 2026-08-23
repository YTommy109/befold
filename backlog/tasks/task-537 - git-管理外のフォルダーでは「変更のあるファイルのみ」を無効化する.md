---
id: TASK-537
title: git 管理外のフォルダーでは「変更のあるファイルのみ」を無効化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-22 12:39'
updated_date: '2026-08-23 05:39'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 781000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
git 管理下でないディレクトリを開いていても、View メニューの「変更のあるファイルのみ表示」とサイドバーヘッダーの同トグルが操作でき、メニューも有効のまま。実際には何も起きない（絞り込む git 状態が無いため）ので、操作できること自体が誤り。ユーザーは「効かない機能」に見える。

現状の実装:
- BefoldApp/befold/App/AppDelegate.swift:276 validateMenuItem は sidebar 表示 3 項目の有効／無効を SidebarDisplayMenuState.isEnabled で決めているが、この値は「アクティブなビューアウィンドウがあるか」だけを見ており、開いているフォルダーが git 管理下かを見ていない（BefoldApp/befold/App/SidebarDisplaySettings.swift:105 付近）。
- サイドバーヘッダー側のトグル（BefoldApp/befold/Viewer/SidebarHeaderView.swift:24 onToggleChangedFilesOnly）も同様に常に押せる。
- 実際の絞り込みは SidebarListingCoordinator.swift:90 で showChangedFilesOnly を反転させ、git 状態を一覧タスクへ結合する経路（同 145 付近）。git リポジトリ外なら git 状態が空なので結果が変わらない。

「変更のあるファイルのみ」だけの話ではなく、git 由来の UI（差分表示など）が同じ穴を持っていないかも合わせて確認する。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に従い、個別の分岐追加ではなく『開いているフォルダーが git 管理下か』を 1 箇所で持ち、メニューとヘッダーの双方がそこを参照する形にできないか検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git 管理下でないフォルダーを開いているとき、View メニューの「変更のあるファイルのみ表示」が無効（グレーアウト）になる
- [x] #2 同じ状況でサイドバーヘッダーの同トグルも操作できない（または表示されない）
- [x] #3 git 管理下のフォルダーでは従来どおり操作でき、絞り込みが効く
- [x] #4 git 管理下かどうかの判定は 1 箇所に集約され、メニューとヘッダーが同じ値を参照する
- [x] #5 ユニットテストで、git 管理外／管理下それぞれの有効・無効状態を固定する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 『git 由来の機能を出してよいか』の判定を BaseDirectoryDescriptor に 1 箇所だけ置く
2. 差分表示(GitDiffAvailability)もその判定を経由させ、両者がずれない形にする
3. FileListModel.canFilterChangedFiles として露出し、メニューとヘッダーの双方がそこを見る
4. メニューは項目ごとの有効判定を SidebarDisplayMenuState.isEnabled(for:) へ移し、GUI なしで検証できるようにする
5. サイドバーヘッダーは押せないボタンを残さず、git 管理外では出さない
6. 判定を壊したらテストが落ちることを実測で確かめる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 起票後の調査: 他の git 由来 UI は同じ穴か（2026-08-22）

結論: **同じ穴を持つのは「変更のあるファイルのみ」だけ。差分表示系は既に塞がっている。**

### 差分表示（塞がっている）
- `BefoldApp/befold/App/GitDiffAvailability.swift` が `BaseDirectoryDescriptor.Kind` から可用性を導出し、`.plainFolder` / `.unusableRepository` を `.unavailable` にする。
- `ViewerCapabilities.swift:95-97` で `canSelectDiffMode = ... && gitDiffAvailability.allowsDiffSelection`、`canToggleDiffLayout = canSelectDiffMode && showsDiff`。
- メニュー（`ViewerMenuValidator.validateDisplayModeItem`）もツールバーのセグメントも `canSelect(_:)` だけを見るので、両方まとめて無効化される。
- テストで固定済み: `ViewerCapabilitiesTests.swift:128`（`.unavailable` で `canSelectDiffMode` が false）、同 :134 `canSelectDiffFollowsTheSameCondition`。

### 変更のあるファイルのみ（塞がっていない = 本タスク）
- メニュー: `AppDelegate.swift:275` → `SidebarDisplayMenuState`（`SidebarDisplaySettings.swift:110`）の `isEnabled = settings != nil` のみ。git の事実を見ていない。
- サイドバーヘッダー: `SidebarHeaderControlsModel.swift:90-101` がボタンを無条件に組み立て、`SidebarHeaderControls.swift:84` がハンドラを繋ぐ。ここにも git の事実の入力が無い。
- つまり ADR 0002 段 2 の「能力へ畳む」形に**サイドバー表示 3 項目だけが乗っていない**のが構造上の原因。

### その他の git 由来 UI
- サイドバーの git バッジ: git 状態が無ければ描かれないだけで、操作できてしまう面は無い。
- 比較基準の切替（`GitComparisonBase`）: 現状 UI からは切り替えられない（TASK-353 が To Do）。UI が付くときに同じ穴を作らないよう、本タスクで作る判定を参照させること。

### 実装方針への含意
新しい述語を足すのではなく、既に `FileListModel.baseDirectory`（`FileListModel.swift:202`、`BaseDirectoryDescriptor.Kind`）が持っている事実を `SidebarDisplayMenuState` とヘッダーのモデルの双方へ通すのが最小。`GitDiffAvailability` と同じ入力源になるので、差分側と判定がずれない。

TASK-539（AI が書いた変更を差分表示でレビューする事例記事）がこの機能を主役に据える。**記事を出す前にこの不具合が直っている方がよい**——記事を読んで試した人が git 管理外のフォルダを開くと、押せるのに何も起きないトグルに最初に出会うことになる。

## 実装（2026-08-23）

### 判定を 1 箇所に集約した

`BaseDirectoryDescriptor.allowsGitFeatures(_:)`（BefoldKit）を新設し、**差分表示とサイドバーの絞り込みが同じ判定を見る**形にした。

- `GitDiffAvailability.make` は種別を直接 switch していたのをやめ、この関数を経由させた
- `FileListModel.canFilterChangedFiles` が同じ関数を呼ぶ
- メニュー（`SidebarDisplayMenuState`）とヘッダー（`SidebarHeaderControlsModel`）はどちらも `FileListModel.canFilterChangedFiles` を受け取る

**nil（基準ディレクトリ未解決）は落とさない。** 解決は非同期なので、未解決を false にすると初期表示で入れ替わりが起きる。`GitDiffAvailability` の既存の縮退規則（確定した否定でだけ落とす）に合わせた。

### メニューの有効判定を値型へ移した

当初は `validateMenuItem` の中に `return state.isEnabled && state.canFilterChangedFiles` と書いていたが、**それだと GUI を起動しないと検証できない**。判定を `SidebarDisplayMenuState.isEnabled(for: SidebarDisplayChange)` へ移し、項目ごとの条件をこの値型だけが持つ形にした。

あわせて、セレクタ → `SidebarDisplayChange` の対応表を `AppDelegate.sidebarChange(for:)` に 1 つだけ置き、**有効判定と実行が同じ表を見る**ようにした（別々に列挙すると項目を足したとき片方だけ対応して静かにずれる）。

### ヘッダーはボタンを消す

メニューは項目位置が固定なのでグレーアウトが自然だが、ヘッダーは並びが詰まるので押せないボタンを残すより消えたほうが素直。`SidebarHeaderControlsModel` の `canFilterChangedFiles` には**既定値を持たせていない**（渡し忘れが『git 管理外でも出る』へ静かに倒れる形を作らない / CLAUDE.md の TASK-319 の教訓）。

### 壊れることの実測

`allowsGitFeatures` を常に true へ変えて実行し、**3 系統が落ちる**ことを確認した（確認後に復元）。

- `BaseDirectoryDescriptorGitFeatureTests`「git ルートでだけ git 由来の機能を出す」
- `FileListModelGitCapabilityTests`「git 管理外・扱えないリポジトリでは絞り込めない」
- `GitDiffAvailabilityTests`「git 管理外・扱えないリポジトリでは選べない」← **差分表示側も同じ判定に繋がっている証拠**

### swiftlint

新規違反ゼロ。main / 作業ツリーとも 54 件で、生 diff も空（`/swiftlint-baseline` の手順 4 で『真の新規』『解消したもの』とも空）。

## 検証（2026-08-23）

`swift test` を実行し、本タスクが触る 5 スイートが全て合格することを確認した。

- `BaseDirectoryDescriptorGitFeatureTests` passed
- `FileListModelGitCapabilityTests`（新規） passed
- `SidebarDisplayMenuStateTests` passed
- `SidebarHeaderControlsModelTests` passed
- `GitDiffAvailabilityTests` passed

AC を直接固定しているケース: 「git 管理外では変更ファイルのみ表示だけが選べない」「git 管理外で無効になるのは変更ファイルのみ表示だけ」「git 管理外では変更のみ表示のボタンが出ない」「git 管理下では 3 項目とも使える」「アクティブウィンドウが無ければ git 管理下でも全項目が無効」「git 管理外・扱えないリポジトリでは選べない」（差分側が同じ判定を見ている証拠）。

新規テストファイルを追加したので `xcodegen generate` を実行済み。

### 同一実行で落ちた既存の失敗（本タスクとは別系統）

`ViewerRendererZoomIntegrationTests`(3) / `ViewerRendererOneShotIntegrationTests`(1) / `ViewerRendererContentUpdateIntegrationTests`(3) が失敗。症状は `readiness.isReady` が false のまま・`diagram-wrap` が null・600 秒のタイムリミット超過で、いずれも viewer.html が準備完了へ到達しない形。本タスクの diff は `BefoldRenderKit` を 1 行も触っていない（変更は BaseDirectoryDescriptor / AppDelegate / SidebarDisplaySettings / FileListModel / SidebarHeader*）。CLAUDE.md の「WebView/GUI 層は自動テスト対象外」に該当する層。**未確認: main のベースラインで同じ 7 件が落ちることは測っていない。**
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 管理外のフォルダーで「変更のあるファイルのみ表示」が操作できてしまう不具合を、判定の集約で塞いだ。BaseDirectoryDescriptor.allowsGitFeatures(_:) を新設し、差分表示（GitDiffAvailability）とサイドバーの絞り込み（FileListModel.canFilterChangedFiles）が同じ判定を見る形にした。メニューの有効判定は SidebarDisplayMenuState.isEnabled(for:) へ移して GUI なしで検証できるようにし、セレクタ対応表を AppDelegate.sidebarChange(for:) に 1 つだけ置いて有効判定と実行がずれないようにした。ヘッダーは押せないボタンを残さず非表示にする。検証: swift test で BaseDirectoryDescriptorGitFeatureTests / FileListModelGitCapabilityTests / SidebarDisplayMenuStateTests / SidebarHeaderControlsModelTests / GitDiffAvailabilityTests が全て合格。allowsGitFeatures を常に true へ変えると 3 系統が落ちることも実測済み。swiftlint は main と同じ 54 件で新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
