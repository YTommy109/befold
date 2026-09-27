---
id: TASK-485.34
title: ジャンプバーを開いている間も cmd+G / cmd+shift+G で次・前の目印へ移動できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:47'
updated_date: '2026-09-25 13:55'
labels:
  - jump
dependencies: []
parent_task_id: TASK-485
ordinal: 835000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

検索では cmd+G / cmd+shift+G（Edit > 次を検索 / 前を検索）で前後のマッチへ移れるが、統合バーがジャンプのモードのときは何も起きない。ジャンプの前後移動は Enter / shift+Enter だけ（viewer-src/keyboard.ts の resolveJumpNavigationKey）。

## 現状（実測 / 2026-09-25 時点）

- Edit メニューの findNext / findPrevious は WebViewDocumentRenderer.findNext → ViewerFindBridge.findNextScript → _mmdFindNextIfOpen（viewer-src/find.ts）と伝わる
- _mmdFindNextIfOpen は _mmdFind.isOpen() = isBarOpen('find') を見るので、ジャンプのモードでは無視される
- ジャンプ側には _mmdJumpNextIfOpen / _mmdJumpPrevIfOpen（viewer-src/jump.ts）が既にある

## 検討の経緯

ジャンプを開くキーとして cmd+G・cmd+J も比べたうえで、開くキーは cmd+shift+F のまま（TASK-485.28）とした。cmd+G は macOS の慣習で「次の結果へ進む」操作であり、開く操作には合わない。cmd+J は macOS 標準の「選択部分へジャンプ」と意味がぶつかり、cmd+F / cmd+shift+F が同じキーでトグルする組み合わせも崩れる。一方、ジャンプバーはバーのモード違いなので、検索と同じ cmd+G / cmd+shift+G で前後に移れるほうが一貫する。

## 注意

- 開いているのが検索かジャンプかで振り分ける先を 1 箇所に置く（JS の現在のバーのモードが唯一の持ち主。Swift 側に開閉状態の写しを作らない）
- PDF 面はジャンプを持たないので、検索の挙動を変えない
- メニュー項目の表示名（次を検索 / 前を検索）をジャンプ中にどう見せるかも決める
- 紹介サイトのショートカット表（TASK-485.25）に載る前、ゲート撤去（TASK-485.16）より前に決めて入れる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ジャンプバーを開いている間、cmd+G で次の目印、cmd+shift+G で前の目印へ移動し、末尾・先頭で巡回する（Enter / shift+Enter と同じ振る舞い）
- [x] #2 検索バーを開いている間の cmd+G / cmd+shift+G の振る舞いは変わらない（Web 面・PDF 面とも）
- [x] #3 バーが閉じている間は cmd+G / cmd+shift+G が何もしない（従来どおり）
- [x] #4 検索とジャンプのどちらへ振り分けるかを決める判定が 1 箇所にあり、それを破ると落ちるテストがある
- [x] #5 Edit メニューの項目の有効・無効と表示名が、ジャンプ中の挙動と食い違わない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. bar-mode.ts に開いているバーで検索/ジャンプへ振り分ける _mmdBarNextIfOpen / _mmdBarPrevIfOpen を置く
2. Swift の PlainFunction を差し替え、使われなくなった _mmdFindNextIfOpen / _mmdFindPrevIfOpen を撤去
3. ⌘G / ⇧⌘G の有効判定と guard を canFind から canToggleJump へ
4. JS / Swift のテスト、viewer-ui.md の更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 振り分けの判定は bar-mode.ts の _mmdBarNextIfOpen / _mmdBarPrevIfOpen の 1 箇所（currentBar() で find → _mmdFind、jump → _mmdJump）。Swift は PlainFunction.barNextIfOpen / barPrevIfOpen を呼ぶだけで開閉の写しを持たない。
単純化の検討: 新しい状態は足さず、既存の bar.ts の currentBar() をそのまま読む。_mmdFindNextIfOpen / _mmdFindPrevIfOpen は呼び出し元が無くなったため撤去（入口の数は増えていない）。
有効判定: ⌘G / ⇧⌘G は canFind ではなく canToggleJump（⇧⌘F と同じ）を見る。TASK-485.32 と同型の穴（ジャンプ可・検索不可の表示でジャンプバーを開いているのに項目がグレー）を避けるため。現状の種別では canJump ⇒ canFind なので実害は無いが、判定を揃えて構造で塞いだ。ViewerMenuValidator は documentJump / findNext / findPrevious を barActions にまとめた。
項目名: 「次を検索 / 前を検索」のまま。ジャンプは検索バーのモード違いとして同じバーに出るため「バーの中で次へ」と読め、名前を切り替えるには Swift がバーのモードの写しを持つ必要がある（Description の注意に反する）。
PDF 面: PDFDocumentRenderer.findNext は変更なし（ジャンプを持たない）。
検証: jest 677 件通過、swift test 1994 + 72 件通過、swiftlint は origin/main 比で新規 0・解消 0（46 件）、oxlint / oxfmt / tsc クリーン。
戻すと落ちる実測: bar-mode.ts でジャンプ側の next を外すと『ジャンプバーを開いている間は目印を前後に移り、端で巡回する』が落ちる。ViewerMenuValidator / DocumentCommandController を HEAD に戻すと『ジャンプはできるが検索はできない表示でも、次へ・前への項目が有効で押すと届く』が 3 件の期待失敗で落ちる。
未実施: 実機での手動確認（WebView 層は自動テスト対象外）。
docs: viewer-ui.md のバー開閉の節へ ⌘G / ⇧⌘G を追記。native-app-design.md は型の追加・責務移動が無いため更新不要。サイトと README のショートカット表は TASK-485.25 の範囲。
/review-design は実装前に回していない（局所的な入口の差し替えと判断した）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
⌘G / ⇧⌘G を、開いているバー（検索かジャンプ）の前後移動に振り分けるようにした。振り分けの判定は bar-mode.ts の _mmdBarNextIfOpen / _mmdBarPrevIfOpen の 1 箇所で、Swift は写しを持たない。メニューの有効判定と guard は ⇧⌘F と同じ canToggleJump を読む。項目名は据え置き。JS / Swift ともに、判定を崩すと落ちるテストを追加した。
<!-- SECTION:FINAL_SUMMARY:END -->
