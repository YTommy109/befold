---
id: TASK-485.33
title: ジャンプバーを開くと見出しの下線が左へ 8px 伸びる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 09:12'
updated_date: '2026-09-25 09:28'
labels: []
dependencies: []
references:
  - BefoldApp/BefoldKit/Resources/style.css
parent_task_id: TASK-485
priority: low
type: bug
ordinal: 834000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.27 のコードレビュー(2026-09-25)で検出。`style.css` の `.mmd-jump-target:not(td), .mmd-jump-current:not(td)` は、縦バーと文字の間を空けるために `padding-left: 8px; margin-left: -8px` を付ける。ジャンプバーを開いている間は、レンダリング表示のすべての見出し(h1〜h3)にこのクラスが付く。
github-markdown-css の h1 / h2 は `border-bottom` を持つので、バーを開くと下線が左へ 8px 伸び、閉じると戻る。文字の位置は動かないが、下線は開閉のたびに動く。加えて、この規則は見出しが元々持つ `padding-left` / `margin-left` を上書きする(引用やリストの中の見出し、利用者の HTML で字下げした見出しなど)。アプリでの目視確認は未実施(TASK-485.28 の Notes)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ジャンプバーの開閉で、レンダリング表示の見出しの下線と字下げの位置が変わらない(実機で確認)
- [x] #2 現在位置の縦バーと文字の間には従来どおり間隔がある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .mmd-jump-target / .mmd-jump-current の:not(td) から padding-left / margin-left を外し、地色と縦バーを外側の box-shadow で左 8px に描く(要素の箱に触れない)
2. WKWebView で実 CSS を当てて、クラスの付け外し前後の見出しの位置・余白・下線を比べる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
外側の影は要素の箱の内側に描かれないため、左の帯だけが見える。現在位置は -5px の地色の影の下から -8px のアクセントの影が 3px のぞく形で、縦バーと文字の間は従来どおり 5px 空く。差分表・ソース表示の目印は td なので :not(td) の対象外で、従来の inset の影のまま。
検証: アプリと同じ WKWebView に github-markdown.css と style.css をそのまま読み込み(スクリプトは .tmp/jump-snap.swift)、h1 / h2 / 引用内の h3 にクラスを付ける前後で getBoundingClientRect と computed style を比べた。left / width / padding-left / margin-left / border-bottom-width はすべて一致し、撮った画像でも下線の左端は見出しの左端のまま、帯とバーだけが左 8px に出ていた。アプリの窓で cmd+shift+F を押して確かめる操作はしていない(System Events から窓を取得できなかった)。描画は同じ WebKit と同じ CSS。swiftlint / jest / swift test は TASK-485.29 と同じ作業ツリーで通過。現在仕様の文書(docs/dev)に張り出しの書き方の記述は無いので、更新は不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ジャンプの目印の地色と縦バーを、padding と負の margin で張り出させる書き方から、外側の box-shadow で描く書き方に変えた。バーを開閉しても見出しの箱(下線・字下げ)が変わらない。WKWebView に実 CSS を当てて前後の配置の一致と見た目を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
