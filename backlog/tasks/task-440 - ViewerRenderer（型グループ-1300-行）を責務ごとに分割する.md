---
id: TASK-440
title: ViewerRenderer（型グループ 1300 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-11 05:05'
updated_date: '2026-08-11 05:25'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/BefoldRenderKit/ の ViewerRenderer 型グループ（本体 + 5 本の extension の合算）が 1300 行で、型グループ単位の全 12 グループ中で最大。scripts/check-type-group-size.sh の実測値であり、scripts/type-group-baseline.txt にも同値が凍結されている。

内訳: ViewerRenderer.swift 370 / +RenderHelpers 265 / +ContentUpdate 238 / +OneShot 177 / +MessageHandling 146 / +DirectHTMLLinkPolicy 104。

ファイル単位では全て file_length の warning 400 を下回っており、TASK-428 の起票時にファイル単位で測った 7 件のリストには現れていなかった。合算で数えて初めて顕在化したグループであり、file_length の error 閾値 1000 をグループとしては超えている。

この型は本体アプリと QuickLook 拡張の双方が使う描画エンジンであり、肥大化の影響範囲が広い。分割は extension をさらに切るのではなく、独立した型へ関心を出す形で行うこと（extension を増やしても型グループの合算値は減らない）。

着手前に responsibility-reviewer サブエージェントを回し、どの関心を独立型へ出すかを決めてから実装すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループの合算行数が 400 行以下になる（scripts/check-type-group-size.sh で確認できる）
- [ ] #2 ベースライン scripts/type-group-baseline.txt から ViewerRenderer のエントリが消える
- [ ] #3 分割は extension の追加ではなく独立型への切り出しで行われている（切り出し先の型名が説明できる）
- [ ] #4 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [ ] #5 main との swiftlint 差分に真の新規が無い
- [ ] #6 swift test が既存どおり通り、QuickLook 拡張のビルドも通る
<!-- AC:END -->
