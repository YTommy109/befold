---
id: TASK-659
title: パネル窓の frame autosave 名の登録失敗を無視しており、位置が黙って保存されなくなる（TASK-656 のレビュー指摘）
status: To Do
assignee: []
created_date: '2026-09-28 06:30'
labels:
  - bug
dependencies:
  - TASK-657
priority: low
type: bug
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-656 の実装後レビュー（/code-review high）の指摘。

`HostedPanelWindowController` の init が `window.setFrameAutosaveName(name)` の戻り値（Bool）を捨てている。同じ保存名を使う窓が既に生きていると AppKit は登録を拒否し、その窓の移動・リサイズは保存されない。失敗しても何も伝わらない。

テストでは既に起きている。`reopenedFrame` は 1 つ目の窓が生きたまま同名で 2 つ目を作るため、2 つ目の登録は失敗している。復元は登録より前に済むのでアサートは通るが、2 つ目の窓の移動は保存されない。

本番では現状パネルごとに 1 インスタンスなので起きていない。起きるのは、コントローラーを作り直す変更や、設定のビルダーを写して保存名を共有した新パネル（TASK-657 の指摘 4）が入ったとき。TASK-657 で方針の引き方を 1 箇所へ畳むと共有の経路が変わるため、そちらを先に片付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 保存名の登録に失敗したことが、テストまたは開発時の検査で分かる
- [ ] #2 同じ保存名を 2 つのパネルが持つ構成を作れない、または作ったら落ちるテストがある
<!-- AC:END -->
