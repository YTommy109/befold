---
id: TASK-325
title: GitDiffLoader をウィンドウ間で共有して git diff の二重起動を防ぐ
status: To Do
assignee: []
created_date: '2026-08-05 16:09'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: low
type: chore
ordinal: 512000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

GitDiffLoader はウィンドウごとに生成される（ViewerWindowController.swift:58 の lazy var diffLoader = Self.makeDiffLoader()、実体は ViewerWindowController+Diff.swift:11）。このため in-flight 合流はウィンドウ内でしか効かず、同じ変更ありファイルを 2 窓で開いているとファイル変更イベントで両窓のローダーが同時に git diff HEAD -- path を起動する。合流の doc コメントが防ぐと謳っている二重起動がウィンドウをまたぐと起きる。アプリ共有の GitStatusStore と対照的。

修正: GitStatusStore と同様にアプリ共有のインスタンスにする（ViewerWindowManager 経由で注入）。

関連: TASK-321（in-flight 合流が古い差分を返す問題）。同じ型の構造に触るため、まとめて実施すると効率的。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同じファイルを 2 窓で開いた状態のファイル変更イベントで、git diff の起動が 1 回に合流する
- [ ] #2 ウィンドウを閉じても他窓の差分取得に影響しない
<!-- AC:END -->
