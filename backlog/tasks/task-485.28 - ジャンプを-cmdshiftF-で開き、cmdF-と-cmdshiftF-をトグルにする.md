---
id: TASK-485.28
title: ジャンプを cmd+shift+F で開き、cmd+F と cmd+shift+F をトグルにする
status: Done
assignee: []
created_date: '2026-09-25 08:34'
updated_date: '2026-09-25 08:55'
labels: []
dependencies: []
parent_task_id: TASK-485
ordinal: 829000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
文書内ジャンプの呼び出しを cmd+shift+F に割り当てる。ジャンプ 3 種（見出し・定義・変更ブロック）は排他（TASK-485.26）なので、キーは 1 つでその表示で使える種類を開く。ジャンプが無い表示では検索を開く。
cmd+F は常に検索を開く（差分表示中に変更ブロックへ振り分ける ViewerCapabilities.defaultBarKind は撤去する）。
cmd+F / cmd+shift+F はトグル: バーが閉じていれば開く、同じモードで開いていれば閉じる、別モードで開いていればそのモードへ切り替える。
紹介サイトのショートカット表への反映はゲート撤去後（TASK-485.25）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cmd+shift+F でその表示で使えるジャンプ（見出し・定義・変更箇所のどれか）が開く
- [x] #2 ジャンプが無い表示で cmd+shift+F を押すと検索が開く
- [x] #3 cmd+F は表示に依らず検索を開く（差分表示中も）
- [x] #4 同じキーをもう一度押すとバーが閉じ、別のキーならモードが切り替わる
- [x] #5 MainMenuBuilder の「キー等価を付けない」旨の doc コメントが実態に合っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. JS: bar-mode.ts に _mmdToggleBarMode(mode) を足す。currentMode() === mode なら closeCurrentBar()、それ以外は既存の openMode(mode)（閉→開、別モード→切替）。モード切替ボタンは openMode のまま（押しても閉じない）。開閉の状態は JS（bar.ts）だけが持ち、Swift に写しを持たない。
2. DocumentRendering: openFind() / openJump(kind:) を toggleFind() / toggleJump(kind:) に置き換える（本番の呼び出し元は DocumentCommandController だけ。実測: rg）。Web 面は _mmdToggleBarMode を呼ぶ。**PDF 面も toggleFind を実装する**（findModel.isOpen なら閉じる）。PDF の toggleJump は従来どおり能力で塞いで来ない。
3. DocumentCommandController: openBar(kind:) を toggleFind() / toggleJump() に置き換える。toggleJump は canJump(to:) を満たす種類（排他なので高々 1 つ）を渡し、無ければ toggleFind へ倒す。ViewerCapabilities.defaultBarKind は撤去（cmd+F は常に検索）。
4. メニュー: Edit の種類別 3 項目を 1 項目「ジャンプ…」cmd+shift+F に統合。DocumentJumpKind.menuItemTag / menuLabelKey と関連テストを撤去。ゲート閉では従来どおり非構築。
5. 有効判定: ジャンプ項目は検索へ倒れるため canFind で有効（canFind が false なら検索もジャンプも無い）。
6. 紹介サイト: site/test/shortcuts.test.ts の EXPECTED_MENU_ITEMS（実装の割り当て一覧）にだけ足す。公開の表は「表 ⊆ 実装」しか検査しないので、表へ載せずに済む（載せるのは TASK-485.25）。
7. viewer-bundle.js を npm run build:viewer で作り直す。このワークツリーには node_modules が無いので npm ci が要る。
8. テスト: JS の toggle（閉→開、同モード→閉、別モード→切替、ボタンは閉じない）、Swift のコマンド経路（ジャンプ無し→検索、種類の選択）、PDF の toggleFind、メニュー構築。docs/dev/viewer-ui.md 更新。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design 結果: (3 消費経路) PDF 面も検索の開閉状態を持つので、トグルを Web 面だけに入れると PDF で cmd+F 2 回目が閉じない→DocumentRendering の入口ごと toggle に置き換える。紹介サイトのパーサは MainMenuBuilder の全キー等価を拾い EXPECTED_MENU_ITEMS と完全一致を見る→テストの期待一覧だけ更新、公開表は触らない。(1/9) 開閉状態は JS の bar.ts が唯一の持ち主で、Swift 側に写しを置かないので二重状態にならない。(6) 有効判定は canFind 1 つで線形走査なし。(8) 非同期の差し替えなし。(10) DocumentCommandController 229 行・MainMenuBuilder 451 行、どちらも差し引きで減る見込み。

実装: JS に _mmdToggleBarMode(mode) を足し（bar-mode.ts）、DocumentRendering の openFind/openJump を toggleFind/toggleJump に置換。PDF 面は PDFFindModel.isOpen でトグル。openBar(kind:)・defaultBarKind・DocumentJumpKind.menuItemTag/menuLabelKey・openFindScript/openJumpScript・翻訳キー 3 つを撤去し、Edit > ジャンプ…（⇧⌘F, menu.edit.jump）1 項目にした。ViewerCapabilities.availableJumpKind を追加。
検証: swift test 全 1991 件合格（ToggleBarCommandTests 5 件・PDF のトグル・メニュー構築・validate を追加/更新）、jest 663 件合格（トグル 5 件追加）、site vitest shortcuts 9 件合格（EXPECTED_MENU_ITEMS のみ更新、公開表は未掲載）、oxlint/oxfmt 0、swiftlint 新規 0、markdownlint 0。アプリでの目視確認は未実施。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
cmd+F を常に検索のトグル、cmd+shift+F を表示で使えるジャンプ（無ければ検索）のトグルにした。同じキーで閉じ、別のキーでモードが切り替わる。Edit のジャンプ項目は 1 つに統合。web 面は JS、PDF 面は PDFFindModel が開閉の状態を持つ。Swift/JS/site の全テスト合格で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
