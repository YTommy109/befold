---
id: TASK-538.5
title: 参照用に置いた site/temp の実データを削除する
status: To Do
assignee: []
created_date: '2026-08-22 13:13'
updated_date: '2026-08-22 13:17'
labels: []
dependencies:
  - TASK-538.2
parent_task_id: TASK-538
priority: high
ordinal: 787000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
記事の素材確認のため、実運用の医療費フォルダから CLAUDE.md / README.md をメインチェックアウトの `site/temp/` へ一時コピーしてある（2026-08-22）。**個人情報を含む実データが、git 管理対象のパスに untracked で置かれている状態。**

含まれるもの: 実在の氏名（姓 1・名 2）、医療機関名 2 件、住所、電話番号、メールアドレス、家庭の内情（明細が残っていない年がある等）。

## いつ消せるか

**TASK-538.2（公開版 CLAUDE.md / README.md の書き起こし）が完了した時点。** site/temp をコミットしたくないため、これを最短経路にしてある。TASK-538.3（架空データでの一巡・動作確認）は削除の条件に**含めない**——後回しにし、そこで判明した手順の食い違いは公開版の文書を直す形で吸収する。

元ファイルは iCloud Drive 側（`~/Library/Mobile Documents/com~apple~CloudDocs/医療費/`）に残るので、site/temp は消してよいコピーである。後から参照が要れば元を見ればよい（ただし worktree 外なので、そのときも同じ制約がかかる）。

## 消すまでの間の安全策

untracked のまま `git add -A` を打つと入ってしまう。**先に .gitignore へ `site/temp/` を足しておくこと**（現状 .gitignore に temp の記述は無い。実測: `grep -n temp .gitignore site/.gitignore` が 0 件）。site/temp を残したままコミットする回が 1 回でもあるなら、これは必須。

## 作業場所の注意

site/temp があるのはメインチェックアウト（`/Users/tokutomi/develop/degino/befold/site/temp`）で、worktree 側には無い。worktree 内から作業するエージェントはこのパスに触れない規約なので、削除はユーザーが行うか、メインチェックアウトで作業しているセッションが行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .gitignore に site/temp/ が追加され、誤ってコミットされない状態になっている
- [ ] #2 TASK-538.2 の完了後、site/temp/ が削除されている
- [ ] #3 リポジトリ全体を検索して、実在の氏名・医療機関名・住所・電話番号が残っていないことを確認してある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 順序を変更した（2026-08-22 ユーザー指示）

当初は TASK-538.2 と TASK-538.3 の両方の完了を削除条件にしていたが、**site/temp を一切コミットしたくない**ため、TASK-538.2（公開版 CLAUDE.md / README.md の書き起こし）の完了だけを条件に変更した。TASK-538.3（架空データでの一巡・動作確認）は後回しにし、そこで判明した食い違いは公開版の文書を直す形で吸収する。

したがって順序は次のとおり。

1. TASK-538.2 で公開版を書き起こす（**site/temp を参照するのはここが最後**）
2. site/temp を削除する（このタスク）
3. コミットする
4. 以降、TASK-538.1 / 538.3 / 538.4 を進める。538.3 で手順の食い違いが出たら公開版の文書を直す
<!-- SECTION:NOTES:END -->
