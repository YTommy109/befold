---
id: TASK-515
title: CI の ThreadSanitizer ジョブが ViewerNavigationCoordinator の unowned 参照でクラッシュする
status: Done
assignee: []
created_date: '2026-08-18 08:16'
updated_date: '2026-08-18 08:32'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 755000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485（#559）で ViewerRenderer から切り出した ViewerNavigationCoordinator が renderer を unowned で持ち、かつ `webView(_:decidePolicyFor:)` を async 版で実装していたため、CI の thread-sanitizer ジョブがテスト全件 passed の直後に signal 6 で落ちる（run 32103739053）。

async な @objc delegate メソッドはランタイムが Task を作り self（= コーディネータ）だけを強参照するため、サスペンド中に renderer だけが解放されうる。#559 以前は self が ViewerRenderer 自身だったので Task が renderer を生かしていた。

ReferenceResolutionQueue の TASK-448 と同型（unowned な逆参照を、所有者の死後に読む）。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に該当する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 thread-sanitizer 相当（swift test --sanitize=thread）を複数回まわしてクラッシュが再発しない
- [x] #2 ViewerNavigationCoordinator が renderer を unowned で保持していない
- [x] #3 ナビゲーション delegate に async 版を使わない理由が型のドキュメントに残っている
- [x] #4 renderer 解放後にコールバックが届いてもトラップしないことを固定する回帰テストがあり、unowned へ戻すと落ちることを実測している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因（実測）

バックトレースで確定した（ローカル TSan で再現、`SWIFT_BACKTRACE=enable=yes`）:

```
swift_unownedRetainStrong
ViewerNavigationCoordinator.webView(_:decidePolicyFor:) + 188
  at BefoldRenderKit/ViewerNavigationCoordinator.swift:47:9
[async][thunk] @objc closure #1 in ViewerNavigationCoordinator.webView(_:decidePolicyFor:)
```

async な @objc delegate メソッドは completion-handler 版から呼ばれると必ず一度サスペンドし、
ランタイムが作る Task は self（= コーディネータ）だけを強参照する。
`webView.navigationDelegate` は weak、所有は renderer → coordinator の一方向なので、
飛行中の Task だけが coordinator を生かし renderer は先に解放されうる。
#559 以前は self が ViewerRenderer 自身だったため Task が renderer を生かしていた。

## 対処

1. `renderer` を unowned → weak にし、各コールバックで guard する
2. `decidePolicyFor` を async 版から completion-handler 版へ戻す
   （サスペンドが消えるので窓そのものが生まれない）
3. 型の doc コメントに「ここへ delegate を足すときも completion-handler 版を選ぶ」を明記

## 検証（実測）

- 修正前: 全件 TSan を 3 回まわして 3 回目でクラッシュ再現（full-3.log にバックトレース）
- 修正後: 全件 TSan を 6 回連続 exit=0、unowned トラップ 0 件
- swift test 1641 件 passed
- swiftlint: origin/main とのベースライン差分ゼロ（54 件）
- 回帰テストは `weak` を `unowned` へ戻すと同じ Fatal error で落ちることを実測

## 申し送り

同じ形（unowned な逆参照）は ViewerScriptDispatcher / BridgeMessageRouter /
DirectHTMLModeController / PageZoomProjector / ViewerWindowSessionSync にも残っている。
今回は経路が確定した 1 型だけを直した。全型を weak へ統一するかは別途判断が要る。
<!-- SECTION:NOTES:END -->
