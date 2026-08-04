---
id: TASK-1.15
title: RejectReason の表示文言を BefoldKit ローカライズへ移設する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-19 02:56'
updated_date: '2026-07-19 03:17'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイズ超過・非対応ファイル時のユーザー向け表示が befold/Viewer/UnsupportedFileView.swift と app 側ローカライズ（befold/App/LocalizedBundle.swift、xcodebuild では Bundle.main）に依存しており、QuickLook 拡張からプレースホルダ表示に再利用できない。RejectReason のユーザー向け文言を BefoldKit 側の Localizable リソースへ移し、appex からもアクセスできるようにする。TASK-1.2（viewer.js 注入文字列の移設）と同方針の続きで、対象はネイティブ表示側の文言。2026-07-19 のアーキテクチャレビューで特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 RejectReason のユーザー向け文言が BefoldKit のリソースバンドルから取得できる
- [x] #2 アプリ本体の表示（UnsupportedFileView）は挙動不変
- [x] #3 日英の翻訳漏れがない（l10n チェック通過）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer.unsupported.format / viewer.unsupported.tooLarge の2キーを befold/Resources/Localizable.xcstrings から BefoldKit/Resources/Localizable.xcstrings へ移設(en/ja 両方)
2. RejectReason(BefoldKit) に localizedMessage 算出プロパティを追加し、.befoldKitResources から文言を取得。appex からも再利用可能にする
3. UnsupportedFileView は rejectReason.localizedMessage を使うよう変更(表示挙動は不変)
4. RejectReasonTests で localizedMessage の en/ja を検証、LocalizationTests の BefoldKit 代表キーに unsupported を追加
5. swift build && swift test / l10n チェックで訳漏れなしを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: viewer.unsupported.format/tooLarge の2キーを befold→BefoldKit の Localizable.xcstrings へ移設(en/ja)。RejectReason に localizedMessage(.befoldKitResources 経由)を追加し、UnsupportedFileView は同プロパティを参照。検証: swift build OK / swift test 415 tests passed(RejectReasonTests 新規・LocalizationTests に unsupported 代表キー追加)/ 両カタログの en·ja 翻訳漏れ・プレースホルダ不整合なし。UnsupportedFileView は文言取得元がバンドル差(.l10n→.befoldKitResources)のみで表示挙動は不変。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RejectReason のユーザー向け文言(非対応形式/サイズ超過)を BefoldKit のリソースバンドルへ移設し、RejectReason.localizedMessage で appex からも取得可能にした。UnsupportedFileView は挙動不変。swift test(415 tests)と両カタログの l10n チェックで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
