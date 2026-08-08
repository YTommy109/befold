---
id: TASK-355
title: リリース成果物の配布経路を GitHub Releases から Cloudflare R2 へ移す
status: To Do
assignee: []
created_date: '2026-08-08 01:21'
labels: []
dependencies: []
priority: medium
ordinal: 614000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
直販（Mac App Store を使わない配布）を前提に、リリース成果物と Sparkle の appcast.xml の配信先を GitHub Releases から Cloudflare R2 + Workers へ移す。

背景・狙い:
- 現状の最大のボトルネックは認知とダウンロード数であり、まず「ダウンロード数を正確に測れる」状態にしたい。GitHub Releases では取得できる情報が限られる。
- 将来的にライセンスキー配布や有料版の配信制御を Workers + D1/KV で行う余地を残す。本タスクでは課金・ライセンス層は扱わない（配信経路の移設のみ）。
- Mac App Store は App Sandbox 必須・Sparkle 不可・CLI 配布不可のため採用しない方針。直販なら Sparkle と befold-cli をそのまま維持できる。

前提（未検証。着手時に確認すること）:
- ビルド・署名・公証は macOS が必須のため CI は GitHub Actions の macos runner のままとする。Cloudflare Workers Builds は Worker 用の CI であり xcodebuild は動かない。
- 変更範囲はリリースワークフローの「アップロード先」であり、ビルド・署名・公証の手順自体は変えない想定。
- Sparkle は appcast.xml を HTTPS で取得し EdDSA 署名を検証してから成果物を取得するため、配信元が R2 でも動作するはず。

制約:
- 署名鍵（Sparkle の EdDSA 秘密鍵、Developer ID 証明書）は Cloudflare 側に置かない。署名は GitHub Actions 上で行い、R2 には署名済み成果物のみを配置する。
- 移行期間中は既存ユーザの自動アップデートを壊さないこと（既存の appcast URL からの導線を維持する）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リリースワークフローが署名・公証済みの成果物と appcast.xml を Cloudflare R2 へアップロードする
- [ ] #2 新しい appcast URL を参照する dev ビルドで、旧バージョンから新バージョンへの Sparkle 自動アップデートが実機で成功する
- [ ] #3 既存の appcast URL を使っている配布済みバージョンの自動アップデートが壊れない（リダイレクトまたは両方への配置で担保する）
- [ ] #4 ダウンロード数を確認できる手段が用意されている
- [ ] #5 Sparkle の EdDSA 秘密鍵と Developer ID 証明書が Cloudflare 側に配置されていない
- [ ] #6 配布手順の変更が docs 配下のリリース手順に反映されている
<!-- AC:END -->
