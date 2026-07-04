# コードファイルのシンタックスハイライト表示（Phase 1）設計

## 目的

mmdview を `.mmd` / `.md` 専用ビューアから、プログラムコード・構造化テキスト
（`.swift` / `.py` / `.js` / `.json` / `.yaml` / `.xml` など）もシンタックス
ハイライト付きで表示できるビューアに拡張する。

同梱済みの highlight.min.js（36 言語対応）をそのまま使い、**新規ライブラリは
追加しない**。

## スコープ

- 対象: 同梱 highlight.js が対応する言語の拡張子すべて（下記対応表）
- 行番号表示: なし（YAGNI。必要になったら後続対応）
- Finder 関連付け: 全対応拡張子を Viewer ロールで登録
- 対象外: `.csv` / `.tsv` / `.toon`（ハイライト文法がない。表レンダラーが
  必要なため将来の Phase 3 で別途検討）
- 制約: 拡張子なしファイル（`Makefile` など）は拡張子ベース判定では拾えない
  （`.mk` のみ対応）

## 設計

### 1. FileType の拡張（ルーティング）

`FileType.swift` に `.code(language: String)` ケースを追加する。
対応拡張子の単一情報源は引き続き `FileType.swift`。

```swift
enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case code(language: String)

    /// 拡張子 → highlight.js 言語名。ここが唯一の対応表。
    static let codeExtensionLanguages: [String: String] = [
        "swift": "swift", "py": "python", "go": "go", "rs": "rust",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "java": "java", "kt": "kotlin", "kts": "kotlin",
        "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp",
        "cs": "csharp", "m": "objectivec", "mm": "objectivec",
        "rb": "ruby", "php": "php", "pl": "perl", "pm": "perl",
        "lua": "lua", "r": "r", "sql": "sql",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "graphql": "graphql", "gql": "graphql",
        "css": "css", "scss": "scss", "less": "less",
        "ini": "ini", "toml": "ini", "diff": "diff", "patch": "diff", "mk": "makefile",
        "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yaml",
        "xml": "xml", "plist": "xml", "svg": "xml", "vb": "vbnet",
    ]
    static let codeExtensions = [String](codeExtensionLanguages.keys)
    static let allExtensions = mermaidExtensions + markdownExtensions + codeExtensions
}
```

判定順: mermaid 拡張子 → コード対応表 → それ以外は従来通り Markdown
フォールバック（挙動変更なし）。

### 2. ブリッジ契約（ViewerBridge）

`renderScript` を言語引数付きに拡張する。

- `.code` の場合のみ 3 引数: `render(<json>, 'code', 'swift')`
- `.mmd` / `.markdown` は従来通り 2 引数: `render(<json>, 'md')`

言語名は自前の対応表由来の固定文字列のみだが、JS 側でも既存の
`sanitizeLang()` を通して防御的に二重チェックする。
`ViewerBridgeTests`（Swift/HTML の契約整合テスト）を更新する。

### 3. レンダリング（viewer.html / viewer.js）

純粋ロジックは `viewer.js` に置き、Node で単体テスト可能にする。

```js
// viewer.js — 新規: フルページのコード HTML を組み立てる。
// highlightCode() を再利用し、ハイライト失敗時は
// エスケープ済みプレーン <pre><code> にフォールバックする。
function renderCodeHtml(hljs, str, lang) { ... }
```

`viewer.html` の `render(content, type, lang)` に `type === 'code'` 分岐を
追加し、`renderCodeHtml()` の結果を `diagramWrap` に流し込む。

スタイル:

- `.markdown-body` クラスは付けず、新設の `.code-body` クラスを付与する
- `style.css` に全画面コード表示用スタイルを定義する
  （等幅フォント、パディング、`github.css` / `github-dark.css` の背景色）
- 既存の全体ズーム機構はそのまま効く（ダイアグラム個別ズームは対象外）

### 4. Finder 登録・オープンパネル

- **オープンパネル**: `AppDelegate.supportedContentTypes` は
  `FileType.allExtensions` から UTType を解決しているため、対応表の拡張子が
  自動反映される。既知の安定システム UTI（`public.swift-source`、
  `public.python-script`、`public.json` など）を識別子リストに追記する。
- **Info.plist**: `CFBundleDocumentTypes` に「Source Code」エントリ
  （Role=Viewer、LSHandlerRank=Alternate）を追加する。システム UTI が無い
  拡張子（.go / .rs / .kt / .graphql など）は `UTImportedTypeDeclarations`
  で `public.source-code` 準拠としてインポート宣言する
  （既存の mermaid UTI 宣言と同じパターン）。

### 5. エラー処理

- ハイライト失敗（未知言語・例外）→ エスケープ済みプレーンテキスト
  `<pre><code>` 表示（`highlightCode` の既存フォールバックを踏襲）
- ファイル削除・リネーム → 既存の `FileWatcher` / バナー機構がそのまま動作
  （変更不要）
- 未対応拡張子 → 従来通り Markdown として表示（挙動変更なし）

### 6. テスト

- **FileTypeTests**: 対応表の全拡張子 → 期待ケース/言語、
  `allExtensions` の重複なし、未対応拡張子の Markdown フォールバック
- **ViewerBridgeTests**: `render(<json>, 'code', 'swift')` 形式の生成、
  viewer.html との契約整合
- **viewer.test.js**: `renderCodeHtml()` の正常系・フォールバック・
  XSS エスケープ
- **手動確認**: ビルド・起動して代表的なコードファイルを開き表示確認
  （WebView/GUI 層は規約通り自動テスト対象外）

## 変更ファイル一覧

| ファイル | 変更内容 |
| --- | --- |
| `MmdviewApp/mmdview/Viewer/FileType.swift` | `.code` ケースと拡張子対応表を追加 |
| `MmdviewApp/mmdview/Viewer/ViewerBridge.swift` | `renderScript` に言語引数を追加 |
| `MmdviewApp/mmdview/Resources/viewer.js` | `renderCodeHtml()` を追加 |
| `MmdviewApp/mmdview/Resources/viewer.html` | `render()` に `code` 分岐を追加 |
| `MmdviewApp/mmdview/Resources/style.css` | `.code-body` スタイルを追加 |
| `MmdviewApp/mmdview/App/AppDelegate.swift` | 安定システム UTI を追記 |
| `MmdviewApp/mmdview/Info.plist` | Source Code の DocumentType / UTI 宣言 |
| `MmdviewApp/mmdviewTests/` | FileType / ViewerBridge テスト更新 |
| `MmdviewApp/mmdview/Resources/viewer.test.js` | `renderCodeHtml` テスト追加 |

## 判断の記録

- **案 A（Swift 側で言語確定）を採用**: 拡張子リストはオープンパネルと
  Info.plist のためにどのみち Swift 側に必要であり、ext→言語マッピングを
  `FileType.swift` に集約すれば判定源が 1 箇所に保たれる。
  JS 側判定（案 B）は判定が 2 箇所に割れる。highlightAuto（案 C）は
  誤判定と性能の問題で不採用。
- **`.json` / `.yaml` / `.xml` を Phase 1 に含める**: 同梱 highlight.js が
  対応済みで追加コストがほぼゼロのため、当初 Phase 2 予定だった構造化形式も
  今回まとめて対応する。
