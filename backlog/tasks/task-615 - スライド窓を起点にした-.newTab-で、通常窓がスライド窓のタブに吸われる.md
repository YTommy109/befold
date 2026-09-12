---
id: TASK-615
title: スライド窓を起点にした .newTab で、通常窓がスライド窓のタブに吸われる
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 13:53'
updated_date: '2026-09-11 14:34'
labels: []
dependencies: []
ordinal: 805000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-613 のコードレビュー（finderA）で検出し、実測で確定した既存の穴。TASK-613 が「同じファイル」のケースまで広げた。

実測（ヘッドレスのテストホスト、`MockedViewerWindowManager`）: スライド窓 A を起点に `.newTab` で別ファイル B を開くと、B の通常窓（`kind == .viewer`）が A のタブグループに入る。同じファイル A を `.newTab` で開いた場合も同様（TASK-613 前はスライド窓自身が再利用候補になって前面化していたが、今は候補から外れて通常窓が新しく開き、それがスライド窓のタブになる）。`ViewerWindowChrome` はスライド窓に `tabbingMode = .disallowed` を立てているが（コード参照）、これは**自動**タブ化を止めるだけで、`NSWindow.addTabbedWindow(_:ordered:)` の明示的な結合は通る（実測: `tabbingMode.rawValue == 2` のまま `tabGroup` が非 nil になった）。

経路（コード参照）: スライド窓内のリンク cmd+クリック → `ViewerWindowController+References.openReference` → `openFileElsewhere(url, .newTab, .afterSource, window)` → `ViewerWindowManager.openViewer(disposition: .newTab, relativeTo: slideWindow)` → `ViewerTabGrouping.present(asTabOf: slideWindow)` → `attachAsTab`。起点側の種別（`joinsTabs`）を見る場所がどこにも無い。

方針の候補: 起点の窓が `joinsTabs == false` なら `.newTab` を `.newWindow` として扱う。判定を置くのは `openViewer`（`asTabOf:` を決めている 1 箇所）か `ViewerWindowOpenPolicy`。起点の `kind` は `sourceWindow.windowController as? ViewerWindowController` から引ける（`ViewerTabGrouping.viewerPath(of:)` と同じ形）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライド窓を起点に `.newTab` で別ファイルを開くと、独立した通常窓が開き、スライド窓のタブグループには入らない
- [x] #2 スライド窓を起点に `.newTab` で同じファイルを開いた場合も同様に独立した通常窓が開く
- [x] #3 通常窓を起点にした `.newTab` の挙動（タブ合流・置き場所・背面で開く）は変わらない
- [x] #4 起点の種別で分岐する判定は 1 箇所に置き、`ViewerWindowManagerTabTests` で実配線のテストを持つ
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `ViewerWindowOpenPolicy` に純粋判定 `effectiveDisposition(_:relativeTo:)` を足す。起点の窓の種別が `joinsTabs == false` なら `.newTab` を `.newWindow` へ倒す。起点の kind は `sourceWindow.windowController as? ViewerWindowController` から引く(`ViewerTabGrouping.viewerPath(of:)` と同じ形)。
2. `ViewerWindowManager.openViewer` の冒頭で 1 回だけ適用し、以降の `reusableController` / `asTabOf` / `select` はすべて正規化後の disposition を見る(起点の種別で分岐する判定はこの 1 箇所だけ)。
3. `ViewerWindowKind.joinsTabs` の doc に「逆向き(この窓のグループへ他の窓がタブとして加わる)も同じ述語で決める」を追記する。`tabbingMode = .disallowed` は自動タブ化しか止めず `addTabbedWindow` は通る、という実測も併記。
4. `ViewerWindowManagerTabTests` に実配線のテストを 2 件(別ファイル / 同じファイル)。通常窓起点の既存テストが変わらないことも既存テストで担保。

### /review-design の結果（実装前）

- 項目 3（消費経路の全列挙）: `openViewer` 内で disposition を読むのは ①`reusableController` ②`kind` 決定 ③`asTabOf` ④`select` の 4 箇所。正規化した値を**同名のローカルで shadow** し、以降から元の引数へ触れなくする（項目 9 の「破れない構造」を兼ねる）。
- 項目 3（兄弟箇所）: `.newTab` を実際のタブ結合へ変えるのは `openViewer` の `asTabOf` だけ。`OpenDisposition` の他の読み手（`SidebarContextMenu` / `FileListView` / `SidebarKeyAction` / `ViewerWindowController+References.openReference`）はいずれも disposition を作るか素通しするだけで、タブ結合を決めない（実測: `rg 'OpenDisposition|\.newTab|disposition' BefoldApp/befold/`）。
- 項目 2（不変条件）: スライド窓にはサイドバーが無い（`allowsSidebar == false`）ので `fileListDidRequestOpenElsewhere` は起点になりえず、実際の起点は文書内リンク（`openReference`）だけ。倒したあと `tabPlacement` は無視されるが、`.newTab` のときだけ意味を持つという既存の契約どおり。
- 項目 1（判定の真実の源）: 起点の種別は `ViewerWindowController.kind`（生成時に確定し不変）で見る。`sourceWindow` が nil / 非ビューア窓のときは倒さない = 現状のまま（変化なし）。
- 挙動の変化として残るもの: 同じファイルが**別の通常窓**で開いている状態でスライド窓からリンクを cmd+クリックすると、その通常窓を前面化せず新しい窓が開く。これは変更前も同じ（起点のタブグループに候補が居ないため `reusableController` は nil を返していた）ので、今回の差分による退行ではない。
- 項目 10（行数）: `ViewerWindowOpenPolicy` 67 行 → 約 80 行、`ViewerWindowManager` グループ 326 行 → 約 328 行（実測: `scripts/check-type-group-size.sh`）。プロトコル準拠・stored property・注入クロージャはいずれも増えない。
- 項目 4 / 5 / 6 / 8: 該当しない（新しい表示状態は無く、同期の純粋変換 1 回で、初期化順序も非同期の世代管理も絡まない）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: `ViewerWindowOpenPolicy.effectiveDisposition(_:relativeTo:)` を新設し、起点の窓が `joinsTabs == false` の種別なら `.newTab` を `.newWindow` へ倒す。`ViewerWindowManager.openViewer` の冒頭で **引数を同名のローカルで shadow** して適用したので、以降の再利用判定・`asTabOf`・`select` はすべて解釈後の値を見る（元の要求へ触れる経路が構文的に残らない = AC #4 の「1 箇所」の担保）。`ViewerWindowKind.joinsTabs` の doc に両方向の述語であることと `tabbingMode = .disallowed` の限界を書いた。

検証（実測）:
- 新規テスト 2 件（`ViewerWindowManagerTabTests`）が実 NSWindow の `tabGroup` で測って passed。
- **修正を外すと落ちることを確認した**: `effectiveDisposition` の guard を一時的に無効化して `swift test --filter ViewerWindowManagerTabTests` を実行 → 2 件とも `(opened.window?.tabGroup?.windows.contains { $0 === slideWindow } → true) != true` で失敗（= 通常窓がスライド窓のタブグループに吸われる事象を再現）。
- AC #3（通常窓起点の `.newTab` が変わらない）は既存 9 件（タブ合流・置き場所 end/afterSource・背面で開く・同グループ内の重複抑止・別窓で開いているだけなら新タブ）が変更なしで passed。
- `swift test` 全体 2007 tests passed。`/swiftlint-baseline` の origin/main 差分ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スライド窓を起点にした `.newTab` を `.newWindow` として解釈する判定を `ViewerWindowOpenPolicy.effectiveDisposition(_:relativeTo:)` へ 1 箇所だけ置き、`openViewer` が引数を shadow して適用するようにした。通常窓がスライド窓のタブグループへ吸い込まれなくなる。実 NSWindow でタブグループを測る新規テスト 2 件で担保し、修正を外すと 2 件とも落ちることも確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
