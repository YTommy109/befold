---
id: TASK-352
title: サイドバーのバッジと差分ビューアが別の基準で比較している
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-07 04:49'
updated_date: '2026-08-07 05:37'
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

worktree 内の markdown ファイルで、サイドバーに M バッジが出ているのに、ソース表示へ切り替えても差分表示にならない。「差分を左右に並べる」を実行してもレイアウトが変わらない。build 1.12.2-dev.3 (build 1282)。再起動しても M は出たまま。

対象ファイルは**ブランチでコミット済み**で、作業ツリーはきれい（`git status --porcelain` と `git diff HEAD --stat` がどちらも空。ユーザー実測）。

## 原因（コード参照で確定）

**バッジと差分ビューアが別の基準で比較している。**

- サイドバーのバッジ（`GitStatusReader.swift:95-104`）は、ワーキングツリーの状態に加えて `branchChange` を持つ。`git merge-base HEAD <defaultBranch>` で base を求め、`git diff --name-status -z <base> HEAD` を読む。つまり**このブランチでコミットされた変更**を M / A として出す
- 差分ビューア（`GitDiffReader.swift:13,45`）は `git diff HEAD -- <path>`。つまり**作業ツリー vs HEAD**。ブランチでコミット済み・作業ツリーがきれいなファイルでは空になる

どちらも自分の基準では正しく、基準が揃っていないだけ。バッジが「変更あり」と言っているファイルに差分が出ないのはこの食い違いによる。

「markdown 限定かも」に見えたのは、その markdown がブランチでコミット済みで、比較対象の .swift には未コミットの編集があったためと思われる。

## 切り分け済み（実測、ヘッドレス）

Swift の配線とモード切替は正常。markdown をレンダリング表示から差分 ON でソース表示へ切り替える経路を再現し、`renderModeCanToggle=false sourceModeCanToggle=true fetches=1 diffText=set isDiffShown=true` を確認した。TASK-337 の修正は効いている。JS 側（`viewer-main.js` の `render` / `_renderSource` / `_renderDiffHtmlIfAvailable` / `_sourceLanguage`）も markdown を除外していない。

## 方針（ユーザー承認済み）

差分ビューアの基準をバッジと揃える。`git diff <merge-base HEAD defaultBranch> -- <path>` にする。

- フィーチャーブランチでは、ブランチでコミットした変更＋ステージ済み＋未ステージが 1 つの差分として出る。バッジが出ているファイルには必ず差分がある、という一貫性が生まれる
- main 上では `merge-base(HEAD, main) == HEAD` なので現在の挙動と同じ

検討が要る点:

1. コスト: 取得のたびに `merge-base` と `origin/HEAD` の解決が増える。`GitStatusReader` は毎回引いているので、キャッシュの置き場を揃えるか判断する
2. 縮退: `defaultBranch` を解決できない場合（detached HEAD、`origin/HEAD` 未設定、リモート無し）。「解決できたか」という事実で判定し、できなければ `HEAD` へ落とす。空になったから落とす、にはしない
3. 基準の集約: 今回の食い違いは、基準が `GitStatusReader` と `GitDiffReader` に二重に実装されていることから来ている。同じ穴を塞ぐには基準の解決を 1 箇所へ寄せる

「未コミットの変更」と「ブランチの変更」を切り替える表示設定は本タスクに含めない（別タスクへ）。

## スコープ

`FeatureGate.isSourceDiffEnabled` / `isSidebarGitStatusEnabled` の配下。コミット件名には `(gate)` を付けること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ブランチでコミット済み・作業ツリーがきれいなファイルでも、ソース表示で差分が出る
- [x] #2 main 上（merge-base == HEAD）では従来と同じ差分が出る
- [x] #3 defaultBranch を解決できない場合は HEAD 基準へ落ちる。判定は「解決できたか」という事実で行い、差分が空かどうかでは判定しない
- [x] #4 比較基準の解決が 1 箇所に集約され、GitStatusReader と GitDiffReader が同じ基準を使っている
- [x] #5 基準がずれたら落ちるテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 基準の解決を `GitComparisonBaseResolving` / `GitComparisonBaseResolver` として切り出し、`GitStatusReader` の private 実装（defaultBranch / originHeadBranch / merge-base）をそこへ移す。
2. `GitStatusReader.branchChanges` を解決器経由にする。base が nil なら従来どおり空（ブランチ差分を諦める）。
3. `GitDiffReader` を解決器経由にする。base が nil のときだけ HEAD へ落とす。
4. 実 git の結合テストで、ブランチのコミット済み変更・デフォルトブランチ上・base 不明時の 3 ケースと、バッジと差分の一致を固定する。
5. 追加コストを実測する。xcodegen generate（新規ファイルのため必須）。swiftlint のベースライン差分ゼロを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-07 実装:

- `GitComparisonBase.swift` を新設し、`defaultBranch` / `originHeadBranch` / `merge-base` の解決を `GitStatusReader` の private から移した。両 reader が同じ解決器を使う（既定は渡された runner を共有するので、テストで縮めたタイムアウトが基準の解決にも効く）。
- `GitDiffReader` は `git diff <base> -- <path>`。base が nil のときだけ `HEAD` へ落とす（差分が空だったから落とす、ではない）。
- merge-base はコミット・チェックアウトで動くため**キャッシュしない**。保持すると `GitStatusStore` が fingerprint で避けている陳腐化を持ち込む。doc コメントに明記した。

検証（すべて実測）:
- 新規テスト 4 件が通る。`swift test` 全体 1186 件通過（20.5 秒）。
- 検知能力: 基準を `HEAD` へ戻すと「ブランチでコミットした変更が…差分に出る」と「バッジがブランチ変更を示すファイルには差分がある」の 2 件が落ちる。縮退の 2 件（デフォルトブランチ上・base 不明時）は戻しても通るのが正しい。
- swiftlint: origin/main とのベースライン差分ゼロ（両者 78 件）。
- xcodegen generate 実行済み（新規ファイルのため）。

コスト実測（このリポジトリ、20 回平均）:
- symbolic-ref: 7.7 ms/回
- merge-base: 9.6 ms/回
- diff 本体: 11.5 ms/回

差分取得 1 回あたり 11.5 ms → 約 30 ms（2.6 倍）。メインアクターの外で走るため UI は止まらない。キャッシュは入れていない（simplify 優先）。効かせるなら `defaultBranch`（symbolic-ref 側 7.7 ms）が候補で、こちらは安定した値なのでキャッシュしても陳腐化しない。実害が出たら検討する。
<!-- SECTION:NOTES:END -->
