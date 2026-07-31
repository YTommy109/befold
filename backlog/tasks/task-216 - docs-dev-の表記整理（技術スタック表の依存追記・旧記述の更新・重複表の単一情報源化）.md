---
id: TASK-216
title: docs/dev の表記整理（技術スタック表の依存追記・旧記述の更新・重複表の単一情報源化）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 03:13'
updated_date: '2026-07-31 08:29'
labels: []
dependencies: []
priority: low
ordinal: 296000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 9a555c9 のコードレビュー指摘（CONFIRMED）のうち、実害は小さいが一貫性を損なうクリーンアップ 3 件。

1. docs/dev/native-app-design.md:196 — 自動アップデート節は Sparkle 2 前提に書き換えられたのに、技術スタック表に Sparkle 2 が載っていない（DOMPurify も同様）。依存棚卸しやセキュリティレビューでこの表を情報源にすると実際にリンクされている外部フレームワークを見落とす。
2. docs/dev/native-app-design.md:215 — テスト方針節の「Updates/ 配下の各コンポーネント…を befoldTests/ で網羅する」が自前アップデータ時代の記述のまま。実態は Updates/ は UpdateChannel.swift 1 ファイル、テストも UpdateChannelTests.swift のみ。
3. docs/dev/viewer-rendering-dataflow.md:66 — 「viewer.html の JS 分岐」の type→ビルダー表が、14-31 行の FileType 表の「JS 描画関数」列とほぼ同一のマッピングを二重記載している。リネームや種別追加時に片方だけ更新されると矛盾するため、片方から描画関数列を落として相互参照にし単一情報源化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 native-app-design.md の技術スタック表に Sparkle 2 と DOMPurify が記載されている
- [x] #2 native-app-design.md のテスト方針節が Updates/ の現状（UpdateChannel のみ）と一致している
- [x] #3 viewer-rendering-dataflow.md の type→描画関数マッピングが単一情報源になっている（もう一方は相互参照）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Package.swift / project.yml / BefoldKit/Resources を読み、実際にリンク・同梱されている依存を確認して native-app-design.md の技術スタック表に追記する
2. befold/Updates/ と befoldTests/ の実態を確認し、テスト方針節の記述を現状（UpdateChannel のみ）に合わせる
3. viewer-rendering-dataflow.md の FileType 表から「JS 描画関数」列を落とし、JS 分岐節の表を単一情報源として相互参照する（ディレクティブコメントで依存を宣言）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
項目3の単一情報源の選択: 「viewer.html の JS 分岐」表を情報源として残し、FileType 表から「JS 描画関数」列を落とした。理由は (a) FileType 表の見出しが「種別・レンダラ・同梱アセット対応」であり JS 関数名は見出しの責務外、(b) JS 分岐表はビルダーと viewer.js ヘルパーを対で持ち情報量が多い、(c) 先に来る FileType 表には jsValue 列が残るので、読み手は jsValue をキーに後段の表へ辿れる。FileType 表直下に相互参照リンクを追加し、JS 分岐節の見出し直下に <!-- derived-from #filetype--種別レンダラ同梱アセット対応 --> を置いた（表のキーが FileType.jsValue 由来であるため）。
技術スタック表には AC 記載の Sparkle 2 / DOMPurify に加え、Package.swift の swift-argument-parser と Resources 同梱の github-markdown.css / github.css / github-dark.css も追記した（表を依存棚卸しの情報源とする目的に合致するため）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/dev の 3 件の表記ずれを実装に合わせて修正した。技術スタック表に Sparkle 2 / DOMPurify / swift-argument-parser / github-markdown-css を追記（Package.swift・project.yml・BefoldKit/Resources で実在を確認）、テスト方針節の Updates/ 記述を UpdateChannel.swift 1 ファイルの現状に更新（befold/Updates/ と befoldTests/UpdateChannelTests.swift で確認）、viewer-rendering-dataflow.md の type→描画関数マッピングを「viewer.html の JS 分岐」表に一本化し FileType 表からは相互参照にした（関数名は viewer-main.js の grep で実在確認）。実装コードは変更していない。
<!-- SECTION:FINAL_SUMMARY:END -->
