---
id: TASK-485.31
title: ジャンプの無い表示で「ジャンプ…」が検索と同じ動作になり、バーには「検索」だけのスイッチが出る
status: To Do
assignee: []
created_date: '2026-09-25 09:12'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerMenuValidator.swift
  - BefoldApp/viewer-src/bar-mode.ts
parent_task_id: TASK-485
priority: low
type: enhancement
ordinal: 832000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.26 で見出しジャンプを Markdown だけにし、TASK-485.28 で cmd+shift+F を「使えるジャンプが無ければ検索」にした(2026-09-25 のコードレビューで検出)。この組み合わせで、mmd・JSON・YAML・HTML・SVG・CSV/TSV・定義ジャンプ未対応の言語など多くの表示に次の 2 点が生じる。
- Edit > ジャンプ…(cmd+shift+F)が有効なまま表示され、押すと Edit > 検索…(cmd+F)と同じことをする。項目名からは検索が開くと分からない。`ViewerMenuValidator.validateDocumentJumpItem` は `canFind` を返すため、グレーアウトもしない
- 統合バー上段のモード切替スイッチ(`bar-mode.ts` の `updateSwitchAppearance`)が「検索」1 つだけのセグメントを出す。以前は見出しがどの表示でも使えたので、選択肢は常に 2 つ以上あった。選択肢が 1 つのスイッチは押しても何も変わらない
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ジャンプの無い表示で Edit > ジャンプ… をどう見せるか(無効化 / 検索へ倒すことを項目名で示す / 現状維持)を決め、その根拠を Notes に残す
- [ ] #2 選べるモードが検索だけのとき、モード切替スイッチを出すかどうかを決め、出さないなら jest で固定する
<!-- AC:END -->
