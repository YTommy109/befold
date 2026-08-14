---
id: TASK-438.2
title: 差分表示モードの選択可否を git の状態から導出する
status: To Do
assignee: []
created_date: '2026-08-13 14:00'
updated_date: '2026-08-14 13:30'
labels:
  - git
milestone: m-5
dependencies:
  - TASK-438.1
parent_task_id: TASK-438
priority: medium
type: bug
ordinal: 110200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-438 の決定（論点 2: ADR どおりに実装する）の実装。ADR の記述は変えず、実装を追随させる。

**TASK-480 を統合したタスク**（起票時は別タスクだったが、同じ 1 箇所の条件を触るため 1 本に畳んだ）。差分表示モードを選べない理由は次の 2 つがあり、どちらも `ViewerCapabilities.canSelectDiffMode` が判断していない。

1. **リポジトリごと git が使えない**（非 git ディレクトリ・取得失敗）
2. **git は使えるが、そのファイルに変更がない**（サイドバーに変更バッジが付いていないファイル）

## 現状の乖離

ADR（libgit2 移行）の Fallback 節は縮退の 1 つとして「差分表示モードを選択不可にする（既存の「管理外」扱いと同じ）」を挙げているが、**未実装**。

- `BefoldApp/befold/Viewer/ViewerCapabilities.swift:70` の `canSelectDiffMode` は `onDocument && !isBinaryContent && supportsDiffDisplay` で決まり、**git の可用性もファイルの変更有無も見ていない**（ファイル種別のみ）
- 結果、モードは選べる。`ViewerDiffPresenter.refresh()`（`App/ViewerDiffPresenter.swift:82-108`）がゲートを通ってから取得し、`displayableDiff(_:)`（同 :113-120）が `.diff(text)` 以外（`.noChanges` / `.notInRepository` / nil 含む）を nil に畳んで**黙って通常のソース表示へ戻す**
- ツールバー（`App/ViewerToolbarController.swift:204`）と View メニュー（`App/ViewerMenuValidator.swift:82`）は同じ `capabilities` を引くため、両方とも有効のまま

## 変更有無の情報源（ケース 2）

サイドバーのバッジは `FileListModel.gitStatus`（`SidebarGitStatus`、`App/SidebarGitStatus.swift`）を見ており、能力側とは**完全に別系統**。唯一の接点である `App/ViewerWindowController+SidebarHost.swift:25-27` の `gitStatusDidApply() { refreshDiff() }` は差分**本文**の再取得だけで、`refreshToolbarState()` を呼ばない。

## 論点（実装着手前に決めること）

**`canSelectDiffMode` は同期的に計算される値だが、git の可用性もファイルの変更有無も非同期に届く**。素直に足すと初期表示で「一瞬選べる → 選べなくなる」（またはその逆）が起きうる。次を設計レビューで確定させること。

- 未解決（まだ分からない）と解決済みで使えない／変更なしを、能力の導出でどう扱うか。ADR 0002 の「能力は状態から導出する」設計に沿った形にする
- `gitStatus == nil`（未取得／git 管理外）と「変更なし（空だが nil ではない）」の区別。`SidebarGitStatus` の doc コメントが TASK-285 の実例付きで注意している箇所
- 表示中ファイルが `SidebarGitStatus.covers(_:)` の範囲外（サイドバー一覧外）のケース、サイドバーが無いウィンドウでの扱い
- 変更なしのとき、ボタンを無効化するのか、選べた上で「変更なし」を明示するのか
- 表示モード復元・降格（`App/DisplayModeStore.swift:66`）も種別のみで判定しており、同じ入力を要するか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git が使えないリポジトリで差分表示モードが選択不可になっている
- [ ] #2 git の変更がないファイルを開いたとき、ツールバーの差分表示セグメントと View メニューの差分コマンドがともに無効になっている（または「変更なし」がユーザーに伝わる形になっている）
- [ ] #3 ViewerCapabilities.canSelectDiffMode が git の可用性とファイルの変更有無を見ており、ツールバーとメニューで条件が分岐していない
- [ ] #4 可用性・変更有無が未解決の間の扱いが決まっており、初期表示で選択可否が意図せず入れ替わらない
- [ ] #5 変更のあるファイルでは従来どおり差分表示を選べることがテストで固定されている
- [ ] #6 選択不可（または明示表示）になることがテストで固定されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## TASK-480 統合時の調査メモ（実装前）

TASK-480「git の変更がないファイルで差分表示ボタンが無効にならない」を本タスクへ統合した。以下は TASK-480 の調査で得た内容（Explore による実測、実装はしていない）。

- 構造に沿う修正案: git の可用性・変更有無を `ViewerCapabilitiesFactory.make`（`App/ViewerCapabilitiesFactory.swift:32`）の引数へ追加し、`App/ViewerWindowController+Capabilities.swift:22` の `capabilities` で `fileListModel.gitStatus` から供給する。条件は `ViewerCapabilities.swift:70` の 1 箇所に保つ（ADR 0002）。
- `gitStatusDidApply`（`App/ViewerWindowController+SidebarHost.swift:25-27`）にツールバー再同期を足す必要がある。現状は `refreshDiff()` のみで、git 状態が届いてもボタンの有効判定は更新されない。
- 取得結果の理由（`GitFileDiff.noChanges` / `.notInRepository`、`App/GitFileDiff.swift:8-23`）は `ViewerStore.diffText: String?` に潰されて失われる。理由を保持する状態は現状ない。ケース 1 とケース 2 を UI で区別するなら、ここに手を入れる必要がある。
<!-- SECTION:NOTES:END -->
