---
id: TASK-485.19.2
title: バーのDOM/CSSを1つに統合しモード切替スイッチを追加する
status: To Do
assignee: []
created_date: '2026-08-21 09:12'
labels: []
dependencies:
  - TASK-485.19.1
parent_task_id: TASK-485.19
priority: high
ordinal: 776000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer.html の #mmd-find-bar / #mmd-jump-bar を単一の #mmd-bar コンテナへ再構成し、
モード切替スイッチ（検索/見出し/変更箇所）を追加する。このサブタスクでは見た目と
スイッチのクリックで表示領域が切り替わることまでを対象とし、検索・ジャンプの
既存ロジック（find.ts / jump.ts）への結線は次のサブタスクで行う。

対象:
- viewer.html:43-78 の #mmd-find-bar / #mmd-jump-bar 統合
- style.css:644-654 の .mmd-find-toggles 絶対配置前提の見直し
  （入力欄を持たないモードと同居させても崩れないレイアウトにする）
- モードごとの固有入力領域だけを差し替える
  （検索: 入力欄+Aa/ab|/.*トグル、見出し: レベルトグル、変更箇所: なし）
- 件数表示・前へ/次へ・閉じるは共通のまま
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 検索/見出し/変更箇所を切り替えるモード切替スイッチが1つのバーに存在する
- [ ] #2 モードごとに固有の入力領域だけが表示され、共通要素（件数・前後・close）は1つを共有する
- [ ] #3 見た目の統合によりレイアウト崩れが無いことを実機確認している
<!-- AC:END -->
