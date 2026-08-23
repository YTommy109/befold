---
id: TASK-485.19.1
title: 検索/ジャンプ共通操作の1箇所化リファクタ（振る舞い変更なし）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 09:11'
updated_date: '2026-08-21 09:33'
labels: []
dependencies: []
parent_task_id: TASK-485.19
priority: high
ordinal: 775000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find.ts と jump.ts に重複配線されている件数表示・前後移動・close ボタンのクリック配線を
共通モジュールへ1箇所化する準備リファクタ。TASK-485.19 本体（モード統合）に着手する前段。

対象（Explore調査より）:
- 件数表示・前後移動・close の配線パターンは find.ts:468-480 と jump.ts:344-361 で
  ほぼ同じ形が重複している
- navigation.ts は既に move/highlight/count算術を共通化済み（TASK-485.12）。
  今回はイベント配線側の重複を1箇所化する

振る舞いは一切変えない（既存の viewer-main.test.js / viewer-main-jump.test.js が
そのまま緑のままであること）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 件数表示・前後移動・closeボタンのクリック配線が共通モジュールに1箇所化されている
- [x] #2 find.ts / jump.ts の既存テストが無変更で全て通る（振る舞い変更なし）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
件数表示（navigation.ts の formatNavigationCount）は TASK-485.12 で既に共通化済みだったため対象外。今回1箇所化したのは前へ/次へ/閉じるボタンのクリック配線（bar-controls.ts の wireBarControls）。find.ts:468-480 と jump.ts:341-361 の重複を解消。振る舞い変更なし: npm run typecheck:viewer は既存のmarkdown.ts/vendor.tsのエラーのみ（今回変更ファイルに新規エラーなし）、npm run build:viewer 成功、npm test 550/550件通過、npm run check:viewer-cycles で循環importなし。oxlint/oxfmtはこのworktreeにインストールされておらずローカル実行不可（npm ci が package-lock不整合で失敗）。フォーマットはfind.ts/jump.ts既存スタイル（2スペース・シングルクォート・セミコロンあり）に手動で合わせた。

native-app-design.md への反映は不要と判断（内部の配線ヘルパー追加のみで、doc記載のコンポーネント一覧・責務分担に変化なし。バー統合自体の反映はTASK-485.19全体が完了した時点でTASK-485.19.5側でまとめて行う）。Swiftコードは未変更のためswiftformat/swift test/型グループ計測/responsibility-reviewerは対象外。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
find.ts と jump.ts に重複していた前へ/次へ/閉じるボタンのクリック配線を bar-controls.ts の wireBarControls へ1箇所化。振る舞い変更なし（npm test 550/550通過、typecheck/build/cycle-checkいずれも既存エラーのみで新規エラーなし）。
<!-- SECTION:FINAL_SUMMARY:END -->
