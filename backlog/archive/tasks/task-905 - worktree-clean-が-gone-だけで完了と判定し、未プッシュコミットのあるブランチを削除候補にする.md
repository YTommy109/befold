---
id: TASK-905
title: worktree の完了判定を 1 か所にまとめ、worktree-clean が [gone] だけで完了と判定する問題を塞ぐ
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:30:00Z'
updated_date: '2026-11-07T02:39:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ブランチの完了判定が `scripts/worktree-reset.sh` と `scripts/worktree-clean.sh` に別々にあり、片方の修正がもう片方に届かない。

`worktree-reset.sh` は #687 で `[gone]` を判定から外し（squash merge 後に同じブランチへ積んだ未プッシュコミットを失う実例があった。TASK-528）、#713 でマージ済み PR の head との照合を足した（後続の PR が同じファイルを変更すると未マージと誤判定していた）。一方 `worktree-clean.sh` は今も「main の祖先である」か「上流が `[gone]` である」かで判定する。未コミットの変更がある worktree は除外するが、未プッシュのコミットは見ていないため、未プッシュコミットのあるブランチも削除候補に入る。

`worktree-clean.sh` だけを直すと、また片方だけが古くなる。CLAUDE.md の「同型のバグが 2 回目に出たら、個別修正をやめて構造で塞ぐ」に従い、判定を共有する形で塞ぐ。

補足:
- 完了判定の self-test は `worktree-reset.sh --self-test` にあり、CI（`ci.yml`）はこれを実行する。CI の実行条件に入っている worktree 系スクリプトは `scripts/worktree-reset.sh` だけ。
- `scripts/worktree-status.sh` は完了判定を持たないので対象外。
- 切り直す前のブランチにある版のスクリプトが動く問題は、共有化しても解消しない（`.claude/commands/worktree-reset.md` に記載）。

未確認: `worktree-clean.sh` の判定より後の確認と削除の処理（89 行目以降）は読んでいない。実際に作業が失われる経路になるかは、着手時に確かめる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ブランチの完了判定が 1 か所にあり、`worktree-reset` と `worktree-clean` の両方がそれを使う
- [x] #2 上流が `[gone]` で、マージ済み PR に含まれない未プッシュコミットがあるブランチは `worktree-clean` の削除候補に入らない
- [x] #3 squash merge 済みで未プッシュコミットが無いブランチは、後続の PR が同じファイルを変更していても `worktree-clean` の削除候補に入る
- [x] #4 上記の判定を検証するテストがあり、判定の置き場所を変更すると CI で実行される
- [x] #5 `worktree-reset` と `worktree-clean` の手順書の完了判定の説明が実装と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 完了判定を scripts/lib/branch-completion.sh へ移し、worktree-reset.sh と worktree-clean.sh が source する。判定は祖先 → マージ済み PR の head との一致 → 変更ファイルの内容一致の順。[gone] は判定に使わない
2. worktree-clean の基準をローカル main から origin/main 優先へ揃える
3. 内容の照合をリポジトリのルート基準・リテラルの pathspec で行う（実測: サブディレクトリから worktree-reset を実行すると未プッシュコミットを squashed と誤判定して削除した）
4. gh は stdin を /dev/null にする（worktree-clean の while read ループの入力を読ませない）
5. worktree-clean で [gone] なのに候補外のブランチはスキップ理由を表示する（表示のみで判定には使わない）
6. worktree-clean.sh に --self-test を足す。前提が [gone] であることを確認し、--force 後に未プッシュのブランチが残ることまで見る。worktree-reset の self-test にサブディレクトリのケースを足す
7. ci.yml の on.paths 2 箇所と変更検出の正規表現に worktree-clean.sh と lib を足し、self-test を実行する
8. 手順書 2 つを実装に合わせる

/review-design: 項目 1・4・5・7 の指摘を上記 3〜6 に反映。他の項目は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手時の確認: worktree-clean.sh --force は候補に git worktree remove と git branch -D を実行するため、未プッシュコミットは実際に失われる（起票時の未確認事項が解消）。worktree-reset.sh にも別経路の消失を実測で確認した。サブディレクトリから実行すると git diff の pathspec が cwd 基準になって一致扱いになる。

方針: 判定を worktree-clean にだけ移植せず lib へ移した。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に従う。

単純化の検討: [gone] の分岐を消すだけなら worktree-clean の修正は小さいが、squash 済みブランチが候補に入らなくなり（完了条件 3）、判定を移植すると 2 か所に戻るため採らなかった。

検証: 判定を 6 種類壊して self-test が落ちることを実測（cwd 基準の pathspec / PR head 照合なし（2 スクリプト）/ --no-fetch でも gh を使う / [gone] を完了扱い / スキップ理由の表示なし）。修正前の worktree-reset をサブディレクトリから実行するとブランチが削除されることも再現した。CI run 42330306184 の type-group-size ジョブで両 self-test が success。ci.yml の検出正規表現は worktree-clean.sh と lib に一致、無関係な lib には不一致。bash 3.2 で実行。

動作の変更: worktree-clean の基準をローカル main から origin/main 優先へ変更。ローカルの main にしか入っていないブランチは候補から外れる（安全側）。

未実施: shellcheck（手元に無い）。Swift の変更なしのため Swift のテストと swiftlint は対象外。

native-app-design.md への反映は不要（開発用スクリプトのみで、アプリの構成に変化なし。docs/dev に worktree スクリプトへの言及なし）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブランチの完了判定を scripts/lib/branch-completion.sh へまとめ、worktree-reset と worktree-clean の両方から使うようにした。

塞いだ経路は 2 つ。worktree-clean --force が上流 [gone] だけで未プッシュコミットのあるブランチを削除する経路と、worktree-reset をサブディレクトリから実行すると未マージでも squashed と判定して削除する経路（着手時に実測で発見）。

両スクリプトの self-test を CI で実行する。判定を壊すと落ちることを 6 種類の変更で確認した。

残るリスク: 切り直す前のブランチにある古い版のスクリプトは引き続き動く（手順書に確認方法を記載）。
<!-- SECTION:FINAL_SUMMARY:END -->
