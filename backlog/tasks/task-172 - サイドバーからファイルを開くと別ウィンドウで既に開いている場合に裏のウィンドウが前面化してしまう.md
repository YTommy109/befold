---
id: TASK-172
title: サイドバーからファイルを開くと別ウィンドウで既に開いている場合に裏のウィンドウが前面化してしまう
status: To Do
assignee: []
created_date: '2026-07-27 11:42'
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
- [ ] #1 フロントウィンドウのサイドバーから、他の(裏の)ウィンドウで既に開いているファイルを選択しても、裏のウィンドウが前面化してユーザーのフォーカスを奪わない
- [ ] #2 既存の『1ファイル1ウィンドウ』の重複防止ポリシー(同じファイルを二重にウィンドウ表示しない)は維持される、または意図的に変更する場合はその理由が明記される
- [ ] #3 ViewerWindowControllerToolbarTests 等の既存ウィンドウ管理関連テストが引き続きパスする
<!-- AC:END -->
