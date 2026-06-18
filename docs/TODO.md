# native-app-design.md — 設計レビュー TODO

## Important（実装前に決定必要）

- [ ] **サンドボックス・エンタイトルメント方針を決定する**
  - App Sandbox を有効にするか否かを明記する
  - Sandbox 有効時は State Restoration でのファイル再オープンに
    `NSURL.bookmarkData(options: .withSecurityScope)` が必要になる
  - `DispatchSource` での親ディレクトリ FD 監視も Sandbox 内では
    権限取得手順が必要になるため、entitlements の内容も設計書に列挙する

- [ ] **JS ブリッジの `render()` インターフェース仕様を定義する**
  - `.mmd`（mermaid 直渡し）と `.md`（markdown-it 変換）でパスが異なるため、
    `render(content, type)` か `renderMmd` / `renderMd` に分けるかを決める
  - `.md` 内 mermaid フェンスで構文エラーが発生した場合のエラーパネル表示方針も定義する

- [ ] **`loadFileURL` と JS リソース参照方式を決定する**
  - viewer.html から mermaid.min.js / markdown-it.min.js を
    外部ファイル参照するか、インライン埋め込みにするかを決める
  - `WKWebView.loadFileURL(_:allowingReadAccessTo:)` の `allowingReadAccessTo`
    スコープを明記する

- [ ] **`.md` の `LSHandlerRank: Alternate` の意図を明記する（または Owner に変更する）**
  - markdown-it.js 追加で .md 表示品質が上がった今、Alternate のまま据え置くなら
    「既存エディタのデフォルトを上書きしない意図」と明記する

## Minor（実装開始前に記述推奨）

- [ ] **Sparkle 2 のセットアップ詳細を設計書に追記する**
  - SUFeedURL の配置場所（GitHub Pages か GitHub Releases assets か）
  - EdDSA 鍵の管理方法（GitHub Actions Secret 等）
  - 初回起動時の自動確認ダイアログ設定（`SUEnableAutomaticChecks` の初期値）

- [ ] **`FileWatcher` の actor 設計を決定する**
  - Swift 6 strict concurrency 環境では GCD ベースの `DispatchSource` と
    SwiftUI（MainActor）の混在でコンパイルエラーが出やすい
  - `@MainActor` で囲む / 独自 `actor FileWatcher` にする / Swift 5 互換モードにする
    のいずれかを選んで設計書に明記する

- [ ] **WebView JS テスト方針を事前検証する**
  - XCTest で headless WKWebView が安定するか確認する
  - ズーム計算・エラーパネル表示条件など純粋なロジックは
    Jest（Node.js）で単体テストする選択肢も検討する

- [ ] **`evaluateJavaScript` のレースコンディション対策を設計する**
  - 起動直後のファイル変更イベントが WebView ロード完了前に届くケースの
    ハンドリング方針（`ViewerStore` → `ViewerWebView` の更新タイミング）を定義する
