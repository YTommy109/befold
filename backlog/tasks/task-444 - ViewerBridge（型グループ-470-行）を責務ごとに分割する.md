---
id: TASK-444
title: ViewerBridge（型グループ 470 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-11 05:07'
updated_date: '2026-08-11 05:26'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 100700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/BefoldKit/ の ViewerBridge 型グループが 470 行（本体 376 / +PayloadKeys 66 / +Diff 28）。scripts/check-type-group-size.sh の実測値で scripts/type-group-baseline.txt にも凍結されている。

ファイル単位では全ファイルが file_length の warning 400 を下回っており、TASK-428 の起票時のファイル単位リスト（7 件）には現れていなかった。合算で初めて顕在化したグループ。超過幅が 70 行と小さいため priority は low。

ViewerBridge は本体アプリ・QuickLook 拡張の双方が使う BefoldKit の型で、WKWebView へ渡すペイロードの組み立てを担う。分割は extension を増やす形では効かない（合算値が減らない）。着手前に responsibility-reviewer サブエージェントを回して切り口を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループの合算行数が 400 行以下になる（scripts/check-type-group-size.sh で確認できる）
- [ ] #2 ベースライン scripts/type-group-baseline.txt から ViewerBridge のエントリが消える
- [ ] #3 分割は extension の追加ではなく独立型への切り出しで行われている
- [ ] #4 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [ ] #5 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->
