---
id: TASK-604.3
title: AppDelegate からパネル提示と窓生成の合成を切り出す
status: Done
assignee: []
created_date: '2026-09-09 00:01'
updated_date: '2026-09-09 00:34'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: medium
ordinal: 879000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/AppDelegate` グループは 398 行（`AppDelegate.swift` 327 + `+HostedPanels.swift` 71）。

## 返済先（約 −110 行、398 → 約 287）

**(a) 単一インスタンスパネル → `HostedPanelPresenter`（−72）**
`AppDelegate+HostedPanels.swift:14-70` の `makePanelController` は `AboutView` / `SettingsView` / `FeatureOverviewView` / `KeyboardShortcutsView` / `AIIntegrationView` / `OSSLicensesView` と窓の寸法・リサイズ可否の対応表で、ライフサイクルとは無関係。規約「独立して使える部品は別ファイルに置く」の対象。

`AppDelegate.swift:32` の `var hostedPanels: [HostedPanel: HostedPanelWindowController]` は **AppDelegate 唯一の可変 stored property**（他 8 個は `let`）。`stores` を private にできない理由（`AppDelegate.swift:23-26` の doc）もこの extension が `codeFontPreference` を読むことに由来しており、レジストリごと出せばその制約も消える。6 つの @objc は `panels.toggle(.about)` へ変わるだけでレスポンダチェーン上の位置は変わらない。

**(b) 窓生成の合成点 → `ViewerWindowManagerFactory`（−29）**
`AppDelegate.swift:74-104` の `makeWindowManager` は 13 個の共有依存の配線と `GitStatusStore` の後差しを持つ composition root。`AppStores`（63 行）は「ストアの束」であって組み立て役ではないので新型が妥当。

**(c) 補助（−19）**
`pruneRecentRepositories`（`:138-148`）→ 既存の `RecentRepositoryRecorder`。`UNUserNotificationCenterDelegate` 準拠（`:316-327`）→ `ForegroundNotificationPresenter`。protocol 準拠が 3 → 2 に落ちる。

## 移動できないコード: 約 177 行（44%、支配的ではない）

`MainMenuBuilder.swift` が `#selector(AppDelegate.showAbout(_:))` を target=nil で登録しているため、@objc アクション 15 本（71 行）・セレクタ対応表（17 行）・`validateMenuItem`（31 行）・NSApplicationDelegate 要件（約 50 行）・`main()`（8 行）は動かせない。返済後 287 行で 111 行の余裕。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AppDelegate グループが 300 行以下になっている
- [x] #2 hostedPanels のレジストリが AppDelegate から出ており、stores を private にできない理由が解消しているか、解消しない理由が doc にある
- [x] #3 メニューからのパネル表示が実機で動くことを確認してある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
(a) 単一インスタンスパネルのレジストリと組み立てを HostedPanelPresenter（新規・独立型）へ。(b) 窓生成の合成点を ViewerWindowManagerFactory（新規）へ。AppDelegate+HostedPanels.swift は削除した。

AC #2: stores は private に戻せた。extension が codeFontPreference を読むことだけが internal の理由だったため、レジストリごと出して制約が消えた。同じ理由で windowManager も private にできた（外部の読み手が無いことを事前 grep で確認）。AppDelegate の可変 stored property は 0 個になった。

(c)（pruneRecentRepositories → RecentRepositoryRecorder / UNUserNotificationCenterDelegate → ForegroundNotificationPresenter）は実施しなかった。(a)+(b) で 398 → 291 行になり AC #1 を満たすため必要がなく、いずれも移すと得より損が大きい。prune は worktreeCatalog を必要とするが RecentRepositoryRecorder はそれを持っておらず、依存を 1 本足すことになる。通知 delegate は 1 メソッド 6 行の準拠で、専用の型と保持先を新設するほうが行数も概念も増える。

AC #3（実機確認）: xcodebuild で .app を作って起動し、System Events でメニューから 6 パネルすべてを開けることを確認した（befold について / 機能説明 / キーボードショートカット / AI コーディングエージェント連携 / オープンソースソフトウェア謝辞 / 設定…）。単一インスタンスのトグル（同じ項目を再度選ぶと閉じる）も OSS 謝辞で確認済み。

実測: AppDelegate グループ 398 → 291 行。HostedPanelPresenter 93 行 / ViewerWindowManagerFactory 40 行。swift test 1941 tests / 320 suites 全通過、check-type-group-size.sh exit=0、swiftformat 差分なし。swiftlint は移設で持ち込まれた function_body_length（main にもあった既存警告）を設定ビューの抽出で解消し、新規指摘 0 件。
<!-- SECTION:NOTES:END -->
