---
id: TASK-662.7
title: 実 NSWindow・描画・巨大入力を使うテストを集約・縮小する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 04:30'
updated_date: '2026-09-29 08:17'
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
- [x] #1 SettingsViewSnapshotTests の描画が 1 回になり、ピクセル走査が NSColor を 1 画素ごとに作らない
- [x] #2 SlideWindowIntegrationTests・SessionRestorerTests の実窓の生成回数が減っている（前後の数を Notes に）
- [x] #3 StringChunkReader の上限を注入でき、テスト入力が MB 単位でなくなっている
- [x] #4 統合テストから単体テストへ移したケースは、守っている修正を戻すと移行後のテストが落ちることを確認している
- [x] #5 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. StringChunkReader に maxChunkBytes を注入できる init 引数を足し、static は defaultMaxChunkBytes へ改名する（改名で extension 側の取りこぼしをコンパイルエラーにする）。テストは 16KB の上限で測る
2. TextEncodingTests の所要時間比テストを「判定窓の後ろの不正バイトで結果が変わらない」振る舞いテストへ置き換える
3. SettingsViewSnapshotTests: 描画を static の Result に 1 回だけキャッシュし、表示・アクティベートをやめ、ピクセルは sRGB RGBA8 へ描き直した生バイトで読む
4. UnsupportedFileViewSnapshotTests.damagedDocumentMessageDiffersFromOthers を描画なしの文言比較へ
5. SlideWindowIntegrationTests の slide 側 5 件・通常窓側 3 件を 1 テストずつへ、SessionRestorerTests の表示オプション 4 件を 1 件へ
6. SwipeHistoryMonitorTests は窓 1 枚（defer: true）を共有、SidebarListingSeedTests の canApply 3 件は固定 URL
7. 移したテストが修正を戻すと落ちることを確認し、前後の時間を測る
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容
- StringChunkReader: init に maxChunkBytes を足し（既定は defaultMaxChunkBytes = 1MB）、static を defaultMaxChunkBytes へ改名した。改名したのは、extension 側に Self.maxChunkBytes が残ると注入が黙って効かなくなるため（残っていればコンパイルエラーになる）。本番の呼び出し元（ViewerLoadPipeline）は既定値のまま
- StringChunkReaderTests / StringChunkReaderMarkdownTests: バイト上限を扱う 8 件を上限 16KB の注入で測る。16KB にしたのは、1000 行の "a,b,c\\n"（6KB）とクォート規定長（500 バイト）の両方より十分大きくないと、測りたい分岐に届かないため。unbalancedQuoteLargeCSVIsChunked は 300,000 行（1.8MB）→ 30,000 行（180KB）
- NormalizedTextCacheLazyGrowthTests は改名だけを追随した（正規化窓 2MiB を超える必要があるテストなので、入力は縮めていない）
- TextEncodingTests: 9MB を 12 回判定して時間比をとるテストを、「Shift_JIS の先頭（> sniffLength）の後ろに 0xFF を置いても Shift_JIS と判定される」振る舞いテストへ置き換えた
- SettingsViewSnapshotTests: 描画を static の Result に 1 回だけキャッシュした（BEFOLD_SNAPSHOT_GROUPING=0 の目視用だけは別に描く）。showAndActivate をやめ、表示もアクティベートもせずに cacheDisplay で描く。ピクセルは CGContext（sRGB / RGBA8）へ描き直した生バイトで読み、1 画素ごとに NSColor を作らない
- UnsupportedFileViewSnapshotTests.damagedDocumentMessageDiffersFromOthers: 描画 3 回 + PNG 3 回をやめ、localizedMessage の比較だけにした（バナーは rejectReason.localizedMessage をそのまま描く。描かれることは drawsTheDamagedDocumentMessage が測る）
- SlideWindowIntegrationTests: slide 側の性質 5 件を slideWindowProperties、通常窓側 3 件を viewerWindowCounterparts へまとめた。kind.allowsSidebar は ViewerWindowKindTests が窓なしで測っているので、ここからは外した
- SessionRestorerTests: hiddenFiles / lineNumbers / sortOrder / noOptions の 4 件を optionsApplyToRestoredWindowWithoutPersisting の 1 件にした。オプション未指定の復元は restoreLastSessionDropsMissingFilesFromRecord が通る。restoreKeepsTabGroupsStableAcrossTwoRestarts は currentSessionLayout が NSApp の全窓を見るため、他テストの窓に左右される（既存コメントのとおり、自分のパスに関係するグループだけを比べて回避している）。直列時は 1.0 秒でこのスイートの最大
- SwipeHistoryMonitorTests: 窓を static の 1 枚（defer: true）で共有した。handlePhase は窓を見ない
- SidebarListingSeedTests: canApply の 3 件は実在しない固定 URL にした（一時ディレクトリと 4 ファイルを作らない）

## AC#2 実窓の生成回数
- SlideWindowIntegrationTests: 13 件 15 枚 → 7 件 9 枚
- SessionRestorerTests: 12 件 22 枚 → 9 件 19 枚
- SettingsViewSnapshotTests: 4 枚（どれもアクティベートあり）→ 1 枚（アクティベートなし）

## AC#4 修正を戻すと落ちること（実測）
一時的に戻してビルドし、対象テストだけを回した（確認後に戻した）:
- TextEncoding.detectWithFallback の 2 段目を data 全体での判定にする → legacyDetectionLooksOnlyAtSniffWindow が detectEncoding(head + tail) == .shiftJIS で落ちた
- StringChunkReader+Quotes の不均衡クォート放棄（quotedRunLength > maxQuotedFieldBytes）を無効化 → unbalancedQuoteLargeCSVIsChunked が count >= 25 と <= 10000 の 2 件で落ちた（16KB の上限でも検出できる）
- RejectReason.damagedDocument の文言キーを tooLarge に差し替える → damagedDocumentMessageDiffersFromOthers が落ちた

## AC#5 計測（手元、debug、2026-09-29）
- 対象 10 スイートの --no-parallel --filter: 77 件 7.19 秒 → 75 件 4.95 秒（NormalizedTextCacheLazyGrowthTests を後から足したので変更後は 1 スイート多い）
  - SettingsViewSnapshot 1.41 → 0.41、StringChunkReader 0.73 → 0.05、TextEncoding 0.84 → 0.44、SlideWindowIntegration 0.85 → 0.51、SessionRestorer 2.62 → 2.39、StringChunkReaderMarkdown 0.08 → 0.01
- swift test（並列）全体: 変更前 38.8 秒（2005 件）→ 変更後 37.7 / 36.6 秒（1996 件）
- swift test --no-parallel 全体: 変更前 47.7 秒 → 変更後 45.5 秒
- 並列・直列とも全件緑。swiftlint は main 比で新規ゼロ（/swiftlint-baseline）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
巨大入力と実窓・描画を繰り返し作っていたテストを縮めた。StringChunkReader の上限を注入できるようにして MB 単位の入力をやめた。時間比のテストは振る舞いのテストへ置き換えた。設定ビューの描画は 1 回にしてアクティベートをやめ、ピクセルは生バイトで読む。Slide / SessionRestorer の窓は 1 フィールド違いのテストをまとめて減らした。対象スイートの直列は 7.19 → 4.95 秒、全体は並列 38.8 → 36.6〜37.7 秒、直列 47.7 → 45.5 秒。移行したテストは、守っている修正を戻すと落ちることを確かめた。
<!-- SECTION:FINAL_SUMMARY:END -->
