# HTML 外部リソース対応 & ドキュメントタイプ登録

## 背景

befold は `.html` / `.htm` ファイルを開けるが、2 つの問題がある:

1. **Finder の「このアプリで開く」に befold が表示されない** — Info.plist の CFBundleDocumentTypes に HTML エントリがない
2. **HTML 内の相対パス CSS・画像・フォントが読み込まれない** — 現在の実装は HTML コンテンツを文字列として読み、viewer.html 内の `iframe.srcdoc` に注入するため、ベース URL がなく相対参照が解決できない

## 設計

### 1. HTML ドキュメントタイプ登録

Info.plist の `CFBundleDocumentTypes` に HTML エントリを追加する。

- UTI: `public.html`（macOS 標準、`.html` / `.htm` 両対応）
- Role: Viewer
- LSHandlerRank: Alternate（ブラウザが Owner）

### 2. HTML 直接ロード

HTML ファイルのレンダリング表示時のみ、viewer.html を経由せず `WKWebView.loadFileURL` で直接読み込む。

**原則:**
- レンダリング表示 + HTML → `loadFileURL(htmlFile, allowingReadAccessTo: parentDir)` で直接ロード
- ソース表示 / 削除状態 / 他ファイルタイプ → 従来の viewer.html + evaluateJavaScript パス
- モード切替時は WKWebView の全ページリロードが発生する（ユーザー操作のため許容）

**Coordinator の状態管理:**

`isDirectHTMLMode` フラグで現在のロードモードを追跡:

```
updateContent(content, fileType, isDeleted, filePath):
  if fileType == .html && !isDeleted && filePath != nil:
    → loadFileURL(filePath, allowingReadAccessTo: parentDir)
    → isDirectHTMLMode = true, isReady = false
  else:
    if isDirectHTMLMode:
      → viewer.html を再ロード
      → pendingUpdate に通常レンダリングを設定
    else:
      → 従来の evaluateJavaScript パス
```

**ファイル変更検知:**

ViewerStore は引き続き content を文字列として読み込む。HTML 直接ロードモードでは content 文字列は使わず、filePath の `loadFileURL` で再ロードする。content の変化が SwiftUI の更新サイクルをトリガーするため、ライブプレビューは自然に機能する。

### 3. Zoom 対応

HTML 直接ロード時は viewer.html の JS zoom 関数が存在しないため、WKWebView の `pageZoom` プロパティを使用する。

- ViewerWindowController の `zoomIn`/`zoomOut`/`resetZoom` を分岐
- `pageZoom` の値を ZoomStore に保存
- メニューの cmd+/- ショートカットは macOS メニューシステム経由で動作する
- ctrl+ホイール（ピンチ）は HTML 直接ロード時には非対応（将来 WKUserScript で追加可能）

### 4. ソース表示との切替

- ソース表示: viewer.html に戻し、既存の code レンダリングで HTML ソースを表示
- レンダリング表示: HTML 直接ロードに切替
- 切替時は WKWebView の全ページリロードが発生

## 変更対象

| ファイル | 変更内容 |
|---|---|
| Info.plist | HTML ドキュメントタイプ追加 |
| ViewerWebView.swift | filePath パラメータ追加、HTML 直接ロードモード実装 |
| ViewerContentView.swift | store.filePath を ViewerWebView に渡す |
| ViewerWindowController.swift | zoom アクションの分岐 |

## スコープ外

- HTML 内の `<script>` 実行（セキュリティ上、意図的に非対応のまま）
- ctrl+ホイールによるピンチズーム（HTML 直接ロード時）
