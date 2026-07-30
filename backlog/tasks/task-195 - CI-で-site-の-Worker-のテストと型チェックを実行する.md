---
id: TASK-195
title: CI で site/ の Worker のテストと型チェックを実行する
status: To Do
assignee: []
created_date: '2026-07-30 00:06'
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
