---
id: TASK-214
title: docs/dev の実装と矛盾する記述を修正する（code-review 指摘の高優先分）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 03:12'
updated_date: '2026-07-31 08:13'
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
- [x] #1 cli-launch.md の Step 6 とフローチャートが「パス指定なし・デフォルトオプション時は forward しない」実装どおりの分岐を記述している
- [x] #2 viewer-rendering-dataflow.md の 3 分類表に行指向テキストの 100MB 上限が明記されている
- [x] #3 native-app-design.md の技術スタック表の SPM 行が実際のターゲット構成と一致している
- [x] #4 native-app-design.md のテストツリーで QuickLook 関連テストの帰属先が実際のターゲットと一致している
- [x] #5 BundleAccessor（SPM/Xcode 両ビルドのリソースバンドル解決）の説明が native-app-design.md に復元されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実装を読んで5件の現状を確認する（CLIAppLauncher.run / ViewerLoadPipeline + NormalizedTextCache / Package.swift / befoldTests・befoldCLITests の実ファイル / BundleAccessor.swift）
2. cli-launch.md: Step 6 を「コールドローンチ後、paths 空かつオプション既定なら forward せず 0 で終了。それ以外はポーリングして forward」に修正し、mermaid フローチャートにも同分岐を追加
3. viewer-rendering-dataflow.md: 3 分類表の行指向テキスト行のサイズ上限を 100MB（NormalizedTextCache.maxFileSizeBytes）と明記
4. native-app-design.md: 技術スタック表の SPM 行を実際の 8 ターゲット構成に更新（この行のみ変更）
5. native-app-design.md: テストツリーの befoldTests / befoldCLITests のコメントを実際の帰属に修正
6. native-app-design.md: BefoldKit ツリーに BundleAccessor.swift（SPM/Xcode 両ビルドのリソースバンドル解決）を復元
7. 各 AC を検証してコミット（docs:）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: (1) CLIAppLauncher.run の guard !paths.isEmpty || options != CLIOpenOptions() else { return 0 } を確認し Step 6/7 とフローチャートの分岐を実装に一致させた。(2) ViewerLoadPipeline.swift の isChunkable 時の上限が NormalizedTextCache.maxFileSizeBytes、同 15 行で 100MB、超過時 .fileTooLarge を確認。(3) Package.swift のターゲット宣言 8 件（BefoldCLI/BefoldKit/BefoldRenderKit/befold/befold-cli/BefoldTestSupport/befoldTests/befoldCLITests）と一致させた。(4) ViewerRendererOneShotTests/RendererFeaturesTests/QuickLookBadgeTests が befoldTests/、befoldCLITests/ には QuickLookInfoPlistTests のみを確認。(5) BefoldApp/BefoldKit/BundleAccessor.swift が現存し SWIFT_PACKAGE で .module / それ以外で Bundle(for:) を返すことを確認しツリーに復元。ドキュメントのみの変更のためビルド/テストへの影響なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/dev の実装と矛盾する 5 件を修正した。cli-launch.md はコールドローンチ後に引数がなければ転送しない分岐を Step とフローチャートへ反映、viewer-rendering-dataflow.md は行指向テキストの 100MB 上限を明記、native-app-design.md は SPM 8 ターゲット構成・QuickLook テストの帰属先・BundleAccessor.swift の説明を修正/復元。各項目は該当 Swift ソースと Package.swift、テストディレクトリの実ファイルを読んで確認した（実装側は未変更）。
<!-- SECTION:FINAL_SUMMARY:END -->
