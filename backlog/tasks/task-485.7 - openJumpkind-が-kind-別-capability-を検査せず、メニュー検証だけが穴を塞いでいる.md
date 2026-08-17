---
id: TASK-485.7
title: 'openJump(kind:) が kind 別 capability を検査せず、メニュー検証だけが穴を塞いでいる'
status: To Do
assignee: []
created_date: '2026-08-17 14:02'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: bug
ordinal: 714800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`WebViewCommandController.openJump(kind:)`（`BefoldApp/befold/App/WebViewCommandController.swift:114`）は粗い `capabilities().canJump` しか guard せず、kind 別の規則（changeBlock は showsDiff が必要）はメニュー検証（ViewerMenuValidator）だけで守られている。`ViewerCapabilitiesFactory.swift:39-41` は「メニュー検証とコマンド guard の両方を capability で閉じる」と述べており、実装と矛盾する。

per-kind API 自体は存在する（`ViewerCapabilities.canJump(to:)`、`ViewerCapabilities.swift:103-107`）が、コマンド経路の誰も呼んでいない。kind は `DocumentRendering.swift:39` / `WebViewDocumentRenderer.swift:68` を生 String で通るため、コンパイラは per-kind 検査を強制できない。

再現シナリオ: 差分表示中にメニューが「変更ブロックへ移動」を有効と検証 → メニュー追跡中に file watcher 由来の更新で plain source へフォールバック（showsDiff=false）→ クリックが粗い guard を通過し、非差分ビューに 0/0 の changeBlock バーが開く。レース自体は稀で結果も良性（0/0 バー）だが、将来の非メニュー入口（stable 昇格時のキーバインド・ツールバー）が同じ穴を継承する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コマンド経路（openJump）が kind 別 capability で閉じている
- [ ] #2 showsDiff=false のとき changeBlock ジャンプが開かないことをテストが固定する
- [ ] #3 将来の入口が per-kind 検査を迂回できない構造（生 String 渡しの見直しを含めて検討する）
<!-- AC:END -->
