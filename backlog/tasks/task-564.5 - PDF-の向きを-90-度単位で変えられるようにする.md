---
id: TASK-564.5
title: PDF の向きを 90 度単位で変えられるようにする
status: To Do
assignee: []
created_date: '2026-08-29 00:42'
updated_date: '2026-08-29 00:42'
labels: []
dependencies:
  - TASK-564.1
  - TASK-564.2
  - TASK-564.3
parent_task_id: TASK-564
priority: medium
type: feature
ordinal: 819000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

横向きにスキャンされた PDF などを、90 度単位で回して読めるようにする。

## 前提

`PDFPage.rotation`（0 / 90 / 180 / 270）と `PDFView.rotate(byDegrees:)` で実現できる。TASK-564.2（1 ページフィット）に依存させているのは、回転するとページの縦横比が変わり、画面にフィットする倍率が変わるため。回転後もフィットが保たれることを両タスクの整合として確認する必要がある。

## 論点（実装着手前に `/review-design` で詰める）

- **回転の適用範囲**: 文書全体を回すのか、現在ページだけを回すのか。ページごとに向きが混在する PDF があるため、全体回転だと一部だけ正しくならない。逆にページ単位だと、ページを送るたびに回し直す手間が出る。既定をどちらにするかを決める。
- **記憶**: 回転状態は TASK-564.3 の「ウィンドウの生存期間だけ記憶する表示状態」に含める（永続化しない）。含めない判断をするなら理由を記録すること。
- **操作の入口**: メニュー項目とキーボードショートカットの新設が要る。追加先は `MainMenuBuilder+ViewMenu`（既存のズーム項目群の近傍）、`MenuShortcutCatalog` / `ViewerShortcutCatalog` / `ShortcutKey`、ヘルプの一覧 `HelpShortcutSections`、ローカライズ `Localizable.xcstrings`。有効判定は `ViewerCapabilities` に新しい能力を足して `ViewerMenuValidator` から返す（メニュー構築時に種別で分岐しない、という既存の原則を守る）。
- **ショートカットの衝突**: 新設するキーが既存のショートカットとぶつからないことを `/menu-audit` で確認する。
- **`Localizable.xcstrings` の編集**: キー順にソートし直さない。既存の並びを保ち、近縁キーの直後に挿入する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF を 90 度単位で時計回り・反時計回りに回転できる
- [ ] #2 回転後も 1 ページが画面にフィットした状態が保たれる
- [ ] #3 回転が文書全体かページ単位かの判断と理由が Implementation Notes に記録されている
- [ ] #4 回転の操作がメニュー項目とキーボードショートカットの両方から届き、`ViewerCapabilities` の能力として PDF 以外では無効になっている
- [ ] #5 新設したショートカットが既存のものと衝突しないことを `/menu-audit` で確認済み
- [ ] #6 メニュー項目とヘルプのショートカット一覧が日本語・英語の両方でローカライズされている
- [ ] #7 別ファイルへ移って戻ったときに回転状態が保たれ、ウィンドウを閉じるとリセットされる
<!-- AC:END -->
