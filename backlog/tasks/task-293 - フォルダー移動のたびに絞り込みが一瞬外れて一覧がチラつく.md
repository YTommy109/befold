---
id: TASK-293
title: フォルダー移動のたびに絞り込みが一瞬外れて一覧がチラつく
status: Done
assignee: []
created_date: '2026-08-04 12:21'
updated_date: '2026-08-04 13:42'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 468000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
1.11.7-dev.4 (1176) で再現。「変更されたファイルのみ表示」が ON の状態で、サイドバーから `backlog/tasks` のようなファイル数の多いフォルダーへ降りるとき・そこから上がるときに、ファイル一覧が一瞬すべて表示されてから絞り込まれる（チラつく）。降りる／上がるのどちらでも起きる。

一覧の取得と git 状態の取得は別タスクで走り完了順が保証されないため、移動直後は新しいディレクトリの git 状態がまだ届いていない。絞り込み側は「状態が未解決（nil）」「状態が別ディレクトリのもの（directoryKey 不一致）」のとき絞り込みを行わず全件を返す設計になっており（TASK-285 / `SidebarGitStatus`・`FileListModel.visibleEntries`）、この空白期間に絞り込み前の一覧が一度描画されているものと見られる。

この縮退（絞り込まない）は「移動直後に一覧が消える」ことを避けるための意図的な設計なので、単に縮退をやめると別の不具合に化ける。表示の切り替わりをどう見せるか（状態が届くまで前の絞り込み結果を保つ／一覧の反映を git 状態と揃える／移動中は描画を抑える など）を含めて方針を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「変更されたファイルのみ表示」ON でフォルダーを降りる／上がるとき、絞り込み前の全件一覧が一瞬描画されない
- [x] #2 移動直後に一覧が空になったり、対象フォルダーの内容が表示されないままにならない（TASK-285 の縮退が守っていた挙動を壊さない）
- [x] #3 採用した方針（縮退の扱いをどう変えたか）と、その根拠が記録される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 方針の検討（縮退の扱い）

TASK-285 の縮退（gitStatus が nil / directoryKey 不一致なら絞り込まない）は「移動直後に
一覧が消える」を防ぐための意図的な設計であり、これ自体は正しい。縮退を弱める修正は
非 git ディレクトリや取得失敗時に一覧を空にする方向に働くため採らない。

まず単純化を検討した結果、**縮退が起きる空白期間そのものを無くす**方針を採った。
チラつきの原因は縮退の判定ではなく「一覧と git 状態を別タスクで反映していたこと」であり、
状態を足す（移動中フラグ・前回の絞り込み結果の保持など）必要はない。

- performListing で列挙と git 状態取得を**並行に起こし、同じメインアクター実行で一緒に反映**する。
  取得は並行のままなので待ち時間は遅いほうに揃うだけ（直列化しない）。
- 縮退の判定（FileListFilter.gitChangeFilter / SidebarGitStatus.directoryKey）は一切変更していない。
  index ウォッチャ由来の refreshGitStatuses は従来どおり独立して走るため、縮退は保険として残る。
- 併せて `.git/index` の監視管理を GitIndexWatch へ切り出した（SidebarNavigator の
  file_length / type_body_length を main のベースラインに戻すため。振る舞いは同じ）。

## 検証

- 新規テスト SidebarNavigatorListingCoherenceTests: 移動先の git 取得を列挙より遅らせ、
  pendingListingTask 完了時点で activeGitChangeFilter が解決済み・visibleEntries が
  絞り込み済みであることを確認。**修正前のコードでは 2 件の期待が落ちることを実測**
  （activeGitChangeFilter → nil / visibleEntries → 全件）。
- swift test 全体 1075 件パス（連続 5 回）。
- swiftlint: SidebarNavigator.swift / 新規 2 ファイルとも main からの新規警告ゼロ。

## 追記: 実機確認で残っていた 2 経路（実測で特定）

最初の修正（列挙と git 状態のペア化）だけでは、実機のちらつきは止まらなかった。
ユーザーの再確認でサイドバー・プレビューの両方が残っていることが分かり、
`visibleEntries` に一時ログを仕込んで実測した。

1. **プレビュー（FolderListingView）**: 自前でディスク列挙しており、モデルの git 状態と
   完了順が揃っていなかった。表示中ディレクトリを見ているときはサイドバーが揃えた一覧を
   そのまま使う（FileListModel.listingSource / FolderListingSource）。選択中のサブフォルダーを
   見ているときだけ従来どおり自前で列挙する（git 状態の対象外で絞り込み自体が働かない）。
   ディレクトリ全列挙が 1 回減る副次効果もある。

2. **サイドバー**: 絞り込みの突き合わせ先が `currentDirectory` だった。移動要求は
   currentDirectory を先に進めるため、一覧が届くまでの間だけ縮退していた。突き合わせ先を
   `entriesDirectory`（手元の一覧が由来するディレクトリ）に変更。空状態の文言
   （activeGitChangeFilter）も同じ基準へ揃えた。

3. **真因（実測ログ）**: `degraded entries=122 entriesDir=tasks curDir=backlog statusDir=.../backlog`。
   `.git/index` 監視や再読込を契機とする**単独の git 取得**が、移動先を対象に一覧より先に
   着地し、画面に出ている一覧（移動元）に対応する状態を上書きで失わせていた。ペア化は
   この単独経路には効かない。`FileListModel.gitStatus` の書き込みを `applyGitStatus(_:for:)`
   1 本に絞り、**手元の一覧がまだ別ディレクトリのものなら一覧が届くまで保留**するようにした。
   保留は状態が nil（git 管理外・取得失敗）でも「どのディレクトリの結論か」を持たせ、
   非 git フォルダーへの移動を「まだ届いていない」と取り違えないようにしている。

## 教訓

自分で書いた回帰テストが通っても、それは**自分が想定した順序**を固定しただけだった。
実機で再現が続いたら、次の修正案を考える前にログで実際の順序を採ること。

## 追加検証

- swift test 全体 1080 件パス。追加した 2 件の回帰テストは、それぞれ修正を戻すと落ちることを実測。
- 実機（Debug ビルド）でユーザーがちらつき解消を確認済み（サイドバー・プレビューとも）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「変更されたファイルのみ表示」ON でのフォルダー移動時に、絞り込みが一瞬外れて全件が見えるちらつきを解消した。TASK-285 の縮退は変えず、縮退が起きる空白期間を無くす方針。(1) 列挙と git 状態を同じタスクで並行取得し一緒に反映、(2) 絞り込みの突き合わせ先を currentDirectory から entriesDirectory へ、(3) プレビューは表示中ディレクトリならサイドバーの一覧を共有、(4) 真因だった「移動先の状態が一覧より先に着地して手元の一覧の状態を失う」問題を、一覧が届くまで保留する applyGitStatus(_:for:) で解消。検証は swift test 1080 件と実機確認。
<!-- SECTION:FINAL_SUMMARY:END -->
