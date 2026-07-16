# /pr — push & プルリクエスト作成

現在のブランチを push し、`gh pr create` でプルリクエストを作成してください。

手順:
1. `git log origin/main..HEAD --oneline` で PR に含まれるコミットを確認する
2. 未 push のコミットがあれば `git push -u origin <ブランチ名>` する
3. PR タイトルの Conventional Commits type（`feat` / `fix` / `chore` / `refactor` / `docs` / `test` / `ci` / `perf`）に対応するラベルを 1 つ選ぶ
4. 対応する backlog タスクの `References` に GitHub Issue の URL が記載されていれば、その Issue 番号を控える（`backlog task view <ID> --plain` で確認）
5. `gh pr create --label <type> --assignee YTommy109` で PR を作成し、URL を報告する

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
