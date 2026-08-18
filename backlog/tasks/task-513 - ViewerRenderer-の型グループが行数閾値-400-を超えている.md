---
id: TASK-513
title: ViewerRenderer の型グループが行数閾値 400 を超えている
status: To Do
assignee: []
created_date: '2026-08-18 02:16'
labels: []
milestone: m-6
dependencies: []
priority: medium
type: chore
ordinal: 753000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`scripts/check-type-group-size.sh` が pre-commit で次を報告する。

```
閾値超過: BefoldApp/BefoldRenderKit/ViewerRenderer が 404 行（閾値 400）
```

内訳（TASK-485.6 のコミット時点、ブランチ falcon-ocotillo）:

| ファイル | 行数 |
| --- | --- |
| `ViewerRenderer.swift` | 243 |
| `ViewerRenderer+ContentUpdate.swift` | 89 |
| `ViewerRenderer+RenderHelpers.swift` | 72 |
| 合計 | 404 |

`origin/main` 時点では 397 行で閾値内だった（`ViewerRenderer.swift` が 236 行）。
TASK-485.x の実装（文書内ジャンプの Swift 側配線）で 7 行増えて超えたもの。

このチェックは現状 exit 0 の助言レベルで、コミットは通る。そのため気づかれずに
増え続ける経路になっている。

## 方針の注意

CLAUDE.md のとおり、**閾値を緩める（`scripts/type-group-exceptions.txt` への追記）を
既定の解にしない**。合算値は extension へ割っても減らないため、責務を別の型へ
切り出すのが本筋。着手時に `ViewerRenderer` の責務（WKWebView ドライバ・
ブリッジ送信・描画ミラーの確定）のどれを分けられるかを先に見る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerRenderer の型グループ合計が 400 行以下になる
- [ ] #2 分割は extension ではなく別の型への切り出しで行う（合算値が減ることを check-type-group-size.sh で確認する）
- [ ] #3 type-group-exceptions.txt への追記で済ませていない、または追記した場合は理由が Notes に実測付きで残っている
- [ ] #4 swift build / swift test が通り、swiftlint のベースライン差分がゼロ
<!-- AC:END -->
