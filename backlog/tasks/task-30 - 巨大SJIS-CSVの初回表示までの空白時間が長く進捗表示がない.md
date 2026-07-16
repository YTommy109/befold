---
id: TASK-30
title: 巨大SJIS CSVの初回表示までの空白時間が長く進捗表示がない
status: To Do
assignee: []
created_date: '2026-07-16 13:44'
updated_date: '2026-07-16 14:14'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 70
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
巨大(数十MB級)なShift_JISのCSVファイルを初めて開くと、内容が表示されるまで空白のまま長時間待たされる。NormalizedTextCache のデコード(SJIS→String変換)・行インデックス構築・dataHashのSHA256計算が同期的にバックグラウンドタスクで行われる間、ユーザーには進捗が一切見えない。原因箇所と処理時間の内訳(デコード/行インデックス構築/ハッシュ計算のどこが支配的か)を調査し、プログレス表示(不確定プログレスバー、または行数ベースの進捗)を追加できるか検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 巨大SJIS CSV(数十MB級)を開いた際のデコード〜初回チャンク表示までの処理時間内訳が計測されている
- [ ] #2 空白表示が続く間、ユーザーに読み込み中であることを示すインジケータ(不確定プログレスバー等)が表示される
<!-- AC:END -->
