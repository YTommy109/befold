---
id: TASK-365
title: appcast の配信一致検証を R2 基準に差し替える
status: To Do
assignee: []
created_date: '2026-08-08 08:55'
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
- [ ] #1 リリース後の疎通確認手順が、Worker の /appcast.xml 応答と R2 上の appcast.xml を比較する形になっている
- [ ] #2 手順が docs 配下（site/README.md もしくは開発ガイド）に記載されている
<!-- AC:END -->
