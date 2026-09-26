---
id: TASK-485.16
title: 文書内ジャンプのフィーチャーゲートを外して stable に載せる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 05:42'
updated_date: '2026-09-26 06:33'
labels:
  - feature-gate
milestone: m-6
dependencies:
  - TASK-485.19
  - TASK-485.31
  - TASK-485.32
  - TASK-485.34
parent_task_id: TASK-485
type: chore
ordinal: 755000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

文書内ジャンプ（TASK-485）は `FeatureGate.isDocumentJumpEnabled` で dev / DEBUG ビルドにだけ
露出している（`BefoldApp/befold/App/FeatureGate.swift:37`）。`FeatureGate` の doc コメント自身が
「stable 昇格時は該当機能の分岐を撤去してデフォルト有効化すること（撤去タスクを backlog 登録）」と
定めており、その撤去タスクがこれにあたる。

安定稼働を確認したうえでゲートを外し、stable ビルドでも見出し・変更ブロック・関数定義の
ジャンプが使えるようにする。

## 撤去対象（実測: `rg 'isDocumentJumpEnabled'`）

プロダクトコード 6 ファイル:

- `App/FeatureGate.swift:14-16, 37` — 名前付きプロパティと doc コメントの節
- `App/ViewerCapabilitiesFactory.swift:42`
- `App/MainMenuCoordinator.swift:71`
- `App/MainMenuBuilder.swift:23-30, 40, 125, 159` — 引数と `if isDocumentJumpEnabled` 分岐
- `App/HelpShortcutSections.swift:28-30` / `App/ViewerShortcutCatalog.swift:72-79`（`findOnlyItems` の要否も判断）
- `App/KeyboardShortcutsView.swift:7`
- `Viewer/ViewerCapabilities.swift:19, 58, 72, 80, 132`

テスト 7 ファイル（`MainMenuFixture` / `MainMenuBuilderTests` / `ViewerShortcutCatalogTests` /
`ViewerMenuValidatorTests` / `ViewerCapabilitiesTests` / `FeatureGateTests` /
`HelpShortcutSectionsTests`）。ゲート OFF を前提にしたケース（`MainMenuBuilderTests:267`、
`ViewerCapabilitiesTests:144, 171`、`ViewerShortcutCatalogTests` の closed 系）は
「ゲートが無くなった後に何を担保するか」を決めてから消す/書き換える。

## 判断が要る点（着手時に決めて Notes へ残す）

1. **`FeatureGate` 自体を残すか。** `isDocumentJumpEnabled` が唯一の名前付きプロパティのため、
   撤去すると `inProgressFeaturesEnabled` に呼び出し元が無くなる。TASK-510 で「最小構成で再導入」
   した経緯があるので、次の開発中機能のために枠だけ残すか、いったん消すかを明示的に決める。
2. **`ViewerCapabilities.swift:132` の `isDocumentJumpEnabled: false`。** ここは既定値として
   false を渡している箇所で、フラグを消すと `canJump` の値が変わる。何を意図した既定なのかを
   確認し、変わってよいのかを判断する。
3. **`ViewerShortcutCatalog.findOnlyItems`。** ゲート OFF 用の一覧なので、撤去後に使われなく
   なるなら一緒に消す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 stable ビルド（プレリリースでないバージョン）で編集メニューのジャンプ項目が表示され、実行できる
- [x] #2 isDocumentJumpEnabled の参照がプロダクトコード・テストの両方から消えている（rg で 0 件）
- [x] #3 上記「判断が要る点」の 3 点それぞれについて、決めた内容と理由が Implementation Notes に残っている
- [x] #4 ゲート OFF を前提にしていたテストが、削除・書き換えのどちらであれ意図を説明するコメント付きで整理されている
- [x] #5 ヘルプのショートカット一覧とメニューの乖離検知テストが通る（swift test）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FeatureGate と isDocumentJumpEnabled の配線をプロダクトコードから撤去
2. ゲート閉専用の findOnlyItems / Expectation.findClose / shortcuts.viewer.findClose を撤去
3. ゲート OFF 前提のテストを削除・書き換え（理由をコメントに残す）
4. docs/dev の現在仕様を更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 判断が要る点の決定
1. FeatureGate は型ごと削除した（FeatureGate.swift / FeatureGateTests.swift）。名前付きプロパティが isDocumentJumpEnabled だけで、撤去後は呼び出し元が 0 になる。次の開発中機能のために空の枠を残すのは推測上の需要で、復元は TASK-510 と同じく git 履歴から 1 ファイル戻すだけで済む（TASK-510 自体がその手順の実績）。
2. ViewerCapabilities.none の isDocumentJumpEnabled: false は、フラグを消しても canJump は変わらない。.none は isPresentingDocument: false なので onDocument が偽になり、canJump はゲートに関係なく false。何もできない既定値という意図はそのまま保たれる。
3. ViewerShortcutCatalog.findOnlyItems はゲート閉専用の一覧なので削除した。あわせて Expectation.findClose と Localizable.xcstrings の shortcuts.viewer.findClose も削除した（読み手 0）。items / section は引数なしの static に、HelpShortcutSections.all も static var にした。PDFFindOverlay の Esc のコメントは barClose を指すよう直した（Help の一覧は種別に関係なく出るので、PDF の Esc は「バーを閉じる」の説明と食い違わない）。

## ゲート OFF 前提だったテストの扱い
- MainMenuBuilderTests の「ゲート閉では項目を構築しない」: 担保する対象ごと無くなったので削除（理由を後継テストの doc コメントに書いた）。ゲート開のテストは名前から「ゲート開」を外して残した。
- ViewerCapabilitiesTests の「ゲート閉では不可」: 「テキストの文書を提示していれば可、バイナリでは不可」に書き換えた。
- ToggleBarCommandTests の「ジャンプ能力が無ければ検索へ倒れる」: ゲート閉の代わりにバイナリ（PDF 相当。検索はできるがジャンプはできない）で同じ経路を担保した。
- ViewerShortcutCatalogTests / viewerShortcutCatalog.test.ts: ゲート閉の系統（findOnly）を削除し、Esc は 1 行で barClose であることを残した。
- FeatureGateTests: 型ごと削除。

## 検証
swift test 1988 + 72 件通過（削除したゲート関連分だけ減った）、jest 676 件通過、xcodegen generate 後の xcodebuild build が exit 0、swiftlint は origin/main 比で新規 0（46 件のまま）、oxlint / oxfmt / tsc / markdownlint で指摘なし。rg 'isDocumentJumpEnabled|FeatureGate' はプロダクトコードとテストで 0 件（backlog・スナップショット spec・CHANGELOG の履歴記述は除く）。
AC #1: バージョンで分岐するコードが無くなり、MainMenuBuilder.build は常にジャンプ項目を構築する（MainMenuBuilderTests『Edit メニューにジャンプ項目が 1 つだけ ⇧⌘F で並ぶ』）。stable 版 .app を実際に起動して確かめてはいない。
docs: viewer-ui.md（ゲートの節を撤去後の記述へ）と native-app-design.md（ショートカット一覧の行）を更新した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
文書内ジャンプのフィーチャーゲートを撤去し、stable ビルドでも使えるようにした。FeatureGate は呼び出し元が無くなったため型ごと削除し、ゲート閉専用のショートカット一覧（findOnlyItems / findClose）も削除した。ゲート OFF 前提のテストは、担保対象が消えたものは削除し、残る不変条件（バイナリではジャンプ不可、ジャンプ能力が無ければ検索へ倒れる）は別の入力で担保し直した。
<!-- SECTION:FINAL_SUMMARY:END -->
