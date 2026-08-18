---
id: TASK-504
title: AI 連携パネルの説明を CLI 前提と対応形式に合わせる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 11:42'
updated_date: '2026-08-16 14:13'
labels:
  - chore
dependencies: []
priority: low
ordinal: 121500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help > AI コーディングエージェント連携（BefoldApp/befold/App/AIIntegrationView.swift）の説明と、同梱の skill ファイル（BefoldApp/befold/Resources/befold-review-skill.md）に、実装とずれている点が 2 つある（TASK-502 の調査で判明）。

1. skill は 'command -v befold && befold <path>' で CLI が入っていなければ黙ってスキップする作り（befold-review-skill.md:21-22）だが、画面の説明（Localizable.xcstrings の aiIntegration.detail）にも UI にも「CLI が必要」という記載が無く、App メニューの「コマンドラインツールをインストール」（MainMenuBuilder.swift:52）への導線も無い。CLI 未導入のユーザーは、skill を保存しても何も起きない理由が分からない。
2. skill の対象が .md / .mmd に限定されている（befold-review-skill.md:5,11）が、実際の befold は SVG / HTML / CSV・TSV / 画像 / PDF / ソースコードにも対応している（BefoldApp/BefoldKit/FileType.swift）。エージェントに見せられる範囲を実力より狭く書いている。

なお skill 本体を英語のまま置くのは意図的な判断（AIIntegrationView.swift:4-7）なので、これは変えない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI が必要であることと、未導入時の導線（App メニューのコマンドラインツールをインストール）が画面から分かる
- [x] #2 skill ファイルの対象形式が実際の対応形式と食い違わない記述になっている
- [x] #3 skill 本体は英語のまま（画面の説明のみ日英そろえる）
- [x] #4 追加・変更した文言が Localizable.xcstrings に日英そろって登録され、LocalizationTests が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. skill ファイル（befold-review-skill.md）の front matter description と When to use を、befold が実際に対応する形式（Markdown / Mermaid / SVG / HTML / CSV・TSV / 画像 / PDF / ソースコード）に合わせて書き直す。英語のまま。
2. AIIntegrationView に「befold CLI が必要」であることと、未導入時は App メニュー > コマンドラインツールをインストール から入れられることを示す注記を追加する（新規 l10n キー aiIntegration.cliRequired、日英）。
3. HelpPanelResourceTests に skill の対象形式記述を固定するテストを足すか検討。
4. swift build / swift test / swiftlint ベースライン差分を確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: (1) AIIntegrationView に CLI 前提の注記ブロック（aiIntegration.cliRequired, 日英）を説明文とコピーボタンの間へ追加し、App メニュー > コマンドラインツールをインストール への導線を明記した。(2) befold-review-skill.md の front matter description と When to use を、実際の対応形式（.md/.mmd/.svg/.html/.csv/.tsv/画像/PDF/ソース）に合わせて書き直し、Requirements 節で befold CLI が要ることを明示した（英語のまま）。(3) aiIntegration.detail が 'Markdown or Mermaid' に限定していた記述も日英とも一般化した。

担保: HelpPanelResourceTests に 'skill が挙げる拡張子はすべて befold が扱える形式' を追加（skill 本文から拡張子らしい綴りを抽出し FileType.isSupported で検査）。このテストは実際に働いており、最初の版で書いた 'befold.app' を未対応拡張子 .app として検出して落ちた（そのため 'the befold app' へ書き換えた）。

検証: swift test --skip Integration --skip FileWatcherTests で 1474 tests / 226 suites すべて成功（LocalizationTests の全キー en/ja 検査を含む）。swiftlint は origin/main 展開ツリーとの差分で真の新規ゼロ・解消ゼロ。swiftformat --lint は全ターゲット 0 files require formatting。markdownlint-cli2 は 0 issues。

未実施: パネルの実描画確認。ImageRenderer では body の ScrollView が空画像になるため測れず（実測: 560x620 が全面白）、外観確認はリリース前の手動チェックに委ねる。docs/dev/native-app-design.md にはこのパネルの記述が無いため更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI 連携パネルに befold CLI が前提であることと App メニューからの導入導線を明記し、同梱 skill の対象形式を befold の実際の対応形式へ合わせた。skill が挙げる拡張子を FileType.isSupported で検査するテストで担保し、swift test 1474 件成功・swiftlint 新規ゼロ・swiftformat/markdownlint クリーンを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
