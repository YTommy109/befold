---
id: TASK-72.4
title: QuickLook Extension のターゲット・Info.plist・entitlements を設定する
status: To Do
assignee: []
created_date: '2026-07-19 06:44'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
project.yml に app-extension タイプの QuickLook Extension ターゲットを追加し、befold アプリターゲットへの embed 依存を設定する。Info.plist に QLSupportedContentTypes(対象UTI一覧)と NSExtension 辞書を設定し、entitlements にサンドボックス有効・ネットワークなしを設定する。.svg は public.xml 側に紐づけ、画像系UTIとの重複を避ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 xcodegen generate で QuickLook Extension ターゲットが生成される
- [ ] #2 Info.plist の QLSupportedContentTypes が対象拡張子のUTIのみを含み、PDF/画像のUTIを含まない
- [ ] #3 entitlements でサンドボックスが有効になっており、不要な権限(ネットワーク等)が付与されていない
<!-- AC:END -->
