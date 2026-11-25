---
id: TASK-930.7
title: 一覧を出しているフォルダーが消えたときの本文とタイトルを決める
status: To Do
assignee: []
created_date: '2026-11-25T13:14:00Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 869000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25、重要度 important)。本文がフォルダー X の一覧を出している間に X が削除・改名されると、取り直しで選択は外れるが意図は .folder(X) のまま残り、本文は存在しないディレクトリの一覧(失敗表示)、窓のタイトルは X のままになる。ADR 0013 以前は開いている文書へ戻っていた。注意: TASK-930.1 の Implementation Plan 7(c) と Notes で「フォルダーが消えても本文を文書へ戻さず一覧の失敗表示のままにする」と意図して決めている(サイドバーの同期は意図を書かない = ADR 0013 決定 3)。直すなら、サイドバーではなく窓が事実(フォルダーが存在しない)を見て意図を書き直す形にする必要がある。挙動の判断が要るため、着手前にユーザーへ方針を確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォルダーが消えたときの本文の挙動(失敗表示のまま / 文書へ戻る / 親フォルダーの一覧へ移る)をユーザーと決め、Notes に記録している
- [ ] #2 決めた挙動を、サイドバー側の型に意図を書く口を与えずに実装している
- [ ] #3 削除と改名の両方をテストで確かめ、修正を戻すと落ちることを確かめている
<!-- AC:END -->
