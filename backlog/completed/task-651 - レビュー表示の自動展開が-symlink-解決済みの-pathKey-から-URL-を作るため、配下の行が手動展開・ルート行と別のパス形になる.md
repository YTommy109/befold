---
id: TASK-651
title: レビュー表示の自動展開が symlink 解決済みの pathKey から URL を作るため、配下の行が手動展開・ルート行と別のパス形になる
status: Done
assignee: []
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 09:31'
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
- [x] #1 symlink 経由で開いたディレクトリでレビュー表示の自動展開が起きたとき、配下の行の URL が `entriesDirectory` と同じパス形（symlink 未解決）になるテストがある
- [x] #2 自動展開された配下の行で `PathRelativizer.relativePath` が相対パスを返す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
revealChangedFolders が券に載せる URL を entriesDirectory + (key の directoryKey 以降) で作る。単純化の検討: 起票時の方向（行があれば folderEntryURL、無ければ合成）の 2 経路は不要。行 URL も DirectoryLister/子リストが親 URL に子名を足して作るので、合成 1 経路で行の形と一致する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- foldersToReveal の戻り値はすべて directoryKey + "/" 配下（SidebarGitStatus.foldersToReveal の prefix 判定）なので、相対部分は dropFirst(directoryKey.count + 1) で取れる。
- テストは実在する symlink（TempDir 配下 link → real）で組む。normalizedPathKey は実在しないパスでは symlink を解決しないため、変更ファイル a/x.md を実際に置く必要があった。
- 修正を外すと新テストの 2 期待（行 URL の形・relativePath）が落ちることを確認済み。
- 本体テストが type_body_length を超えたので、新テストは SidebarNavigatorReviewExpansionTests+PathForm.swift へ分割（fixture 群を internal 化）。
- 仕様文書: viewer-ui.md のレビュー表示節は振る舞い（どのフォルダーが開くか）を書いており、券の URL のパス形は範囲外なので更新不要。

- 検証: swift test --filter SidebarNavigatorReviewExpansionTests 13 件 pass、--filter 'Sidebar|FileList|PathRelativizer' 437 件 pass、swiftlint（変更 3 ファイル）0 件。全体 swift test は WKWebView の ViewerRendererOneShotIntegrationTests（loadOneShot は描画完了まで待ってから返る: WKErrorDomain Code=4）で失敗後に停止し、単独実行でも 300 秒無応答。今回の差分（SidebarTreePresenter と対応テスト）とは依存関係が無い。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
レビュー表示の自動展開が券に載せる URL を、symlink 解決済みの pathKey ではなく entriesDirectory + 相対部分で作るようにした。自動展開された配下の行が利用者の開いたパス形になり、相対パスのコピーが絶対パスへ落ちなくなる。実在する symlink を使ったテストを追加（修正を外すと 2 期待が落ちることを確認）。
<!-- SECTION:FINAL_SUMMARY:END -->
