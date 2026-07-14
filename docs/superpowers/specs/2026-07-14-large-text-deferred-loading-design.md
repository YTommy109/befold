# 大容量テキスト段階読み込み・非 UTF-8 エンコーディング対応

Issue: [#190](https://github.com/YTommy109/befold/issues/190) — ヘッダー行なしの .csv が表示できない

## 背景

テキストファイルの読み込み上限が 10MB に設定されており、それを超えるファイルは「このファイル形式はプレビューに対応していません」と表示される。22MB の CSV ファイル（行政データ等）で報告された。

10MB 上限はメインアクター上の同期読み込みでビーチボール化を防ぐために設けられたもの。単純に上限を引き上げると保護が失われるため、段階読み込みで解決する。

## 設計

### 読み込み戦略

| ファイルサイズ | 動作 |
|-------------|------|
| ≤ 10MB | 現状通り同期読み込み（変更なし） |
| > 10MB かつ ≤ 50MB | 先頭 10MB をプレビュー表示 → 非同期で全量読み込み → 差し替え |
| > 50MB | `isUnsupported = true`（現状と同じ保護） |

### 非表示理由の分離

現状は `isUnsupported: Bool` 一本で「非対応形式」と「サイズ超過」を兼ねている。これを分離する。

```swift
// BefoldKit に追加
enum RejectReason: Sendable, Equatable {
    case unsupportedFormat  // バイナリ等の非対応形式
    case fileTooLarge       // サイズ上限超過
}
```

`LoadedContent` を拡張:

```swift
struct LoadedContent: Sendable, Equatable {
    let rejectReason: RejectReason?  // nil = 正常読み込み
    let content: String
    let isTruncated: Bool            // 新規：部分読み込みフラグ
}
```

`ViewerStore` では `isUnsupported: Bool` を `rejectReason: RejectReason?` に置き換え、既存の参照箇所は computed property `var isRejected: Bool { rejectReason != nil }` で移行する。

`UnsupportedFileView` は `rejectReason` を受け取り、メッセージを分ける:

- `.unsupportedFormat` → 「このファイル形式はプレビューに対応していません」
- `.fileTooLarge` → 「ファイルが大きすぎるため表示できません」

### ContentLoader の変更

```swift
// 既存（上限を 50MB に変更）
func load(from:fileType:) -> LoadedContent

// 新規：先頭 10MB だけ読み込む
func loadPreview(from:fileType:) -> LoadedContent
```

- `loadPreview` は先頭バイトを読み、最後の改行位置で切断して返す（行途中の切断防止）
- サイズ超過時は `rejectReason: .fileTooLarge` を返す
- バイナリ判定時は `rejectReason: .unsupportedFormat` を返す

### FileReading の変更

部分読み込み用メソッドを追加:

```swift
func readString(from url: URL, maxBytes: Int) -> String?
```

先頭 `maxBytes` バイトを読み、最後の改行で切断した文字列を返す。

### 非 UTF-8 エンコーディング対応

`decodeUnicodeText()` の既存デコード順:

1. BOM 検出 → 対応エンコーディングで復号
2. NUL バイトあり → UTF-16 として復号
3. NUL なし → UTF-8 として復号

ステップ 3 で UTF-8 復号が失敗した場合のフォールバックを追加:

4. `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)` でエンコーディングを自動推定し復号

これにより Shift_JIS / EUC-JP / ISO-2022-JP 等の日本語エンコーディングをまとめて対応する。エンコーディング切り替えメニューやファイル単位の記憶は設けない（自動推定は決定論的で、同じファイルに対して常に同じ結果を返すため）。

### ViewerStore の変更

`loadContent()` の新しいフロー:

1. ファイルサイズ確認
2. ≤ 10MB: 現状通り `load()` で同期読み込み
3. > 10MB かつ ≤ 50MB:
   - `loadPreview()` で先頭 10MB を同期読み込み → 即表示
   - `Task` で `load()` を非同期実行 → 完了後に `content` を差し替え
4. > 50MB: `isUnsupported = true`

新しい状態:

- `isTruncated: Bool` — プレビュー表示中であることを示す
- 全量読み込み完了後に `false` に戻す

### JS 側の変更

- `isTruncated` 時に「ファイルの一部を表示中…」バナーを表示
- 全量到着後にバナーを消して再レンダリング

### QuickLook（将来）

`loadPreview()` だけ呼べばプレビュー完了。フル読み込みは不要。ContentLoader / BefoldKit のロジックをそのまま共有できる。

## 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `BefoldKit/RejectReason.swift`（新規） | `RejectReason` enum 追加 |
| `ContentLoader.swift` | `loadPreview` 追加、`LoadedContent` に `rejectReason` / `isTruncated` 追加、上限 50MB 化 |
| `FileReading.swift` | `readString(from:maxBytes:)` 追加、`decodeUnicodeText()` に非 UTF-8 フォールバック追加 |
| `ViewerStore.swift` | `isUnsupported` → `rejectReason` 移行、段階読み込みフロー |
| `UnsupportedFileView.swift` | `rejectReason` に応じたメッセージ分岐 |
| `ViewerContentView.swift` | `isUnsupported` → `isRejected` + `rejectReason` 参照に更新 |
| `viewer.html` / `viewer.js` | truncated バナー表示・非表示 |
| テスト各種 | 上記に対応するテスト |

## テスト

- `ContentLoaderTests`: `loadPreview` で先頭のみ返ること、改行境界で切れること
- `ViewerStoreTests`: 10MB 超ファイルで `isTruncated` が `true` → 全量読み込み後に `false`
- `DefaultFileReaderTests`: `readString(from:maxBytes:)` の動作確認
- `DefaultFileReaderTests`: Shift_JIS / EUC-JP データの `decodeUnicodeText` フォールバック確認

## スコープ外

- エンコーディング切り替えメニュー（自動推定で十分、YAGNI）
- ファイル単位のエンコーディング記憶（自動推定は決定論的なので不要）
- ヘッダー行の有無の自動判定（現状の「1 行目をヘッダーとして表示」を維持）
