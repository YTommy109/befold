---
id: TASK-604.1
title: ViewerBridge の受信方向の別名を消し、検索・ジャンプの契約を兄弟型へ出す
status: Done
assignee: []
created_date: '2026-09-09 00:01'
updated_date: '2026-09-09 00:20'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: high
ordinal: 877000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`BefoldApp/BefoldKit/ViewerBridge.swift` は **387 行の単一ファイル**で、型グループ閾値 400 と SwiftLint の `file_length` warning 400 を同時に踏む位置にある。

成長の実測: TASK-444 の返済（470 → 315、2026-08-12）から 18 日・4 機能で **+72 行**（1 機能平均 +18）。残り 13 行は 1 機能ぶんに満たない。CSV の回（2026-08-27）は兄弟型 `ViewerCsvBridge` を新設してなお本体が +12 増えており、関心を出しても `PlainFunction` のケース追加と共有プリミティブの doc で本体は増える。

## 段階

**段階 1（最小手当て、−19 行）**: 受信方向のメッセージ名の別名 7 本を削除する。`zoomChangedMessageName` / `referenceActivatedMessageName` / `referenceContextMenuMessageName` / `loadMoreLinesMessageName` / `resolveReferencesMessageName` ほか。実測で**本番コードからの参照は 0 件**、利用者はテスト 9 ファイルのみで、`ViewerBridgeMessage.<case>.rawValue` を直接読む形へ書き換えられる。

これは `ViewerBridge.swift:7-8` の doc が「逆方向(JS → Swift の postMessage メッセージ名)は `ViewerBridgeMessage` が持つ」と宣言しているのに別名が残っている、TASK-444 の境界の片側未了の是正でもある。

**段階 2（−93 行）**: 関心ごとに兄弟型へ出す。`ViewerCsvBridge.swift` の doc が「extension ではなく兄弟の型にしてある。extension はファイルを分けても型グループの行数には合算されるため、責務を分けたことにならない」と既定パターンを明文化している。

- 検索バーの契約（開閉・前後移動・`FindOptions`・初期値注入・ローカライズ文字列）→ `ViewerFindBridge`（約 45 行）
- 文書内ジャンプの契約（`openJumpScript` / `jumpAvailabilityScript` / `initialJumpLevelsScript` / `jumpStringsScript`）→ `ViewerJumpBridge`（約 48 行）

残すのは共有プリミティブ（`jsonLiteral` / `assignGlobalScript` / `defaultingFallback` / `contentCallScript`）、`PlainFunction`（JS 側の存在検証に使う `CaseIterable` なので**割らない**。`ViewerCsvBridge` が既に外から参照している前例あり）、render / appendChunk / 表示モード / 注入系。

387 → 約 290 行。

## 制約

`MainMenuBuilder` と違い、**外部の glob 制約は無い**（`scripts/` `.github/workflows/` `site/vitest.config.ts` を grep して 0 件）。契約テストは Swift のファイル名ではなく `viewer-bundle.js` / `viewer.html` を読む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 受信方向のメッセージ名の別名がすべて削除され、テストが ViewerBridgeMessage を直接読んでいる
- [x] #2 検索とジャンプの契約が兄弟型へ出ており、extension ではないことが doc に書いてある
- [x] #3 ViewerBridge グループが 320 行以下になっている
- [x] #4 swift test と ViewerBridgeContractTests が通り、viewer-bundle.js との突き合わせが壊れていない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
段階 1: 受信方向の別名 7 本（zoomChanged / referenceActivated / referenceContextMenu / loadMoreLines / resolveReferences / jumpLevelsChanged / findOptionsChanged）を削除し、テスト 9 ファイルを ViewerBridgeMessage.<case>.rawValue へ書き換えた。本番参照は事前 grep で 0 件を確認済み。あわせて `!rawValue.isEmpty` を見るだけの loadMoreLinesMessageNameIsDefined を削除（String enum の rawValue は空にならないので何も検証していなかった）。

段階 2: 検索の契約を ViewerFindBridge、ジャンプの契約を ViewerJumpBridge へ兄弟型として切り出した（extension にしない理由を両ファイルの doc に明記）。FindOptions も ViewerFindBridge へ移動（呼び出し 2 箇所を更新）。

実測: ViewerBridge グループ 387 → 271 行（AC #3 の 320 以下を満たす）。swift test 1941 tests / 320 suites すべて通過。scripts/check-type-group-size.sh exit=0、swiftformat 差分なし、swiftlint の新規指摘なし。

なお ViewerBridgeContractTests が 381 行で閾値に近い（TASK-604.2 の対象）。
<!-- SECTION:NOTES:END -->
