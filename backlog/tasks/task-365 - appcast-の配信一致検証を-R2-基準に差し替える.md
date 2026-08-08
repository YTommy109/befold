---
id: TASK-365
title: appcast の配信一致検証を R2 基準に差し替える
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 08:55'
updated_date: '2026-08-08 09:51'
labels: []
dependencies: []
priority: low
ordinal: 626000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-355 で appcast の正が GitHub Releases から Cloudflare R2 へ移ったため、TASK-182 の Notes に記録された検証手順（Worker 応答と GitHub 直の appcast の sha256 先頭 16 桁の一致）が意味を持たなくなった。比較対象を R2 オブジェクトへ差し替える。

検証したいのは「Worker が appcast を改変せずに返していること」であり、比較先が配信の正でなければその保証にならない。現状の手順のまま回すと、R2 と GitHub が乖離したときに GitHub 側と一致していることを確認して安心してしまう。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リリース後の疎通確認手順が、Worker の /appcast.xml 応答と R2 上の appcast.xml を比較する形になっている
- [x] #2 手順が docs 配下（site/README.md もしくは開発ガイド）に記載されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現行の検証手順（TASK-182 Notes: Worker 応答と GitHub 直 appcast の sha256 先頭16桁比較）と R2 移行後の配信経路を確認する
2. docs/dev/development.md の「配布経路」節に「リリース後の疎通確認（appcast の配信一致）」を追加し、比較先を R2 オブジェクト（befold-dist/appcast.xml / appcast-develop.xml）にする
3. GitHub 直 appcast を比較先にしてはならない理由を明記する
4. site/README.md の staging 節から新節へリンクする
5. 実際にコマンドを本番へ実行して一致を実測し、markdownlint を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

docs/dev/development.md の「配布経路（成果物の置き場所）」節の直後に「リリース後の疎通確認（appcast の配信一致）」を追加した。比較は Worker 応答と R2 オブジェクトの sha256 完全一致（先頭16桁ではなく全体）。stable / develop 両チャンネルのコマンドを記載。GitHub 直の appcast を比較先にしてはならない理由（v1.10.0 以前向けに残しているだけで配信の正ではない）と、wrangler 認証の注意、本番へ実行してよい理由（update_check の記録は走るが README の方針で許容される確認）を併記した。site/README.md:191 の staging 節から新節へリンクを張った。

## 実測（2026-08-08、本番）

    npx wrangler r2 object get befold-dist/appcast.xml --remote --pipe | shasum -a 256
    curl -fsS https://befold.tommy109.workers.dev/appcast.xml | shasum -a 256
    → 両方 b18c66b69d890b64eeb72b656ae450efe525bb7a11b06e7d4a44d6607f99da05（一致）

    befold-dist/appcast-develop.xml / /appcast-develop.xml
    → 両方 a57bded1275793544d5d5569f6510105e32c34bef930c18ccaaa0382e6b65d36（一致）

markdownlint-cli2: 65 files, 0 issues。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
リリース後の appcast 疎通確認を、GitHub 直 appcast との比較から配信の正である R2 オブジェクトとの比較へ差し替え、docs/dev/development.md に手順として明記した（従来は TASK-182 の Notes にしか無く、R2 と GitHub が乖離しても一致確認が通ってしまう状態だった）。stable / develop 両チャンネルを本番で実測し sha256 が完全一致することを確認、markdownlint も 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
