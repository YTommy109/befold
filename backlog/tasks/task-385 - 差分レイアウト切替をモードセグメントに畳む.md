---
id: TASK-385
title: 差分レイアウト切替をモードセグメントに畳む
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-09 08:24'
updated_date: '2026-08-09 08:42'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 643000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ツールバーの差分レイアウト切替ボタン（rectangle.split.2x1、ViewerToolbarController.swift:173-179）を廃止し、モード切替セグメントの差分セグメントに畳む。

## 動機

差分レイアウト切替は「差分モードのサブ設定」なのに、モード選択セグメント・ブックマークと同列の独立ボタンとして並んでいる（階層が 1 段違うものが同列）。しかも差分モード以外では押せないため、常時無効のボタンがツールバーを占有している（消すと幅が動くため出したまま無効化している: ViewerToolbarController.swift:244）。

## 仕掛け

1. 差分セグメントのアイコンを固定の plus.forwardslash.minus から、**現在の差分レイアウトを表すアイコン**へ変える。インライン = plus.forwardslash.minus、左右分割 = rectangle.split.2x1。どちらも既存のシンボルで、それぞれのレイアウトの絵として嘘がない（非 side-by-side はインラインであって上下分割ではない: ViewerWindowController+Diff.swift:54）。
2. 差分モードを選択中に差分セグメントを再クリックするとレイアウトが切り替わる。
3. cmd+\ とメニュー項目は従来どおりで、レイアウト変更に伴いアイコンも変わる。
4. 独立した差分レイアウトのツールバーアイテム（diffLayoutItemIdentifier）を廃止する。

差分モードを選んでいないときも、現在の DiffDisplayPreference の値のアイコンを出す（次に差分へ入ったときのレイアウトと一致させる）。DiffDisplayPreference はアプリ全体で 1 個を共有する（ViewerWindowManager.swift:27）。

## 未検証の前提

- NSSegmentedControl の .selectOne で、選択済みセグメントの再クリックが action を発火するか。発火しない場合は .momentary + 選択状態の自前管理となり applyModeToggleState（:235）の作りが変わる。
- アクセシビリティ: セグメントの accessibilityDescription / ツールチップがモード名と現在のレイアウトの両方を伝える必要がある。

すべて FeatureGate.isSourceDiffEnabled の内側（commit には (gate) スコープを付ける）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差分レイアウトの独立ツールバーアイテムが存在しない
- [x] #2 差分セグメントのアイコンが現在の差分レイアウトを表す（インラインと左右分割で異なる）
- [x] #3 差分モード選択中に差分セグメントを再クリックするとレイアウトが切り替わる
- [x] #4 cmd+\ / メニューからレイアウトを変えたときもセグメントのアイコンが追従する
- [x] #5 差分セグメントのアクセシビリティ説明とツールチップが、モードと現在のレイアウトの両方を伝える
- [x] #6 ゲート OFF 相当の構成で差分セグメント自体が存在しないことがテストで担保される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. **先に実機で確認**: NSSegmentedControl(.selectOne) が選択済みセグメントの再クリックで action を発火するか。発火しなければ .momentary + 選択の自前管理へ切り替える（applyModeToggleState の作りが変わるため、ここで方針が分岐する）。

1. ModeSegments.symbol(for:) を symbol(for:isSideBySide:) にする。差分は isSideBySide ? "rectangle.split.2x1" : "plus.forwardslash.minus"、他モードは従来どおり。ゲート注入（modes(isSourceDiffEnabled:)）と同型の純粋関数にして 2 状態をユニットテストで押さえる。生成コストを避けるため NSImage は 2 枚を static に持つ。

2. applyModeToggleState(:235) で、選択状態・有効/無効に加えて差分セグメントの image / ツールチップ / accessibilityDescription を毎回反映する（生成時だけでは ⌘\ に追従しない）。文言は ViewerCommandTitles にレイアウト込みのものを足す（lineNumbers(isShown:) / bookmark(isBookmarked:) と同型）。

3. modeSegmentChanged で、入口の host.effectiveDisplayMode が .diff かつクリック先も差分セグメントなら setDisplayMode ではなく toggleDiffLayout を呼ぶ。判定は sender.selectedSegment（AppKit が更新済み）ではなく host の状態を真実の源にする。

4. レイアウト変更をツールバーへ再同期する経路を足す。ViewerWindowController+Diff.toggleDiffLayout は preference を書くだけで refreshToolbarState を呼んでおらず（他窓も含めて）アイコンが取り残される。ViewerWindowManager の viewerWindowDidToggleHiddenFiles / ...ChangedFilesOnly と同型のデリゲート通知を足し、refreshAllToolbars() へ合流させる。

5. セグメント幅のジッター対策。makeModeSegmentedControl(:371) は『ラベル固定だから幅が動かない』を前提にしている。2 シンボルで幅が変わるか実測し、変わるなら setWidth(forSegment:) で固定する。

6. 独立アイテム（diffLayoutItemIdentifier / diffLayoutItemClicked / applyDiffLayoutState）と layout(:173-179) の分岐を撤去する。ViewerToolbarControllerTests の defaultItemIdentifiers の期待値を更新する。

7. 記録する判断: 狭いウィンドウのオーバーフロー(»)メニューからレイアウト切替が消えることを許容する（View メニューと ⌘\ が残る。埋めるにはセグメント全体の menuFormRepresentation が要り、廃止したはずの構造が戻る）。

/review-design の結果: 上記 1〜5 が指摘由来。該当しない項目は 2（セグメント添字の解決規則を変えない）・8（非同期の着地なし）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装済み。

判断と担保:
- 再クリック判定は ModeSegments.action(for:current:) の純粋関数へ切り出した。AppKit のマウスイベントを起こさずに『差分表示中の差分セグメントだけがレイアウト切替』を 5 ケースで固定できる。
- アイコンはシンボル名ごとに 1 枚を static にキャッシュし、テストは同一性で実アイテムへの反映を確かめる（refreshToolbarState は onContentReloaded 等から高頻度に走るため毎回 NSImage を作らない）。
- **設計レビューで見つけた既存の穴**: toggleDiffLayout は preference を書くだけで refreshToolbarState を呼んでおらず、⌘\ でレイアウトボタンの色が更新されていなかった（コード参照からの推論）。アイコン化するとこれが致命傷になるため、viewerWindowDidToggleDiffLayout 通知 → refreshAllToolbars() を足した。DiffDisplayPreference はアプリ全体共有なので全窓が対象。通知の有無はテストで固定した。
- セグメント幅を setWidth で固定した。makeModeSegmentedControl は『ラベル固定だから幅が動かない』を前提にしていたため、アイコン入替でこの前提が崩れる。
- ViewerToolbarController.swift が 400 行の上限を新たに超えた（main 392 → 429）ため ModeSegments を独立ファイルへ分割。.swiftlint.yml の feature_gate_direct_reference allowlist と FeatureGate.swift の列挙も追従（FeatureGateEnumerationTests が両者を突き合わせるため、片方だけ直すと落ちる）。

記録した判断（許容）: 狭いウィンドウのオーバーフロー(»)メニューからレイアウト切替は消える。モードセグメントは menuFormRepresentation を持てない（分解できない）ため。View メニューと ⌘\ が残るので操作不能にはならず、埋めるには廃止したはずの独立アイテムが戻る。

検証:
- swift test 1221 tests / 178 suites 全成功（新規: アイコンの 2 状態・再クリック判定 5 ケース・レイアウト変更のアイコン追従・通知の有無）
- swiftformat --lint 0 件、swiftlint は変更ファイルで新規警告なし
- 実機（dev ビルド）でユーザーがボタン操作・キーボード操作の双方の動作を確認。NSSegmentedControl(.selectOne) は選択済みセグメントの再クリックで action を発火する（Plan の手順 0 の未検証前提はこれで解消。.momentary へ切り替える代替案は不要だった）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツールバーの差分レイアウト切替ボタンを廃止し、モード切替セグメントの差分セグメントに畳んだ。差分セグメントのアイコンが現在のレイアウト（インライン=plus.forwardslash.minus / 左右分割=rectangle.split.2x1）を表し、差分表示中の再クリックで切り替わる。あわせて、従来 preference を書くだけでツールバーへ再同期していなかった経路にデリゲート通知を足し、⌘\ やメニューからの変更・他ウィンドウのアイコンも追従するようにした。検証は swift test 1221 tests 全成功と、dev ビルド実機でのボタン/キーボード両操作の動作確認。
<!-- SECTION:FINAL_SUMMARY:END -->
