---
id: TASK-45
title: apply() の early-return が loadFailed をリセットしない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-17 05:09'
updated_date: '2026-07-17 07:28'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.apply() でハッシュと fileType が一致して早期リターンする際、loadFailed フラグがリセットされない。チャンク読込エラー後に同一内容でファイルが再保存されると、エラーバナーが永続しリトライ手段もなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 apply() の early-return パスで loadFailed が false にリセットされ、chunkSession が適切に処理される
- [x] #2 チャンク読込エラー後に同一内容で再読込した際にエラーバナーが消えることをテストで確認
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: 新しい状態(例: 専用フラグ)は追加しない。既存の loadFailed を early-return の判定条件にそのまま組み込む(cache.dataHash == contentHash && fileType == self.fileType && !loadFailed)。前回チャンク読込が失敗している場合は「同一内容」であっても early-return させず、通常の再適用パス(chunkSession 張り直し・loadFailed=false リセットなど)を通す。
2. ViewerStore.apply() の .chunked ケース(line 346)と .full ケース(line 361)の early-return 条件に !loadFailed を追加する。
3. テスト追加: チャンク読込エラー後に「同一内容」で再読込したときに loadFailed が false にリセットされ、再度「続きを読み込む」が機能することを確認するテストを ViewerStoreTests.swift に追加(既存の loadFailedResetsOnReload は内容が変わるケースのみなので、同一内容ケースを補う)。
4. swift test で検証。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
apply() の .chunked/.full 早期リターン条件に !loadFailed を追加(既存 loadFailed を再利用、新規状態は追加しない)。同一内容での再読込で loadFailed がリセットされることを検証するテストを ViewerStoreTests.swift に追加(TASK-45)。swift test で全 361 件成功を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.apply() の early-return 条件(hash・fileType 一致時)に !loadFailed を追加し、直前のチャンク読込が失敗している場合は同一内容の再読込でも通常の再適用パスを通して chunkSession を張り直し loadFailed をリセットするよう修正。新規テスト loadFailedResetsOnReloadWithIdenticalContent を含む swift test 全 361 件が成功。
<!-- SECTION:FINAL_SUMMARY:END -->
