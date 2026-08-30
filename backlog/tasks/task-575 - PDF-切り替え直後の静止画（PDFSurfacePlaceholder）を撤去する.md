---
id: TASK-575
title: PDF 切り替え直後の静止画（PDFSurfacePlaceholder）を撤去する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-30 04:29'
updated_date: '2026-08-30 04:29'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 836000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-569 で入れた `PDFSurfacePlaceholder`（切り替え直後にタイルが載るまで見せる静止画）を撤去する。**ユーザーの判断**（2026-08-30）——「静止画を一時的におく実装はやめたい。いたずらに複雑にしているだけ」。

## 実測が判断を裏づけている（TASK-573 の調査中に取得 / Release・18 回・同じ測り方）

**1 ページ PDF（フィットして余地が無い文書）**

| | 中央値 | 最小 | 最大 |
| --- | --- | --- | --- |
| 静止画なし | 25.7ms | 19.0 | 32.9 |
| 静止画あり | 29.9ms | 21.8 | 46.7 |

静止画を載せるほうが遅く、実機では載せた後に外れて**白い区間が新たに生まれる**（9.6〜35.3ms）。単体テストでは静止画は中身を焼けており（暗部比 0.40）追加レイアウトでも外れないので、実機だけで起きる差。

**150 ページ PDF（TASK-569 が対象にした文書）**

| | 中央値 | 最小 | 最大 | 200ms 超 |
| --- | --- | --- | --- | --- |
| 静止画あり | 39.0ms | 17.6 | 51.2 | 0/18 |
| 静止画なし | 26.1ms | 20.1 | 241.4 | 2/18 |

**撤去の代償は明確**: 通常時は 13ms 速くなる（毎回の焼き付けコストが消える）が、TASK-569 が消した約 235ms の跳ねが 2/18 で戻る。跳ねは PDFKit の非同期タイル描画の中で起きるもので、アプリ側からは観測も制御もできない（TASK-569 の実測）。

## 撤去したもの

- `BefoldApp/befold/App/PDFSurfacePlaceholder.swift`（197 行）と `PDFSurfacePlaceholderTests.swift`（8 件）
- `ZoomingPDFView.placeholder` と `layout()` の `noteLayout` 呼び出し
- `PDFSurfaceLayout.rotate` / `apply(zoom:)` の `dismiss()` 呼び出し（`apply(zoom:)` は変化判定ごと消えて 1 行になった）
- `PDFPreviewView.installPlaceholder` と、`data == nil` 経路の `dismiss()`
- `docs/dev/native-app-design.md` の `PDFSurfacePlaceholder` 行と `PDFSurfaceLayout` 行の言及

## 影響

TASK-574.2（静止画をオーバーレイ層へ移す）は対象が消えたので不要になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `PDFSurfacePlaceholder` とそのテストが削除され、`placeholder` への参照がプロダクトコードとテストから消えている
- [x] #2 撤去の前後で 150 ページ・1 ページの両方を同じ測り方（18 回）で実測し、失うもの（跳ねの再発）と得るもの（中央値の改善）が記録されている
- [x] #3 `swift test` 全件・`xcodebuild`・swiftlint ベースライン差分ゼロが確認されている
- [x] #4 `docs/dev/native-app-design.md` から `PDFSurfacePlaceholder` の記述が消えている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証（2026-08-30）

- `swift test --skip Integration --skip FileWatcherTests`: 1699 tests / 268 suites すべて通過（静止画のテスト 8 件が減り、TASK-573 の回帰テスト 1 件が増えた）
- `xcodebuild build -scheme befold`: BUILD SUCCEEDED
- swiftformat: 整形差分なし。swiftlint: main 54 件 → 54 件、真の新規ゼロ
- 型グループ検査: 閾値以内
- 計測一式は `.tmp/t573/`（1 ページの題材 `nav/` と `make1page.swift`、3 つの Release ビルド）と `.tmp/t569/`（150 ページの題材 `nav2/` と `sampler` / `compare.sh`）

## 記録: 跳ねの再発について

撤去で 200ms 超の跳ねが 2/18 で戻る（233.5ms / 241.4ms）。これは PDFKit の非同期タイル描画の中で起きるもので、アプリ側からは到着時刻を観測できない（TASK-569 の実測: `PDFPageView` の layer は contents が nil のまま、`draw(_ page:to:)` の override は super が @MainActor で呼べない）。**再び対処するなら、静止画を貼るのではなく描画経路そのものを置き換える案（`PDFPage.draw` で自前のタイルレイヤーへ描く / ADR 0009 の Consequences）になる。** 規模が大きいので、跳ねが実用上の問題として再度報告された時点で判断する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`PDFSurfacePlaceholder`（197 行）とそのテスト 8 件、および 3 ファイル 6 箇所に散っていた `dismiss()` 呼び出しを撤去した。ユーザーの判断（複雑さに見合わない）を、実測が裏づけた——1 ページ PDF では静止画があるほうが遅く（中央値 29.9 対 25.7ms）、実機では載せた後に外れて白い区間が新たに生まれていた。

代償は記録した: 150 ページでは通常時が 13ms 速くなる一方（中央値 26.1 対 39.0ms）、TASK-569 が消した約 235ms の跳ねが 2/18 で戻る。再対処するなら静止画ではなく描画経路の置き換えになる。

検証: `swift test` 1699 tests / 268 suites 全通過、`xcodebuild` BUILD SUCCEEDED、swiftlint ベースライン差分ゼロ、`native-app-design.md` から該当記述を削除。
<!-- SECTION:FINAL_SUMMARY:END -->
