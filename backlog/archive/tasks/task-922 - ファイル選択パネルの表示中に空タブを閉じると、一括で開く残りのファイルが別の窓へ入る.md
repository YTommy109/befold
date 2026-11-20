---
id: TASK-922
title: ファイル選択パネルの表示中に空タブを閉じると、一括で開く残りのファイルが別の窓へ入る
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T12:47:00Z'
updated_date: '2026-11-07T13:04:00Z'
labels:
  - tabs
  - ui
dependencies: []
priority: low
type: bug
ordinal: 888000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-917 の code-review high で挙がり、条件が重なる稀な経路として見送ったもの。空タブで ⌘O のパネルを開いたまま空タブを閉じ、複数のファイルを選ぶ。最初のファイルが既に別の窓 W で開いていると、閉じた起点は `ViewerWindowOpenPolicy.resolveOrigin` で起点なしの `.currentTab` になり、W が前面に出る。`DocumentOpener.openInTabs` はその W を次の起点にするので、残りのファイルが W のタブとして開く。利用者は W を選んでいない。TASK-917 以前はこの一括が丸ごと捨てられていた。裏付けはコード参照のみで、未再現。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 起点の空タブが閉じた一括オープンで、残りのファイルの開き先が決まり、docs/dev/viewer-ui.md に書かれている
- [x] #2 最初のファイルが別の窓で開いているときの動作を自動テストで確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: 一括オープンで最初の文書が既存の無関係な窓を再利用したら、その窓を残りの起点にしない。閉じた起点の扱いは従来どおり openViewer の入口の resolveOrigin に任せ、起点が閉じていれば残りは起点なしで開く。最初の文書が新しく開いた窓へは残りをまとめる。viewer-ui.md に記載。
code-review high: 最初の版は openInTabs で閉じた起点を独自に判定しており、文書の窓へドロップして途中でその窓を閉じると、残りがタブグループへ入らず別々の窓に散らばる退行を生んでいた。TASK-917 の『経路ごとに閉じた起点を判定しない』規則にも反していたので撤去し、『呼び出し前から開いていて、起点のタブグループの外にある窓』を起点にしない判定だけにした。
DocumentTabOpeningIntegrationTests が type_body_length を超えたので、起点が消えた要求に関するテストを DocumentOpenerVanishedOriginTests へ分けた。
実測: 判定を外すと closedBlankBatchDoesNotJoinUnrelatedWindow が落ちる。swift test 2009 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。ファイル選択パネルそのものは操作できないので、パネルが呼ぶ openInTabs の経路で測っている。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
空タブが閉じた一括オープンで、最初の文書が入った既存の無関係な窓を残りの起点にしないようにした。閉じた起点の扱いは resolveOrigin に任せたまま、残りは起点なしで開くか、最初の文書が新しく開いた窓へまとまる。
<!-- SECTION:FINAL_SUMMARY:END -->
