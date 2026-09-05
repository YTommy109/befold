---
id: TASK-591
title: 'TASK-586 の後始末: 存在しない ⌃⌘P の記述と古い doc コメントを直し、1 行ラッパーを畳む'
status: To Do
assignee: []
created_date: '2026-09-05 02:48'
labels:
  - sidebar
dependencies: []
priority: low
type: chore
ordinal: 856000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-586 の実装後レビューで見つかった、動作に影響しない取りこぼし 3 点。

- `ViewerWindowController+FileList.swift` の doc（「メニュー(⌃⌘T・⌃⌘P)と同じ経路」）と `FileListViewDelegate.swift` の doc（「メニュー(⌃⌘P)と同じ `toggleSlideMode(_:)`」）がスライドモードの ⌃⌘P ショートカットを主張しているが、`MainMenuBuilder+ViewMenu.swift` は TASK-585 の判断でキー無しの項目として追加しており、`p` は Quick Open（⌘P）と Print（⇧⌘P）にしか割り当てられていない。ショートカットはシンボルではないので `check-doc-symbols` では検知できず、後続タスクが予約済みと誤認する。⌃⌘T は正しい。
- `ViewerWindowController+FileList.swift` の extension ヘッダーが「行操作の受け先」のままで、同 extension が `fileListDidRequestDisplayChange(_:)` も実装するようになったことを反映していない（`FileListView.swift` 側は更新済み）。
- `ViewerWindowAssembler.makeFileListView(for:)` はクロージャ撤去後、`FileListView(model:delegate:)` を返すだけの単一式で呼び出し元 1 箇所。doc コメントはもうやっていないことを説明し、ファイルヘッダーの「生成物のクロージャがコントローラを弱参照で捕捉するための make* ヘルパー」という根拠も当てはまらない。

/code-review high（2026-09-05）の指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コード中の doc コメントにスライドモードの ⌃⌘P という記述が無く、View メニューの項目（ショートカット無し）を指す表現になっている
- [ ] #2 `ViewerWindowController+FileList.swift` の extension ヘッダーが行操作と表示切り替えの両方を受けることを述べている
- [ ] #3 `makeFileListView` が無くなり、呼び出し元で `FileListView(model:delegate:)` を直接組んでいる
<!-- AC:END -->
