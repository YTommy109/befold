---
id: TASK-322
title: refreshDiff がメインスレッドで git rev-parse を実行し UI をブロックし得る問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:08'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 506000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

ViewerWindowController+Diff.swift:24 の refreshDiff は、コンテンツリロードのたびに gitFileIndex.repositoryRoot(forDirectoryAt:) を MainActor 上で同期呼び出しする。rootByDir キャッシュにない ディレクトリでは GitCommandFileIndex が git rev-parse サブプロセスを実行し、GitCommandRunner のタイムアウトは 10 秒 + terminationGrace 5 秒。GitDiffReading 自身の契約（「必ずメインアクターの外で呼ぶこと」）が diff 本体を Task.detached に逃がしているのと同種のブロッキングが、root 解決だけメインスレッドに残っている。

症状: ネットワークボリュームや応答の遅い git など、コールドな環境でルート未キャッシュのファイルを開く/切り替えるたびに、rev-parse が返るまで最大タイムアウト分メインスレッドが停止しアプリ全体がビーチボールになる。

修正: root 解決も含めて非同期経路（Task 内・detached）へ移す。TASK-226（GitCommandRunner async 化・GitCommandFileIndex actor 化）と関連するため、先行着手する場合は重複しない範囲で直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ルート未キャッシュのディレクトリのファイルを開いても、git 応答待ちでメインスレッドがブロックしない
- [ ] #2 root 解決失敗時（リポジトリ外）の挙動は従来どおり差分なし表示になる
<!-- AC:END -->
