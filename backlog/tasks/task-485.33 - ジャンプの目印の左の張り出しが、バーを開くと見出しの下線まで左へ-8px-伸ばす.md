---
id: TASK-485.33
title: ジャンプバーを開くと見出しの下線が左へ 8px 伸びる
status: To Do
assignee: []
created_date: '2026-09-25 09:12'
updated_date: '2026-09-25 09:12'
labels: []
dependencies: []
references:
  - BefoldApp/BefoldKit/Resources/style.css
parent_task_id: TASK-485
priority: low
type: bug
ordinal: 834000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.27 のコードレビュー(2026-09-25)で検出。`style.css` の `.mmd-jump-target:not(td), .mmd-jump-current:not(td)` は、縦バーと文字の間を空けるために `padding-left: 8px; margin-left: -8px` を付ける。ジャンプバーを開いている間は、レンダリング表示のすべての見出し(h1〜h3)にこのクラスが付く。
github-markdown-css の h1 / h2 は `border-bottom` を持つので、バーを開くと下線が左へ 8px 伸び、閉じると戻る。文字の位置は動かないが、下線は開閉のたびに動く。加えて、この規則は見出しが元々持つ `padding-left` / `margin-left` を上書きする(引用やリストの中の見出し、利用者の HTML で字下げした見出しなど)。アプリでの目視確認は未実施(TASK-485.28 の Notes)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ジャンプバーの開閉で、レンダリング表示の見出しの下線と字下げの位置が変わらない(実機で確認)
- [ ] #2 現在位置の縦バーと文字の間には従来どおり間隔がある
<!-- AC:END -->
