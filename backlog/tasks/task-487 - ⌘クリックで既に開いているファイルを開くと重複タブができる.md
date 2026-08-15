---
id: TASK-487
title: ⌘クリックで既に開いているファイルを開くと重複タブができる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-15 11:37'
updated_date: '2026-08-15 12:31'
labels:
  - bug
dependencies:
  - TASK-482
priority: high
type: bug
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ユーザー報告: サイドバーのファイル行を ⌘ クリックしたとき、そのファイルが既に別のタブで開かれていても新規タブが作られてしまう。既に開いているファイルなら、新規タブを作らず既存のタブをアクティブにしてほしい。

TASK-482（サイドバーの修飾キーによる新規タブ・新規ウィンドウ振り分け、PR #529）のフォローアップ。現在の実装は `OpenDisposition.newTab` を受けると無条件に新規タブを作る経路になっており、「同じファイルが既にタブグループ内で開いているか」の照合を行っていない。

検討事項（着手時に確認）:

- 照合の範囲: 同じタブグループ内のみか、全ウィンドウ横断か（まずは同じタブグループ内が自然）
- ⌘⇧（新規ウィンドウ）にも同じ重複抑止を適用するか
- ビューア内 Markdown リンクの ⌘ クリック（`BridgeMessageRouter` 経由）も同じ経路を通るため、挙動を揃えるかどうか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーのファイル行を ⌘ クリックしたとき、そのファイルを表示中のタブが同じタブグループに既にあれば、新規タブを作らずそのタブがアクティブになる
- [x] #2 該当ファイルを開いているタブが無い場合は、従来どおり新規タブで開く
- [x] #3 修飾キー無しクリック・⌃ クリックの挙動は変わらない
- [x] #4 ユニットテストが「既存タブあり → アクティブ化」「既存タブなし → 新規タブ」の両ケースを検証している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
前提(裏付け):
- .newTab/.newWindow の素通しは issue #431(既に開いているファイルで newWindow が無反応に見える)対応で意図的に入った(コード参照: ViewerWindowManager+OpenViewer.swift:35-39 のコメント)
- 全オープン経路(サイドバー ⌘クリック / ⌘Return / ビューア内リンク ⌘クリック / DirectHTML)は ViewerWindowManager.openViewer に合流する(Explore 調査で実測。BridgeMessageRouter → openReference → openFileElsewhere → openViewer)。よって openViewer での修正は経路間の挙動差を生まない
- パス同一性は normalizedPathKey が単一の情報源(URL+NormalizedPathKey.swift:7)。ViewerTabGrouping.viewerPath(of:) と controllers のキーは両方これを使う

単純化検討: 新しい分岐を素通し分岐の外に足すのではなく、既存の .currentTab 重複抑止分岐と統合する。「disposition ごとの既存コントローラ解決」を 1 つの private ヘルパー(.currentTab=全体から first / .newTab=sourceWindow のタブグループ内 / .newWindow=常に nil)に置き、前面化・オプション適用・return の共通ブロックは 1 箇所のまま増やさない。状態は増えず、述語 1 つの追加で済む。

手順:
1. TDD: ViewerWindowManagerTabTests の newTabOpensDuplicateForAlreadyOpenFile を「既存タブの前面化(controllers 件数 1・selectedWindow が既存)」へ書き換え、追加で「別ウィンドウ(タブグループ外)で開いている場合は従来どおり新規タブ」を新設(照合範囲=同一タブグループの判断が破れたら落ちるテスト)。newWindow の重複許可テストは変更しない
2. ViewerWindowManager+OpenViewer.openViewer に上記ヘルパーを導入し、.newTab で同一タブグループ内に同じ normalizedPathKey のタブがあれば ViewerDisplayOptionsApplier.apply + NSApp.activate + focusWindow で前面化して return。issue #431 コメントを「newWindow のみ素通し / newTab はタブグループ内で抑止(TASK-487)」へ更新
3. 検討事項の決定: 照合範囲=同一タブグループのみ / ⌘⇧(newWindow)は #431 の意図を保ち素通しのまま / ビューア内リンクは経路合流により自動的に同挙動(追加実装なし)
4. swiftformat + swiftlint ベースライン差分ゼロ確認、swift test、native-app-design.md 追随、finalization

/review-design 結果(計画変更なし・決定の追記):
- 既存コントローラ解決は controllers[key] を真実の源にできる(switch/rename 時に remapController が rekey する: +SessionSync.swift:26-34 で実測)。.newTab はそのうち sourceWindow のタブグループ(ViewerTabGrouping.tabWindows)に window が属すものを採る
- 絞り込み点 openViewer での抑止は、⌘クリックのほかコンテキストメニュー「新しいタブで開く」とビューア内リンク ⌘クリックにも同時に効く(意図した決定)。#431 の「無反応に見える」問題は、タブ選択の切り替わりが可視応答になるため newTab では再発しない
- openViewer の doc コメントと #431 参照コメントを新挙動(newWindow のみ素通し)へ更新する
- 型グループ実測 369 行 → 約 390 行。責務・準拠・stored property の増加なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検討事項の決定:
- 照合範囲は同一タブグループのみ(controllers[key] のうち sourceWindow のタブグループに window が属すもの)。別ウィンドウで開いているだけなら従来どおり新規タブ。この粒度はテスト newTabOpensTabWhenFileIsOpenOnlyInAnotherWindow が担保する
- ⌘⇧(newWindow)は issue #431 の意図(明示的な新規ウィンドウ要求)を保ち素通しのまま。既存テスト newWindowOpensDuplicateForAlreadyOpenFile が担保する
- ビューア内 Markdown リンクの ⌘ クリックとコンテキストメニュー「新しいタブで開く」は openViewer に合流するため、追加実装なしで同じ抑止が効く(絞り込み点での修正)

実装メモ:
- 既存の .currentTab 重複抑止分岐と統合し、disposition ごとの再利用可否を private ヘルパー reusableController に集約(前面化・オプション適用ブロックは 1 箇所のまま)
- タブ選択は ViewerTabGrouping.selectTab を新設して明示的に行う(ヘッドレス環境では makeKeyAndOrderFront だけでは tabGroup.selectedWindow が追随しないため。attachAsTab の選択処理も同ヘルパーへ寄せた)
- native-app-design.md のサイドバー節へ新挙動を追記

検証: swift test 全 1566 件成功(exit 0)。TDD で newTabActivatesExistingTabInSameGroup の失敗(重複タブ生成で count=2)を先に実測してから実装。swiftlint main ベースライン差分ゼロ(54=54、ルール×ファイル一致)。markdownlint 0 issues
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
openViewer の重複抑止を disposition ごとの reusableController に統合し、.newTab は起点ウィンドウと同じタブグループに同じファイルのタブがあれば新規タブを作らず既存タブを選択・前面化するよう修正。ユニットテスト(既存タブあり→前面化 / 別ウィンドウのみ→新規タブ)を追加し、swift test 全 1566 件成功・swiftlint ベースライン差分ゼロで検証
<!-- SECTION:FINAL_SUMMARY:END -->
