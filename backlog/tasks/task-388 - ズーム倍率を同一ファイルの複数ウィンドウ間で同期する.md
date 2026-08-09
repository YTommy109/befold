---
id: TASK-388
title: ズーム倍率を同一ファイルの複数ウィンドウ間で同期する
status: To Do
assignee: []
created_date: '2026-08-09 10:12'
labels:
  - zoom
dependencies:
  - TASK-382
priority: medium
type: bug
ordinal: 515000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0002 の「状態の所在」の基準（TASK-382 で追加）を当てた結果の逸脱。

ズーム倍率は ZoomStore がファイルパス単位で永続化する（BefoldApp/befold/App/ZoomStore.swift:6,17,21-30）。基準では「文書の性質に属する状態」であり、同一ファイルを開いた全ウィンドウで一致していなければならない。しかし表示モード（ViewerWindowManager.mirrorDisplayMode）にあたる窓間同期の経路が存在しない。

実測:
- 保存は WebViewCommandController.swift:55-62 / ViewerWindowController.swift:576
- 適用は WebViewCommandController.swift:44-47（applyStoredZoom）
- 窓 A で cmd+プラス を押すと共有辞書は更新されるが、窓 B の WKWebView には反映されない。B がファイル切替・再ロード・ウィンドウ再生成で applyStoredZoom を通ったときに初めて A の値へ飛ぶ

設計で決めること:
- 表示モードと同じ「setZoom の完了後にデリゲート経由 → ViewerWindowManager がパスキー引きでミラー」の形に揃えるか
- ミラー側が永続化も再通知もしない（無限再帰を構造的に防ぐ）点は表示モードと同じにする
- そもそもズームを「文書の性質」ではなく「窓ごとの見え方」と再定義する選択もありうる。その場合は ZoomStore の粒度自体を見直すことになり、ADR 0002 の基準側を修正する

着手前に /review-design を回すこと（既存の共通経路と不変条件に触れるため）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一ファイルを開いた 2 つのウィンドウでズーム倍率が食い違わない、または「同期しない」と決めた場合はその判断と理由が ADR 0002 に反映されている
- [ ] #2 決めた粒度が破れたら落ちるテストがある
<!-- AC:END -->
