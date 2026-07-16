---
id: TASK-18
title: /webview-smoke のデフォルト対象パスが誤っており引数省略時にタイムアウトする
status: To Do
assignee: []
created_date: '2026-07-16 04:07'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/webview-smoke.swift はデフォルトで BefoldApp/befold/Resources を対象にするが、実際の viewer.html / viewer.js は BefoldApp/BefoldKit/Resources にある。TASK-17 の手動確認時、引数なしで実行すると viewer.html が見つからず WKWebView のナビゲーションが完了せず 20 秒後に FAIL: timeout で失敗した。BefoldApp/BefoldKit/Resources を明示すれば正常に全項目 PASS する。デフォルト値をリソースの実際の格納場所に合わせるか、README/コメントの手順を更新する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 引数省略で swift scripts/webview-smoke.swift を実行した場合に PASS する
- [ ] #2 デフォルト対象パスの記述(スクリプト冒頭コメント)が実際の viewer.html の場所と一致している
<!-- AC:END -->
