---
id: TASK-526
title: リモート画像が CSP img-src を素通りして読み込まれる
status: To Do
assignee: []
created_date: '2026-08-19 03:29'
labels:
  - bug
dependencies: []
priority: high
ordinal: 768000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 事象

Markdown 中のリモート画像（`https://` の shields.io バッジ等）が **実際に読み込まれる**。viewer.html の CSP は `img-src 'self' data:`（BefoldApp/BefoldKit/Resources/viewer.html:17）で、設計上はブロックされる前提だった。TASK-524 の Description も「リモート URL の画像は CSP と『ネットワークへ出ない』設計により表示しない。これは意図した挙動」と書いているが、**この前提は誤り**。

文書を開くだけで外部ホストへリクエストが出る（IP・User-Agent・どの文書をいつ開いたかが相手に渡る）。

## 実測（2026-08-19、TASK-524 の実機確認中）

実アプリと同じ `loadFileURL(_:allowingReadAccessTo:)` 経路で viewer.html を読み、`render(doc, 'md')` した後に計測した使い捨てスクリプトの結果。

入力: `<img src="https://img.shields.io/badge/license-MIT-blue" alt="b">`

```text
complete = 1;
naturalWidth = 78;
src = "https://img.shields.io/badge/l";
violations = ( );
```

- `naturalWidth = 78` は実際に画像バイトを取得してデコードできたことを意味する
- `securitypolicyviolation` イベントは **1 件も発火していない**（CSP がこの取得を検査していない）
- 実 README.md（embedder 適用後）を同じ経路で描画したときも、shields.io バッジ 3 枚が naturalWidth 102 / 99 / 78 で読み込まれた

## 既存のスモークテストが検知できなかった理由

`scripts/webview-smoke.swift` の `checkExfilBlocked` は `<img src="https://..." onload="..." onerror="...">` を入れて `window.__exfil` を見る。しかしインラインイベントハンドラは `script-src 'self'`（'unsafe-inline' 無し）で実行がブロックされるため、**画像が読み込まれても onload が走らない**。結果は 'PENDING' になり、判定は 'LOADED' のときだけ落ちるので通ってしまう。守りたい対象（画像の取得が起きないこと）と測っているもの（インラインハンドラが走ったか）がずれている。

## 未確認

- meta タグの CSP が file:// オリジンで `img-src` に効かないのが WKWebView の仕様なのか、`default-src 'none'` との組み合わせの問題なのかは切り分けていない
- QuickLook 拡張（BefoldQuickLook）と直接 HTML モード（DirectHTMLModeController）でも同じかは未確認
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スモークテストを naturalWidth（実際に取得できたか）で判定する形へ直し、現状で落ちることを確認する
- [ ] #2 リモート画像の取得を実際に止める（WKWebView 側の仕組みで止めるか、meta CSP が効かない原因を特定して直す）
- [ ] #3 止めたときのユーザー向けの見え方を決める（黙って壊れた画像にするのか、代替表示を出すのか）
- [ ] #4 QuickLook 拡張と直接 HTML モードでも同じ経路が塞がっていることを確認する
<!-- AC:END -->
