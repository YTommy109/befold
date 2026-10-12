---
id: TASK-701
title: CLI から行番号・アンカーを指定して開けるようにする
status: To Do
assignee: []
created_date: '2026-10-12 13:07'
labels:
  - cli
dependencies: []
priority: low
ordinal: 890000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI は開く位置を指定できない。`befold file.md:42` や見出しアンカーで開く手段が無く、エディタ・grep 結果・エージェントの出力から直接該当箇所へ飛べない。CLIOpenOptions と CLIRequest に該当フィールドが無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 行番号を指定して開くと、開いた後にその行へジャンプする（構文は `path:LINE` か `--line <n>` かを設計で決め、パスに : を含む場合の曖昧さを扱う）
- [ ] #2 Markdown の見出しアンカー指定の要否を決め、採るなら実装、採らないなら理由を Notes に残す
- [ ] #3 本体にジャンプ手段が既にあるか（rg "jumpTo" BefoldApp/befold）を先に確認し、あれば再利用する
- [ ] #4 CLIRequestWire のテストと README/cli-launch.md の更新
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
未確認: 本体側の既存ジャンプ経路の有無。着手前に /review-design を回す。
<!-- SECTION:NOTES:END -->
