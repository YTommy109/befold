---
id: TASK-1.7
title: markdown-it の HTML サニタイザ XSS バイパスを DOMPurify で塞ぐ
status: To Do
assignee: []
created_date: '2026-07-18 13:40'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: bug
ordinal: 6110
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー（2026-07-18）で発見（High）。viewer.js:1141 で md.render(content) の結果を innerHTML 代入しているが、viewer.html:493-502 の正規表現サニタイザがバイパス可能。markdown-it（同梱 14.2.0, html:true, viewer.html:479-488）は HTML ブロック内の行をタグ構造未検証で生通過させ、属性区切りにスラッシュを使うと ' on…=' 除去（\\s+ 要求）を素通りする。実測: 入力 <div>\\n<img src=x/onerror=alert(1)>\\n</div> がサニタイズ後も onerror 残存し、innerHTML 挿入時に発火→任意 JS 実行。名前空間属性（<a xlink:href=1 onload=…>）も残存。CSP は script-src 'unsafe-inline'（viewer.html:13）でインラインイベントハンドラを許可するためブロックできず、サニタイザが唯一の防御。XSS からは window.webkit.messageHandlers.referenceActivated.postMessage を直接呼べ（isTrusted はネイティブ側で無検証）、Swift 側 NSWorkspace.shared.open（ViewerWindowController.swift:232）で外部 URL を開けるため情報持ち出し経路になる。QuickLook は未選択ファイルを自動プレビューし攻撃ハードルが激減するため QuickLook 前に必須。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 正規表現サニタイザを廃し DOMPurify（または html:false）で HTML をサニタイズしている
- [ ] #2 スラッシュ区切り属性・名前空間属性を使った onerror/onload バイパスが再現しないことをテストで確認している
- [ ] #3 既存の Markdown/mermaid レンダリング表示に回帰がない
<!-- AC:END -->
