---
id: TASK-333
title: ブックマークの ⌘D→⌘B 変更が stable にゲートなしで出てしまう問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:48'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 509300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MainMenuBuilder.swift:191 でブックマークのキー equivalent を無条件に ⌘D から ⌘B へ変更している一方、その変更を正当化する ⌘D の差分メニュー項目は addDiffItems 内の FeatureGate.isSourceDiffEnabled ガードの中でしか追加されない。stable ビルドでは ⌘D が何にも割り当たらないまま、ブックマークだけが黙って ⌘B に移動する。さらにこの変更を含む commit は (gate) スコープなので /release-notes stable から除外され、告知もされない。アプリ内ヘルプ・Localizable.xcstrings:112 は依然 ⌘D と記載している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stable ビルドでブックマークのショートカットが従来どおり動く（⌘B へ移すならゲートに合わせて切り替わる）
- [ ] #2 アプリ内ヘルプ・Localizable.xcstrings の記載が実際のキー割り当てと一致する
- [ ] #3 stable に出る挙動変更がリリースノートに載る形になっている（commit スコープの扱いを含めて確認する）
<!-- AC:END -->
