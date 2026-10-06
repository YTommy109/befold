---
id: TASK-671
title: release.yml の公証申請ステップが notarytool の失敗（HTTP 403 等）を握りつぶす
status: To Do
assignee: []
created_date: '2026-10-06 01:23'
labels:
  - chore
dependencies: []
references:
  - .github/workflows/release.yml
ordinal: 856000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v1.23.0 の Release（run 37395913838、2026-10-06）で、`notarytool submit` が「HTTP status code: 403. A required agreement is missing or has expired.」で拒否されたのに「.app を公証申請する」ステップは成功扱いになり、失敗は次のステープルのステップで「Record not found」を 3 回リトライした後（約 45 秒後）にようやく出た。原因は release.yml の公証申請ステップが `xcrun notarytool submit ... | tee` のパイプで、`bash -e` には pipefail が無く終了コードが tee のものになること。失敗の検知は `status: Invalid` の grep だけで、リクエスト自体の失敗（契約失効・認証エラー・ネットワーク）は素通りする。根本原因（Apple 側の契約失効）はこのタスクの対象外で、リポジトリ外の作業。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 公証申請ステップで notarytool が非 0 で終わったとき、そのステップ自体が失敗し、ステープルのステップへ進まない
- [ ] #2 status: Invalid のときの公証ログ出力（既存の挙動）は維持される
- [ ] #3 .github/workflows 内に、pipefail 無しで `| tee` を使うステップが他に無いことを確認している（実測: 2026-10-06 時点では release.yml:152 のみ）
<!-- AC:END -->
