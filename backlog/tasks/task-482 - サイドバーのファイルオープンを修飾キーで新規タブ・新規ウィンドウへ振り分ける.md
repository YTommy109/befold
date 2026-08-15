---
id: TASK-482
title: サイドバーのファイルオープンを修飾キーで新規タブ・新規ウィンドウへ振り分ける
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 12:22'
updated_date: '2026-08-15 10:31'
labels:
  - feature
milestone: m-2
dependencies: []
priority: high
ordinal: 699000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの行をクリックすると常に現在のタブでファイルが差し替わる（`FileListView.swift:117-141` のシングルタップが `switchFile` へ直行）。別タブ・別ウィンドウで開く手段は右クリックメニュー（`SidebarContextMenu.swift:34-37`）だけで、ビューア内の Markdown リンクが既に持っている修飾キーの操作体系がサイドバーには届いていない。

befold には修飾キーから開き方を決める単一の対応表 `OpenDisposition`（`BefoldKit/OpenDisposition.swift:16-22`）が既にあり、Markdown リンク（`BridgeMessageRouter.swift:54-64`）と直接 HTML モード（`DirectHTMLLinkPolicy.swift:17-47`）の両方がこれを通している。サイドバーだけがこの表を通っていない状態なので、新しい規則は作らず既存の表へ配線する。

対応表（既存・変更しない）:

| 修飾 | disposition |
|---|---|
| なし | `.currentTab` |
| ⌘ | `.newTab` |
| ⌘⇧ | `.newWindow` |
| ⌃ / 右クリック | コンテキストメニュー（開かない） |

配線先も既存で、`FileListViewDelegate.fileListDidSelectFile(_:)` と `fileListDidRequestOpenElsewhere(_:disposition:)`（`FileListViewDelegate.swift:20,26`）の 2 本がそのまま使える。新しい状態も新しい経路も増えない。

VSCode の Explorer では ⌘クリックは複数選択・⌥クリックが横に開くだが、befold のサイドバーは単一選択（`model.selection` が単一の id）で複数選択の概念が無く ⌘ が空いている。VSCode に合わせるのではなく befold 内のリンク操作へ揃える判断を採る（ユーザー確認済み）。

修飾キーの取得は `NSEvent.modifierFlags` をハンドラ内で読む方式を採る。`SpatialTapGesture` は修飾キーを運ばないため何らかの取得手段が要るが、`HistoryButtonView.swift:37-41` が既に同じ方式で ⌘/⌃クリックを判定しており前例と一致する。`NSClickGestureRecognizer` を重ねる案は、行の当たり判定を AppKit 側へ持ち込むため採らない（ユーザー確認済み）。

キーボード操作も同時に揃える。`SidebarKeyAction.action(key:modifiers:target:mode:)`（`SidebarKeyAction.swift:59-79`）は既に `EventModifiers` を受け取っており、Return に ⌘ / ⌘⇧ を足す形で拡張できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーのファイル行を ⌘ クリックすると、現在のタブの表示を変えずに同じタブグループの新規タブでそのファイルが開く
- [x] #2 サイドバーのファイル行を ⌘⇧ クリックすると、現在のタブの表示を変えずに新規ウィンドウでそのファイルが開く
- [x] #3 ⌘ / ⌘⇧ クリックでは `model.selection` が移動しない（サイドバーの選択はそのウィンドウが表示中のファイルを表す不変条件を保つ）
- [x] #4 修飾キー無しのクリックは従来どおり現在のタブで表示が差し替わり、選択も移動する
- [x] #5 ⌃ クリックではファイルを開かない（コンテキストメニューに委ねる）
- [x] #6 開閉三角の当たり判定（`SidebarRowIndent.isWithinDisclosure`）は修飾キーの有無にかかわらず従来どおり最優先で処理される
- [x] #7 サイドバーにフォーカスがある状態で ⌘Return は新規タブ、⌘⇧Return は新規ウィンドウでファイルを開き、修飾キー無しの Return は従来どおり現在のタブで開く
- [x] #8 修飾キーの対応表は `OpenDisposition` の 1 箇所のままで、サイドバー用の独自の判定表を新設していない
- [x] #9 ユニットテストが ⌘ / ⌘⇧ / 修飾なし / ⌃ の 4 ケースについて、呼ばれるデリゲートメソッドと disposition、および selection が動くかどうかを検証している
- [x] #10 テストは修正を戻すと落ちることを確認済み
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListView: singleTapGesture の三角 early-return 後の処理を internal な handleRowTap(entry, modifiers: NSEvent.ModifierFlags) へ抽出し、ジェスチャ側は NSEvent.modifierFlags を読んで渡す（handleKey(_:modifiers:) と同じ流儀。注入クロージャは既に 4 本あるため readModifierFlags 注入は採らない）。handleRowTap: ⌃ を含めば何もしない → OpenDisposition(modifiers:) で判定 → .currentTab は従来どおり selection 更新 + openIfFile + focus、.newTab/.newWindow はファイル行のみ selection を動かさず fileListDidRequestOpenElsewhere。フォルダ行は修飾に関わらず従来動作。selection 更新は必ず disposition 判定の後。
2. doubleTapGesture: 修飾 ⌘/⌃ を含むときは何もしないガードを追加（⌘クリック 2 連打で double 側の currentTab オープンが発火し「表示を変えない」が破れるのを防ぐ）。
3. SidebarKeyAction: .openFile に OpenDisposition の連想値を追加（既定 .currentTab 相当は forward が .openFile(.currentTab) を返す）。case .return where modifiers.contains(.command) を通常の .return より前に追加し、target が .file なら .openFile(OpenDisposition(commandKey: true, shiftKey: modifiers.contains(.shift)))、それ以外は .ignored。disposition の導出は OpenDisposition へ委譲し、SidebarKeyAction に独自対応表を作らない。
4. 連想値追加後、rg '\.openFile' で全消費箇所を列挙して束縛付きパターンへ書き換える（case .openFile: は連想値付きでも黙って全マッチするため、コンパイラでは検出されない）。既知: FileListView+Keyboard.swift:61（performOnSelectedEntry）、SidebarKeyActionTests.swift:63。.openFile(let d) の消費側: .currentTab → openIfFile、それ以外 → entry.kind == .file なら fileListDidRequestOpenElsewhere。
5. TDD: 先にテスト。(a) handleRowTap の 4 ケース（修飾なし/⌘/⌘⇧/⌃）で FileListViewDelegateSpy の selected/openedElsewhere と model.selection を検証、(b) SidebarKeyActionTests に ⌘Return→.openFile(.newTab)・⌘⇧Return→.openFile(.newWindow)・Return→.openFile(.currentTab)、(c) キーボード消費側の openElsewhere 貫通。実装を戻して落ちることを確認（AC #10）。
6. SidebarContextMenu.swift:5-9 の責務分離コメント更新、docs/dev/native-app-design.md 追随、xcodegen 不要（新規ファイルなし）を確認。
未確認前提: SpatialTapGesture.onEnded 時点の静的 NSEvent.modifierFlags がクリック時の修飾状態を表す（ハンドラ同期実行のため成立見込み。実機 /run で ⌘クリックを確認する）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
設計レビュー(/review-design)の反映: (1) readModifierFlags クロージャ注入は採らず、handleKey と同じ「ジェスチャ側で NSEvent.modifierFlags を読んで internal メソッド handleRowTap へ渡す」方式にした(FileListView への注入クロージャは既に 4 本で規定超過のため)。(2) .openFile に連想値を足すと case .openFile: が黙って全マッチするため rg で消費箇所を全列挙して束縛付きへ書き換えた(消費箇所は FileListView+Keyboard.swift の 1 箇所 + テスト)。(3) 計画にあった doubleTapGesture の ⌘ ガードは不要と判明: performRowAction は .openFile を default: break で無視するため(FileListView.swift:95-102)、ダブルクリック経路から現在タブのオープンは発火しない。⌘クリック 2 連打はクリック回数どおり 2 タブ開く(許容)。
検証: swift test 全 1455 件 GREEN。RED はコンパイル失敗(handleRowTap 未定義 / openFile 連想値なし)で確認、さらにサボタージュ(⌘タップ経路で selection を動かす)で ⌘/⌘⇧ タップの 2 テストが落ちることを実測し AC #10 を担保。swiftlint main 差分ゼロ(54→54)。xcodebuild build 成功(新規ファイル SidebarModifierOpenTests.swift は xcodegen generate 済み)。markdownlint 0 件。
未確認の前提(リリース前手動チェック対象): SpatialTapGesture.onEnded 時点の静的 NSEvent.modifierFlags がクリック時の修飾状態を表すこと。ハンドラは同期実行で、ユーザーは ⌘ を押したままクリックするため成立する見込みだが、GUI 層は自動テスト対象外のため実機で ⌘クリック→新規タブを 1 回確認する。

/finish-task 追記: check-type-group-size.sh --check 閾値以内。responsibility-reviewer は未実施と判断——本タスクは型・プロトコル準拠・stored property・注入クロージャのいずれも増やしていない(メソッド追加と enum ケースの連想値のみ。クロージャ注入は設計レビューで意図的に回避)。native-app-design.md は更新済み(OpenDisposition の消費元にサイドバーを追記、サイドバー節に開き分けを追記)。ADR 不要(新しい不可逆判断なし、既存 OpenDisposition への合流のみ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーのファイル行を修飾キーで開き分けるようにした。⌘クリック/⌘Return は新規タブ、⌘⇧クリック/⌘⇧Return は新規ウィンドウ(いずれも選択=表示中ファイルの不変条件を保つため選択は動かさない)、⌃クリックはコンテキストメニュー、修飾なしは従来どおり現在のタブ。対応表は新設せず既存の OpenDisposition 1 箇所に委譲し、配線も既存の FileListViewDelegate 2 メソッドをそのまま使った(新しい状態・経路なし)。実装: FileListView.handleRowTap(タップ+修飾キー)、SidebarKeyAction.openFile への OpenDisposition 連想値追加と ⌘Return 分岐、openIfFile(_:with:) での配り分け。検証: 新規 SidebarModifierOpenTests(タップ 4 ケース + Return 3 ケース)と SidebarKeyActionTests 追加 3 件を含む swift test 全 1455 件 GREEN、サボタージュで落ちることを実測、swiftlint main 差分ゼロ、xcodebuild 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
