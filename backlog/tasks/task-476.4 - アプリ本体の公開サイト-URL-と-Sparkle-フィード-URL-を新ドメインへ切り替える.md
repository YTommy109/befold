---
id: TASK-476.4
title: アプリ本体の公開サイト URL と Sparkle フィード URL を新ドメインへ切り替える
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 06:17'
labels:
  - site
dependencies:
  - TASK-476.1
  - TASK-476.2
parent_task_id: TASK-476
priority: high
type: chore
ordinal: 101400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
アプリからサイトを指す URL を新ドメインへ更新する。ADR 0007 の決定 3 で「切り替える」と確定済み。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

対象（実測）:
- `BefoldApp/BefoldKit/AppLinks.swift:10,15` の homepage（?ref=about）/ help（?ref=help）
- `BefoldApp/befold/Updates/UpdateChannel.swift:21,23` の appcast / appcast-develop
- 対応するテスト `AppLinksTests.swift:12,24` / `UpdateChannelTests.swift:30,36`（いずれもホストを固定値で期待している）

注意点:
- Sparkle のフィード URL 変更が効くのは、この変更を含むバージョンをインストールしたユーザーのみ。旧ホストへのアクセスは永続するため、**旧ホストの appcast 配信を止める前提の実装をしない**。
- 切り替える理由は可搬性（独自ドメインは DNS で向き先を差し替えられるが `*.workers.dev` は Cloudflare アカウントに固定される）。「旧ホストを止められるようになるから」ではない — ADR 0007 の決定 1 で旧ホストは恒久維持と決めている。
- `?ref=` の値は既存の集計軸と互換を保つ（値を変えると過去データと接続できない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppLinks の homepage / help が befold.degino.com を指し、?ref= の値は従来のまま
- [ ] #2 appcast / appcast-develop の URL が befold.degino.com へ更新され、UpdateChannelTests が新 URL を検証している
- [ ] #3 更新チェックが新 URL で実際に動作することを dev ビルドで確認し、結果を Implementation Notes に記録している
- [ ] #4 旧ホストの appcast も同時に 200 を返し続けることを確認している（切り替えが旧経路を壊していない）
<!-- AC:END -->
