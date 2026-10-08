---
id: TASK-671
title: release.yml の公証申請ステップが notarytool の失敗（HTTP 403 等）を握りつぶす
status: Done
assignee:
  - '@claude'
created_date: '2026-10-06 01:23'
updated_date: '2026-10-06 01:36'
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
- [x] #1 公証申請ステップで notarytool が非 0 で終わったとき、そのステップ自体が失敗し、ステープルのステップへ進まない
- [x] #2 status: Invalid のときの公証ログ出力（既存の挙動）は維持される
- [x] #3 .github/workflows 内に、pipefail 無しで `| tee` を使うステップが他に無いことを確認している（実測: 2026-10-06 時点では release.yml:152 のみ）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 公証申請ステップで、tee へのパイプ直後に ${PIPESTATUS[0]} を rc へ保存する（pipefail は使わない: Invalid 時に非 0 で終わっても既存のログ出力ブロックへ届くようにするため）
2. Invalid ブロックの後に rc が非 0 なら ::error:: を出して exit する
3. .github/workflows 内の '| tee' を grep し、他に pipefail 無しのものが無いことを確認する
4. actionlint 等が使えれば構文を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証（2026-10-06）: 偽の xcrun/ditto で実ステップ本文を bash -e 実行。403（Invalid なし・exit 1）は修正前 EXIT=0 → 修正後 EXIT=1。Invalid（exit 1）は公証ログ出力 + 「Notarization failed with status Invalid」で EXIT=1（既存挙動を維持）。Accepted（exit 0）は EXIT=0。AC3: grep "| tee" .github/workflows/*.yml は release.yml:152 のみで、そこを直した。actionlint（PostToolUse フック）は指摘なし。判断: pipefail は使わない。Invalid で notarytool が非 0 終了すると、ログ出力ブロックへ届く前にステップが落ちるため、${PIPESTATUS[0]} を保存して Invalid ブロックの後で判定した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
release.yml の公証申請ステップで notarytool の終了コードを ${PIPESTATUS[0]} で保存し、Invalid ブロックの後に非 0 なら失敗させた。偽の notarytool を使った再現で、403 相当が修正前 EXIT=0 → 修正後 EXIT=1、Invalid / Accepted の挙動は不変であることを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
