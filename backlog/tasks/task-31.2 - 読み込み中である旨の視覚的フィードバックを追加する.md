---
id: TASK-31.2
title: 読み込み中である旨の視覚的フィードバックを追加する
status: Done
assignee: []
created_date: '2026-07-16 15:05'
updated_date: '2026-07-16 15:32'
labels: []
dependencies: []
parent_task_id: TASK-31
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-31 AC#2の対処方針のうち、視覚的フィードバックによる対応を実装する。巨大ファイル読み込み中に別ファイルへの切り替え操作をしても、ユーザーが「処理中で反映待ちである」と分かるようにする。根本原因の修正(タスクキャンセルや優先度調整)と独立して着手できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ファイル読み込み処理中、サイドバーまたはビューア領域に読み込み中であることを示す視覚的インジケータが表示される
- [ ] #2 読み込みが完了すると、インジケータは表示された内容の切り替えと同時に消える
- [ ] #3 巨大ファイル読み込み中に軽量ファイルへ切り替えた場合でも、インジケータにより処理中であることが利用者に伝わる
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
task-31本体の修正(TextEncoding.detectEncodingへのsniffLength適用)により、巨大SJIS CSVの読み込みが数十秒から数百msに短縮された。通常のファイルサイズでは体感できる遅延がほぼなくなったため、読み込み中の視覚的フィードバックの必要性は低いと判断しクローズする。100MB上限の巨大ファイルやFileWatcher連発時は依然として数百ms〜数秒の遅延がありうるが、別途必要になった時点で再起票する。
<!-- SECTION:FINAL_SUMMARY:END -->
