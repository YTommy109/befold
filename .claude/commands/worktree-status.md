# /worktree-status — worktree・ブランチ・PR・作業内容を一覧する

引数: $ARGUMENTS（省略可。`--no-pr` | `--fetch`）

**ウィンドウを閉じた後に「どの worktree で何をしていたか」を会話なしで特定する**ための
読み取り専用コマンド。ユーザーに worktree を尋ねる前に、まずこれを実行する。

## 手順

```bash
scripts/worktree-status.sh $ARGUMENTS
```

出力をそのままユーザーに報告する。ユーザーが探している作業を特定する場合は、
「未コミットあり」「origin/main から N commit」「PR がまだ無い」ものを候補として挙げる。

各 worktree について次を表示する。

- ブランチ名と `origin/main` からのコミット数（**worktree 名とブランチ名は一致しない**）
- PR 番号と状態（`gh` があるとき。open / merged / closed を問わず最新 1 件）
- 未コミット変更の有無
- 最終コミットの日時と件名（= 何をしていたか）
- 絶対パス（そのまま `cd` や作業再開に使える）

何も変更しない。`--fetch` を付けたときだけ `git fetch --prune` する。

## 3 つの worktree コマンドの使い分け

| コマンド | 目的 | 変更 |
|---|---|---|
| `/worktree-status` | **どこで何をしていたかを調べる**（閉じたウィンドウの特定、PR 未作成の作業探し） | しない（読み取り専用） |
| `/worktree-reset` | 作業が終わった worktree を**残したまま**次のブランチを切り直す | ブランチを切り替える |
| `/worktree-clean` | 完了した worktree を**まとめて捨てる** | worktree を削除する |

迷ったら `/worktree-status` から始める。捨ててよいか・切り直してよいかの判断材料
（未コミット変更・PR の状態・main からの差分）がすべて出る。
