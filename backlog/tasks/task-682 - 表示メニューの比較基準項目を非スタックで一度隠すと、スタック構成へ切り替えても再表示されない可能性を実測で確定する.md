---
id: TASK-682
title: 表示メニューの比較基準項目を非スタックで一度隠すと、スタック構成へ切り替えても再表示されない可能性を実測で確定する
status: To Do
assignee: []
created_date: '2026-10-08 08:48'
labels:
  - bug
dependencies:
  - TASK-680
priority: low
ordinal: 871000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high(2026-10-08、TASK-679 の差分)の指摘。ViewerMenuValidator.validateDisplayModeItem が validate の中で NSMenuItem.isHidden を書き換えている。AppKit が hidden な項目にも validateMenuItem を回すことを前提にしており、回さない場合は一度隠れた「スタック全体の変更」が二度と現れない。

**未確認**: AppKit が hidden な NSMenuItem に対して validateMenuItem を呼ぶかどうかはレビュー時点で実測していない。呼ぶなら本件は不要で、タスクは「実測結果を Notes に残して見送り」で閉じる。

**再現手順(実測用)**: 非スタック状態で表示メニューを 1 回開く(.defaultBranch が isHidden=true になる)→ スタック構成のブランチへ切り替える(resolution.parentDiffersFromDefault=true)→ もう一度表示メニューを開く。サイドバーの ▾ には「スタック全体の変更」が出るのにメニューには出なければ再現。/menu-audit でこの順に測る。

再現したら、隠す判定を validate の外(メニューを開く直前の NSMenuDelegate.menuNeedsUpdate 等)へ移すか、隠さず無効化(isEnabled=false)に倒す。TASK-680 で選択肢の導出を 1 本化するので、その後に測るほうが二度手間にならない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /menu-audit で「非スタックで開く → スタックへ切替 → 再度開く」の順に実測し、結果(再現する/しない)を Notes に残す
- [ ] #2 再現した場合、スタック構成へ切り替えた後の表示メニューに「スタック全体の変更」が出る(isHidden の書き換えが validate の外にあるか、隠す代わりに無効化する)
<!-- AC:END -->
