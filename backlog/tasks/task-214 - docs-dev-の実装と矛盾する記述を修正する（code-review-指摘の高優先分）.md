---
id: TASK-214
title: docs/dev の実装と矛盾する記述を修正する（code-review 指摘の高優先分）
status: To Do
assignee: []
created_date: '2026-07-31 03:12'
labels: []
dependencies: []
priority: high
ordinal: 286500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
doc/improve_doc ブランチのコミット 9a555c9 に対する高精度コードレビューで、docs/dev の記述が実装と事実レベルで矛盾する箇所が 5 件確認された（全件 CONFIRMED）。ドキュメントを信頼した開発者が存在しないコードパスを調査したり、誤ったターゲットにテストを置いたりする実害があるため修正する。

対象:
1. docs/dev/cli-launch.md:42 — Step 6 と mermaid フローチャートが「コールドローンチ後は必ずポーリングして forward する」と記述しているが、CLIAppLauncher.run はパスが空かつオプションがデフォルトの場合 guard で 0 を返し forward しない（BefoldApp/befold-cli/CLIAppLauncher.swift:92）。素の befold 起動では Distributed Notification は送信されない。
2. docs/dev/viewer-rendering-dataflow.md:52 — 「読み込み側の 3 分類」表の行指向テキスト（csv/code/markdown）のサイズ上限欄が「段階読込」のみで上限なしに読めるが、実際は ViewerLoadPipeline.load が NormalizedTextCache.maxFileSizeBytes = 100MB を適用し超過時は fileTooLarge で reject する（ViewerLoadPipeline.swift:84-92, NormalizedTextCache.swift:15）。
3. docs/dev/native-app-design.md:204 — 技術スタック表が SPM ビルドを「BefoldKit / befold / befoldTests の3ターゲット」と記述したままで、同文書内の 8 ターゲット構成ツリーおよび Package.swift と矛盾。
4. docs/dev/native-app-design.md:75 — テストツリーが QuickLook テストを befoldCLITests に帰属させているが、実際は ViewerRendererOneShotTests / RendererFeaturesTests / QuickLookBadgeTests は befoldTests/ にあり、befoldCLITests にあるのは QuickLookInfoPlistTests のみ。
5. docs/dev/native-app-design.md:54 — 旧ツリーから削除された BundleAccessor.swift（SPM/Xcode 両ビルドでのリソースバンドル解決）の説明がどこにも残っておらず、現存するファイルと不変条件のドキュメントが失われた。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cli-launch.md の Step 6 とフローチャートが「パス指定なし・デフォルトオプション時は forward しない」実装どおりの分岐を記述している
- [ ] #2 viewer-rendering-dataflow.md の 3 分類表に行指向テキストの 100MB 上限が明記されている
- [ ] #3 native-app-design.md の技術スタック表の SPM 行が実際のターゲット構成と一致している
- [ ] #4 native-app-design.md のテストツリーで QuickLook 関連テストの帰属先が実際のターゲットと一致している
- [ ] #5 BundleAccessor（SPM/Xcode 両ビルドのリソースバンドル解決）の説明が native-app-design.md に復元されている
<!-- AC:END -->
