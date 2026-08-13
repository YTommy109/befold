---
id: TASK-476.4
title: アプリ本体の公開サイト URL と Sparkle フィード URL を新ドメインへ切り替える
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
labels:
  - site
dependencies:
  - TASK-476.1
  - TASK-476.2
parent_task_id: TASK-476
priority: high
ordinal: 101400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
アプリからサイトを指す URL を新ドメインへ更新する。

対象（実測）:
- BefoldApp/BefoldKit/AppLinks.swift の homepage（?ref=about）/ help（?ref=help）
- BefoldApp/befold/Updates/UpdateChannel.swift:21,23 の appcast / appcast-develop
- 対応するテスト AppLinksTests / UpdateChannelTests

注意点:
- Sparkle のフィード URL 変更が効くのは、この変更を含むバージョンをインストールしたユーザーのみ。旧ホストへのアクセスは永続するため、旧ホストの appcast 配信を止める前提の実装をしない。
- 切り替え可否そのものは TASK-476.1 の ADR で決める。ADR が「切り替えない」と決めた場合、本タスクはアプリ内リンク（homepage / help）のみのスコープになる。
- ?ref= の値は既存の集計軸と互換を保つ（値を変えると過去データと接続できない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppLinks の homepage / help が befold.degino.com を指し、?ref= の値は従来のまま
- [ ] #2 ADR の決定に従い appcast URL が更新され、UpdateChannelTests が新 URL を検証している
- [ ] #3 更新チェックが新 URL で実際に動作することを dev ビルドで確認し、結果を Implementation Notes に記録している
<!-- AC:END -->
