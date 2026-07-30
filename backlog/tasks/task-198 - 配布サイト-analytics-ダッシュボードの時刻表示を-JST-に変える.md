---
id: TASK-198
title: 配布サイト analytics ダッシュボードの時刻表示を JST に変える
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-30 04:28'
updated_date: '2026-07-30 04:44'
labels: []
dependencies: []
ordinal: 282000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/src/views/dashboard.tsx で event.ts を new Date().toISOString() で UTC 表示している（22行目・127行目のヘッダ・137行目）。日本のユーザー向け運用のため JST 表示に変更する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ダッシュボードの時刻列が JST（UTC+9）で表示される
- [x] #2 見出しの表記が「時刻 (UTC)」から JST であることが分かる表記に更新されている
- [x] #3 テストまたは目視確認で表示時刻が UTC+9 ずれていることを確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. dashboard.tsx に JST 変換用ヘルパー formatJst(ts) を追加する（UTC+9 オフセットを加算し 'YYYY-MM-DD HH:mm:ss' 形式で返す。タイムゾーン名前付き文字列生成に依存できない Workers 環境のため Date のミリ秒加算+ISO文字列整形で実装）。
2. サーバー側テーブル行（137行目）で formatJst(event.ts) を使う。
3. クライアント側 STREAM_SCRIPT（22行目）の new Date(event.ts).toISOString() 部分を同じ +9時間オフセットのロジックに書き換える（テンプレート文字列内の素の JS なので同ロジックをインライン実装）。
4. ヘッダ表記（127行目）を「時刻 (UTC)」から「時刻 (JST)」に変更する。
5. 目視確認: dev サーバーでダッシュボードを開き、既知の UTC 時刻イベントに対し表示が +9 時間になっていることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
formatJst ヘルパー(+9h オフセット→ISO整形)を追加し、サーバー側行(137行目)とクライアント側SSEスクリプト(旧22行目)双方をJST表示に変更。ヘッダを「時刻 (JST)」に更新。npm run typecheck / npm run test (42 passed) 通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
dashboard.tsx に formatJst ヘルパー(+9h オフセット)を追加し、サーバー側の最新イベント行とクライアント側SSEスクリプトの時刻表示を JST に統一。見出しを「時刻 (JST)」に変更。npm run typecheck・npm run test(42 passed)が通過し、UTC 00:00:00 → JST 09:00:00 の変換をnodeスクリプトで確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
