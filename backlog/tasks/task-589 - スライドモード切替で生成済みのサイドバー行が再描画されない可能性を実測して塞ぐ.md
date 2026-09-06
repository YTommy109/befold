---
id: TASK-589
title: スライドモード切替で生成済みのサイドバー行が再描画されない可能性を実測して塞ぐ
status: To Do
assignee: []
created_date: '2026-09-05 02:48'
updated_date: '2026-09-06 09:25'
labels:
  - sidebar
  - slide-mode
dependencies: []
priority: medium
type: bug
ordinal: 854000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-587 の `FileListView` は `model.transient.isSlideMode` を NSTableView ベースの `List` の行ビルダークロージャ内で読んでいる。`FileListEntryRow.swift` 冒頭の doc コメントはまさにこの置き場所を「Observation の追跡外」と記録しており（`gitStatus` を行の body で評価するクロージャで渡している理由）、生成済みの行がスライドモード切替で再描画されない可能性がある。`FileListView.body` 自身が読むのは `listSnapshot.visible` だけ、`SidebarHeaderView` は別 body で読み、`setSlideMode` はフィルタ有効時しか `listSnapshot` を変えないため、構造的に再構築を強制するものが無い。

TASK-587 の目視確認は幅変更（`splitView.setPosition`）と同時だったので、セルの再レイアウトが偶然効いていた可能性がある。まず幅を変えないトグル（例: 一時的に幅変更を外す、または既にスライド幅のまま切替を往復する）で実測し、追跡されているなら FileListEntryRow のコメントを直す。追跡されていないなら、読み取りを行 body で評価されるクロージャへ移す（`gitStatus` と同じ形）。

/code-review high（2026-09-05、TASK-586 のブランチ上）の指摘（PLAUSIBLE）。main には PR #632 で入っている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 幅変更を伴わないスライドモードの切替で、表示中の行がその場でマスク／解除されることを実測し、結果（追跡される／されない）を Implementation Notes に残す
- [ ] #2 追跡されない場合、isSlideMode の読み取りを行 body で評価される形へ移し、切替直後に行が再描画される
- [ ] #3 追跡される場合、FileListEntryRow.swift 冒頭の「Observation の追跡外」の記述を実測に合わせて直す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
見送り予定: スライドモードを専用ウィンドウへ移す（TASK-593）の決定により、行のマスク自体が撤去対象になった。撤去サブタスク TASK-593.1 の完了時に見送りの要約付きで Done にする。
<!-- SECTION:NOTES:END -->
