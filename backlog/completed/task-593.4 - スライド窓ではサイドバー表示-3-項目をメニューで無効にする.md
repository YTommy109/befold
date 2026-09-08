---
id: TASK-593.4
title: スライド窓ではサイドバー表示 3 項目をメニューで無効にする
status: Done
assignee: []
created_date: '2026-09-06 10:52'
updated_date: '2026-09-06 10:52'
labels:
  - sidebar
  - slide-mode
dependencies: []
parent_task_id: TASK-593
priority: medium
type: bug
ordinal: 862000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-593 の実機確認で、スライド窓でも View メニューの「サイドバーをツリー表示」が押せることが分かった（ユーザー指摘）。サイドバーが無い窓では切り替える先の一覧そのものが無く、押しても結果が見えない。

指摘は「ツリー表示」1 項目だったが、**同じ理由が不可視ファイル・変更のみにもそのまま当てはまる**ので、項目ごとに塞がず有効判定の絞り込み点（`SidebarDisplayMenuState.isEnabled`）で 3 項目まとめて無効にする。`AppDelegate.validateMenuItem` は「項目ごとの条件をここに書かない」と doc で決めてあり（TASK-537）、その規約に沿う置き場でもある。

spec が「並びは開いた時点の元サイドバーの表示順を引き継ぐ」と決めているので、開いた後に 4 値を変えられないほうが仕様とも整合する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライド窓がアクティブなとき View メニューの「サイドバーをツリー表示」「不可視ファイルを表示」「変更ファイルのみ表示」がいずれも無効になる
- [x] #2 通常のビューア窓では 3 項目とも従来どおり選べる（対のテストで担保）
- [x] #3 判定は `SidebarDisplayMenuState.isEnabled` の 1 箇所にあり、`validateMenuItem` に項目ごとの条件が増えていない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

`SidebarDisplayMenuState.init` に `allowsSidebar` を**既定値なしで**足し
（`canFilterChangedFiles` と同じ理由。渡し忘れが静かに「常に有効」へ倒れる形を作らない）、
`isEnabled = settings != nil && allowsSidebar` にした。`AppDelegate.validateMenuItem` は
`ActiveViewerProvider.fromMainWindow()?.kind.allowsSidebar ?? false` を渡すだけで、
項目ごとの条件は増えていない。

## 指摘より広げた範囲と、その理由

ユーザーの指摘は「サイドバーをツリー表示」1 項目だったが、**3 項目すべて**を無効にした。

- 無効にする理由（切り替える先の一覧が無い）が 3 項目に等しく当てはまる。1 項目だけ塞ぐと、
  隣の 2 つが同じ理由で押せるまま残る
- 有効判定の置き場が既に 1 箇所に決まっており（TASK-537 で `validateMenuItem` に
  項目ごとの条件を書かないと決めた）、そこへ足すと自動的に 3 項目へ効く。
  1 項目だけにするほうがかえって例外を書くことになる
- spec の「並びは開いた時点の元サイドバーの表示順を引き継ぐ」とも整合する
  （開いた後に 4 値を変えられると、この「開いた時点の」が崩れる）

**もし不可視ファイル・変更のみは押せるままにしたい場合は、`isEnabled(for:)` に
項目ごとの分岐を入れる形に戻す必要がある**（その場合は上記の規約との折り合いを
別途決めることになる）。

## 検証（実測）

- `swift test`: `Test run with 1905 tests in 313 suites passed after 40.681 seconds.`
  （TASK-593.3 完了時の 1903 件 + 新規 2 件）
- `xcodebuild build -scheme befold -configuration Debug`: exit 0
- swiftlint ベースライン差分: 真の新規 0
- `check-type-group-size.sh --check`: 閾値以内
- `markdownlint-cli2` / `check-doc-symbols.sh` / `check-doc-citations.sh`: いずれも exit 0
- 逆検証: `&& allowsSidebar` を外すと新テストが 4 件のアサートで実際に落ちることを確認した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スライド窓ではサイドバー表示 3 項目（ツリー表示・不可視ファイル・変更のみ）を View メニューで無効にした。判定は `SidebarDisplayMenuState.isEnabled` の絞り込み点 1 箇所で、`validateMenuItem` に項目ごとの条件は増やしていない。指摘はツリー表示 1 項目だったが、同じ理由が残り 2 項目にも当てはまるためまとめて塞いだ。
<!-- SECTION:FINAL_SUMMARY:END -->
