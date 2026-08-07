---
id: TASK-352
title: プレビュー→ソースモード切替で差分表示が消える
status: To Do
assignee: []
created_date: '2026-08-07 04:49'
updated_date: '2026-08-07 04:50'
labels:
  - bug
  - diff
dependencies: []
priority: high
ordinal: 612000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状（ユーザー報告）

markdown ファイルをプレビューモードで開き、差分表示(View > 差分を表示)をONにした状態で
ソースモードへ切り替えると、差分が表示されなくなる。build 1.12.2-dev.3 (build 1282) で発生。

## 調査結果（コード参照、静的読解のみ）

同じ症状のバグは TASK-337 で既に修正されたはずになっている。

- `BefoldApp/befold/App/ViewerWindowController.swift:660-679` の `setSourceMode` は、
  `didChange` のとき `applySourceMode(newValue)` で `store.isSourceMode` を同期更新した後、
  `refreshDiff()` を呼んでいる（TASK-337 のコメントあり）。
- `refreshDiff()`（`ViewerWindowController+Diff.swift:23-44`）は `capabilities.canToggleDiff`
  を確認してから非同期で `git diff` を取得し、`store.diffText` に反映する。
- `ViewerContentView.diffState`（`ViewerContentView.swift:29-33`）は
  `diffDisplayPreference.isEnabled && store.diffText != nil` のときのみ差分状態を返す。

静的に読む限り経路は正しく配線されており、TASK-337 の修正が既に main（HEAD 9ccc8861 相当、
build 1282 に含まれる）に入っている。にもかかわらずユーザーは症状を再現しているため、
以下のいずれかを疑う必要がある。

- TASK-346/TASK-349（差分取得の合流ウィンドウ変更、2026-08-07 対処）に起因する新しい
  タイミング回帰（`refreshDiff` の非同期取得が別の契機と競合し、古い結果で上書きされる等）
- JS 側（`viewer-main.js` の `_renderDiffHtmlIfAvailable` / `render()` の再描画契機）が
  `store.diffText` の遅延到着を正しく拾えていない
- 特定のファイル種別・リポジトリ状態（未追跡ファイル・.git 未検出など）でのみ起きる条件

## 次のアクション

- 実機での再現手順を確定する（プレビューで差分ONにしてからソースへ切替、の具体的な
  タイミングと対象ファイルの git 状態）
- 再現できたら、`refreshDiff` の呼び出しと `store.diffText` 反映のタイミングをログで実測する
  （固定間隔の推測ではなく実測。CLAUDE.md「固定間隔の性能計測は結論が逆転する」参照）
- TASK-346/349 で変更された合流タイミングとの関連を優先して疑う（直近の変更のため）

## 前提（未確認）

- ユーザーが「差分表示トグルは有効化された状態だった」ことは確認済み（本人回答）
- 「最初からソースモードで開いた場合」と「プレビューから切り替えた場合」の切り分けは未確認
- 差分パネル自体が非表示になるのか、パネルは出るが空になるのかは未確認
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 実機で再現手順が確定している(対象ファイル・git状態・操作順序)
- [ ] #2 refreshDiff呼び出しとstore.diffText反映のタイミングを実測したログがある
- [ ] #3 根本原因がTASK-346/349由来のタイミング回帰かJS描画側の問題か切り分けられている
- [ ] #4 原因箇所に対する修正とテストが追加されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
追加報告: 「差分を左右に並べる」(toggleDiffLayout) を実行してもレイアウトが変わらず
インライン(シングル)のまま。toggleDiffLayout は capabilities.canToggleDiff を通過すれば
diffDisplayPreference.layout を反転するだけ(ViewerWindowController+Diff.swift:66-68)なので、
以下のいずれかが疑われる。
- そもそも diffState.text が nil で表示するものが無いため、レイアウトを変えても見た目が
  変わらない(本タスクの主症状と同一原因の可能性が高い)
- layout の反転自体は効いているが、JS側の再描画契機(_renderDiffHtmlIfAvailable /
  renderSideBySideDiffHtml)がレイアウト変更だけでは再描画されない
実機再現の際はこの2点目もあわせて確認する。
<!-- SECTION:NOTES:END -->
