---
id: TASK-415
title: セッション復元で重複パスがタブグループから窓を奪う
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 07:27'
updated_date: '2026-08-10 11:47'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 507100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SessionRestorer.restoreTabGroup（SessionRestorer.swift:203）は保存レイアウトの各パスを windowManager.window(forPath:) で引くが、この実装は controllers[path]?.first?.window（ViewerWindowManager.swift:418）で最初の 1 件しか返さない。同じパスが 2 つのタブグループに含まれる保存レイアウトだと、2 件目が復元済みの窓を再ターゲットしてしまう。

再現: README.md をタブグループ A の窓 1 とタブグループ B の窓 2 で開く（重複は設計上許容）。currentSessionLayout() は両グループに同じパスを記録する。再起動するとグループ A の復元で README.md の窓が作られる。続くグループ B の復元では openViewer が .currentTab の重複抑止（ViewerWindowManager.swift:231）で早期 return して窓を作らず、window(forPath:) がグループ A の窓を返し、attachAsTab(window, to: previousWindow, select: false) の addTabbedWindow がその生きている窓を A から B へ移す。結果、A はタブが 1 つ欠け B は 1 つ増える。終了と再起動のたびに再発する。

TASK-412（noteClosed の参照カウント欠落）と同じ「controllers が多重マップであることを呼び出し側が無視している」型。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同じパスが複数のタブグループに含まれる保存レイアウトを復元しても、既存の窓が別グループへ移動しない
- [x] #2 重複パスの 2 件目は新しい窓として復元される（または明示的に読み飛ばす。どちらを採るか判断を Implementation Notes に残す）
- [x] #3 終了と再起動を 2 回繰り返してもタブ構成が保存時と一致する
- [x] #4 ユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. まず失敗するテストを書いて再現する。
2. 単純化の余地を検討する（引き当て方を変えるか、経路そのものを無くすか）。
3. window(forPath:) による引き当てを復元経路から無くし、openViewer の戻り値を使う。
4. 重複パスの 2 件目の扱いを決めて実装する。
5. mutation check で、各変更が担保されていることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
再現（実測）: SessionRestorerTests に、shared を 2 グループに含む保存レイアウトの復元テストを追加。修正前は shared のコントローラが 1 個しか作られない（2 件目が .currentTab の重複抑止に当たって窓を作らず、window(forPath:) が 1 件目を返して addTabbedWindow がそれを奪う）。往復テストの失敗出力は症状そのもので、グループ A が [only-a] だけになり、B が [only-b, shared] になっていた。

AC2 の判断: 「2 件目は新しい窓として復元する」を採った。同じファイルを複数窓で開くことは設計上許容されており（ViewerWindowManager.controllers が 1 パス複数コントローラの多重マップである理由そのもの）、保存レイアウトはその状態を正しく記録している。読み飛ばすと、ユーザーが自分で作った構成が起動のたびに 1 タブずつ減る。

実装:
- ViewerWindowManager.openViewer を @discardableResult で ViewerWindowController? を返すようにした（新規生成、または前面化した既存。開けなければ nil）。doc に「呼び出し直後に window(forPath:) で引き直すと別の窓を掴む」ことを明記。
- SessionRestorer.restoreTabGroup は戻り値の窓を使い、window(forPath:) では引き直さない。選択タブもパス引き当てではなく、このループで開いた窓の同一性で決める（同じ理由で別グループの窓を選択しうるため）。
- 復元全体で開いたパスを openedPaths で持ち回り、2 件目以降は .newWindow で開く。

検証:
- 追加テスト 2 本。(a) 重複パスで既存窓を奪わない、(b) 終了と再起動を 2 回繰り返してもタブ構成が保存時と一致する（AC3）。再起動は別フィクスチャ（=別プロセス相当）へ保存レイアウトを渡す形で表現した。
- mutation check 2 回: disposition の判定を .currentTab 固定へ戻すと両テストが落ちる。window(forPath:) での引き直しへ戻しても往復テストが落ちる。どちらの変更も担保されている。
- フルスイート 1389 tests / 202 suites すべて pass。SessionRestorerTests のみ 3 回連続実行しても pass（並行実行に対する安定性の確認）。
- swiftformat 0 件（fix モードで機械に整形させた）。swiftlint はベースライン差分なし（変更で 1 件減っている: 削除した多行 if の opening_brace）。

テスト作成時の注意（実測）: currentSessionLayout() は NSApp のウィンドウを全て見るため、フルスイート実行では他テストの窓が混ざる。パスも同ファイル内の他テストと衝突していたため、このテスト専用のパス（/dup-repo, /restart-repo）へ分け、自分のパスに関係するグループだけを比較している。

未確認: 実機での目視確認は行っていない（同じファイルを 2 つのタブグループで開いて終了・再起動する操作）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
保存レイアウトに同じパスが 2 度現れると、2 件目の復元が既存の窓を引き当てて addTabbedWindow がそれを前のグループから奪う問題を修正した。ViewerWindowManager.openViewer が対象コントローラを返すようにし、SessionRestorer.restoreTabGroup は window(forPath:)（多重マップの先頭を返す）で引き直さず戻り値の窓を使う。重複パスの 2 件目以降は .newWindow で新しい窓として復元し、選択タブも窓の同一性で決める。検証はユニットテスト 2 本（既存窓を奪わない／再起動 2 回でタブ構成が一致）と mutation check 2 回（disposition の判定・引き当ての除去のどちらを戻しても落ちる）。フルスイート 1389 tests pass。
<!-- SECTION:FINAL_SUMMARY:END -->
