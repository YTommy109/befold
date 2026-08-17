---
id: TASK-485.15
title: レビューで確定した小粒の後始末（未使用 API・重複・キャッシュ・必須引数化）をまとめて片付ける
status: To Do
assignee: []
created_date: '2026-08-17 14:06'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: low
type: chore
ordinal: 752000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

/code-review high の確定済み指摘のうち、上位 10 件のカットで漏れた小粒 6 件をまとめて起票する。いずれも独立の小修正で、1 つの PR で片付く規模。実施しない項目は理由を Notes に残す。

### 1. HeadingJumpLevelDefaults のデフォルト引数をやめて必須引数にする（PLAUSIBLE）

`ViewerWindowManager.swift:114` と `ViewerWindowController.swift:247` の両呼び出し箇所が `HeadingJumpLevelDefaults()`（UserDefaults.standard 直結）をデフォルト引数で生成する。設計は app-wide 単一インスタンス（doc コメント）だが、将来の呼び出し側が黙って窓ごとのストアを作れてしまい、単一性を固定するテストも無い。CLAUDE.md の「決めたことには、破れたら落ちるものを付ける…デフォルト引数をやめて必須引数にする」の型（memory: window-scoped-live-value-app-wide-default も参照）。

### 2. FeatureGate の computed property をキャッシュする（CONFIRMED）

`FeatureGate.swift:20-` の `isDocumentJumpEnabled` / `inProgressFeaturesEnabled` はアクセスごとに `AppVersion.current`（実行パスの syscall + Bundle(path:).infoDictionary）を再計算する。`ViewerCapabilitiesFactory.make` は validateMenuItem のたびに項目数分呼ばれる。プロセス生存中に値は変わらないので `static let` にする。

### 3. closeJump / jumpNext / jumpPrevious の死んだ Swift 配管を撤去する（CONFIRMED）

`DocumentRendering.swift:40-42` → WebViewDocumentRenderer → WebViewCommandController → ViewerBridge と配管されているが、プロダクションの呼び出し元ゼロ（Esc/Enter/Shift+Enter は JS 側で処理。rg で確認済み）。テストだけが同期を保つ投機的配管なので撤去する。stable 昇格でキーバインドをメニューに載せるときに必要なら、そのとき再導入する。

### 4. IME ガードの 3 重コピーを共通述語にする（CONFIRMED）

`isComposing || keyCode === 229` が `keyboard.ts:75`（resolveBarCloseKey）・`keyboard.ts:96`（resolveJumpNavigationKey）・`find.ts:447` の 3 箇所にある。1 つの共有述語へ。

### 5. HeadingJumpLevels.none と contains(_:) の未使用 public API を消す（CONFIRMED）

`HeadingJumpLevels.swift:16/22`。contains はどこからも呼ばれず、.none はテスト 1 箇所のみ（インライン構築で代替可能）。呼び出し側が現れたときに再導入する。

### 6. FeatureGate の #if DEBUG 両腕の重複を畳む（CONFIRMED）

`FeatureGate.swift:22` 付近、両腕がリテラル 1 つ違いで同じ呼び出しを繰り返す。isDebugBuild だけを #if で決めて呼び出しを 1 本にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 6 項目それぞれについて、実施したか、見送りの理由を Notes に記録したかのどちらかになっている
- [ ] #2 実施した項目は既存テストが通り、必須引数化（項目 1）は破ると落ちるテストか構造で担保されている
<!-- AC:END -->
