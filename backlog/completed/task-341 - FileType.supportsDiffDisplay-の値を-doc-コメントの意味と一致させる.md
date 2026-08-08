---
id: TASK-341
title: FileType.supportsDiffDisplay の値を doc コメントの意味と一致させる
status: Done
assignee: []
created_date: '2026-08-06 05:35'
updated_date: '2026-08-06 06:46'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 607000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

FileType.swift:162-171。doc コメントは「ソース表示へ git 差分を重ねられる種別かどうか」と定義し、直前の supportsSourceMode はバイナリ（画像・PDF）を対象外と明記するのに、supportsDiffDisplay は .image / .pdf にも true を返す。現状は ViewerCapabilities が showsCodeContent と AND するため無害だが、BefoldKit は QuickLook / CLI からも使われる公開 API であり、単独でこのプロパティを読む将来の呼び出し元が「画像でも差分を表示できる」と判断して描画されない git サブプロセスを起動し得る（TASK-324 が CSV で塞いだのと同型の無駄）。

supportsSourceMode から導出する（source 可能 かつ 非 CSV）か、image/pdf を false に列挙して自己整合にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 supportsDiffDisplay が doc コメントの意味どおりの値を返す（.image / .pdf は false）
- [x] #2 canToggleDiff など既存の外部挙動が変わらないことをテストで確認する
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileType.supportsDiffDisplay を .image / .pdf も false に列挙し、doc コメント(バイナリはテキストソースを持たない)と自己整合にした。FileTypeTests のパラメータへ image/pdf を追加。修正を戻すと当該テストが 2 件失敗することを実測で確認済み。canToggleDiff は ViewerCapabilities で showsCodeContent と AND するため外部挙動は不変(全 1078 テスト green)。
<!-- SECTION:FINAL_SUMMARY:END -->
