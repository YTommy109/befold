---
id: TASK-438.2
title: git が使えないとき差分表示モードを選択不可にする
status: To Do
assignee: []
created_date: '2026-08-13 14:00'
labels:
  - git
dependencies:
  - TASK-438.1
parent_task_id: TASK-438
priority: medium
ordinal: 671200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-438 の決定（論点 2: ADR どおりに実装する）の実装。ADR の記述は変えず、実装を追随させる。

## 現状の乖離

ADR（libgit2 移行）の Fallback 節は縮退の 1 つとして「差分表示モードを選択不可にする（既存の「管理外」扱いと同じ）」を挙げているが、**未実装**。

- ViewerCapabilities.swift:70 の canSelectDiffMode は onDocument && !isBinaryContent && supportsDiffDisplay で決まり、**git の可用性を見ていない**（ファイル種別のみ）
- 結果、モードは選べる。ViewerDiffPresenter.refresh()（:87-110）がゲートを通ってから取得し、displayableDiff(_:)（:117-120）が .diff(text) 以外（nil 含む）を nil に畳んで**黙って通常のソース表示へ戻す**

## 論点（実装着手前に決めること）

**canSelectDiffMode は同期的に計算される値だが、git の可用性はリポジトリ解決が絡む非同期の値**。素直に足すと初期表示で「一瞬選べる → 選べなくなる」（またはその逆）が起きうる。次を設計レビューで確定させること。

- 未解決（まだ分からない）と解決済みで使えないを、能力の導出でどう扱うか。ADR 0002 の「能力は状態から導出する」設計に沿った形にする
- ゲート対象の範囲。差分は FeatureGate.isSourceDiffEnabled 配下（dev 限定）なので、stable の挙動は変わらない

## 注意

FeatureGate 配下のコードを変更する commit には (gate) スコープを付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git が使えないリポジトリで差分表示モードが選択不可になっている
- [ ] #2 ViewerCapabilities.canSelectDiffMode が git の可用性を見ている
- [ ] #3 可用性が未解決の間の扱いが決まっており、初期表示で選択可否が意図せず入れ替わらない
- [ ] #4 選択不可になることがテストで固定されている
<!-- AC:END -->
