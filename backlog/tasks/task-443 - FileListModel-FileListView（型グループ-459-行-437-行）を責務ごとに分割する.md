---
id: TASK-443
title: FileListModel / FileListView（型グループ 459 行 / 437 行）を責務ごとに分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 05:06'
updated_date: '2026-08-12 01:55'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 100800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/Viewer/ のサイドバー系 2 グループが閾値 400 を超えている。scripts/check-type-group-size.sh の実測値で scripts/type-group-baseline.txt にも凍結されている。

- FileListModel 459 行（本体 378 / +Snapshot 55 / +TreeRows 26）
- FileListView 437 行（本体 326 / +Keyboard 111）

どちらもファイル単位では file_length の warning 400 を下回っており、TASK-428 の起票時のファイル単位リスト（7 件）には現れていなかった。合算で初めて顕在化したグループ。超過幅は他の返済対象（ViewerRenderer 1300 / ViewerWindowController 1255 / SidebarNavigator 611）より小さいため priority は low。

2 つを 1 タスクにまとめているのは、同じサイドバーの表示経路にあり、モデル側とビュー側で関心の置き場所を同時に決めたほうが筋が良いため。分割の途中でどちらか片方だけが閾値以下になる状態は許容するが、タスクの完了は両方が閾値以下になった時点とする。

分割は extension を増やす形では効かない（合算値が減らない）。独立型へ関心を出すこと。着手前に responsibility-reviewer サブエージェントを回して切り口を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FileListModel の型グループ合算行数が 400 行以下になる
- [x] #2 FileListView の型グループ合算行数が 400 行以下になる
- [x] #3 ベースライン scripts/type-group-baseline.txt から両グループのエントリが消える
- [x] #4 分割は extension の追加ではなく独立型への切り出しで行われている
- [x] #5 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [x] #6 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListModel グループ（490 → 400 以下）から独立型へ切り出す
   1a. parentRow(of:) を FileListSnapshot へ移す（FileListModel+TreeRows.swift を削除。-26 行）。判定材料は visible 行の depth の連なりで、既に FileListSnapshot が visible を持つ。呼び出し元 FileListView+Keyboard.selectParentRow は perform(_:in:) から snapshot を受け取れる
   1b. git 状態の受け入れ判定（gitStatus / pendingGitStatus / appliedGitStatusSequence / PendingGitStatus / applyGitStatus / invalidatePendingGitStatus / promotePendingGitStatusIfNeeded）を値型 SidebarGitStatusGate へ切り出す。ADR 0003 の『反映可否は FileListModel 側』は保つ（model が gate を保持して委譲するだけ。取得側の SidebarGitStatusCoordinator とは別物）
   1c. NSTableView のフォーカス／スクロール（sidebarTableView / focusSidebarTable / scrollSelectionIntoView）を SidebarTableFocuser へ切り出す
2. FileListView グループ（420 → 400 以下）から独立型へ切り出す
   2a. navigationHeader のボタン群（ソート順・不可視・git 変更のみ・フィルター）を SidebarNavigationHeader へ切り出す
3. xcodegen generate → swift build → swift test → xcodebuild
4. scripts/check-type-group-size.sh --update-baseline で両エントリが消えることを確認
5. swiftlint を main とのベースライン差分ゼロで確認（/swiftlint-baseline）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 起票時からの実測差分 (2026-08-11 / code-review high)

PR #483 で FileListModel 型グループのベースラインが 457 → 484 へ引き上げられている（scripts/type-group-baseline.txt:16）。TASK-442.2 が FileListModel+Lookup.swift（22 行）と entry(forPathKey:) を、既に閾値 400 を超えていたグループへ足したため。

内訳（HEAD 実測）: FileListModel.swift 381 + FileListModel+Snapshot.swift + FileListModel+TreeRows.swift + FileListModel+Lookup.swift = 484 行。起票時の Description にある 459 行は古い。

`scripts/check-type-group-size.sh` は超過時に「増加」と出して exit 1 するため、ベースラインの引き上げがそのまま抑止の解除になっている。このタスクの AC#1 / AC#3 でベースラインのエントリごと消えるが、それまでの間は「引き上げてよい前例」として残る点に注意。

## 実施内容 (TASK-443)

責務ごとに独立型へ切り出した（extension の追加はしていない。逆に 2 本を削除）。

**FileListModel グループ 490 → 382 行**

- `FileListModel+TreeRows.swift` を削除し、`parentRow(of:)` を `FileListSnapshot.parent(of:)` へ移設。判定材料（visible 行の depth の連なり）は既に FileListSnapshot が持っており、モデルの stored property を 1 つも参照していなかった
- `FileListModel+Lookup.swift` を削除し、`folderEntryURL(forKey:)` / `matchingEntryURL(for:)` を `FileListEntryIndex` へ移設。folderEntryURL は線形走査をやめ、`folderByPathKey` 辞書（構築は entries.didSet の 1 パス内）で O(1) にした。TASK-450 の「先勝ちは kind を見ない」制約は辞書を分けることで解消
- git 状態の受け入れ判定（recency + ディレクトリ対付け / ADR 0003）を `FileListGitStatusGate`（nonisolated struct）へ切り出し。取得側の SidebarGitStatusCoordinator とは別物で、ADR 0003 の『反映可否は FileListModel 側』は保っている（model が gate へ委譲し、結論の `gitStatus` だけを観測対象へ書く）
- NSTableView 操作（focus / scroll）を `SidebarTableFocuser`（@MainActor class・非 @Observable）へ切り出し。FileListModel の `import AppKit` の唯一の理由だった
- `listingSource(for:)` を `FolderListingSourceResolver` へ切り出し（PreviewTargetResolver と同じ形）

**FileListView グループ 420 → 319 行**

- ヘッダー（基準ディレクトリ行・フォルダー名・4 トグル・フィルター欄）を `SidebarHeaderView` へ切り出し。`@FocusState` も一緒に移した

## 副産物: ← キーの二重評価を修正

`selectParentRow` が `model.parentRow(of:)` を呼び、その中で listSnapshot を再評価していたため、「1 打鍵につき絞り込みは 1 回」（TASK-418）が ← の経路だけ破れていた。snapshot を引数で渡す形に閉じた。担保として `FileListViewFilteredKeyboardTests.selectParentKeyEvaluatesSnapshotOnce` を追加し、**元の実装へ戻すと評価回数 2 で落ちること**を実測で確認済み。

## 観測（@Observable）の扱い

gate を観測対象の stored property にすると、保留・sequence の書き換え（画面に出ない）でも再描画とツールバー再同期が走り、TASK-278 と同型の回帰になる。`@ObservationIgnored private var gitStatusGate` とし、画面に出る `gitStatus` だけを観測対象のまま残した。

## 検証

- `swift test`: 1442 tests / 214 suites すべて通過
- `xcodebuild build -scheme befold`: BUILD SUCCEEDED（xcodegen generate 実行済み）
- swiftlint: origin/main を別ディレクトリへ展開して比較し、差分ゼロ（61 件で一致）
- `scripts/check-type-group-size.sh --check`: ベースライン以内。両エントリが baseline から消えた

## スコープ外（要フォロー）

responsibility-reviewer の指摘のうち、閾値達成に不要だったため見送ったもの:

1. `FileListView` の注入クロージャが 8 → 5 本になったが規約の上限 3 を超えたまま。`FileListViewDelegate` プロトタイプ化の余地あり
2. コンテキストメニュー（67 行）の `SidebarContextMenu` への切り出し
3. `backHistory` / `forwardHistory` が `NavigationHistory` の二重表現（View が @Observable 経由で読むため、NavigationHistory 側を @Observable にする必要があり影響範囲が別）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListModel / FileListView の型グループを責務ごとに独立型へ分割し、両方を閾値 400 以下にした（Model 490→382 / View 420→319）。

新設: FileListGitStatusGate（git 状態の受け入れ判定 / ADR 0003）、SidebarTableFocuser（NSTableView 操作）、FolderListingSourceResolver（プレビューの供給元判定）、SidebarHeaderView（ヘッダー UI）。
既存型へ移設: parentRow → FileListSnapshot.parent(of:)、folderEntryURL / matchingEntryURL → FileListEntryIndex（辞書化して O(1) に）。extension は追加せず、FileListModel+TreeRows / +Lookup の 2 本を削除した。

副産物として、← キーだけ listSnapshot を再評価して TASK-418 の『1 打鍵につき絞り込みは 1 回』が破れていた点を修正し、破れたら落ちるテストを追加した（元の実装へ戻すと評価回数 2 で落ちることを実測で確認）。

検証: swift test 1442 件すべて通過、xcodebuild BUILD SUCCEEDED、origin/main を別ディレクトリへ展開して比較した swiftlint 差分ゼロ、check-type-group-size.sh --check がベースライン以内（両エントリが baseline から消えた）。
<!-- SECTION:FINAL_SUMMARY:END -->
