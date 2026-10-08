---
id: TASK-682
title: 表示メニューの比較基準項目を非スタックで一度隠すと、スタック構成へ切り替えても再表示されない可能性を実測で確定する
status: Done
assignee: []
created_date: '2026-10-08 08:48'
updated_date: '2026-10-08 11:03'
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
- [x] #1 /menu-audit で「非スタックで開く → スタックへ切替 → 再度開く」の順に実測し、結果(再現する/しない)を Notes に残す
- [x] #2 再現した場合、スタック構成へ切り替えた後の表示メニューに「スタック全体の変更」が出る(isHidden の書き換えが validate の外にあるか、隠す代わりに無効化する)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測(2026-10-08): AppKit は isHidden=true の NSMenuItem にも NSMenu.update() で validateMenuItem を呼ぶ。最小ハーネス(autoenablesItems=true のメニューに hidden な項目 1 つ、target に validateMenuItem の呼び出し回数を数えさせる)で update() 後に calls=1 を確認。よって validate 内の isHidden 書き換えで一度隠れた項目が再表示されなくなる経路は無く、再現しない。見送り。限界: /menu-audit の実アプリ(スタック構成のリポジトリを用意する手順)ではなく NSMenu 単体での実測。実メニューバー経由も同じ NSMenu.update を通る前提。

/menu-audit 手順で実アプリを実測(2026-10-08、Debug ビルド、AX ダンプ)。リポジトリ: main ← feat-a ← feat-b、.git/gh-stack にスタック定義、a.md に未コミット変更。(1) 非スタックの solo ブランチで表示 > 比較基準を開く → 「このブランチの変更」(✓)と「作業中の変更」のみ(スタック全体は隠れている)。(2) feat-b へ切替(checkout -f)→ (3) 再度開く → 「このブランチの変更」(✓)/「スタック全体の変更」/「作業中の変更」の 3 項目で、「スタック全体の変更」が再表示された。結果: 再現しない。先に行った NSMenu 単体ハーネスでも AppKit は hidden 項目に validateMenuItem を呼ぶと確認済み(補強)。コード変更なし、見送り。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
実アプリで再現せず見送り。非スタック→スタック切替後も「スタック全体の変更」が再表示される。AC#2 は再現時のみ適用のため対象外(再現しないことを実測で確認済み)。
<!-- SECTION:FINAL_SUMMARY:END -->
