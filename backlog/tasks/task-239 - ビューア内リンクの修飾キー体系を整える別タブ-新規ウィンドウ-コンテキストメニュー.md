---
id: TASK-239
title: ビューア内リンクの修飾キー体系を整える(別タブ/新規ウィンドウ/コンテキストメニュー)
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 12:21'
updated_date: '2026-07-31 15:03'
labels:
  - feature
dependencies: []
references:
  - BefoldApp/BefoldKit/Resources/viewer-main.js
  - BefoldApp/befold/App/ReferenceResolutionCoordinator.swift
  - BefoldApp/befold/App/ViewerWindowManager.swift
  - BefoldApp/befold/App/ViewerWindowController.swift
documentation:
  - docs/superpowers/specs/2026-07-31-link-click-modifiers-design.md
priority: medium
ordinal: 442000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ビューア本文のリンク・パス参照の開き方が「同一ウィンドウ」「新規ウィンドウ」の 2 通りしかなく、開き方が Bool 1 個(referenceActivated の newWindow)で表現されているため第 3 の開き方を足す余地がない。またタブとして開く経路が存在せず、タブ結合は SessionRestorer.restoreTabGroup がセッション復元時に addTabbedWindow を直接呼ぶ形でしかない。クリック=同一ウィンドウ、cmd+クリック=別タブ(前面)、cmd+shift+クリック=新規ウィンドウ、ctrl+クリック=コンテキストメニュー、という体系へ整える。cmd+クリックの意味が新規ウィンドウから別タブへ移る非互換な変更を含む。設計は docs/superpowers/specs/2026-07-31-link-click-modifiers-design.md を参照。サイドバーは対象外(List 内部の NSTableView が cmd+クリックを複数選択として先に処理するため)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ビューア本文のリンク/パス参照で、クリック=同一ウィンドウ、cmd+クリック=同じタブグループへ追加して前面化、cmd+shift+クリック=新規ウィンドウ、が成り立つ
- [x] #2 ctrl+クリック(右クリック)でコンテキストメニューが出て、開く/別タブで開く/新しいウィンドウで開く/Finder で開く/コピーする/相対パスをコピーする が選べる
- [x] #3 外部 URL は修飾キーによらずブラウザで開き、解決待ち・解決失敗のパス参照は従来どおり反応しない
- [x] #4 修飾キーから開き方への変換が 1 箇所に集約され、その対応表にユニットテストがある
- [x] #5 タブ結合の手続きが ViewerWindowManager 側に集約され、セッション復元経路も同じ実装を通る(復元の挙動は不変)
- [x] #6 既存テストが通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
自動検証: swift test 961 tests / 131 suites 全 PASS、npx jest 334 tests 全 PASS、swiftformat --lint clean、markdownlint clean。手動検証: dev ビルド(xcodebuild Debug)を起動し .tmp/link-check.md で cmd+クリック=別タブ前面化 / cmd+shift+クリック=新規ウィンドウ / ctrl+クリック=マウス位置にメニュー / 外部 URL での Finder・相対パスコピーのグレーアウト / 未解決参照の無反応 / 直接 HTML モードの 3 通り をユーザーが確認済み(期待通り)。

主な設計判断: 修飾キー→開き方の対応表を BefoldKit の OpenDisposition に集約し、JS ブリッジは押下状態(metaKey/shiftKey)のみ送る。タブ結合は ViewerWindowManager.attachAsTab を単一実装元とし SessionRestorer も同経路。コンテキストメニューの表示位置は JS 座標でなくマウス位置(CSS ピクセル変換とページズームの影響回避)。

レビューで検出し修正した実バグ: (1) NSMenu.autoenablesItems 既定 true のため項目の無効化が実行時に効かなかった、(2) 外部 URL の右クリック「開く」系がファイル経路へ流れ Web リンクに「ファイルが見つかりません」アラートが出た、(3) ctrl+クリック時に click 経路が同時発火しうる穴、(4) 外部オープンを注入化しテスト実行時に実ブラウザが起動しないようにした。

非互換変更: cmd+クリックの意味が「新規ウィンドウ」から「別タブ」へ変わる(旧挙動は cmd+shift+クリックに残る)。リリースノートでの告知が必要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ビューア本文のリンク/パス参照に修飾キーによる開き分けを導入した。クリック=同一ウィンドウ、cmd+クリック=同じタブグループへ追加して前面化、cmd+shift+クリック=新規ウィンドウ、ctrl+クリック=コンテキストメニュー(開く/別タブで開く/新しいウィンドウで開く/Finder で開く/コピーする/相対パスをコピーする)。修飾キー→開き方の変換は BefoldKit の OpenDisposition 1 箇所に集約し、JS ブリッジ経由のクリックと直接 HTML モードの両方がそこへ合流する。タブ結合は ViewerWindowManager.attachAsTab を単一実装元とし、セッション復元も同じ経路を通す(挙動は不変)。外部 URL は修飾キー・メニュー項目によらずブラウザで開き、解決待ち・解決失敗のパス参照は無反応のまま。検証は swift test 961 tests 全 PASS / npx jest 334 tests 全 PASS / swiftformat・markdownlint clean と、dev ビルドでの手動確認(6 項目、期待通り)。cmd+クリックの意味が新規ウィンドウから別タブへ変わる非互換変更を含む(旧挙動は cmd+shift+クリック)。
<!-- SECTION:FINAL_SUMMARY:END -->
