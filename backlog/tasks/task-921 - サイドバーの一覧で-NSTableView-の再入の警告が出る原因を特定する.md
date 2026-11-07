---
id: TASK-921
title: サイドバーの一覧で NSTableView の再入の警告が出る原因を特定する
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T12:47:00Z'
updated_date: '2026-11-07T12:55:00Z'
labels:
  - sidebar
  - appkit
dependencies: []
priority: medium
type: bug
ordinal: 887000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-07 の実機確認（スタック #769 の最上層を Xcode 27.2 の Debug でビルドし、設定を分離して起動）で、アプリのログに次の警告が 1 回だけ出た。`WARNING: Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.` AppKit は将来これを assert に変えると書いているので、放置すると将来の macOS でクラッシュになりうる。サイドバーの一覧は SwiftUI の `List` で、背後の `NSTableView` を `SidebarTableFocuser` が first responder にし、選択の変更で `fileListDidSelectFile` から窓の切り替えや空タブの置き換えが走る。どの操作で出たかは記録できていない。同じ回では空タブ・サイドバー・ドロップ・Quick Open・Reload など 8 項目を操作していた。2 回目の実機確認（サブフォルダへの移動の 1 手順だけ）では出なかった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 警告が出る操作手順を特定し、Notes に記録している（特定できなければ、試した手順と結果を記録している）
- [x] #2 原因が befold のコードにあれば直し、同じ手順で警告が出ないことを確かめている
- [x] #3 原因が AppKit や SwiftUI の側にあれば、その根拠と回避の要否を記録している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査（2026-11-07）:
1. 行のビューが窓に載った時点で first responder を変える経路（SidebarTableViewLocator → SidebarTableFocuser.tableView の didSet → makeFirstResponder）を疑い、同じ形の NSTableView を検証プログラムで作って実測した。同期でも次のランループでも警告は出なかった。
2. 選択の変更（tableViewSelectionDidChange）の中で reloadData・insertRows・選択の変更を行う形、shouldSelectRow の中で reloadData する形も実測した。いずれも警告は出なかった（素の NSTableView では再現しない）。
3. これまでの全体テストのログ 30 件（実際の FileListView を窓に載せるテストを含む）を検索したが、同じ警告は 0 件だった。テストは描画まで進まないので、この経路を通らないと見ている。
4. 同じ警告は SwiftUI の List / Table で広く報告されている（Apple Developer Forums thread 720332 ほか）。一覧が更新している最中にデータが変わると出るという報告が中心で、Apple による原因の説明と公式の修正は見つからなかった。回避策として挙がっている『変更をメインアクターで行う』は、FileListModel が @MainActor で既に満たしている。
結論: 警告が出る操作手順は特定できなかった。befold のコードに原因を特定できるものは見つからず、直す対象は無い。証拠は SwiftUI の List の側を指しているが、断定はできない。回避の追加は不要と判断する（警告の段階で動作への影響は無く、1 回だけの観測で再現手順が無い）。
見直す条件: AppKit がこれを assert に変えたとき、または再現手順が見つかったとき。再現したら、Xcode の Runtime Issues と、警告の直前の操作（サイドバーの開閉・ファイルの切り替え・空タブの置き換え）を記録する。参照: https://developer.apple.com/forums/thread/720332
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-07T12:55:00Z

---

AC #1 は『特定できなければ、試した手順と結果を記録』側で満たした。AC #2 は befold のコードに原因が見つからなかったので、直す対象が無い。AC #3 は、証拠が SwiftUI の List を指すことと、回避を追加しない理由を Notes に記録した。

---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの一覧で 1 回だけ出た NSTableView の再入の警告を調べた。検証プログラムで 3 つの形を実測し、テストのログも検索したが再現せず、操作手順は特定できなかった。同じ警告は SwiftUI の List で広く報告されている既知のもので、befold の側に直す対象は見つからなかった。見直す条件を Notes に残した。
<!-- SECTION:FINAL_SUMMARY:END -->
