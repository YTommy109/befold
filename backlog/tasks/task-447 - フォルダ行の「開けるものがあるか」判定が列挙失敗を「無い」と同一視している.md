---
id: TASK-447
title: フォルダ行の「開けるものがあるか」判定が列挙失敗を「無い」と同一視している
status: Done
assignee: []
created_date: '2026-08-11 12:34'
updated_date: '2026-08-13 04:35'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 675000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`DirectoryLister.containsSupportedFile`(BefoldApp/befold/Viewer/DirectoryLister.swift:157-159)は `firstSupportedFile` 経由で列挙失敗を nil → false へ畳む。結果、**読めないフォルダ**がサイドバーの行で「開けるものが無いフォルダ」と同じ見た目になる。

TASK-410 で扱った 3 経路（ルート一覧・プレビュー・Quick Open）の外だったため、そちらでは触っていない。TASK-404 / TASK-410 で導入した「失敗と空を型で分ける」方針の残りの適用先。

判断が要る点: 行のバッジ（開けるものがあるか）に第 3 の状態を足すのか、ツリー展開の `.expandedFailed` と同じ見せ方へ寄せるのか。展開してみれば失敗は分かる（TASK-404）ので、行のバッジは変えないという結論もありうる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 読めないフォルダの行が、開けるファイルの無いフォルダと同じ見た目にならない（区別しないと決める場合は理由を Notes に残す）
- [x] #2 決めた振る舞いをユニットテストで固定している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. containsSupportedFile の消費側を実測で確定する（結果: FileListView.swift:129 の .disabled 1 箇所のみ。行の見た目には影響しない）
2. 単純化検討: 第 3 の状態を足さず、Bool の意味を「開ける対応ファイルを 1 件取れるか」と doc で明示する
3. 読めないフォルダで containsSupportedFile == false になることをユニットテストで固定する
4. 区別しないと決めた理由を Notes に残す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 結論: 列挙失敗と「開けるものが無い」を区別しない（決定）

**起票時の前提が実コードとずれていた。** `containsSupportedFile` は行の見た目（バッジ・
アイコン・文字色）には一切影響しない。消費側は `FileListView.swift:129` の
`.disabled(!entry.containsSupportedFile)` の 1 箇所だけで、コンテキストメニュー
「新しいタブ/ウィンドウで開く」の可否判定に使われる（grep 実測: befold ターゲット内の
参照は FileListEntry の定義とこの 1 行のみ）。

そのうえで区別しないと決めた理由:

1. この判定が問うのは「開ける対応ファイルを 1 件取れるか」だけ。読めないフォルダで
   有効化しても、押した先の `DirectoryLister.firstSupportedFile` が nil を返すので
   何も起きないボタンになる（FileListView.swift:120-128）。disabled のままが正しい。
2. 列挙失敗そのものの区別は既にツリー展開側が担っている。
   `SidebarDisclosureState.expandedFailed` が警告三角 + `folder.enumerationFailed` の
   help を出す（FileListEntryRow.swift:68、TASK-404）。第 3 の状態を足すと同じ事実の
   表現が 2 系統になる。
3. 単純化検討の結果、Bool のままで意味を doc に明示するのが最小の変更。

## 変更内容

- `DirectoryLister.containsSupportedFile(in:)` と `FileListEntry.containsSupportedFile`
  の doc に「読めなかったフォルダも false に畳むのは決めた振る舞い」と理由を明記。
- `DirectoryListerSupportedFileTests`（DirectoryListerTests から分離。file_length /
  type_body_length を超えたため。TASK-298 と同じ理由）で振る舞いを固定:
  chmod 000 のフォルダに .mmd を入れても `containsSupportedFile == false`、
  一方で `DirectoryLister.childEntries` は nil を返して列挙失敗の区別が残ることを確認。
  root 実行では chmod 000 が効かず逆の枝を通るため `.enabled(if: getuid() != 0)` で落とす。

## 検証

- `swift test` 全件: 1468 tests / 232 suites passed（31.5s）。
- swiftlint: 変更した 3 ファイルで新規警告ゼロ（分割前に出ていた file_length /
  type_body_length は分割で解消）。
- `xcodegen generate` 実行済み（テストファイル新規追加のため）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
列挙失敗と「開けるものが無い」を区別しない、と決定して固定した。containsSupportedFile の消費側はコンテキストメニューの disabled 判定 1 箇所だけで行の見た目には影響せず（起票時の前提の誤り）、読めないフォルダで有効化しても何も起きないボタンになるため disabled が正しい。列挙失敗の区別はツリー展開側の expandedFailed（TASK-404）が担う。理由を doc コメントに明記し、DirectoryListerSupportedFileTests で振る舞いを固定。swift test 1468 件パス、swiftlint 新規警告ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
