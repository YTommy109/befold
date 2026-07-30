---
id: TASK-182.4
title: アプリの Sparkle フィード URL を新 Worker へ切り替える
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:35'
updated_date: '2026-07-29 12:46'
labels: []
dependencies:
  - TASK-182.2
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: medium
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/Updates/UpdateChannel.swift の feedURLString（stable/develop 両方）を新 Worker の appcast URL に変更する。旧 GitHub appcast 固定タグは既存ユーザーのため残す（後方互換）。この変更を含むアプリをリリースすると既存ユーザーは次回チェックで新フィードへ移行する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 UpdateChannel.swift の stable/develop フィード URL が新 Worker の appcast URL を指す
- [x] #2 旧 GitHub appcast 固定タグは維持され既存ユーザーが壊れない
- [x] #3 新フィード経由でアップデートチェックが成功する（手動確認）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. UpdateChannel.swift の feedURLString を Worker の appcast URL（https://befold-site.tokutomi.workers.dev/appcast.xml と /appcast-develop.xml）に変更する
2. UpdateChannelTests.swift の期待値を新 URL に更新する
3. swift test で該当テストが通ることを確認する
4. release.yml が GitHub の appcast 固定タグへ publish し続けている（Worker はそれをプロキシする）ことを確認し、後方互換が保たれることを検証する
5. 新フィード URL が実際に Sparkle の appcast を返すことを curl で確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証ログ:
- `swift test --filter UpdateChannelTests` → 5 tests passed（feedURLString の期待値を新 URL に更新）
- 全体テスト（PostToolUse フックの swift test）も通過
- 新旧フィードの内容一致を確認: curl で取得した Worker 経由 /appcast.xml と GitHub 直の appcast.xml が diff で identical（develop も identical）。EdDSA 署名・enclosure URL もそのまま
- release.yml は従来どおり appcast 固定タグへ appcast.xml / appcast-develop.xml を publish しており、旧 URL を見る既存ユーザーは影響を受けない（Worker はそれをプロキシするだけ）
- AC#3 の実機確認: Debug ビルドを起動し、メニュー『アップデートを確認…』を System Events でクリック。本番 D1 の update_check 件数が 3 → 4 に増え、増えた行は ua_summary='Sparkle' / channel='develop'（dev ビルドのため develop）だった。実アプリの Sparkle が新フィードを取得できたことを実データで確認。エラーダイアログも出ていない

補足（今回のスコープ外）: Sparkle の User-Agent には OS 情報が含まれないため、update_check の os 列は NULL になる。OS 別集計はブラウザ経由の visit/download が対象。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
UpdateChannel.swift の feedURLString を配布サイト Worker の appcast URL（https://befold-site.tokutomi.workers.dev/appcast.xml と /appcast-develop.xml）へ切り替え、テストの期待値も更新した。Worker は GitHub の appcast をプロキシするだけで内容は byte 一致、GitHub の appcast 固定タグも release.yml で維持されるため既存ユーザーは影響を受けない。実機の Sparkle でアップデートチェックを実行し、本番 D1 に ua_summary='Sparkle' の update_check が記録されることまで確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
