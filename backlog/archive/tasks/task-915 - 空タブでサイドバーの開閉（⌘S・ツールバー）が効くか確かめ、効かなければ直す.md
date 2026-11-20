---
id: TASK-915
title: 空タブでサイドバーの開閉（⌘S・ツールバー）が効くか確かめ、効かなければ直す
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T12:09:00Z'
labels:
  - sidebar
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
  - BefoldApp/befold/App/DocumentFileDropView.swift
priority: high
type: bug
ordinal: 881000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。空タブにはフォーカスを取る部品が無いので first responder は窓自身になりうる。`toggleSidebar(_:)` は宛先なしのアクションで、`ViewerSplitViewController` はビューの responder chain 上にある。窓から上へ辿る経路には split view が乗らず、`DocumentFileDropView.install` が contentViewController を素の container に差し替えているので、container 経由の転送にも期待できない。そうなると、サイドバーを閉じた窓から開いた空タブではサイドバーをもう開けない。

未確認（仮説）: コードからの推論で、再現はしていない。TASK-910 の Notes にも実機未確認とある。既存テストは `toggleSidebar` を直接呼ぶので、この経路を測っていない。確認方法: `/run` で閉じたサイドバーの窓から ⌘T を押し、⌘S とツールバーのボタンを試す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 実機で空タブの ⌘S とツールバーのボタンを試した結果が Notes に記録されている
- [x] #2 サイドバーを閉じた窓から開いた空タブで、⌘S とツールバーのボタンからサイドバーを開閉できる
- [x] #3 開閉が利用者の操作として保存値へ記録される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（テスト、2026-11-07）: 仮説は外れた。空タブの first responder は窓自身で、アクションの経路は文書タブと同じ『窓 → 窓のコントローラ』。窓へ toggleSidebar: を送ると窓が受けて split view まで届き、開閉されて保存値にも記録される。メニューの検証も窓が有効と返す。実装の変更は不要で、この経路を守る回帰テスト sidebarToggleFromWindowReachesSplitView を追加した。
実機での ⌘S とツールバーのボタンの確認（AC #1）はスタック全体の実機確認でまとめて行う。
全体テストで WKWebView の統合テスト 3 件が一度失敗した（2 件は 600 秒の時間切れ）が、同時に code-review high と別のテストが動いていた回で、単独では 3 件とも成功、負荷の無い全体実行でも 1994 件成功。TASK-675 と同じ型の負荷による失敗と見ている。

実機確認（2026-11-07、スタック #779 の最上層を Xcode 27.2 の Debug でビルド、設定は分離）: サイドバーを閉じた窓から開いた空タブで、⌘S とツールバーのサイドバーのボタンのどちらでも開閉できた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
空タブで ⌘S とツールバーのボタンが効かないという仮説を実測と実機で確かめ、不具合が無いことを確認した。実装は変えず、窓から split view へ届く経路とメニューの検証を守るテストを追加した。
<!-- SECTION:FINAL_SUMMARY:END -->
