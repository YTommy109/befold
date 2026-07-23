---
id: TASK-103
title: PATH経由起動時に befold --version が古いバージョンを表示する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-23 01:01'
updated_date: '2026-07-23 01:03'
labels: []
dependencies: []
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #276-278 で CLI --version のバンドル解決を修正したが、ユーザーが PATH 経由で 'befold' とだけ入力して起動した場合、argv[0] が素のコマンド名になり realpath が解決できず、ハードコードされた fallback バージョンが表示されたままだった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PATH 経由 (bare command name) で起動した場合でも --version が正しいバンドルバージョンを表示する
- [x] #2 フルパス/相対パス経由の起動でも既存の挙動が壊れない
- [x] #3 AppVersion の単体テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppVersion.currentBundleInfoDictionary() の argv[0]+realpath 方式を、_NSGetExecutablePath ベースの実パス取得に置き換える (argv[0] は素のコマンド名の場合 realpath で解決できないため)
2. actualExecutablePath() ヘルパーを追加し、_NSGetExecutablePath でバッファサイズ取得→取得→realpath で symlink 解決
3. AppVersionTests に actualExecutablePath の単体テストを追加
4. swift build / swift test で全体テストを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
_NSGetExecutablePath ベースに置き換え。/tmp に symlink を張って PATH 経由 bare-name 起動を再現し、argv0='verifybin' でも実パス解決に成功することを確認(旧実装は realpath(argv0) 失敗で fallback に落ちていた)。swift test 全594件通過、AppVersionTests単体も6件通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppVersion.currentBundleInfoDictionary() の argv[0]+realpath 方式を _NSGetExecutablePath ベースの actualExecutablePath() に置き換えた。argv[0] はシェルが入力どおりにセットするため PATH 経由で 'befold' とだけ入力すると realpath が解決できず fallback バージョンが表示される不具合を修正。symlink 経由の bare-name 起動を再現するテストスクリプトで実パス解決を確認、swift test 594件・AppVersionTests 6件全通過で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
