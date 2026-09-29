---
id: TASK-638
title: >-
  revealChangedFolders の since: 引数をやめ、presenter が最後に適用した git 状態を持つ（isDirectory
  の重複実装も解消）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 06:21'
updated_date: '2026-09-27 06:42'
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
- [x] #1 `revealChangedFolders` は引数を取らず、前回との差分は presenter が保持する最後に適用した git 状態（と候補集合）から求める。`FileListModel.onGitStatusChange` は引数なしになり、didSet の `oldValue` 受け渡しと doc の該当段落が消えている
- [x] #2 git 状態の更新 1 回あたり `foldersToReveal` の呼び出しは 1 回で、未追跡エントリ 1 件につき stat は 1 回になっている（ponytail コメントの記述も実態に合わせる）
- [x] #3 presenter 内の `ObjCBool` / `fileExists(atPath:isDirectory:)` の直接呼び出しが無くなり、`DirectoryLister.isDirectory(_:)` を使っている
- [x] #4 `SidebarNavigatorReviewExpansionTests` と `SidebarGitStatusRevealTests` が変更なしで全件 pass し、`swift test` 全件と swiftlint の main 差分ゼロを確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarTreePresenter に private struct Reveal { directoryKey, status, targets } と `lastReveal: Reveal?` を置き、`revealedDirectoryKey` と `since:` 引数を撤去する。判定は「同じディレクトリで lastReveal.status == 現在の status なら何もしない」。差分は `targets.subtracting(lastReveal.targets)` で、foldersToReveal の呼び出しは 1 回。
2. `FileListModel.onGitStatusChange` を `(() -> Void)?` にし、didSet は `onGitStatusChange?()` だけにする。doc の「変わる前の値を渡す」を消す。
3. 呼び出し 3 箇所（presenter init / applyRows / SidebarListingCoordinator .toggleChangedFilesOnly）を引数なしにする。
4. isDirectory は `DirectoryLister.isDirectory(URL(fileURLWithPath:isDirectory:))` を使い、インラインの ObjCBool を消す。
5. viewer-ui.md の `revealChangedFolders(since:)` 表記を直す。
review-design: 項目 1（判定の源は前回適用した status との値比較で従来と同じ）、3（消費経路は grep で 3 箇所、フック型の変更で漏れはコンパイルエラーになる）、5（保持するのは SidebarGitStatus の値コピー = COW の辞書参照と Set で、寿命は presenter = 窓と同じ）、6（差分経路の stat が 2N → N）、9（粒度は窓ごとで従来と同じ。presenter 内 private）、10（SidebarTreePresenter 288 行 → 約 295 行）。他は該当なし。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装
- presenter に private struct Reveal { directoryKey, status, targets } と `lastReveal` を置き、`revealedDirectoryKey` と `since:` を撤去。判定は「同じディレクトリで lastReveal.status == 現在の status なら return」。差分は前回の候補集合との引き算で、`foldersToReveal` の呼び出しは 1 回（presenter 内の出現 1 箇所）。
- `FileListModel.onGitStatusChange` は `(() -> Void)?`。didSet の `oldValue` 受け渡しと「変わる前の値を渡す」段落は消した。
- 呼び出し 3 箇所（init / applyRows / SidebarListingCoordinator の .toggleChangedFilesOnly）を引数なしに。フックの型変更で漏れはコンパイルエラーになるため grep 以外の担保は不要。
- isDirectory は `DirectoryLister.isDirectory(URL(fileURLWithPath:isDirectory:))`。presenter の ObjCBool 出現 0。
- review-design は Plan 記載のとおり指摘なし。責務レビュー: stored property は `revealedDirectoryKey: String?` が `lastReveal: Reveal?` に置き換わっただけで数は同じ、型・プロトコル準拠・注入クロージャは増えていないため回していない。

## 検証
- 差分の引き算（`subtracting(previous?.targets ?? [])`）を外すと `SidebarNavigatorReviewExpansionTests.gitUpdateRevealsOnlyNewlyChangedFolders` が Expectation failed: expandedFolderKeys == [key("b")] で落ちることを実測（TASK-637 と同じ担保が維持されている）。
- `SidebarNavigatorReviewExpansionTests` / `SidebarGitStatusRevealTests` は変更なしで pass。サイドバー系 14 スイート 87 件 pass。`swift test --skip Integration --skip FileWatcherTests`: 1885 + 66 件 pass。`xcodebuild build` 成功。swiftlint は origin/main と差分ゼロ（46 → 46）。swiftformat lint 0 件。型グループ: SidebarTreePresenter 288 → 287 行、FileListModel 398 行（閾値内）。
- native-app-design.md への反映は不要（型・依存の向きの変更なし）。viewer-ui.md は `revealChangedFolders(since:)` の表記を `revealChangedFolders()` に直した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`revealChangedFolders` の `since:` 引数を撤去し、presenter が最後に適用したディレクトリ・git 状態・候補集合を `lastReveal` として持つ形にした。`FileListModel.onGitStatusChange` は引数なしになり、`oldValue` の受け渡し契約が消えた。差分経路の `foldersToReveal` 呼び出しは 2 回 → 1 回（未追跡エントリの stat も 2N → N）。インラインの ObjCBool は `DirectoryLister.isDirectory` に置き換えた。既存テストは無変更で pass、差分の引き算を外すと落ちることを実測。全件テスト 1885 + 66 pass、xcodebuild 成功、swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
