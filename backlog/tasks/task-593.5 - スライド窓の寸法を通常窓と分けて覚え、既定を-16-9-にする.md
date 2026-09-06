---
id: TASK-593.5
title: 'スライド窓の寸法を通常窓と分けて覚え、既定を 16:9 にする'
status: Done
assignee: []
created_date: '2026-09-06 11:10'
updated_date: '2026-09-06 13:37'
labels:
  - sidebar
  - slide-mode
dependencies: []
parent_task_id: TASK-593
priority: medium
type: bug
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ユーザーからの問い（スライド窓のサイズはどう決まっているか / 画面共有とプロジェクターで変えるべきか）を調べた結果、**スライド窓は寸法を一切自分で決めておらず**、通常窓とまったく同じ経路（`WindowFrameStore.lastUserAdjustedFrameDescriptor` → 無ければ `ViewerWindowChrome.defaultContentSize` = 1100×850）だった。

これに伴うバグがある。`windowDidEndLiveResize` → `ViewerWindowSessionSync` → `WindowFrameStore.recordUserAdjustedFrame` が**種別を見ずに走る**ため、プレゼン用にスライド窓を 16:9 へ広げると、次に開く通常のビューア窓もその寸法で開く。TASK-593.2 で潰した `setCollapsed` と同型（用途特化の調整が全体の既定へ漏れる）。

## 決定

- 寸法の記憶を**窓の種別ごと**（`.viewer` / `.slide` の 2 値）にする
- スライド窓の既定を **1280×720（16:9）** にする
- **出力先（画面共有 / プロジェクター）では分けない。** 必要な比が今はどちらも 16:9 で差が小さい一方、アプリは出力先を判定できず必ず手動切り替えになる。切り替え忘れが「意図しない比で映る」害になる
- フルスクリーンはアプリから強制しない（ユーザー判断 / 2026-09-06）。`collectionBehavior` に `.fullScreenPrimary` は入ったままなので、利用者が自分で操作するぶんには従来どおり効く
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライド窓は保存された寸法が無ければ 16:9（1280×720）で開く
- [x] #2 スライド窓をリサイズしても通常窓の既定寸法が変わらない（逆も同じ）
- [x] #3 スライド窓が未調整のとき、通常窓の寸法へフォールバックしない
- [x] #4 通常窓は既存の保存キー `WindowFrameLastUserAdjusted` をそのまま読み、利用者の既存の寸法が失われない
- [x] #5 ADR 0010 に粒度を広げた追補があり、ファイル単位を退けた理由が巻き戻っていないことが書かれている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

- `ViewerWindowKind.defaultContentSize`: `.viewer` は 1100×850（従来値）、`.slide` は 1280×720（16:9）。`ViewerWindowChrome.defaultContentSize` の定数は種別側へ移した
- `ViewerWindowChrome.applyInitialFrame(_:to:kind:isOccupied:)`: `kind` を**既定値なし**で受ける（渡し忘れるとスライド窓が 16:9 でない寸法で開く形が静かにできる）
- `WindowFrameStore`: `recordUserAdjustedFrame(_:for:)` / `lastUserAdjustedFrameDescriptor(for:)` へ。キーは `.viewer` = 既存の `WindowFrameLastUserAdjusted`、`.slide` = 新設の `WindowFrameLastUserAdjustedSlide`
- 書き手（`ViewerWindowSessionSync`）と読み手（`ViewerWindowManager.makeController`）が `controller.kind` / `kind` を渡す

## UserDefaults キーの扱い（規約チェック）

**旧キーの削除・改名・意味の変更はしていない。** 通常窓は既存キーをそのまま読むので移行は不要で、
新設はスライド窓の側だけ。`rg` で `WindowFrameLastUserAdjusted` の読み手が 0 になっていないことを
確認済み（`WindowFrameStore.lastUserAdjustedKey(for:)` の `.viewer` 分岐が読む）。

**種別をまたぐフォールバックは入れない。** スライド窓が未調整のときに通常窓の値を借りると、
避けたい「文書用の寸法でプレゼンが始まる」が初回に起きる。テストで固定した。

## ADR 0010 との関係

ADR 0010 は「新しいウィンドウの寸法はアプリ全体で 1 個」。粒度を種別ごと 2 値へ広げたので、
**巻き戻しではなく追補**として同 ADR に日付つきで追記した。あの ADR が退けたのはファイル単位
（記憶が無限に増え、後からの調整が過去のファイルへ永久に届かない / 実測 104 件中一致 1 件）で、
閉じた 2 値ではその失敗モードが再現しない。ファイル単位の API を置かない規則は変えていない。

## 検証（実測）

- `swift test`: `Test run with 1911 tests in 313 suites passed after 42.543 seconds.`（593.4 時点の 1905 件 + 新規 6 件）
- `xcodebuild build -scheme befold -configuration Debug`: exit 0
- swiftlint ベースライン差分: 真の新規 0
- `check-type-group-size.sh --check` / `markdownlint-cli2` / `check-doc-symbols.sh` / `check-doc-citations.sh`: いずれも通過
- **逆検証**: `recordUserAdjustedFrame(descriptor, for: controller.kind)` を `.viewer` 固定へ戻すと、統合テストが実際に落ちて漏れを再現することを確認した（`lastUserAdjustedFrameDescriptor(for: .viewer)` が `"0 0 1600 900 ..."` に書き換わり、`.slide` 側は nil のまま）

## 未検証

16:9 が画面共有・プロジェクターで実際に見やすいかは主観の伴う判断なので、実機での確認は
利用者に委ねる。既定値を変えたいだけなら `ViewerWindowKind.defaultContentSize` の 1 箇所。

## 追記: CI で落ちたテストを直した（2026-09-06）

`SlideWindowIntegrationTests` の「スライド窓は保存された寸法が無ければ 16:9 で開く」が
GitHub Actions の macOS ランナーで失敗した（実測: 比が 1.52、期待 16:9 = 1.778）。

**原因はテストの測る対象。** `window.contentView.frame.size` という**実現された窓の寸法**を
アサートしていたが、AppKit は窓をディスプレイに合わせて切り詰めるため、CI の仮想
ディスプレイでは 16:9 にならない。守りたいのは「既定値が 16:9 であること」で、実現された
寸法は AppKit の都合。手元では画面が大きいため通っており、環境依存に気づけなかった。

`ViewerWindowKind.slide.defaultContentSize` を直接測る純粋なテストへ移し
（`ViewerWindowKindTests`）、通常窓の既定値 1100×850 も対で固定した。統合テスト側からは
寸法のアサートを削除した（窓の生成そのものは他のケースが見ている）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スライド窓の寸法を通常窓と別に覚えるようにし（`WindowFrameStore` を窓の種別ごと 2 値へ）、既定を 16:9（1280×720）にした。あわせて「スライド窓をリサイズすると次に開く通常窓まで同じ寸法になる」漏れを塞いだ。出力先（画面共有 / プロジェクター）での分岐は、アプリが出力先を判定できず手動切り替えの忘れが害になるため採らなかった。判断の経緯は ADR 0010 の追補に記録。
<!-- SECTION:FINAL_SUMMARY:END -->
