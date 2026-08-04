---
id: TASK-279
title: resolveFileToOpen 経路だけ native backing への変換が漏れている（TASK-273 のレビュー指摘）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 02:00'
updated_date: '2026-08-04 05:06'
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
- [x] #1 開いている文書の URL(ViewerStore.currentURL)が、出所(CLI・セッション復元・Quick Open・フォルダー解決・サイドバー切替・リネーム)を問わず native 裏打ちで保持される
- [x] #2 文書 URL が保持される経路を洗い出し、変換の漏れがないことを確認する(確認結果を実装ノートに残す)
- [x] #3 FileManager 由来の非 ASCII パスで開いた場合とリネーム検知の場合の双方について、裏打ちが揃うことを検証するユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 文書 URL が fileURL になる全経路を調査し、共通の絞り込み点を特定する。
2. 絞り込み点(ViewerStore の pendingURL 代入)を 1 つの private setter に集約し、そこで nativeBackedFileURL へ揃える。
3. 実ファイル(非 ASCII 名)を使ったテストで、openFile 経路とリネーム経路の双方の裏打ちを検証する。合成 URL では NSString 裏打ちを再現できないため実ファイルを使う。
4. 変換を外すとテストが落ちることを実測する。
5. 列挙側(DirectoryEnumeration)のコメントに、開く経路の変換場所を追記する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 指摘より広い範囲を、より少ない箇所で直した

指摘は「resolveFileToOpen だけ変換が漏れている」だったが、経路調査の結果、開く対象 URL の入口は 21 経路あり(CLI・Finder/Dock・Open パネル・Recent/ブックマーク・セッション復元・リポジトリ復元・リンク解決・サイドバーのコンテキストメニュー・Quick Open・履歴の戻る/進む・ウィンドウ内切替・監視によるリネーム)、resolveFileToOpen を通るのはそのうち一部でしかなかった(サイドバーのコンテキストメニューは firstSupportedFile、リンク解決や履歴はどちらも通らない)。

一方 ViewerWindowController.fileURL は計算プロパティで、実体は store.currentURL(= pendingURL)ただ 1 つ。pendingURL への代入は openFile と handleRename の 2 箇所だけで、21 経路すべてがこのどちらかを必ず通る。そこで resolveFileToOpen を個別に直すのではなく、pendingURL の代入を 1 つの setter に集約し、そこで裏打ちを揃えた。消費側が防御的に揃え直す必要がなくなる。

## 現時点の実害は小さい(severity の実測)

今日の消費側は既に防御的に変換している(FileListModel.selection の setter、FileListEntry.init)。ウィンドウの重複判定も normalizedPathKey という String キーで、URL のハッシュを通らない。したがってこれはユーザーが体感する不具合の修正ではなく、「消費側の防御に頼らず、保持先で不変条件を成立させる」ための硬化である。指摘の failure_scenario にある「将来 URL をキーにする参照」への備えが実際の価値。

## 検証

- 変換を外すと、追加した 2 テスト(openFile 経路・リネーム経路)がいずれも落ちることを実測。
- swift test: 969 tests / 138 suites 成功。xcodebuild build -scheme befold: BUILD SUCCEEDED(新規ファイル追加のため xcodegen generate 実施済み)。
- swiftlint: origin/main を git archive でスクラッチパッドへ展開して比較。新規の警告はゼロ(総数 77 件で一致)。既存の ViewerStore.swift の file_length / type_body_length の数値だけが 430→442 行・257→260 行へ増えている(元から違反しており、setter の 3 行ぶん)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
開く対象 URL の裏打ちを、resolveFileToOpen ではなく文書 URL の保持先(ViewerStore の pendingURL 代入)で揃えるようにした。経路調査で、fileURL の実体は store.currentURL 一箇所であり、21 ある入口すべてが openFile か handleRename のどちらかを必ず通ると分かったため、指摘された 1 経路ではなく全経路を 1 つの setter でカバーしている。実ファイル(非 ASCII 名)を使ったテストを 2 件追加し、変換を外すと両方落ちることを実測した。検証: swift test 969 件成功、xcodebuild BUILD SUCCEEDED、swiftlint は main 比で新規警告ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
