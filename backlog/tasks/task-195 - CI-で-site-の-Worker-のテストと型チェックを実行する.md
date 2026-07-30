---
id: TASK-195
title: CI で site/ の Worker のテストと型チェックを実行する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-30 00:06'
updated_date: '2026-07-30 00:22'
labels: []
dependencies: []
priority: high
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/ の Cloudflare Worker には vitest 39 件と tsc --noEmit があるが、GitHub Actions のワークフロー（ci.yml / release.yml / verify-dmg.yml）はいずれも site/ を参照しておらず、CI で一度も実行されていない。品質担保がローカル実行だけに依存しており、site/ の変更を含む PR がテスト未実行のままマージされうる。

Swift 側と同様に CI で自動実行し、site/ に変更がある PR で必ず回るようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 site/ に変更がある PR で vitest が CI 上で実行され、失敗時にジョブが赤くなる
- [x] #2 site/ に変更がある PR で tsc --noEmit が CI 上で実行される
- [x] #3 site/ に変更が無い PR では該当ジョブがスキップされ、CI 時間を無駄に消費しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .github/workflows/site.yml を新設する。ci.yml に job を足す案は採らない。ci.yml の on.paths が BefoldApp/** に絞られているため job を足しても site/ 変更では起動せず、paths に site/** を足すと site だけの変更で高コストな macOS ランナー（swift build / test）まで走ってしまう。独立ワークフロー + paths フィルタなら AC#3（site/ 変更が無いときスキップ）がフィルタ自体で満たされる。既に verify-dmg.yml が独立ワークフローの前例。
2. ubuntu-latest・Node 24・npm キャッシュ（cache-dependency-path: site/package-lock.json）で構成し、既存の js-test ジョブと同じ流儀に揃える。
3. ステップ順は npm ci → typecheck → test。型エラーは安価に落ちるので先に回す。
4. concurrency で連続 push の古い実行を打ち切る（ci.yml と同じ方針）。
5. 検証は PR #321 の実 CI 実行で行う。site/ を導入する当ブランチに載せるので、同じ PR のチェックとして実際に走る。意図的に落として赤くなることも確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
.github/workflows/site.yml を新設した（ci.yml への job 追加は採らず独立ワークフロー。理由は Implementation Plan に記載）。ubuntu-latest / Node 24 / npm キャッシュで npm ci → typecheck → test の順に実行する。

検証（PR #321 の実 CI 実行 run: Site CI / test ジョブ = SUCCESS）:
#1 #2 CI ログで npm ci（83 packages）→ tsc --noEmit → vitest 5 ファイル 39 件 passed が実行されたことを確認。
失敗時に赤くなることは、GitHub Actions がステップの非ゼロ終了で落とす仕様に依るため、ローカルで終了コードを直接確認した: 失敗テストを 1 件足した状態の npm test = 1、型エラーを入れた状態の npm run typecheck = 2。いずれも確認後にファイルを削除し、git status がクリーンなことと 39 件通過に戻ることを確認済み。
.dev.vars は gitignore 対象で CI に存在しないため、退避した状態でもテストが 39 件通ることを事前に確認した（認証情報は vitest.config.ts の miniflare bindings で固定されている）。

AC#3 は未チェック。この PR 内では原理的に検証できない。pull_request イベントの paths フィルタは PR 全体の差分（base...head）に対して評価されるため、当 PR は site/ を含む以上どのコミットでも Site CI が起動する。また main には site/ も site.yml も存在せず、ワークフローは head ref に存在しないと実行されないため、比較対象を作れない。

AC#3 の着手条件: PR #321 が main にマージされ、その後 site/ を含まない PR または push が発生した時点で、Site CI が起動していないことを gh run list で確認すればよい。

AC#3 を実測で確定（2026-07-30）。PR #321 マージ後、backlog/ の 2 ファイルのみを変更する PR #322（branch docs/post-merge-verification）を作成して検証した。

結果: gh run list --branch docs/post-merge-verification が空（起動した run なし）、gh pr checks 322 は 'no checks reported'。Site CI（paths: site/** と .github/workflows/site.yml）も CI（paths: BefoldApp/** と .github/workflows/ci.yml）も起動せず、両ワークフローの paths フィルタが意図どおり機能していることを確認した。

参考: PR #321 での Site CI 実行時間は 18 秒で、CI 全体（build-and-test 3m7s）への影響は小さい。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.github/workflows/site.yml を新設し、site/ の vitest 39 件と tsc --noEmit を CI で実行するようにした。ci.yml への job 追加ではなく独立ワークフローにしたのは、ci.yml の paths が BefoldApp/** に絞られており job を足しても site/ 変更では起動せず、paths に site/** を足すと site だけの変更で高コストな macOS ランナーまで走るため。PR #321 の実 CI 実行（Site CI = SUCCESS、18 秒）で npm ci → typecheck → 39 件 passed を確認し、失敗時の非ゼロ終了もローカルで確認（npm test = 1、typecheck = 2）。site/ を含まない PR #322 でワークフローが 1 件も起動しないことも実測済み。
<!-- SECTION:FINAL_SUMMARY:END -->
