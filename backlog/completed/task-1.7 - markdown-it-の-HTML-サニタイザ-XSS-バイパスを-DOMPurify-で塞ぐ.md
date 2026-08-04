---
id: TASK-1.7
title: markdown-it の HTML サニタイザ XSS バイパスを DOMPurify で塞ぐ
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-18 13:40'
updated_date: '2026-07-18 14:51'
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
- [x] #1 正規表現サニタイザを廃し DOMPurify（または html:false）で HTML をサニタイズしている
- [x] #2 スラッシュ区切り属性・名前空間属性を使った onerror/onload バイパスが再現しないことをテストで確認している
- [x] #3 既存の Markdown/mermaid レンダリング表示に回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化の検討: 正規表現サニタイザ(viewer.html:477-490)を自前で強化(スラッシュ区切り・名前空間属性対応など)する案は却下。
場当たり的なパターン追加は今回のバイパスを塞いでも次のバイパスを生む(実際に今回もこの正規表現自体がバイパスされた)。
既存の「viewer.js に純粋ロジックを置きJestでテストする」設計(sanitizeLang/highlightCode等と同型)を踏襲しつつ、
サニタイズ処理自体は自前実装せず実績のあるDOMPurifyに委譲する。新規の状態や分岐を増やさない。

## 実装手順
1. DOMPurify 3.4.12(2026-07-18時点の最新・既知CVE全て修正済み)を
   BefoldApp/BefoldKit/Resources/dompurify.min.js としてベンダリング(curl -fsSL cdn.jsdelivr.net/npm/dompurify@3.4.12/dist/purify.min.js)
2. BefoldApp/Package.swift の BefoldKit resources に .copy("Resources/dompurify.min.js") を追加
3. viewer.html に <script src="dompurify.min.js"> タグを追加(markdown-it.min.js の後)
4. viewer.js に純粋関数 sanitizeRenderedHtml(purify, html) を追加(module.exports にも追加)。中身は purify.sanitize(html) を呼ぶだけの薄いラッパ(Jest からDOMPurifyインスタンスを差し替えてテスト可能にするため関数化)
5. viewer.html:477-490 の正規表現ベースの md.render 上書きを削除し、sanitizeRenderedHtml(DOMPurify, ...) を呼ぶ形に置き換える
6. BefoldApp/package.json の devDependencies に dompurify@3.4.12 と jsdom(テスト専用、DOMPurifyの実行にDOM実装が要るため)を追加、npm install で package-lock.json 更新
7. BefoldApp/befold/Resources/__tests__/viewer.test.js に sanitizeRenderedHtml のテストを追加:
   - スラッシュ区切り属性バイパス (<img src=x/onerror=alert(1)>) が無害化される
   - 名前空間属性バイパス (<a xlink:href=1 onload=...>) が無害化される
   - 通常のMarkdown/HTML(strong, a href等)が壊れずに残る(回帰確認)
8. .claude/commands/check-vendored-deps.md と .claude/agents/vendored-deps-auditor.md にDOMPurifyを追記(既存の棚卸し対象に追加する既存パターンを踏襲)
9. swift build / npx jest 実行、/webview-smoke でMarkdown・mermaid・HTML表示の目視回帰確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了(2026-07-18)。

検証:
- npx jest: 199 passed(新規 sanitizeRenderedHtml テスト6件含む)。
  実際のバイパス確認は文字列一致ではなく jsdom で DOM 構築し on* 属性の有無を検査する形にした
  (単純な文字列一致では `src="x"/onerror=alert(1)` のような「onerrorという文字列を含むが
  実際は src の値の一部で発火しない」ケースを誤検知するため)。実HTML5パーサ(jsdom)で
  クォート閉じ直後の "/" が before-attribute-name state に戻り onerror が独立属性として
  パースされる(=旧正規表現の \s+ 要求バイパス再現)ことを確認した上で、サニタイズ後は
  当該属性が消えることを検証。
- swift test: 368 passed。
- swift build: 成功。dompurify.min.js が .build/.../befold_BefoldKit.bundle に copy されることを確認。
- swift scripts/webview-smoke.swift: PASS。ただし data: iframe のCSPブロック確認テストは
  DOMPurify 導入により <iframe> タグ自体が除去されるようになったため(旧: CSP frame-src で
  ブロック→新: サニタイザ層で除去、さらに強い防御)、テストのアサーションを
  「サニタイザ除去 or CSP違反のどちらかでブロックされていればPASS」に更新した
  (scripts/webview-smoke.swift の checkDataFrameBlocked)。

サイドエフェクト: check-vendored-deps.md / vendored-deps-auditor.md にDOMPurifyの棚卸し手順を追記。
package.json に dompurify(実行時と同一の3.4.12)・jsdom(テスト専用、DOMPurify実行にDOM実装が要るため)を追加。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer.html の正規表現ベース HTML サニタイザ(on* 属性除去、\s+ 前提)を廃止し、
DOMPurify 3.4.12(ベンダリング、既知CVE修正済み最新版)による md.render() 出力のサニタイズに置き換えた。
サニタイズ処理は viewer.js の純粋関数 sanitizeRenderedHtml(purify, html) として切り出し、
既存の sanitizeLang/highlightCode と同じ依存注入パターンでJestからテスト可能にした。

検証: npx jest 199件成功(スラッシュ区切り属性・名前空間属性による onerror/onload バイパスが
実HTML5パーサ(jsdom)上でも再現しないことをDOM属性検査で確認する新規テスト6件を含む)、
swift test 368件成功、swift build成功、swift scripts/webview-smoke.swift PASS
(mermaid/markdown描画に回帰なし、data: iframeペイロードはDOMPurifyにタグごと除去されるよう強化)。
<!-- SECTION:FINAL_SUMMARY:END -->
