---
id: TASK-638
title: >-
  revealChangedFolders の since: 引数をやめ、presenter が最後に適用した git 状態を持つ（isDirectory
  の重複実装も解消）
status: To Do
assignee: []
created_date: '2026-09-27 06:21'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarGitStatus.swift
  - BefoldApp/befold/Viewer/FileListModel.swift
  - BefoldApp/befold/Viewer/DirectoryLister.swift
priority: medium
type: task
ordinal: 838000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637（commit c1de117a）のレビュー指摘。`/code-review high` の 3 指摘（単純化・再利用・効率）を 1 件にまとめた。いずれも `SidebarTreePresenter.revealChangedFolders(since:)` の同じ 20 行に閉じる。

## 問題

1. **前回状態の受け渡しが 3 呼び出し点に散っている。** 「全件を開く」か「差分だけ開く」かの判定に必要な *前回の git 状態* を、呼び出し側が `since:` で渡す契約になっている。`FileListModel.gitStatus` の didSet は `oldValue` を、`applyRows` と `SidebarListingCoordinator` の `.toggleChangedFilesOnly` は現在値そのもの（早期 return で no-op になることに依存）を渡す（検証済み: `SidebarTreePresenter.swift` の init・`applyRows`、`SidebarListingCoordinator.swift`）。presenter が `revealedDirectoryKey` と一緒に「最後に適用した状態」を持てば、`since:` も `onGitStatusChange` の引数も `FileListModel` の doc にある「変更前の値を渡す」段落も要らなくなる。検証で挙動が同一になることを確認済み（gitStatus の変更はすべてフックを通り、組み合わせ外では印が nil に戻るため）。

2. **差分経路で `foldersToReveal` を 2 回計算している。** `isRevealed && previous != nil` のとき `status` と `previous` の両方について計算し、未追跡エントリ 1 件につき stat を 2 回（`SidebarGitStatus.swift` の `file.isUntracked && isDirectory(key)`）メインアクター上で行う。前回の候補集合を保持していれば引き算で済む。1 の変更で自然に解消する。

3. **`isDirectory` クロージャがインラインで `ObjCBool` を再実装している。** `BefoldKit/FileReading.swift` の `DefaultFileReader.isDirectory(at:)` に「ObjCBool の取り回しはここ 1 箇所に集約する」とあり、app 側には `DirectoryLister.isDirectory(_:)`（internal・nonisolated static、`DocumentOpener.swift` で使用実績あり）が既にある。注入・Sendable の制約は無い（`foldersToReveal` の引数は非 escaping、テストは `SidebarGitStatusRevealTests` が純粋関数側でスタブを渡している）。

## 注意

- TASK-637 の Notes にある「早期 return を外しても落ちない（差分が空になるだけの最適化）」は、この変更後も同じ性質。差分計算そのものを壊すと `gitUpdateRevealsOnlyNewlyChangedFolders` が落ちることは維持する。
- `revealChangedFolders` を直接呼ぶテストは無いので、引数の削除でテストは変わらない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `revealChangedFolders` は引数を取らず、前回との差分は presenter が保持する最後に適用した git 状態（と候補集合）から求める。`FileListModel.onGitStatusChange` は引数なしになり、didSet の `oldValue` 受け渡しと doc の該当段落が消えている
- [ ] #2 git 状態の更新 1 回あたり `foldersToReveal` の呼び出しは 1 回で、未追跡エントリ 1 件につき stat は 1 回になっている（ponytail コメントの記述も実態に合わせる）
- [ ] #3 presenter 内の `ObjCBool` / `fileExists(atPath:isDirectory:)` の直接呼び出しが無くなり、`DirectoryLister.isDirectory(_:)` を使っている
- [ ] #4 `SidebarNavigatorReviewExpansionTests` と `SidebarGitStatusRevealTests` が変更なしで全件 pass し、`swift test` 全件と swiftlint の main 差分ゼロを確認している
<!-- AC:END -->
