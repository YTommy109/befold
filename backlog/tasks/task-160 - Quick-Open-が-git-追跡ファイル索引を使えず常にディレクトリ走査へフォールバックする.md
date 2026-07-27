---
id: TASK-160
title: Quick Open が git 追跡ファイル索引を使えず常にディレクトリ走査へフォールバックする
status: To Do
assignee: []
created_date: '2026-07-27 05:47'
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
- [ ] #1 git 管理下のファイルを開いた状態で Quick Open を開くと、候補が追跡ファイル索引（trackedFileIndex）由来になる（回帰テストで固定。ルートの親で rev-parse すると失敗する GitRepositoryReading スタブで、修正前に落ちるテストを先に書く）
- [ ] #2 ルート解決（rev-parse 相当）がパネルを開く1回の操作で1度だけ行われ、searchRoot と collect が同じ解決結果を共有する
- [ ] #3 QuickOpenCandidatesTests のスタブが forFileAt 引数を検証し、ルートのディレクトリ URL を渡す誤用を検知できる
<!-- AC:END -->
