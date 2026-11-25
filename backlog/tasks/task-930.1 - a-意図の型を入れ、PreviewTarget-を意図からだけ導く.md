---
id: TASK-930.1
title: (a) 意図の型を入れ、PreviewTarget を意図からだけ導く
status: To Do
assignee: []
created_date: '2026-11-25T00:12:30Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/issues/794
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: high
type: bug
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 1〜3 の土台。いまは PreviewTargetResolver が選択・行・一覧の着地状況から本文の表示を導いており、行が無いと .folder に倒れる。GitHub #794（ツリー表示の Quick Open で本文に一覧が一瞬重なる）はここで直る。既存の入口の挙動（フォルダーに入ったときの自動選択など）は変えず、意図の書き手を既存の入口へ配線するだけにとどめる。挙動の変更は (b)〜(e) で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 窓ごとの意図（文書 URL かフォルダー URL）を 1 つの値で持ち、PreviewTarget はそこからだけ導かれる（選択・行・hasLoadedEntries・isListingCurrent を材料にしない）
- [ ] #2 サイドバーの同期処理（一覧の再読み込み・展開と折りたたみ・レイアウト切り替え・不可視ファイル切り替え・フォルダー移動の後追い）からは意図を書けない構造になっている（書き込み口に届かない、または必須引数で入口を区別する）
- [ ] #3 ツリー表示・リスト表示の両方で、Quick Open から畳まれたサブフォルダー内／別フォルダー／同じフォルダーの行の無いファイルへ切り替えたとき、PreviewTarget の遷移に .folder が一度も現れないことを、子リストの取得をゲートで止めたテストで確かめる。修正を戻すとそのテストが落ちることも確かめる
- [ ] #4 開いているファイルの名前変更の後、再読み込みの着地で PreviewTarget が .folder を通らない（テストで確かめる）
- [ ] #5 .undetermined を残すか消すかを決め、理由を Notes に残す
- [ ] #6 実機で、ツリー表示の ⌘P から畳まれたサブフォルダー内のファイルを開いても、フォルダー一覧が重ならない
<!-- AC:END -->
