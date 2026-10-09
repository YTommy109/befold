---
id: TASK-691
title: サイトにスライド窓・比較基準の切り替え・PDF 内検索の説明を足す
status: Done
assignee: []
created_date: '2026-10-09 07:32'
updated_date: '2026-10-09 08:25'
labels: []
milestone: m-12
dependencies:
  - TASK-690
priority: medium
type: enhancement
ordinal: 880000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実装側にあってサイトに一切書かれていない主要機能がある。調査（2026-10-09、コード読み）: スライド窓は ViewerWindowKind.slide（サイドバー・ツールバー無し、サイドバーの右クリックから開く）で、サイトと README に「スライド」が 0 件。差分の比較基準は「このブランチの変更（既定）／スタック全体／作業中の変更」の 3 択（サイドバーヘッダーと表示メニュー）だが、サイトは既定値の説明だけ。PDF 内検索は PDFKit で実装済みだが、サイトの PDF 記述は「連続スクロール」のみ。TASK-519/520（流入ページ・QuickLook 訴求）とは役割が違い、既存の機能一覧への追記が中心。画像は撮り直しタスクで用意するので、それに依存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 features / landing にスライド窓・比較基準の切り替え・PDF 内検索の説明が入り、記載が現行実装（docs/dev/viewer-ui.md・file-type-display.md）と一致している
- [x] #2 日英の両方で表示できる（既存の Localized の仕組みに乗っている）
- [x] #3 ブックマークの独立メニューと Bookmark Editor、CSV の数値列の書式、ファイル行の ⌘クリックの開き分けについて、載せる／載せないを理由つきで決めて Notes に残す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 対応（2026-10-09）
shared.tsx の MORE_FEATURES に 3 項目（比較基準の切り替え / スライド窓 / PDF 内検索）を日英で追加。MORE_FEATURES は features ページと LP の両方が描くので、features / landing の双方に出る。画像は TASK-690 で足した screenshot-9〜11 がカルーセルに載っている。
- 比較基準: docs/dev/viewer-ui.md「差分の比較基準」の 3 択と、「スタック全体」は親ブランチがデフォルトと異なるときだけ出る条件、窓ごとのライブ値であることに合わせた
- スライド窓: サイドバーの右クリック「スライドモードで開く」（Localizable.xcstrings の ja/en 表記）、サイドバー・ツールバー無しの 16:9、Space/↓ で次・Shift+Space/↑ で前（native-app-design.md の SlideKeyAction）
- PDF 内検索: docs/dev/file-type-display.md「検索とジャンプ」（PDFKit beginFindString、PDF は検索のみでジャンプなし）。件数・前後移動・大文字小文字の切り替えは screenshot-11 の UI で確認

## AC#3: 載せる／載せないの判断
- ブックマークの独立メニューと Bookmark Editor: **載せない**。FEATURES の CLI の項に --bookmark、Quick Open の項にブックマークが検索対象と既にあり、メニュー化や編集画面は操作の詳細で、紹介の軸にならない
- CSV の数値列の書式: **載せない**。screenshot-4（▲ 赤字・桁区切り）が既にカルーセルで見せている。文章で書くと設定項目の羅列になる
- ファイル行の ⌘クリックの開き分け: **載せない**。macOS の標準的な作法（⌘ でタブ／⇧⌘ で窓）で、説明しなくても期待どおりに動く

## 検証
tsc / lint / format 通過。npm test は 441/442。落ちた 1 件は test/public-pages-hosts.test.ts の「/releases のヘッダーに ja の全ナビ項目が出る」で、原因は 5000ms のタイムアウト（最初のリクエストの初期化が遅い）。TASK-690・694 の作業中にも同じファイルで落ちて単体再実行では通っており、文言変更とは無関係の既存の flaky。
<!-- SECTION:NOTES:END -->
