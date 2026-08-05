---
id: TASK-321
title: GitDiffLoader の in-flight 合流が保存前の古い差分を返す問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:08'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 505000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

GitDiffLoader.swift:22 の in-flight 合流は、作業ツリーが変化した後に来た新しい要求を、変化前に開始済みのタスクへ相乗りさせる。短時間に 2 回保存すると、2 回目のリロードの refreshDiff は 1 回目の保存時点のツリーを読んだタスクを await して返し、その後の再フェッチも無効化もないため、表示は 1 回目の保存の差分のまま次のファイルイベントまで止まる。「保存したのに古い差分が出る」という、型の doc コメントが避けると謳っている失敗そのもの。

修正方針の候補: 要求に世代（リクエスト時刻や contentRevision）を持たせ、実行中タスクの開始が要求より古い場合は完了後に再フェッチする、または in-flight 合流をやめて最後の要求だけ生かす（デバウンス + 最新優先）。

関連: GitDiffLoader をウィンドウ間で共有する cleanup タスク（同ファイルの構造に触るため、まとめて実施すると効率的）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一ファイルを短時間に 2 回保存したとき、最終的に表示される差分が 2 回目の保存内容を反映している
- [ ] #2 二重起動抑止（同一要求の合流）の意図した効果は維持される
- [ ] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->
