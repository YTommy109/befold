---
id: TASK-444
title: ViewerBridge（型グループ 470 行）を責務ごとに分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 05:07'
updated_date: '2026-08-12 01:04'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 100700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/BefoldKit/ の ViewerBridge 型グループが 470 行（本体 376 / +PayloadKeys 66 / +Diff 28）。scripts/check-type-group-size.sh の実測値で scripts/type-group-baseline.txt にも凍結されている。

ファイル単位では全ファイルが file_length の warning 400 を下回っており、TASK-428 の起票時のファイル単位リスト（7 件）には現れていなかった。合算で初めて顕在化したグループ。超過幅が 70 行と小さいため priority は low。

ViewerBridge は本体アプリ・QuickLook 拡張の双方が使う BefoldKit の型で、WKWebView へ渡すペイロードの組み立てを担う。分割は extension を増やす形では効かない（合算値が減らない）。着手前に responsibility-reviewer サブエージェントを回して切り口を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 型グループの合算行数が 400 行以下になる（scripts/check-type-group-size.sh で確認できる）
- [x] #2 ベースライン scripts/type-group-baseline.txt から ViewerBridge のエントリが消える
- [x] #3 分割は extension の追加ではなく独立型への切り出しで行われている
- [x] #4 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [x] #5 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. responsibility-reviewer で切り口を決める
2. 受信方向（JS → Swift）の契約を独立型 ViewerBridgeMessage へ切り出し、ViewerBridge+PayloadKeys.swift を削除する
3. ViewerBridge+Diff.swift を独立型 ViewerDiffBridge へ昇格させる
4. 呼び出し元を一括置換し、docs の単一情報源テーブル・モジュールツリーを追随させる
5. xcodegen generate → swift build / swift test / xcodebuild / swiftlint ベースライン
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
responsibility-reviewer の提案（案 1: 受信契約の分離 / 案 3: +Diff の型昇格）を採用した。案 2（検索 UI の ViewerFindBridge 化）は PlainFunction の分割判断を伴い、案 1+3 だけで目標を達成できるため見送った。

レビューの主張『*MessageName 8 定数はプロダクション参照 0 件』は自分でも実測して確認した（grep -rn 'MessageName' のヒットは befoldTests/ 配下のみ）。ただし削除は公開 API の撤去にあたり本タスクの AC 外のため、rawValue からの導出のまま ViewerBridge に残した。

結果:
- ViewerBridge 型グループ 470 → 313 行（本体のみ。+PayloadKeys 66 / +Diff 28 は削除）
- 新設: ViewerBridgeMessage.swift 128 行（BridgeMessage + PayloadKey + payloadKeysByMessageName）、ViewerDiffBridge.swift 30 行（Layout / textScript / layoutScript）
- 断面の根拠: 受信方向（JS → Swift、BridgeMessageRouter と 1 対 1）と送信方向（Swift → JS のスクリプト組み立て）で関心の向きが逆
- 呼び出し元 9 ファイルを一括置換（ViewerBridge.BridgeMessage → ViewerBridgeMessage 等）。ViewerBridge. の旧メンバ参照は 0 件
- docs/dev/rules/product-code.md の単一情報源テーブルを 2 行へ分割、docs/dev/native-app-design.md のモジュールツリーを更新
- 契約テストが読むのは viewer.html / viewer-bundle.js のリソースであり Swift のファイルパスではないため、分割の影響を受けない（実測で確認）

検証: swift test 1433 tests passed / xcodebuild build -scheme befold exit=0 / swiftlint 真の新規ゼロ / swiftformat 差分なし / check-type-group-size.sh --over に ViewerBridge が出ない
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerBridge を関心の向きで分割し、受信契約を ViewerBridgeMessage、git 差分を ViewerDiffBridge という独立型へ切り出した（extension 2 本は削除）。型グループは 470 → 313 行になりベースラインから消えた。swift test 1433 件・xcodebuild ともに通過、swiftlint 新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
