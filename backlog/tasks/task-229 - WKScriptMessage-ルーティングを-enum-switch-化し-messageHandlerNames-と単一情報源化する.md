---
id: TASK-229
title: WKScriptMessage ルーティングを enum + switch 化し messageHandlerNames と単一情報源化する
status: To Do
assignee: []
created_date: '2026-07-31 09:15'
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
- [ ] #1 メッセージ名の一覧が enum 1 箇所で定義され、登録リストとルーティングの双方がそこから導出される
- [ ] #2 各メッセージのペイロード不正時の挙動が明確（該当ケース内で早期 return）である
- [ ] #3 既存のブリッジ動作（zoom/参照/追加読み込み等）がテストで維持されている
<!-- AC:END -->
