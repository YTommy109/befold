---
id: TASK-931
title: サイドバーの ⌘クリックで、起点のタブも同じファイルに切り替わる
status: Done
assignee:
  - '@claude'
created_date: '2026-11-26T04:01:05Z'
updated_date: '2026-11-26T08:08:17Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 872000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
利用者の報告(2026-11-26): サイドバーでファイルを ⌘クリックすると、左端(起点)のタブがアクティブなままそのファイルを表示する。仕様(docs/dev/native-app-design.md の ViewerTabGrouping 節。Safari と同じ)は、新しいタブを右端に背面で開き、表示も焦点も起点に留める。

原因(実測 / 2026-11-26、開発ビルドに一時的な NSLog を入れて ⌘クリックを 3 回): 1 回の ⌘クリックで次の順に呼ばれる。
1. FileListView.handleRowTap(⌘)→ fileListDidRequestOpenElsewhere → ViewerTabGrouping.present(placement: .end, select: false)。新しいタブは右端に背面で開き、選択は起点のまま(ここは仕様どおり)
2. その後、SwiftUI の List(selection:) 自体も ⌘クリックで行の選択を変え、Binding の set(FileListView.tableSelection → commitSelection)が呼ばれる
3. commitSelection がファイル行なので open(_:with: .currentTab)→ switchFile で、起点のタブが同じファイルに切り替わる
結果、起点のタブと右端の新しいタブの両方が同じファイルを出す(続けて ⌘クリックすると同じファイルのタブが 2 つ並ぶ)。

このブランチ(TASK-930)由来ではない: commitSelection からいまのタブで開く経路は main にもある。930.8 で触れたのはフォルダー行の扱いだけ。いつから起きているか(OS の更新で List が ⌘クリックの選択を変えるようになったのか、元からか)は未確認。

着手時の注意: 同型の判定(修飾キーやフラグで後続の選択変更を握りつぶす)は、過去に誤検知を繰り返した型(CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」)。List の選択の書き戻しを、利用者の操作の種別という事実で区別できるか(例: ⌘ 付きのクリックでは List に選択を渡さない、NSTableView 側で修飾キー付きクリックの選択を止める)から検討する。フォルダー行の ⌘クリック(TASK-930.8)も同じ経路を通るので、同時に確かめる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーでファイル行を ⌘クリック / ⌘⇧クリックしても、起点のタブの表示と選択は変わらない
- [x] #2 新しいタブは右端に背面で開く(既存の仕様どおり)
- [x] #3 フォルダー行の ⌘クリックでも起点のタブが変わらない
- [x] #4 実機(開発ビルド)で ⌘クリックの呼び出し順を確かめ、修正を戻すと再現することを確かめる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListView.tableSelection の setter(テーブル発の選択の書き戻しの唯一の入口)で、書き戻しを起こしたイベントが修飾キー付き(⌃/⌘/⌘⇧)のマウスクリックなら確定しない(acceptsTableSelectionWrite。OpenDisposition の判定を handleRowTap と共有)
2. 確定しなかった回は、表の選択を model.selection の行へ戻す(FileListModel.restoreTableSelection → SidebarTableFocuser.restoreSelection)。実機で、戻さないとハイライトがクリックした行に残ることを確かめた
3. テスト: 判定の純粋関数(SidebarModifierOpenTests)と、表の選択の書き直し(FileListModelScrollTests)
4. 実機: 一時 NSLog で呼び出し順・イベント・窓を記録し、T931_DISABLE で修正を戻して再現させる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-26: 修正(FileListView.tableSelection の setter で、⌃/⌘/⌘⇧ のマウスイベント由来の書き戻しを確定しない。acceptsTableSelectionWrite)とテスト(SidebarModifierOpenTests 2 件)を作業ツリーに実装、未コミット。swift test --filter SidebarModifierOpenTests で 11 件すべて通過、判定を return true に戻すと 3 ケースが落ちることを確認。
AC #4 は未実施。背景ジョブには補助アクセスが無く(osascript -1728)、⌘クリックを合成できない。着手できる条件: 利用者が実機でクリックする。ログ入りの開発ビルド(PID 39042、ログは $CLAUDE_JOB_DIR/tmp/befold-fix.log の T931 行。修正を無効にするには T931_DISABLE=1)を起動済み。
未確認の前提: setter が呼ばれた時点の NSApp.currentEvent がその ⌘クリックであること / 書き戻しを止めたあと、表のハイライトが元の行へ戻ること

実機(2026-11-26、開発ビルドに一時 NSLog。コミットしていない):
- 呼び出し順: handleRowTap(⌘, mouseUp) → 約 0.2 秒後に setter。setter 時点の NSApp.currentEvent は同じ ⌘ 付き leftMouseUp(type 2)。前提どおり
- 修正のみ(表の選択を戻さない版): 書き戻しは確定しなかったが、表の selectedRow がクリックした行のまま(2/3/0)→ restoreTableSelection を追加
- 修正あり(窓 19997、1 タブで b.md ⌘ / sub ⌘ / c.md ⌘): 3 回とも cur=a.md のまま、OPEN-CURRENT-TAB 0 件、tableRow=1(a.md)に戻る。後追いの書き戻し(type 34 = pressure を含む)はどれも a.md で、commitSelection の同値ガードで何も起きない。利用者の目視でも、起点タブとハイライトは a.md のまま、新規タブは右端に開いた
- 修正を戻した版(T931_DISABLE、窓 20008): b.md ⌘ で OPEN-CURRENT-TAB b.md、sub ⌘ で選択が sub へ、c.md ⌘⇧(mods=1179648)で OPEN-CURRENT-TAB c.md。再現した。⌘⇧ でも判定は accepted=false
- 途中で、窓の識別子が無いログから『圧力イベントで b.md が開いた』と誤読した。複数タブにまたがった操作で同じログになるので、識別子付きで取り直して否定した
検証: swift test(--skip Integration/FileWatcherTests/PDF)1906 件通過。判定を return true にすると SidebarModifierOpenTests の 3 ケース、restoreTableSelection を空にすると FileListModelScrollTests の 1 件が落ちる。swiftlint は main とのベースライン差分ゼロ。
文書: docs/dev/viewer-ui.md の『行の開き分け』に、書き戻しを確定しない仕組みを 1 文足した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの ⌘ / ⌘⇧ クリックで起点のタブまで同じファイルへ切り替わる不具合を直した。SwiftUI の List が同じクリックで行の選択を書き戻し、それが『いまのタブで開く』経路(commitSelection)に入っていた。List の選択バインディングの setter で、書き戻しを起こしたイベントが修飾キー付きクリックなら確定せず、表の選択を元の行へ戻す。判定はタップとの順序やフラグに頼らず、イベントの事実で行う。キーボードによる選択移動は従来どおり開く(#570)。実機で、修正ありでは起点タブが変わらず、修正を戻すと再現することを確かめた。
<!-- SECTION:FINAL_SUMMARY:END -->
