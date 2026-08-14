---
id: TASK-480
title: git の変更がないファイルで差分表示ボタンが無効にならない
status: To Do
assignee: []
created_date: '2026-08-14 05:45'
updated_date: '2026-08-14 05:48'
labels:
  - git
  - bug
dependencies: []
priority: medium
ordinal: 698000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 現象

サイドバーで git の変更バッジが付いていないファイル（= 作業ツリーに変更なし）を開いても、右上ツールバーのモード切替セグメントの「差分表示」が有効のまま押せる。押しても差分は出ず、`ViewerDiffPresenter.displayableDiff(_:)` が `.diff(text)` 以外を nil へ畳むため、黙って通常のソース表示に戻る（`BefoldApp/befold/App/ViewerDiffPresenter.swift:113-120`）。View メニューの同等コマンドも同じ判定を共有しているため同様（`ViewerMenuValidator.swift:82`）。

## 原因（コード参照）

- 差分ボタンの有効判定は `ViewerCapabilities` 1 箇所に集約されており、`canSelectDiffMode = onDocument && !isBinaryContent && supportsDiffDisplay`（`BefoldApp/befold/Viewer/ViewerCapabilities.swift:70`）。**ファイル種別だけを見ており、そのファイルに git の変更があるかを見ていない。**
- ツールバーのセグメントは `ViewerToolbarController.swift:204` で `host.canSelect(mode)` を引くだけなので、能力側が真ならそのまま有効になる。
- 一方サイドバーのバッジは `FileListModel.gitStatus`（`SidebarGitStatus`。`BefoldApp/befold/App/SidebarGitStatus.swift`）の `files[pathKey]` を見て描いている。**2 つは別の情報源を見ており、能力側に git の状態が一切流れていない。**

## 論点（実装着手前に決めること）

- `canSelectDiffMode` は同期的に導出される値だが、git のファイル状態は非同期に届く（`GitStatusStore` / `SidebarGitStatus`）。素直に足すと初期表示で「一瞬選べる → 選べなくなる」が起きうる。未解決（まだ分からない）／解決済みで変更なしの区別を ADR 0002 の「能力は状態から導出する」に沿ってどう扱うか。
- サイドバーが無いウィンドウ・リポジトリ外のファイルでの扱い。
- 変更なしでも差分表示を選べること自体に意味があるか（選べた上で「変更なし」を明示する案もある）。ボタンを無効化するか、選べるが空表示を明示するかを先に決める。

## 関連

- TASK-438.2「git が使えないとき差分表示モードを選択不可にする」と**同じ `canSelectDiffMode` を触る**。あちらは「リポジトリごと git が使えない」、本タスクは「git は使えるがこのファイルに変更がない」。実装は 1 箇所に集約すべきなので、着手順・統合可否を先に判断すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git の変更がないファイルを開いたとき、ツールバーの差分表示セグメントと View メニューの差分コマンドがともに無効になっている（または「変更なし」がユーザーに伝わる形になっている）
- [ ] #2 判定は ViewerCapabilities 1 箇所で行われ、ツールバーとメニューで条件が分岐していない
- [ ] #3 git 状態が未解決の間の扱いが決まっており、初期表示で選択可否が意図せず入れ替わらない
- [ ] #4 変更のあるファイルでは従来どおり差分表示を選べることがテストで固定されている
- [ ] #5 変更のないファイルで選択不可（または明示表示）になることがテストで固定されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 調査メモ（起票時、実装前）

Explore による実測。実装はしていない。

- 唯一の接点は `ViewerWindowController+SidebarHost.swift:25-27` の `gitStatusDidApply() { refreshDiff() }` だが、これは差分**本文**の再取得であってツールバー再同期（`refreshToolbarState()`）を呼ばない。git 状態が届いてもボタンの有効判定は更新されない経路になっている。
- 構造に沿う修正案: git 有無の入力を `ViewerCapabilitiesFactory.make`（`App/ViewerCapabilitiesFactory.swift:32`）の引数へ追加し、`ViewerWindowController+Capabilities.swift:22` の `capabilities` で `fileListModel.gitStatus` から供給する。
- 追加の落とし穴:
  - `gitStatus == nil`（未取得／git 管理外）と「変更なし（空だが nil ではない）」の区別（`SidebarGitStatus` の doc コメントが TASK-285 の実例付きで強調）
  - 表示中ファイルが `SidebarGitStatus.covers(_:)` の範囲外（サイドバー一覧外）のケース
  - `gitStatusDidApply` にツールバー再同期を足す必要がある
- 取得結果の理由（`GitFileDiff.noChanges` / `.notInRepository`、`App/GitFileDiff.swift:8-23`）は `ViewerStore.diffText: String?` に潰されて失われる。理由を保持する状態は現状ない。
- 表示モード復元・降格（`DisplayModeStore.swift:66`）も種別のみで判定しており、同じ入力を要する可能性がある。

## 統合により取り下げ

本タスクの内容は TASK-438.2「差分表示モードの選択可否を git の状態から導出する」へ統合した。同じ `ViewerCapabilities.canSelectDiffMode`（`BefoldApp/befold/Viewer/ViewerCapabilities.swift:70`）1 箇所を触るため、2 本に分けると条件が分岐する。以降の作業は TASK-438.2 で行う。
<!-- SECTION:NOTES:END -->
