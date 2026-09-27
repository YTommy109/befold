---
id: TASK-651
title: レビュー表示の自動展開が symlink 解決済みの pathKey から URL を作るため、配下の行が手動展開・ルート行と別のパス形になる
status: To Do
assignee: []
created_date: '2026-09-27 08:37'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/BefoldKit/PathRelativizer.swift
  - BefoldApp/BefoldKit/URL+NormalizedPathKey.swift
priority: medium
ordinal: 851000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。コードで裏を取った。

## 現状（検証済み）

- `revealChangedFolders` は候補ごとに `expandFolder(key, at: URL(fileURLWithPath: key, isDirectory: true))` を呼ぶ。`key` は `normalizedPathKey`（`resolvingSymlinksInPath().path`）なので、symlink を解決した実体パス。
- ルート行の URL は一覧（`DirectoryLister`）が返した、利用者が開いたままのパス形。手動展開は行の URL を使う（`folderEntryURL(forKey:)` 経由）。
- `PathRelativizer.relativePath(of:relativeTo:)` は `urlComponents.starts(with: baseComponents)` で判定する（`BefoldKit/PathRelativizer.swift`）。

## 再現の形

`~/proj → /Volumes/Work/proj` の symlink 経由でリポジトリを開く。自動展開されたフォルダーの子行は `/Volumes/Work/proj/a/b.md` になり、「相対パスをコピー」が `baseDirectory`（`~/proj`）との前方一致に失敗して絶対パスを返す。同じフォルダーを手で展開すると行 URL が別形になるので、自動展開と手動展開が交互に起きると行の identity が入れ替わる。

## 方向

券が運ぶ URL を一覧の形から導く。行があるキーは `folderEntryURL(forKey:)`、無いキー（入れ子の一括展開）は `entriesDirectory` に `key` の `directoryKey` 以降を足して作る。`URL(fileURLWithPath: key)` を展開の入口で使わない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 symlink 経由で開いたディレクトリでレビュー表示の自動展開が起きたとき、配下の行の URL が `entriesDirectory` と同じパス形（symlink 未解決）になるテストがある
- [ ] #2 自動展開された配下の行で `PathRelativizer.relativePath` が相対パスを返す
<!-- AC:END -->
