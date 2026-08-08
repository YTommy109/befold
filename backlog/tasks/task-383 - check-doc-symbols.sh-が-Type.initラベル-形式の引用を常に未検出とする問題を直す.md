---
id: TASK-383
title: 'check-doc-symbols.sh が Type.init(ラベル:) 形式の引用を常に未検出とする問題を直す'
status: To Do
assignee: []
created_date: '2026-08-08 13:24'
labels: []
dependencies: []
references:
  - scripts/check-doc-symbols.sh
  - scripts/doc-symbol-allowlist.txt
  - BefoldApp/befold/App/PerFileStateStore.swift
priority: low
type: chore
ordinal: 640000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-378 の作業中に踏んだ、規約文書チェッカーの誤検知（偽陽性）。

scripts/check-doc-symbols.sh の func_decls() は `func <名前>(` にマッチする正規表現でしか宣言を探さないため、イニシャライザは `init(...)` と宣言されていて `func` が付かない。結果、Type.init(ラベル:) 形式の引用は実在していても必ず「<名前> の宣言(引数ラベル ...)が見つかりません」で落ちる。

再現: .claude/CLAUDE.md に `PerFileStateStore.init(defaults:)` と書いて scripts/check-doc-symbols.sh を実行する。宣言は BefoldApp/befold/App/PerFileStateStore.swift:17 に `init(defaults: UserDefaults = .standard)` として実在するが検出されない。TASK-378 では文言を型名参照へ書き換えて回避した（allowlist へは入れていない。allowlist は「架空名・外部 API」用であり、実在シンボルを入れると陳腐化検知が効かなくなるため）。

影響は誤検知のみで、実在しないシンボルの見逃しは起きない。ただし FeatureGate.swift の doc コメントは PerFileStateStore.init(defaults:) 形式で露出点を列挙しており（この形式が自然）、同じ書き方を規約文書へ持ち込むたびに踏む。

対応案: func_decls() を member が init のときイニシャライザ宣言を探す形へ拡張する。ラベル一致の判定ロジック（labels_match）はそのまま使える。--self-test に init のケース（実在する init の引用が通る／実在しないラベルの引用が落ちる）を追加して、検知そのものの回帰を防ぐ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Type.init(ラベル:) 形式で実在するイニシャライザを引用したとき check-doc-symbols.sh が通る
- [ ] #2 実在しない引数ラベルの Type.init(...) 引用は検出されて落ちる
- [ ] #3 --self-test に init の通過例と検知例が追加され、scripts/check-doc-symbols.sh --self-test が成功する
- [ ] #4 .claude/CLAUDE.md のゲート注入の記述を PerFileStateStore.init(defaults:) 形式へ戻しても通ることを確認する
<!-- AC:END -->
