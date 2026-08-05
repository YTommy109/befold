# ADR 0003: git ステータス反映の可否判定を FileListModel の 1 関数に一本化する

- ステータス: Accepted
- 日付: 2026-08-05
- backlog decision: decision-3

<!-- derived-from ../dev/native-app-design.md -->

## Context

サイドバーの git ステータス反映（`SidebarNavigator.performListing` とその周辺）で、性質の同じ順序回帰が
5 回連続で発生した（TASK-293 → TASK-294 → TASK-297 → TASK-299 → TASK-300）。

`performListing` は「絞り込み(showChangedFilesOnly) ON なら一覧と git 状態を同じタスクで待ち合わせてから
一括反映する（結合経路）、OFF なら一覧を先に反映し git 状態は別タスクで遅れて反映する（分離経路）」という
2 つのオーケストレーションを持つ。この分岐自体は意図的な UX トレードオフで、削除対象ではない
（後述 Decision 参照）。

問題は、git 状態を「反映してよいか」の判定が、次の 3 つの状態にまたがって行われていたこと。

| 状態 | 所有クラス | 役割 |
|---|---|---|
| `gitStatusGeneration` | `SidebarNavigator` | 取得を発行するたびに進める採番器 |
| `appliedGitStatusGeneration` | `SidebarNavigator` | 直近に**反映した**世代。「これより新しければ反映する」の比較対象（TASK-299 で導入） |
| `entriesDirectory` / `pendingGitStatus` | `FileListModel` | 手元の一覧のディレクトリと、一覧が届くまで状態を待たせる対付け（TASK-293 で導入） |

`SidebarNavigator.applyGitStatus(_:for:generation:)` が世代の新旧をまず判定し、通過したものだけを
`FileListModel.applyGitStatus(_:for:)` へ渡してディレクトリ対付けを判定する、という**二段構え**になっていた。

この分散が実際に事故を生んだ。

- TASK-294: 結合経路の世代比較を「一致」から「反映時点の最新値と再比較」に変えたところ、比較対象が
  常に自分自身へ書き換わるため実質ガードが無効化され、TASK-299 で作り直した。
- TASK-299: 作り直す際に `appliedGitStatusGeneration` という 4 つ目の状態を新設する必要が生じた。
- TASK-300: ウィンドウクローズ時にこの状態を手動で「発行済みの先頭へ揃える」処理を追加する必要が生じた
  （揃え忘れると閉じたウィンドウのために `.git/index` 監視が再アームされる）。

3 つの状態のうち 2 つ（採番・反映済み世代）が `SidebarNavigator` に、もう 1 つ（ディレクトリ対付け）が
`FileListModel` にあり、「反映してよいか」を答えるには両方を正しい順序で参照する必要がある。この二段構えが
続く限り、新しい変更のたびに片方だけを更新して壊す（TASK-294/299/300 はいずれもこの形）リスクが残る。

## Decision

**git 状態を「反映してよいか」の判定を `FileListModel.applyGitStatus` 1 関数に一本化する。**
`SidebarNavigator` は世代番号の採番のみを担当し、反映可否の判定ロジックは一切持たない。

具体的には次の 2 点を規約とする。

1. **recency ガードを FileListModel へ移す**: `appliedGitStatusGeneration` を `SidebarNavigator` から
   `FileListModel.appliedGitStatusSequence` へ移動し、`applyGitStatus(_:for:sequence:) -> Bool` が
   「発行順の新旧判定（recency）」と「ディレクトリ対付け（TASK-293 由来のpending機構）」を同じ関数内で
   ひとつながりに判定する。`SidebarNavigator` 側はこの戻り値だけを見て `gitIndexWatch.update` を呼ぶかどうかを
   決め、世代の比較そのものには関与しない。
2. **`SidebarNavigator` は採番器に徹する**: `gitStatusGeneration` は「発行するたびに進める連番」としてのみ残す。
   ウィンドウクローズ時の一括無効化（TASK-300）も `FileListModel.invalidatePendingGitStatus(upTo:)` という
   単一の呼び出しに置き換え、`SidebarNavigator` 側で「反映済み世代を発行済みの先頭へ揃える」処理を手書きしない。

**結合/分離のオーケストレーション分岐そのものは統合しない。** 結合経路（TASK-293: 絞り込み ON 時のちらつき防止）と
分離経路（TASK-297: 絞り込み OFF 時のレイテンシ回避）は、どちらも取得結果を待つかどうかという意図的な UX
トレードオフであり、削除すると一方の回帰が再発する。TASK-297 の AC#2（絞り込み ON 時のレイテンシ体感を
ローディング表示等で改善する）は本 ADR のスコープ外とし、UX 判断が必要な別タスクに委ねる。

## Consequences

- `SidebarNavigator` から `appliedGitStatusGeneration` を削除できる。反映可否を判定する状態が
  `FileListModel` 側の 1 箇所（`appliedGitStatusSequence` + `pendingGitStatus`）に集約され、
  今後この経路に手を入れる際は 1 関数を読めば可否判定の全体が分かる。
- TASK-291/293/294/296/297/299/300 の既存回帰テストは、内部実装が変わるだけで観測可能な挙動
  （反映される・反映されない・監視が再アームされない）は変えないため、そのまま regression pin として使える。
- この決定を再検討するトリップワイヤ:
  1. `FileListModel` に反映可否の判定以外の責務（描画・永続化等）が増え、1 クラスが肥大化する
  2. 絞り込み ON 経路のレイテンシ改善（TASK-297 AC#2）に着手する際、結合/分離の分岐自体を見直す必要が生じる
  3. 複数ディレクトリ・複数ソースの git 状態を同時に扱う要件が生まれ、単一の `directoryKey` 対付けでは
     表現できなくなる
