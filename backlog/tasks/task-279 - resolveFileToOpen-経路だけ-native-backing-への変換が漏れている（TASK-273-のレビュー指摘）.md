---
id: TASK-279
title: resolveFileToOpen 経路だけ native backing への変換が漏れている（TASK-273 のレビュー指摘）
status: To Do
assignee: []
created_date: '2026-08-04 02:00'
labels:
  - review-finding
dependencies: []
priority: medium
type: bug
ordinal: 469000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-273 で DirectoryEnumeration の列挙出口にあった nativeBackedFileURL 変換（`for url in contents.map(\.nativeBackedFileURL)`）を外し、必要な消費側で個別に張り直す方針にした。しかし張り直したのは FileListEntry.init と DirectoryLister.allEntriesSorted の 2 つだけで、3 つ目の消費経路 sortedFiles → fileToOpen → SupportedFileResolver.resolveFileToOpen が漏れている。

この経路は AppDelegate.openViewer / SessionRestorer / QuickOpenModel / CLICheckCommand から使われ、フォルダーを渡されたときに最初の開けるファイルへ解決する。結果、非 ASCII パスのフォルダーを CLI（`befold <dir>`）・セッション復元・Quick Open のいずれかから開くと、NSString バッキングのままの URL が open パイプラインへ流れる。以後その URL に対するハッシュ・等価比較は 1 文字ずつの Unicode 正規化を払い続ける（ウィンドウ／タブの重複判定など）。これは TASK-266/268 が潰したメインスレッド停止と同じ種類のコストで、変換して差し込む書き込み点は現状 FileListModel.selection しかない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SupportedFileResolver.resolveFileToOpen がフォルダーから解決して返す URL が native backing になっている
- [ ] #2 CLI・セッション復元・Quick Open のいずれの経路でも、開く対象 URL のバッキングが揃っていることをテストで確認できる
- [ ] #3 列挙出口の全消費経路を洗い出し、変換の張り直し漏れが他にないことを確認する（確認結果を実装ノートに残す）
<!-- AC:END -->
