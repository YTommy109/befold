# /worktree-clean — 完了した worktree の掃除

引数: $ARGUMENTS（省略可。`--force` | `--no-fetch` | `--keep-branch`）

完了した（作業がすべて main に入っている）git worktree を掃除する。
完了判定・保護（未コミット変更のスキップ）・削除はすべてスクリプト内で行われる。
完了判定は `scripts/lib/branch-completion.sh` にあり、`/worktree-reset` と共有している。
上流ブランチの削除（`[gone]`）だけでは完了としない。

## 手順

1. まず **dry-run** で削除対象を確認する（引数なし＝表示のみ）:

   ```bash
   scripts/worktree-clean.sh
   ```

2. 出力された削除対象をユーザーに提示する。
   引数に `--force` が指定されている場合を除き、**ここで実削除の可否を確認する**。

3. 承認された（または `--force` が渡された）場合のみ実削除する:

   ```bash
   scripts/worktree-clean.sh --force $ARGUMENTS
   ```

各ステップの出力をそのままユーザーに報告する。スクリプトがエラーで終了した場合は
エラーメッセージを報告して終了する（勝手にリカバリーを試みない）。

安全策（スクリプト側で担保、把握しておく）:

- main リポジトリ・現在の worktree は対象外
- 未コミット変更がある worktree は `--force` でもスキップ
- 上流が `[gone]` でも main に入っていない変更があるブランチはスキップし、理由を表示する
  （squash merge 後に積んだ未プッシュコミットを消さないため。実例: TASK-528）
- `--force` を明示しない限り削除は行われない

削除対象の作業内容を確認したい場合は、先に `/worktree-status` を実行する
（ブランチ・PR・最終コミット・未コミット変更が読み取り専用で一覧できる）。
worktree を残したままブランチだけ切り直すなら `/worktree-reset`。
