---
id: TASK-160
title: Quick Open が git 追跡ファイル索引を使えず常にディレクトリ走査へフォールバックする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 05:47'
updated_date: '2026-07-27 06:15'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppQuickOpenEnvironment.candidateSet() は git 管理下でリポジトリルート（ディレクトリ URL）を QuickOpenCandidates.collect(root:) に渡し、collect は gitIndex.trackedFileIndex(forFileAt: root) を呼ぶ。しかし GitCommandFileIndex.trackedFileIndex は引数を「ファイル」とみなし deletingLastPathComponent()（= ルートの親）を起点に git rev-parse を実行するため、ルートの親は通常リポジトリ外 → .notARepository → nil となり、常に DirectoryFileScanner へフォールバックする。

影響:
- git 索引（追跡ファイル全件・打ち切りなし）が使われず、深さ8/10000件上限の走査結果しか出ない。TASK-159 の受け入れ確認でも実機で tracked=-1・走査800件フォールバックを観測済みで、この症状と一致する。
- AppDelegate.makeQuickOpenEnvironment の warm(forFileAt: currentFileURL) は正しいキーで索引を構築するため、git ls-files のコストだけ払って命中しない。
- ルートの親が別リポジトリ内（ホームを dotfiles リポジトリにしている等）の場合、外側リポジトリの索引が使われ無関係な候補集合になる。

あわせて AppQuickOpenEnvironment.searchRoot がキャッシュなしの GitRepository を毎回 new して rev-parse を同期実行しており（GitCommandFileIndex の rootByDir キャッシュと二重実装）、パネルを開くたびにメインスレッドで git subprocess が走る。ルート解決を索引側の1回に畳んで同時に解消する。

該当: BefoldApp/befold/App/AppQuickOpenEnvironment.swift:57,83-87 / BefoldApp/BefoldKit/QuickOpenCandidates.swift:88 / BefoldApp/befold/App/GitCommandFileIndex.swift:45-46
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git 管理下のファイルを開いた状態で Quick Open を開くと、候補が追跡ファイル索引（trackedFileIndex）由来になる（回帰テストで固定。ルートの親で rev-parse すると失敗する GitRepositoryReading スタブで、修正前に落ちるテストを先に書く）
- [x] #2 ルート解決（rev-parse 相当）がパネルを開く1回の操作で1度だけ行われ、searchRoot と collect が同じ解決結果を共有する
- [x] #3 QuickOpenCandidatesTests のスタブが forFileAt 引数を検証し、ルートのディレクトリ URL を渡す誤用を検知できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitFileIndexing に repositoryRoot(forFileAt:) を追加（デフォルト実装 nil）。既存 trackedFileIndex の型は据え置き（波及回避）。
2. GitCommandFileIndex: root 解決部を private ヘルパへ抽出し repositoryRoot と trackedFileIndex で共有。rootByDir キャッシュにより両者は同一 rev-parse を共有。
3. QuickOpenCandidates.collect に anchorFile を追加し、git 索引へは root ではなく anchorFile（ファイル URL）を渡す。root は表示・フォールバック走査の基準として維持。
4. AppQuickOpenEnvironment: 独自 GitRepository(repository プロパティ) と searchRoot を削除。root は gitIndex.repositoryRoot(forFileAt: currentFileURL) ?? currentFileURL.parent で 1 回だけ解決し collect へ渡す。
5. TDD: 先に (a) QuickOpenCandidatesTests のスタブが forFileAt を検証しルートのディレクトリ誤用を検知する失敗テスト、(b) GitCommandFileIndex がルートの親で rev-parse 失敗するスタブでも索引を返す回帰テストを追加してから実装。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 全730パス。新規4テスト(quickOpenCollectsFromTrackedIndexForFileInRepo / repositoryRootAndIndexShareSingleRevParse / repositoryRootIsNilOutsideRepo / passesAnchorFileToGitIndex)で AC を固定。swiftformat lint クリーン。設計: 索引の戻り型は据え置き、GitFileIndexing に repositoryRoot(forFileAt:)(既定 nil)を追加してルート解決を索引側1回に畳み、collect には root ではなく anchorFile(ファイル)を渡すよう修正。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
collect が trackedFileIndex(forFileAt:) にルート(ディレクトリ)を渡し常に走査フォールバックしていた誤用を、開いているファイル(anchorFile)を渡すよう修正。ルート解決は GitFileIndexing.repositoryRoot(forFileAt:) 追加で索引の rootByDir キャッシュへ一本化し、AppQuickOpenEnvironment の重複 GitRepository と searchRoot を削除(rev-parse は1回に)。回帰テスト3本で AC を固定、swift test 全730パス。
<!-- SECTION:FINAL_SUMMARY:END -->
