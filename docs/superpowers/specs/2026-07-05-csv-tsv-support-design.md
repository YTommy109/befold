# CSV/TSV レンダリング・ソース表示対応

## 概要

mmdview に CSV/TSV ファイルのテーブル表示（rendered view）と Rainbow カラム着色（source view）を追加する。

## 方針

- テーブル表示・ソース表示どちらも自前実装（外部ライブラリ不使用）
- 既存の Mermaid/Markdown と同じレンダリングパイプラインに乗せる
- CSV と TSV を `.csv(delimiter: String)` で統一的に扱う

## FileType

```swift
case csv(delimiter: String)

static let csvExtensions = ["csv"]
static let tsvExtensions = ["tsv"]

// init(url:) での判定
// csv → .csv(delimiter: ",")
// tsv → .csv(delimiter: "\t")

var jsValue: String { "csv" }
var isRenderable: Bool { true }

var csvDelimiter: String? {
    if case let .csv(delimiter) = self { return delimiter }
    return nil
}
```

`csvDelimiter` は `codeLanguage` と同様に ViewerBridge で第3引数 `lang` パラメータとして JS に渡す。

## CSV パーサー（viewer.html 内 JS）

RFC 4180 準拠の自前パーサー:

- クオートフィールド対応（`"field with, comma"` → `field with, comma`）
- エスケープされたクオート（`""` → `"`）
- フィールド内改行対応
- delimiter を引数で受け取り CSV/TSV を統一処理
- 戻り値: `string[][]`

```javascript
function parseCsv(content, delimiter) {
    // 状態マシンベースのパーサー
    // returns: string[][] (2次元配列)
}
```

## テーブルレンダリング（rendered view）

`render()` 関数に `type === 'csv'` 分岐を追加:

```javascript
if (type === 'csv') {
    var rows = parseCsv(content, lang || ',');
    diagramWrap.className = 'markdown-body';
    diagramWrap.innerHTML = buildTableHtml(rows);
}
```

- 1行目を `<thead>` としてレンダリング
- 2行目以降を `<tbody>` としてレンダリング
- `.markdown-body` クラスで github-markdown.css のテーブルスタイルを再利用
- 空ファイルの場合は空メッセージを表示

## Rainbow ソース表示（source view）

`_renderSource` で `type === 'csv'` の場合にカスタムレンダリング:

```javascript
function renderCsvSource(content, delimiter) {
    // 各行を delimiter で分割（クオート対応）
    // 列 index % COLORS.length で色を決定
    // <pre><code> 内に着色済み HTML を出力
}
```

- 6〜8 色をローテーション
- delimiter はそのまま表示（着色しない）
- クオート内の delimiter は列区切りとして扱わない
- ダークモード対応の色を選定

## Info.plist

### UTImportedTypeDeclarations

- `public.comma-separated-values-text`（CSV）— macOS 標準 UTI
- `public.tab-separated-values-text`（TSV）— macOS 標準 UTI

### CFBundleDocumentTypes

CSV/TSV 用のドキュメントタイプエントリを追加。

## 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `FileType.swift` | `.csv(delimiter:)` ケース追加、拡張子マップ、jsValue、isRenderable、csvDelimiter |
| `viewer.html` | CSV パーサー、テーブルレンダリング、Rainbow ソース表示 |
| `Info.plist` | CSV/TSV UTI 宣言 + ドキュメントタイプ |
| `FileTypeTests.swift` | csv/tsv 拡張子のテスト |
| `ViewerBridgeTests.swift` | csv の renderScript テスト |

### 変更不要なファイル

- `ViewerStore.swift` — テキストファイルとして読み込むだけなので変更不要
- `ViewerBridge.swift` — `csvDelimiter` は `codeLanguage` と同じ `lang` パラメータ経路で渡せるので変更不要
- `ViewerWebView.swift` — 変更不要
- `ViewerContentView.swift` — 変更不要

## エッジケース

- 空ファイル: 空の状態メッセージを表示
- ヘッダーのみ（1行）: `<thead>` のみ、`<tbody>` 空
- 不揃いな列数: 短い行はセルを空で埋める
- 巨大ファイル: ビューアの既存制限に従う（特別な対応なし）
