# /pr — push & プルリクエスト作成

現在のブランチを push し、`gh pr create` でプルリクエストを作成してください。
既に PR がある場合は新規作成せず、その PR を更新します。

手順:

1. `gh pr list --head <ブランチ名> --state all --json number,state,mergedAt` で既存の PR を確認する。
   `--state all` を付けるのは、既定の open だけを見ると**マージ済みの PR を見落とす**ため
   （実績: PR #543 がマージ済みのブランチで `--state all` 無しの確認が `[]` を返し、
   マージ済みの実装コミットごと PR #544 を作り直して macOS の CI を余分に 1 本回した）
   - **open な PR がある場合**: 新規作成しない。push 後に `gh pr edit <番号> --body`
     で本文をブランチ全体の内容に更新する（追加コミット分を「変更内容」「検証」に反映する）。
     タイトル・ラベルはブランチ全体の主眼が変わった場合のみ更新する
   - **マージ済み / クローズ済みの PR しかない場合**: そのブランチは既に用済みなので、
     `git fetch origin main` の後 `git log origin/main..HEAD --oneline` で**まだ main に
     入っていないコミットだけ**を確かめる。squash マージだと元のコミットは sha が変わって
     main に入るため、`git log` 上は「未マージ」に見える点に注意する。マージ済みの作業が
     残っていたら、ブランチを `origin/main` に載せ直してから起票する
   - **無い場合**: 以降の手順で新規作成する
2. `git log origin/main..HEAD --oneline` で PR に含まれるコミットを確認する
   - コミットが 0 件の場合は、未コミットの変更を先にコミットしてよいかユーザーに確認する
   - **マージ済みの作業が混ざっていないこと**を確認する。混ざったまま PR を作ると、
     差分に無関係なパスが入って `on.paths` に一致し、CI が余分に走る
3. 未 push のコミットがあれば `git push -u origin <ブランチ名>` する
4. PR タイトルの Conventional Commits type（`feat` / `fix` / `chore` / `refactor` / `docs` / `test` / `ci` / `perf`）に対応するラベルを 1 つ選ぶ
5. 対応する backlog タスクの `References` に GitHub Issue の URL が記載されていれば、その Issue 番号を控える（`backlog task view <ID> --plain` で確認）
6. `gh pr create --label <type> --assignee YTommy109` で PR を作成し、URL を報告する

Issue 番号が見つかった場合、本文の「概要」節の直後に `Closes #<番号>`（複数あれば `Closes #A, Closes #B` のように列挙）を必ず入れる。マージ時に GitHub が自動で Issue をクローズするため、Final Summary や検証節への言及だけで済ませない。

タイトル: ブランチの主要コミットに合わせた Conventional Commits 形式の日本語。
例: `feat: リリース DMG に Applications フォルダへのリンクを追加する`

本文は次の 3 節で構成する:

```markdown
## 概要

この PR で何がどう変わるかを 1〜3 文で書く。

## 変更内容

ファイル・機能ごとの箇条書き。なぜその変更が必要かも一言添える。

## 検証

実施した検証(ビルド・テスト・手動確認)と、未検証で残る確認事項を書く。
```

注意:

- ベースブランチは `main`
- 複数コミットの場合はタイトルをブランチ全体の目的に合わせる(先頭コミットの丸写しにしない)
- ラベルは PR タイトルの type と一致する 1 つのみ付与する(複数 type にまたがる場合はブランチ全体で最も主要な変更の type を選ぶ)
- Assignees には常に `YTommy109`(自分)を割り当てる
