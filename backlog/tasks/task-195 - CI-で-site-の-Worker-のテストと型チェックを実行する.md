---
id: TASK-195
title: CI で site/ の Worker のテストと型チェックを実行する
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-07-30 00:06'
updated_date: '2026-07-30 00:10'
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
- [ ] #1 site/ に変更がある PR で vitest が CI 上で実行され、失敗時にジョブが赤くなる
- [ ] #2 site/ に変更がある PR で tsc --noEmit が CI 上で実行される
- [ ] #3 site/ に変更が無い PR では該当ジョブがスキップされ、CI 時間を無駄に消費しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .github/workflows/site.yml を新設する。ci.yml に job を足す案は採らない。ci.yml の on.paths が BefoldApp/** に絞られているため job を足しても site/ 変更では起動せず、paths に site/** を足すと site だけの変更で高コストな macOS ランナー（swift build / test）まで走ってしまう。独立ワークフロー + paths フィルタなら AC#3（site/ 変更が無いときスキップ）がフィルタ自体で満たされる。既に verify-dmg.yml が独立ワークフローの前例。
2. ubuntu-latest・Node 24・npm キャッシュ（cache-dependency-path: site/package-lock.json）で構成し、既存の js-test ジョブと同じ流儀に揃える。
3. ステップ順は npm ci → typecheck → test。型エラーは安価に落ちるので先に回す。
4. concurrency で連続 push の古い実行を打ち切る（ci.yml と同じ方針）。
5. 検証は PR #321 の実 CI 実行で行う。site/ を導入する当ブランチに載せるので、同じ PR のチェックとして実際に走る。意図的に落として赤くなることも確認する。
<!-- SECTION:PLAN:END -->
