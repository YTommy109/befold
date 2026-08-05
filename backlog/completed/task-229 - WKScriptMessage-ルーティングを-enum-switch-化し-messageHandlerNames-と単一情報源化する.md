---
id: TASK-229
title: WKScriptMessage ルーティングを enum + switch 化し messageHandlerNames と単一情報源化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:15'
updated_date: '2026-07-31 22:17'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 360000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+MessageHandling.swift:31-66 の if/else-if 連鎖（5 分岐）を enum BridgeMessage: String の switch に置き換える。現状は ViewerRenderer.messageHandlerNames(for:)（登録側の配列、セキュリティ境界）と受信側の if 連鎖が同期を要求される 2 つのリストになっており、登録したのにルーティングを書き忘れると無反応という発見しにくい欠陥が起きうる。enum に寄せると messageHandlerNames も allCases から導出でき単一情報源になる。ペイロード抽出は名前判定と分離し、body 不正で黙って次の else if へ落ちる現挙動も解消する。ViewerRenderer.swift:206-218 の var + 条件付き append も単一式に置き換える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 メッセージ名の一覧が enum 1 箇所で定義され、登録リストとルーティングの双方がそこから導出される
- [x] #2 各メッセージのペイロード不正時の挙動が明確（該当ケース内で早期 return）である
- [x] #3 既存のブリッジ動作（zoom/参照/追加読み込み等）がテストで維持されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerBridge に BridgeMessage: String, CaseIterable を新設し、既存の *MessageName 定数をその rawValue から導出
2. requiresInteractiveBridging を enum に持たせ、messageHandlerNames を allCases からの導出に置換（var + 条件付き append を撤去）
3. payloadKeysByMessageName も BridgeMessage.payloadKeys の網羅 switch から導出（裸の値を送る zoomChanged は nil）
4. 受信側の if/else-if 連鎖を網羅 switch + メッセージ別ハンドラへ分解し、ペイロード抽出を名前判定から分離
5. 登録リストが enum から導出されることを固定するテストを追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
メッセージ名の単一情報源として ViewerBridge.BridgeMessage(String, CaseIterable)を新設。既存の公開定数 *MessageName は enum の rawValue から導出する形にして互換を保った。登録側 messageHandlerNames は allCases + requiresInteractiveBridging のフィルタになり、var + 条件付き append(ViewerRenderer.swift:206-218)を撤去。受信側は BridgeMessage(rawValue:) で写してから網羅 switch で分岐し、各メッセージのペイロード抽出は専用の private ハンドラへ分離した（body 不正時は該当ケース内で早期 return し、次の分岐へ落ちない）。payloadKeysByMessageName も BridgeMessage.payloadKeys の網羅 switch から導出（zoomChanged は裸の数値のため nil = 表に載せない、を型で表現）。ペイロード不正系は既存テスト 6 件が既にカバー済みで、追加で『登録リストが BridgeMessage から導出される』ことを固定するテストを 1 件追加。検証: swift test → 938 passed / npx jest → 336 passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
JS→Swift のメッセージ名を ViewerBridge.BridgeMessage に単一情報源化し、登録リスト・ルーティング・ペイロードキー表の 3 つをそこから導出。受信側の if/else-if 連鎖を網羅 switch + メッセージ別ハンドラへ分解し、body 不正で次の分岐へ落ちる挙動も解消した。swift test 938 件 / jest 336 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
