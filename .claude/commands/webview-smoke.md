# /webview-smoke — WKWebView スモークテスト

テスト規約で WebView / GUI 層は自動テスト対象外だが、CSP や `viewer.html` を
触ったときの回帰は `scripts/webview-smoke.swift` で自動確認できる。実アプリと
同じ `loadFileURL(allowingReadAccessTo:)` 経路で viewer.html を読み込み、GUI を
目視せずに以下を検証する。

## 実行

```bash
swift scripts/webview-smoke.swift
```

検証項目:
1. CSP 下でローカルスクリプト（viewer.js / mermaid / markdown-it）がロードされる
2. `.mmd` が mermaid で SVG 描画される
3. `.md` が markdown-it で描画される
4. 外部画像による情報流出が CSP(`img-src`) でブロックされる

## 報告

- `PASS: ...` かつ exit 0 なら「✅ WebView スモークテスト通過」と報告する。
- `FAIL: ...` が出たら、どの検証項目で落ちたか（スクリプトロード / 描画 / CSP）を
  そのまま伝える。CSP を変更した直後の失敗なら、`viewer.html` の
  `Content-Security-Policy` メタタグを疑う。
