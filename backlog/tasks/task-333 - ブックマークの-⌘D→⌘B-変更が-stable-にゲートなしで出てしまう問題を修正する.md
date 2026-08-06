---
id: TASK-333
title: ブックマークの ⌘D→⌘B 変更が stable にゲートなしで出てしまう問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:48'
updated_date: '2026-08-06 03:19'
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
- [x] #1 stable ビルドでブックマークのショートカットが従来どおり動く（⌘B へ移すならゲートに合わせて切り替わる）
- [x] #2 アプリ内ヘルプ・Localizable.xcstrings の記載が実際のキー割り当てと一致する
- [x] #3 stable に出る挙動変更がリリースノートに載る形になっている（commit スコープの扱いを含めて確認する）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BookmarkShortcut（新規: befold/App/BookmarkShortcut.swift）にキー等価の決定を一元化し、FeatureGate.isSourceDiffEnabled が false のビルドでは従来どおり ⌘D を維持する。MainMenuBuilder とヘルプ（FeatureOverviewView）が同じ値を読むため、片方だけ古くなる形にならない。ヘルプ文言（featureOverview.bookmarks.detail）は ⌘D 直書きをやめて %@ 受けにし、実際の割り当てを差し込む。

担保:
- 純粋判定 BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:) の両分岐をテストで固定（ゲート越しの検証は動作中ビルド側しか通らず空振りするため）。無条件 "b" に戻すと 2 件落ちることを実測。
- View メニューに ⌘D を持つ項目が常にちょうど 1 つであることを検証。
- 文言に ⌘ を直書きすると LocalizationTests の新テストが落ちる。
- FeatureGate の doc コメント列挙に BookmarkShortcut を追加（FeatureGateEnumerationTests が突き合わせるため、追加漏れは落ちる）。

AC#3: ⌘B へ移した commit 75c8cb9b を含むタグは v1.12.1-dev.1 のみで stable 未出荷（git tag --contains で実測）。本修正後 stable の挙動は従来（⌘D=ブックマーク）のままなので、リリースノートに載せるべき stable 向けの挙動変更は発生しない。よって (gate) スコープのままでよい。

swift test 1068 件通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマークのキー等価を BookmarkShortcut に一元化し、差分表示（⌘D）を露出しないビルドでは ⌘D のままにした。ヘルプ文言もキー表記を引数化して実際の割り当てと同期。両分岐の純粋判定テストで担保し、swift test 1068 件通過。
<!-- SECTION:FINAL_SUMMARY:END -->
