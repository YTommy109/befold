---
id: TASK-502
title: Help > 機能説明の内容を現在の機能に合わせて更新する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 10:52'
updated_date: '2026-08-17 14:52'
labels:
  - chore
dependencies: []
priority: medium
type: chore
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help > 機能説明（BefoldApp/befold/App/FeatureOverviewView.swift:18-28）が挙げているのは livePreview / tabs / bookmarks / quickOpen / hiddenFiles / sourceToggle の 6 項目のみで、その後に入った機能が反映されていない。未掲載の例: git 差分表示、文書内検索、フォルダーサイドバー、QuickLook 拡張、befold CLI、対応フォーマット（Mermaid 以外の Markdown / SVG / HTML / CSV・TSV / 画像 / PDF / ソースコード）。

現在の機能一覧の情報源は docs/dev/native-app-design.md（単一の情報源）と CHANGELOG.md。FeatureGate で止めている機能は掲載しないこと（リリースノート生成と同じ基準）。

Help メニューの他のパネル（キーボードショートカット / AI 連携）も同時に内容が現状と合っているか確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 docs/dev/native-app-design.md と CHANGELOG.md を突き合わせ、機能説明に載せるべき項目の一覧が Implementation Notes に記録されている
- [x] #2 FeatureOverviewView の項目が現在の機能に合わせて更新され、FeatureGate 配下の未公開機能は含まれていない
- [x] #3 追加・変更した文言が Localizable.xcstrings に日英そろって登録されている（キー順にソートし直さない）
- [x] #4 LocalizationTests が通り、翻訳漏れがないことを確認している
- [x] #5 Help > キーボードショートカット / AI 連携パネルの内容も現状と一致するか確認し、ずれがあれば直すか別タスクとして起票している
- [x] #6 実機で Help > 機能説明を開き、更新後の内容が表示されることを確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（/review-design）と方針確認を経た最終案。

方針: 機能説明の説明文にはキー表記を一切載せない。ショートカットは Help > キーボードショートカット
（MenuShortcutCatalog がメニュー定義から生成する）が単一の情報源で、そちらに集約する。
これにより「文言だけが古くなる」乖離（TASK-240 と同じ型）が構造的に起きなくなり、
ブックマークだけが持っていた %@ 差し込み機構（FeatureOverviewView.bookmarksDetail）も不要になる。

項目は 8 つ（主力のみ）:
1. 対応フォーマット（Mermaid / Markdown / SVG / HTML / CSV・TSV / 画像 / PDF / ソースコード）
2. リアルタイムプレビュー（ファイル監視して自動再描画）
3. 表示モード切替（レンダリング / ソース / 差分、ファイルごとに記憶）
4. git 連携（サイドバーのステータス表示・差分の重ね表示・変更ファイルのみ表示）
5. サイドバー（ツリー/リスト表示、不可視ファイル、キーボード操作）
6. 検索と Quick Open（文書内検索、パスのあいまい検索）
7. タブとセッション復元（ブックマーク・戻る/進むを含む）
8. CLI と QuickLook（befold コマンド、Finder の Space プレビュー）

担保（破れたら落ちるもの）:
- LocalizationTests の「ブックマークの説明文はキー表記を直書きしない」を全 featureOverview.*.detail へ
  一般化し、⌘/⌃/⌥/⇧ が含まれたら落ちるようにする。個別キーの特例ではなくパネル全体の規約にする。

設計レビューのチェック結果:
- 1 判定の真実の源: 新しい述語を作らない（静的な説明文の差し替えのみ）。該当なし。
- 2 既存の不変条件: 触らない。BookmarkShortcut は MainMenuBuilder 側の利用だけが残る。
- 3 消費経路: FeatureOverviewView.bookmarksDetail の呼び出し元は自身とテスト 1 件のみ（実測: rg で 3 箇所）。
- 4 新しい状態: 追加しない。
- 5 ライフサイクル: 起動時スナップショット（MenuShortcutCatalog.snapshot）への依存を新設しない方針なので順序問題なし。
- 6 高頻度経路: パネルは明示的に開いたときだけ構築される。
- 7 測るものと守るもの: 守りたいのは「説明文が実装から乖離しないこと」で、キー表記直書き禁止テストが直接それを測る。
- 8 非同期: 該当なし。
- 9 粒度: 上記テストが担保。
- 10 行数: FeatureOverviewView 54 行 → 8 項目でも 80 行程度（グループ上限 400、実測 scripts/check-type-group-size.sh）。責務は増えない（stored property もプロトコル準拠も増えない）。

手順:
1. Localizable.xcstrings に 8 項目分の title/detail を日英そろえて用意（不要になったキーは削除、既存の並び順は保つ）。
2. FeatureOverviewView を書き換え、bookmarksDetail と BookmarkShortcut 依存を削除。
3. LocalizationTests のブックマーク専用テストを全項目対象へ一般化。
4. swift test（LocalizationTests / MenuShortcutCatalogTests / MainMenuBuilderTests）。
5. xcodebuild + 実機で Help > 機能説明 を開いて確認。
6. Help > キーボードショートカット / AI 連携のずれは別タスクへ切り出す（本タスクでは直さない）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装内容:
- FeatureOverviewView の項目を 6 → 8 へ差し替えた（対応フォーマット / リアルタイムプレビュー / 表示モード切替 / git 連携 / サイドバー / 検索と Quick Open / タブとセッション復元 / CLI と Quick Look）。旧 hiddenFiles・sourceToggle は サイドバー・表示モード切替へ吸収。
- 説明文からキー表記を全廃した。ショートカットは Help > キーボードショートカット（MenuShortcutCatalog がメニュー定義から生成）に集約する。これに伴い FeatureOverviewView.bookmarksDetail(shortcut:) と BookmarkShortcut への依存を削除し、Feature.detail を String から LocalizedStringResource に戻した（%@ の差し込みが不要になったため）。
- BookmarkShortcut の doc コメントから「ヘルプの説明文が同じ値を読む」記述を落とし、現状（メニュー登録の窓口のみ）に合わせた。
- LocalizationTests のブックマーク専用テストを、featureOverview.* の全訳に対して ⌘/⌃/⌥/⇧ の直書きを禁じるテストへ一般化した。

Help の他 2 パネルの確認結果:
- キーボードショートカット: 構造上「メニューに無いのに載る」ずれは起きない（MenuShortcutCatalog がメニュー定義から生成）。ただしメニューを経由しないキー操作（ビューア内スクロール・サイドバー・Quick Open のキー、マウス/トラックパッド操作）が一切載らない。→ TASK-503 として起票。
- AI 連携: CLI 未導入だと skill が黙ってスキップされる点が説明に無く、skill の対象形式（.md/.mmd）が実際の対応形式より狭い。→ TASK-504 として起票。
- docs/dev/native-app-design.md は Help パネルの内容を扱っていない（grep で該当なし）ため、現在仕様への追随は不要。

検証:
- swift test 全件パス（1566 tests / 246 suites）。
- 新テストが実際に落ちることを確認: 訳の 1 つに ⌘P を混ぜる → 「機能説明の文言はキー表記を直書きしない」が失敗し、戻すと通る。
- swiftformat 実行後、swiftlint の main ベースライン差分は「真の新規」「解消したもの」ともに空。
- xcodebuild（Debug）成功。実機で Help > 機能説明 を開き、日本語 8 項目と英語 8 項目の表示をスクリーンショットで確認した（英語は -AppleLanguages "(en)" で起動）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help > 機能説明 の項目を現在の機能に合わせて 8 項目へ差し替え（対応フォーマット / リアルタイムプレビュー / 表示モード切替 / git 連携 / サイドバー / 検索と Quick Open / タブとセッション復元 / CLI と Quick Look）。あわせて説明文からキー表記を全廃し、ショートカットは Help > キーボードショートカット（メニュー定義から生成される）に集約した。これによりブックマークだけが持っていた %@ 差し込み機構が不要になり、実装が減ると同時に「文言だけが古くなる」乖離（TASK-240 と同じ型）が構造的に起きなくなった。担保として LocalizationTests に featureOverview.* の訳へキー表記を直書きすると落ちるテストを置き、実際に落ちることを確認済み。検証: swift test 全 1566 件パス、swiftlint の main 差分ゼロ、Debug ビルドを起動して日本語・英語の両方でパネル表示をスクリーンショット確認。Help の他 2 パネルのずれは TASK-503（メニュー外のキー操作が一覧に載らない）と TASK-504（AI 連携の CLI 前提と対応形式）へ切り出した。
<!-- SECTION:FINAL_SUMMARY:END -->
