---
id: TASK-662.7
title: 実 NSWindow・描画・巨大入力を使うテストを集約・縮小する
status: To Do
assignee: []
created_date: '2026-09-29 04:30'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: medium
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同じ窓・同じ描画を何度も作る、境界を越えさせるためだけに MB 単位の入力を作る、といった準備の重いテスト。多くは MainActor 上で走る。

## 窓・描画（MainActor）
- `SettingsViewSnapshotTests`（直列 1.16 秒）: 4 件がそれぞれ `renderSettingsView()` で `HostedPanelWindowController` を作り `showAndActivate()`（`NSApp.activate` + key 化）してから `cacheDisplay`。ピクセルは `rep.colorAt` + `usingColorSpace(.sRGB)` で 1 画素ごとに NSColor を作って全行を走査する。描画を 1 回にキャッシュし、既知形式のビットマップを生バイトで読み、アクティベートしない形にする
- `UnsupportedFileViewSnapshotTests.damagedDocumentMessageDiffersFromOthers`: 描画 3 回 + PNG 3 回。文言の差は同テスト内の `localizedMessage` 比較で担保済み
- `SlideWindowIntegrationTests`（13 件すべて実窓）: 「slide で 1 回開く」ことの性質 5 件、通常窓側の対 3 件をそれぞれ 1 テストへまとめる。`kind.allowsSidebar` は窓なしで測れる
- `SessionRestorerTests`（直列 2.7 秒、12 件すべて実窓）: `hiddenFiles` / `lineNumbers` / `sortOrder` / `noOptions` は `CLIOpenOptions` の 1 フィールド違い。まとめても個別の #expect で取りこぼしは検出できる。`restoreKeepsTabGroupsStableAcrossTwoRestarts` は `NSApp` の全窓を見るため他テストの窓に左右される点も記録しておく
- `SwipeHistoryMonitorTests`: 積算ロジックのテストで `NSWindow(defer: false)` を毎回作る
- `SidebarListingSeedTests`: `canApply(to:)` の純粋判定 3 件が毎回ホーム配下に一時ディレクトリと 4 ファイルを作る。固定 URL で足りる

## 巨大入力（非 MainActor だが CPU を使う）
- `StringChunkReaderTests` / `StringChunkReaderMarkdownTests`: `maxChunkBytes = 1MB` が static 固定のため 1〜3MB の入力を 7 件前後で作る。init で上限を注入できれば KB 単位で同じ不変条件を測れる
- `TextEncodingTests.detectEncodingCostDoesNotScaleWithDataSize`: 約 9MB の Shift_JIS を作り 12 回判定して時間比を取る（flaky の余地もある）。「sniffLength より後ろに不正バイトを置いても結果が変わらない」という振る舞いの検証へ置き換えられる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SettingsViewSnapshotTests の描画が 1 回になり、ピクセル走査が NSColor を 1 画素ごとに作らない
- [ ] #2 SlideWindowIntegrationTests・SessionRestorerTests の実窓の生成回数が減っている（前後の数を Notes に）
- [ ] #3 StringChunkReader の上限を注入でき、テスト入力が MB 単位でなくなっている
- [ ] #4 統合テストから単体テストへ移したケースは、守っている修正を戻すと移行後のテストが落ちることを確認している
- [ ] #5 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->
