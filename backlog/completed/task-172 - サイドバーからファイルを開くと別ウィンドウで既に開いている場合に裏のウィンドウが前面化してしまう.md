---
id: TASK-172
title: サイドバーからファイルを開くと別ウィンドウで既に開いている場合に裏のウィンドウが前面化してしまう
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 11:42'
updated_date: '2026-07-27 14:36'
labels: []
dependencies: []
ordinal: 247000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同じディレクトリを二つのウィンドウで開いているケース(W1がa.md、W2がb.mdを表示)で、フロントの W2 のサイドバーから a.md をクリックすると、a.md をすでに開いている裏のウィンドウ W1 が前面化(makeKeyAndOrderFront)してしまい、フロントだったはずの W2 が非アクティブになる。

調査の結果、これは事故ではなく ViewerWindowManager が「1ファイル1ウィンドウ」の不変条件を持っている設計に起因する意図的な挙動と分かった。

- ViewerWindowController.switchFile(to:) (ViewerWindowController.swift:345-359) がサイドバー選択のハンドラで、performFileSwitch(to:) の結果が .openInAnotherWindow(other) の場合に other.focusWindow() を呼び、sidebar.restoreSelection(to: oldURL) でフロント側の選択を元に戻す。コード中のコメントには「明示的なファイル選択では、重複ウィンドウを作らず既存ウィンドウを見せる」とある。
- performFileSwitch(to:) (ViewerWindowController.swift:383-387) は delegate 経由で ViewerWindowManager.viewerWindow(_:windowShowingFileElsewhere:) (ViewerWindowManager.swift:278-283) を呼び、controllers[url.normalizedPathKey] に自分以外のコントローラーがあればそれを返す。
- この判定はフロント/バックグラウンドの区別を一切考慮しておらず、「他のどこかの重複ウィンドウ」と「たまたま裏にある無関係なウィンドウ」を区別できない。

『1ファイル1ウィンドウ』の重複防止という設計意図自体は妥当な可能性があるため、まず新しい状態を増やさずに解決できないか検討する。例えば、対象ファイルを既に表示しているウィンドウが現在のキーウィンドウ自身の場合のみ早期returnする既存ガード(switchFile冒頭のnormalizedPathKey比較)を活かしつつ、『裏の無関係なウィンドウを前面化する』動作そのものの要否をどう扱うかを設計判断として残す。具体的な修正方針(裏ウィンドウは前面化せずフロントウィンドウ側でファイルを開く/切り替えるのか、それとも重複防止ポリシーを維持したままユーザーへの通知方法を変えるのか等)は実装着手時に再検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フロントウィンドウのサイドバーから、他の(裏の)ウィンドウで既に開いているファイルを選択しても、裏のウィンドウが前面化してユーザーのフォーカスを奪わない
- [x] #2 既存の『1ファイル1ウィンドウ』の重複防止ポリシー(同じファイルを二重にウィンドウ表示しない)は維持される、または意図的に変更する場合はその理由が明記される
- [x] #3 ViewerWindowControllerToolbarTests 等の既存ウィンドウ管理関連テストが引き続きパスする
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 制約の由来を git 調査(結論: 意図的仕様でなくコミット834065aeで switchFile が rename処理コピーだった名残)
2. 登録簿 controllers を [String:[ViewerWindowController]] へ多対応化し allControllers/detach を追加
3. switchFile/performFileSwitch の切替中止・他ウィンドウ前面化(windowShowingFileElsewhere/openInAnotherWindow)を撤廃
4. openViewer の新規オープン時重複防止は維持(Finder/CLI 再オープンは既存を前面化)
5. テスト多対応化・新挙動テスト追加、全テスト green
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ユーザー確認で『操作中のアクティブウィンドウ最優先』方針を採用。git 調査により『1ファイル1ウィンドウ』はコミット834065ae(#95)で switchFile が handleRename のコピーだった副産物と判明(元の switchFile eb3a6b71 は制約なしで単純にフロント切替)。controllers を多対応辞書化し、ウィンドウ内切替は他ウィンドウの有無に関わらず自ウィンドウを切り替える。新規オープン(openViewer)の重複ウィンドウ防止は維持。ViewerWindowManagerTests に新挙動3件を追加、全800テスト green。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーからのファイル切替で、対象を別ウィンドウが開いていると裏ウィンドウが前面化しフロントのフォーカスを奪う問題を解消。git 調査で当該『1ファイル1ウィンドウ』制約が意図的仕様でなく switchFile が rename 処理のコピーだった副産物(コミット834065ae)と判明したため、制約を撤廃。登録簿 controllers を [String:[ViewerWindowController]] へ多対応化(allControllers/detach 追加)し、performFileSwitch から他ウィンドウ前面化・切替中止(windowShowingFileElsewhere/openInAnotherWindow)を削除。操作中のアクティブウィンドウがそのまま切り替わる。新規オープン時の重複防止は openViewer 側で維持。ViewerWindowManagerTests に新挙動テストを追加し swift test 全800件 green で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
