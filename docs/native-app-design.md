# macOS ネイティブアプリ（Swift） — 設計ドキュメント

**日付**: 2026-06-11
**ステータス**: ドラフト

## 概要

本ドキュメントは **macOS ネイティブアプリ（Swift）** のアーキテクチャ設計書である。

- 現行 mmdview（Python + FastAPI + pywebview）と**同等の機能**を Swift で再実装する
- `.mmd` / `.md` ファイルを監視し、mermaid.js でリアルタイムプレビューする
- Python 版の「ローカル HTTP サーバー + WKWebView」構成は捨て、
  **プロセス内完結**のネイティブ構成にする

---

## 機能パリティ表

現行実装済み仕様と Swift 版での置き換え方針。

| 現行 mmdview（Python） | Swift 版での実現方法 |
|---|---|
| FastAPI + uvicorn（ローカル HTTP） | **廃止**。`WKWebView` に直接 HTML を供給 |
| pywebview ウィンドウ | SwiftUI + `NSWindow`（複数ウィンドウ） |
| watchdog ＋ 0.2 秒デバウンス | `DispatchSource.makeFileSystemObjectSource` ＋ 同等デバウンス |
| SSE による変更通知 | 不要。同一プロセス内で直接 `WKWebView` を更新 |
| Apple Events（odoc）の自前ハンドリング | `NSApplicationDelegate.application(_:open:)` ／ DocumentGroup |
| 最近開いたファイル（自前 JSON・最大 10 件） | `NSDocumentController` 標準機能 |
| ウィンドウ状態復元（window_state.json） | macOS 標準の State Restoration |
| 自動アップデート（GitHub Releases 自前実装） | **Sparkle 2** を採用 |
| ファイル関連付け（Info.plist / UTType） | 現行 `mmdview.spec` の宣言を Info.plist に移植 |
| ズーム（0.5〜2.0、localStorage） | 現行 JS 実装を移植（`UserDefaults` 永続化に変更） |
| Mermaid エラーパネル・削除バナー | 現行 HTML/CSS/JS を移植 |
| PyInstaller バンドル | Xcode ビルド ＋ codesign / notarization |

---

## アーキテクチャ

```
mmdview.app (Swift / SwiftUI)
  ├── App 層           # ライフサイクル・メニュー・ウィンドウ管理
  ├── FileWatcher      # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore      # 表示状態（ファイル内容・エラー・削除フラグ）
  └── ViewerWebView    # WKWebView
        ├── 同梱アセット（viewer.html / mermaid.min.js / markdown-it.min.js / style.css）
        └── JS ブリッジ
             ├── Swift → JS: evaluateJavaScript（本文更新・削除バナー）
             └── JS → Swift: WKScriptMessageHandler（必要時のみ）
```

- HTTP・SSE・ポート管理は不要になる。ファイル変更は
  `FileWatcher → ViewerStore → evaluateJavaScript` の同一プロセス内伝搬で反映する
- **mermaid.js・markdown-it.js と viewer の HTML/CSS/JS** をアプリバンドルに同梱する
  （htmx・SSE 拡張・_hyperscript は不要になる）
- HTML は `WKWebView.loadFileURL`（バンドル内）で読み込み、
  本文は JS 関数 `render(content)` 呼び出しで差し替える
  （現行の `location.reload()` 方式より、ちらつきとスクロール位置リセットがなくなる）

---

## モジュール構成

```
mmdview/
├── App/
│   ├── MmdviewApp.swift        # @main・Settings・メニュー定義
│   ├── AppDelegate.swift       # application(_:open:)・終了処理
│   └── WindowController.swift  # ウィンドウ生成・タイトル・複数ウィンドウ管理
├── Viewer/
│   ├── ViewerStore.swift       # ObservableObject（content / error / deleted）
│   ├── ViewerWebView.swift     # NSViewRepresentable（WKWebView ラッパー）
│   └── Resources/
│       ├── viewer.html         # 現行 viewer.html から移植（SSE 部分を除去）
│       ├── mermaid.min.js
│       ├── markdown-it.min.js
│       └── style.css
├── FileWatching/
│   ├── FileWatcher.swift       # DispatchSource 監視・デバウンス
│   └── Debouncer.swift
└── mmdviewTests/
```

---

## ファイル監視

現行 watchdog 実装の挙動仕様を引き継ぐ。

- 監視対象はファイルの**親ディレクトリ**（エディタの atomic save =
  rename で inode が変わっても追跡できるようにするため。現行と同じ理由）
- シンボリックリンクは実パスに解決してから比較する（現行 `.resolve()` 相当）
- イベント発生から **0.2 秒のデバウンス**後に読み込み・再描画
  （連続保存での多重描画を防ぐ。現行と同じ値）
- ファイル消失時は `deleted` 状態にし、削除バナー＋グレー背景を表示（現行同等）
- 実装は `DispatchSource.makeFileSystemObjectSource`（`.write` イベント、
  ディレクトリ FD 監視）を第一候補とする。ネットワークボリューム対応が
  必要になったら `FSEventStream` に切り替える

---

## ウィンドウ管理・ファイルオープン

- 1 ファイル = 1 ウィンドウの複数ウィンドウ対応（現行同等）。
  ウィンドウごとに `ViewerStore` と `FileWatcher` を持つ
  （現行 `window_registry` の window_id → WatchService/EventBus 対応と同型）
- `File > Open...`（⌘O）・`File > Open Recent` を提供。
  Open Recent は `NSDocumentController.shared.noteNewRecentDocumentURL(_:)` を使い、
  自前の recent_files.json は持たない
- 「このアプリで開く」「Dock へのドロップ」は
  `application(_:open:)` で受ける。現行の Apple Events 自前パッチ
  （`_patch_app_delegate_for_open_file` / `_StartupFileGate`）で解決していた
  起動順序問題は、AppKit 標準のイベント配送に乗ることで解消される
- ファイル関連付けは現行 `mmdview.spec` の宣言（`com.degino.mmdview.mermaid-diagram`、
  拡張子 `mmd` / `mermaid`、`LSHandlerRank` Owner ＋ markdown Alternate）を
  Info.plist にそのまま移植する
- ウィンドウ位置・サイズ・開いていたファイルの復元は macOS 標準の
  State Restoration（`NSWindow.restorationClass`）で行い、
  自前の window_state.json は持たない

---

## 表示仕様の引き継ぎ

viewer.html・style.css・mermaid 初期化設定は現行実装から移植する。

- **mermaid 初期化**: `startOnLoad: false`、全ダイアグラム種別 `useMaxWidth: false`、
  `theme: 'default'`（現行と同一）
- **`.mmd` の扱い**: 全文を `<pre class="mermaid">` に渡し mermaid.js に処理させる
- **`.md` の扱い**: markdown-it.js で markdown → HTML 変換する。
  ` ```mermaid ` フェンスは markdown-it のカスタムレンダラーで `<pre class="mermaid">` に出力し、
  mermaid.js が SVG 描画する（Web アプリの markdown-it-py と同ファミリーで挙動が揃う）
- **ズーム**: 0.5〜2.0（ボタン・キーは 25% 刻み、ホイールは連続）、基準スケール 0.75、
  `Cmd +/-`・`Ctrl + ホイール`・%表示クリックでリセット。
  永続化は localStorage から `UserDefaults` に変更（ウィンドウ間で共有）
- **エラーパネル**: `mermaid.parseError` で構文エラーの詳細メッセージを
  赤ボーダー・等幅フォントのパネルに表示（現行同等）
- **削除バナー**: ファイル削除時にグレーバナー＋背景色変更（現行同等）

---

## 自動アップデート

現行の自前実装（GitHub Releases API 照合 → DMG ダウンロード → hdiutil マウント →
シェルスクリプトでアプリ置換）は **Sparkle 2 に置き換える**。

| 観点 | 自前実装（現行） | Sparkle 2（採用） |
|---|---|---|
| 実装・保守コスト | DMG マウント・置換スクリプトを自前保守 | フレームワークに委譲 |
| 署名検証 | なし | EdDSA 署名検証あり |
| 配信 | GitHub Releases（latest API） | appcast.xml（GitHub Pages / Releases に配置） |
| UI | htmx 製の独自ダイアログ | 標準の更新ダイアログ |

リリース CI で appcast.xml の生成・署名を行う。配布には codesign + notarization を
必須とする（Sparkle の差し替え更新は署名済みアプリが前提のため）。

---

## 技術スタック

| 技術 | 用途 |
|---|---|
| Swift 6 / SwiftUI + AppKit | アプリ本体（macOS 14+） |
| WKWebView | markdown・mermaid レンダリング |
| mermaid.min.js（同梱） | Mermaid SVG レンダリング（現行のキャッシュ版を流用） |
| markdown-it.min.js（同梱） | `.md` ファイルの markdown → HTML 変換 |
| Sparkle 2 (SPM) | 自動アップデート |
| XCTest | ユニット・UI テスト |

依存管理は Swift Package Manager。プロジェクト生成に XcodeGen 等を使うかは
実装開始時に決める。

---

## テスト方針

現行の「ロジックは厚く、GUI/OS 層は薄く」の方針を踏襲する。

- **ユニットテスト（XCTest）**: FileWatcher（デバウンス・atomic save・シンボリックリンク・
  削除検知）、Debouncer、ViewerStore の状態遷移。現行 `test_watch_service.py` の
  テストケースを移植する
- **WebView 連携**: viewer.html の JS（ズーム・エラーパネル）は現行 Playwright e2e の
  ケースを `WKWebView` ＋ XCTest で再現する
- **GUI/OS 層**（メニュー・State Restoration・Sparkle）: 自動テスト対象外とし、
  リリース前の手動チェックリストで担保する（現行のカバレッジ除外方針と同じ）

---

## リリース計画

1. 現行 Python 版は期待通りに動作していないことが Swift 版への移行動機であり、
   並行メンテナンスは行わない
2. Swift 版が動作し始め次第、GitHub Releases の既存バイナリを削除して置き換える
   （Sparkle 移行のため、初回は手動での入れ替えインストールになる）

---

## スコープ外

- Windows / Linux 対応
- mermaid 以外のダイアグラム形式
- エクスポート機能（SVG / PNG）
- テキスト編集機能（ビューア専用アプリ）
- AI 編集機能
