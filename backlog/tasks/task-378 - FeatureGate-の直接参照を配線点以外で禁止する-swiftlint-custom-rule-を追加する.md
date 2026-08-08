---
id: TASK-378
title: FeatureGate の直接参照を配線点以外で禁止する swiftlint custom rule を追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:49'
updated_date: '2026-08-08 13:21'
labels: []
dependencies:
  - TASK-373
references:
  - BefoldApp/befold/App/FeatureGate.swift
priority: medium
type: chore
ordinal: 514000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。ゲート注入方針（ゲート値を引数で受ける純粋関数に切り出し OFF 側もテストする）は .claude/CLAUDE.md に明文化済みだったが、同じブランチで 3 箇所（DisplayModeStore.restoredDisplayMode / ViewerToolbarController の static 焼き込み / ViewerCapabilities.canSelectDiffMode のゲート漏れ、TASK-373）が違反した。「決めたことには、破れたら落ちるものを付ける」に従い、文書ではなく lint で強制する。

内容: `FeatureGate.` への直接参照を、FeatureGate.swift 自身と明示的に許可した配線点（composition root でゲート値を注入する箇所）以外で禁止する swiftlint custom rule（custom_rules の regex で足りるか、allowlist の持ち方を含めて設計する）。

前提: TASK-373 が直しきる前に導入すると既存違反で即赤になるため、TASK-373 完了後に導入する（依存に設定済み）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FeatureGate.swift と許可配線点以外での `FeatureGate.` 直接参照が swiftlint で検出される
- [x] #2 main とのベースライン差分ゼロ（既存違反は TASK-373 側で解消済みか、明示的に allowlist される）
- [x] #3 ルールの意図と allowlist への追加基準が .claude/CLAUDE.md に 1 段落で記載されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .swiftlint.yml に custom rule feature_gate_direct_reference を追加（included: befold/ 配下のみ = 本番ターゲット、excluded: FeatureGate.swift + 現行の配線点ファイル、severity: error）
2. allowlist の drift を防ぐため、FeatureGateEnumerationTests に .swiftlint.yml の excluded 集合と実際に FeatureGate. を参照するファイル集合が一致することを検証するテストを追加する（stale な allowlist / 先回り allowlist を落とす）
3. .claude/CLAUDE.md のフィーチャーゲート節に、ルールの意図と allowlist 追加基準を 1 段落で追記
4. 検証: swiftlint 実測（既存 0 件維持 + 意図的違反で発火すること）、swift test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: .swiftlint.yml に custom rule feature_gate_direct_reference（included: BefoldApp/befold 配下、excluded: FeatureGate.swift + 配線点 7 ファイル、severity: error）を追加。allowlist の drift 対策として FeatureGateEnumerationTests に lintAllowlistMatchesGateReferences を追加し、.swiftlint.yml の excluded 集合と実際に FeatureGate. を参照するファイル集合の一致を検証する（stale なエントリも先回り追加も落ちる）。

設計判断: 既存の enumerationCoversEveryGateReference は「参照したら doc コメントに列挙せよ」という申告制で、TASK-373 の 3 件はいずれも列挙済みのまま違反していた（申告すれば直読みできる）。lint は allowlist 編集という別の摩擦を課すので上乗せの価値がある。判定はコメント中の言及も含む substring とし、列挙テストと同一セマンティクスに揃えた（match_kinds で識別子に絞ると 2 つの機構で判定がずれ、cross-check が成立しなくなるため）。

実測で判明した罠: included を 'befold/...' と書くとワークツリーのディレクトリ名が befold のため絶対パス全体が一致し、befoldTests まで対象に入って 21 件発火した。'BefoldApp/befold/...' へアンカーして解消。

検証（実測）:
- swiftlint 全体実行で feature_gate_direct_reference の違反 0 件。
- DisplayModeStore.swift に FeatureGate.isSourceDiffEnabled のコメント 1 行を注入すると error として発火することを確認（TASK-373 の違反箇所そのもの）。revert 済み。
- allowlist に実在しないエントリ（Bogus.swift）を足すと lintAllowlistMatchesGateReferences が失敗することを確認。revert 済み。
- swift test --skip Integration --skip FileWatcherTests: 1122 tests / 155 suites 成功。
- swiftlint ベースライン: origin/main と現ブランチともに 78 件・error 0 件で、行数の数値差（本タスク非関与ファイルのブランチ差分）を除き完全一致。
- markdownlint-cli2: 0 issues。scripts/check-doc-symbols.sh: OK。

補足（別件・未対応）: check-doc-symbols.sh は func_decls() が 'func <名前>(' しか探さないため、Type.init(ラベル:) 形式の引用が実在しても必ず「宣言が見つかりません」になる。今回 PerFileStateStore.init(defaults:) を引用して踏んだため、文言を型名参照へ書き換えて回避した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FeatureGate の直接参照を配線点の allowlist に限定する swiftlint custom rule feature_gate_direct_reference を追加した（本番ターゲット befold 配下、severity: error）。allowlist が実態から乖離しないよう、.swiftlint.yml の excluded と実際のゲート参照ファイル集合の一致を FeatureGateEnumerationTests で検証する。ルールの意図と allowlist 追加基準（ゲート値を読んで下位へ引数で渡す composition root に限る）を .claude/CLAUDE.md に追記。検証は発火の実測（違反注入で error / allowlist 汚染でテスト失敗、いずれも revert 済み）、swift test 1122 件成功、swiftlint ベースライン差分ゼロ（78 件・error 0）。
<!-- SECTION:FINAL_SUMMARY:END -->
