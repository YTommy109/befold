---
id: TASK-383
title: 'check-doc-symbols.sh が Type.init(ラベル:) 形式の引用を常に未検出とする問題を直す'
status: Done
assignee: []
created_date: '2026-08-08 13:24'
updated_date: '2026-08-08 13:34'
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
- [x] #1 Type.init(ラベル:) 形式で実在するイニシャライザを引用したとき check-doc-symbols.sh が通る
- [x] #2 実在しない引数ラベルの Type.init(...) 引用は検出されて落ちる
- [x] #3 --self-test に init の通過例と検知例が追加され、scripts/check-doc-symbols.sh --self-test が成功する
- [x] #4 .claude/CLAUDE.md のゲート注入の記述を PerFileStateStore.init(defaults:) 形式へ戻しても通ることを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
func_decls() を member=init のとき別パターンへ分岐させた。行頭 + アクセス修飾子(public/private/required/convenience/override 等)のみを前置として許す正規表現で宣言だけを拾い、rg -r '$1' で修飾子を落として `init(...)` に正規化する（呼び出し側の `Foo.init(` / `self.init(` は行頭一致しないため拾わない）。ラベル一致判定 labels_match はそのまま流用し、ラベルなし `Type.init()` と、括弧なし `Type.init`（member_exists 経由）も init 用の分岐を足した。self-test に `PerFileStateStore.init(defaults:)`（通過）と `PerFileStateStore.init(nonexistentLabel:)`（検知）を追加。検証: scripts/check-doc-symbols.sh --self-test → OK / scripts/check-doc-symbols.sh → exit 0 / markdownlint-cli2 → 0 issues。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
check-doc-symbols.sh の func_decls() をイニシャライザ宣言に対応させ、Type.init(ラベル:) 形式の引用が常に偽陽性になる問題を解消した。self-test に init の通過例・検知例を追加し、.claude/CLAUDE.md のゲート注入の記述を PerFileStateStore.init(defaults:) 形式へ戻した。--self-test OK、既定実行 exit 0 で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
