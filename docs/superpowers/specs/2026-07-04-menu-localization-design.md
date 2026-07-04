# メニュー・ダイアログのローカライズ(日英対応)設計

## 背景

- メニューバーは `MainMenuBuilder.swift` / `RecentDocumentsMenuController.swift` に英語直書きで、日本語環境でも英語表示になる。
- 逆にアップデート関連ダイアログ(`UpdateUI.swift` / `DownloadProgressWindow.swift`)は日本語直書きで、英語環境でも日本語表示になる。
- ローカライズ基盤(`.lproj` / String Catalog / `NSLocalizedString`)は存在しない。

## 目的

macOS のシステム言語設定(およびアプリごとの言語設定)に応じて、メニューと
アップデートダイアログの表示言語を英語/日本語で自動的に切り替える。

## 方式

String Catalog(`Localizable.xcstrings`)を採用する。

- `MmdviewApp/mmdview/Resources/Localizable.xcstrings` に en / ja の全訳を1ファイルで管理する。
- キーは `menu.file.open` のような意味ベース。日本語訳は Apple 標準用語
  (Undo→「取り消す」、Cut→「カット」等)に合わせる。
- 呼び出し側は `String(localized:bundle:)` を使う。可変部を含む文言
  (バージョン番号など)はカタログ値に `%@` を置き、`String(format:)` で埋める。

### ビルド設定

| ファイル | 変更 |
| --- | --- |
| `Package.swift` | `defaultLocalization: "en"` を追加し、`.process("Resources/Localizable.xcstrings")` を登録 |
| `project.yml` | `options.developmentLanguage: en` を追加(Resources は既存の resources フェーズで Xcode が xcstrings を自動コンパイル) |
| `Info.plist` | `CFBundleDevelopmentRegion: en` を追加 |

### バンドル解決

`swift build / swift test`(リソースは `Bundle.module`)と xcodebuild
(`Bundle.main`)の差を吸収するため、`Bundle` 拡張 `Bundle.l10n` を1つ追加する
(`#if SWIFT_PACKAGE` で分岐)。

### 置換対象

- `MainMenuBuilder.swift` — 全メニュータイトル(App/File/Edit/View/Window/Help)
- `RecentDocumentsMenuController.swift` — "Clear Menu"
- `UpdateUI.swift` — 全ダイアログ文言(英語訳を新規追加)
- `DownloadProgressWindow.swift` — 進捗ウィンドウタイトル

## テスト

- 完全性テスト: ビルド済みバンドルの `en.lproj` / `ja.lproj` の
  `Localizable.strings` を読み、キー集合が一致することを検証する。
- 解決テスト: `ja.lproj` のバンドルから代表キーが期待する日本語訳に
  解決されることを検証する。

## 挙動上の注意

- メニューは起動時に一度だけ構築されるため、言語切替の反映はアプリ再起動後
  (macOS 標準挙動)。
- 言語判定は macOS 標準のバンドルローカリゼーション機構に委ねる。
  独自の言語解決ロジックは持たない。
