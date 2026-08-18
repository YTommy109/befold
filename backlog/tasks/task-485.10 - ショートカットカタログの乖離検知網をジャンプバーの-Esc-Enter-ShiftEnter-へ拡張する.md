---
id: TASK-485.10
title: ショートカットカタログの乖離検知網をジャンプバーの Esc / Enter / Shift+Enter へ拡張する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-17 14:03'
updated_date: '2026-08-18 05:24'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 744000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

TASK-503 で作ったカタログ↔実装の乖離検知網が、ジャンプバーへ拡張されていない。dev ビルドのジャンプバーは Esc / Enter / Shift+Enter に反応する（`viewer-src/keyboard.ts:69-96`）が、`ViewerShortcutCatalog`（`BefoldApp/befold/App/ViewerShortcutCatalog.swift:48`）は Esc を find の閉じる（.findClose）としてしか載せず、Enter / Shift+Enter のジャンプ移動はカタログにも `viewerShortcutCatalog.test.js` にも無い。jest のクロスチェックは `resolveBarCloseKey(key, "find", ...)` しか固定していない。

結果、ヘルプ > キーボードショートカットは Esc の説明を誤り、ジャンプキーを載せず、今後ジャンプキーの挙動を変えてもテストが落ちない——検知網が捕まえるはずの言語間乖離そのもの。カタログ側にゲート機構は無く（`HelpShortcutSections.swift:16-26`）、省略を意図と記録したタスクノートも無い。

注意: FeatureGate との整合（開発中機能のショートカットを stable のヘルプへ出すか）は TASK-485.8 の判断と揃えること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 カタログがジャンプバーの Esc / Enter / Shift+Enter を記載する（FeatureGate との整合方針込み）
- [x] #2 jest クロスチェックがジャンプ側のキー解決（resolveBarCloseKey の jump 系 / resolveJumpNavigationKey）も固定する
- [x] #3 ヘルプのショートカット一覧の表示が実装と一致する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerShortcutCatalog を scrollItems / findOnlyItems / documentJumpItems の 3 リテラルに分け、items(isDocumentJumpEnabled:) と section(isDocumentJumpEnabled:) で切り替える（485.8 と同じくデフォルト引数を付けない）
2. Expectation に barClose / jumpNext / jumpPrev を追加。ゲート開では Esc の説明を findClose から barClose（検索・ジャンプ両方を閉じる）へ差し替える
3. ShortcutKey.display(ofViewerKey:) に Enter -> Return を追加（既定の uppercased だと ENTER になる）
4. Localizable.xcstrings に barClose / jumpNext / jumpPrev の en/ja を追加（近縁キーの隣に挿入、全体ソートはしない）
5. HelpShortcutSections.all(isDocumentJumpEnabled:) へ変更し、KeyboardShortcutsView が FeatureGate.isDocumentJumpEnabled を渡す。localizationKeys は両系統の全キーを含める
6. jest 側パーサを配列名ごとの分割に変え、documentJumpItems を resolveBarCloseKey('jump') / resolveJumpNavigationKey へ通す。ジャンプに反応するキーの網羅も candidates で押さえる
7. Swift 側の件数固定をゲート ON/OFF 双方に拡張し、swift test / jest / swiftlint 差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FeatureGate との整合は TASK-485.8 の判断（ゲート閉ではジャンプ機能を露出しない）に揃えた。カタログを scrollItems / findOnlyItems / documentJumpItems の 3 リテラルに分け、items(isDocumentJumpEnabled:) がゲート閉なら findOnlyItems（Esc=検索バーを閉じる）、開なら documentJumpItems（Esc=検索バー・ジャンプバーを閉じる / Return=次の目印へ / ⇧Return=前の目印へ）を足す。Esc は併記せず入れ替える（併記すると一覧に Esc が 2 行出て実装と食い違う）。デフォルト引数は付けない（485.8 と同じ理由）。ShortcutKey.display(ofViewerKey:) に Enter -> Return を追加（既定の uppercased() だと ENTER と表示される）。

検証（実測）: jest の viewerShortcutCatalog.test.js を 10 件へ拡張し全パス。カタログから jumpNext の行を落とすと 3 件（パース件数・向き解決・ジャンプキーの網羅）が落ちることを実測。swift test 1639 件パス（LocalizationTests が新規 3 キーの en/ja を検証、ViewerShortcutCatalogTests がゲート ON/OFF 双方の件数と Esc 入れ替えを固定）。swiftlint は origin/main の git archive 展開ツリーとの差分ゼロ（54 件のまま、真の新規なし）。oxlint --type-aware / oxfmt / markdownlint いずれもクリーン。docs/dev/native-app-design.md の該当行にゲート挙動を追記。

補足: swift test の 1 回目が TASK-485.8 の Notes と同じ 'Attempted to read an unowned reference' で落ちたが、再実行で 1639 件パス。本変更とは無関係な stale ビルド生成物。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ショートカットカタログの乖離検知網をジャンプバーへ拡張した。ゲート開ではカタログが Esc（検索・ジャンプ両方を閉じる）/ Return / ⇧Return を載せ、ゲート閉では従来どおり Esc（検索バーのみ）に留めて TASK-485.8 の非露出方針に揃えた。jest 側は配列名ごとにパースして resolveBarCloseKey('jump') と resolveJumpNavigationKey へ通し、ジャンプに反応するキーの網羅も押さえる。jest 10 件・swift test 1639 件パス、行を落とすと 3 件落ちることを実測、swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
