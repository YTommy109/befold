# テキスト読み込みアーキテクチャ刷新: NormalizedTextCache 設計

<!-- supersedes ./2026-07-14-line-chunked-loading-design.md -->

## 背景

v1.7.0 で導入した `LineChunkReader` は、バイトレベルで
エンコーディング検出・改行走査・チャンク分割を一体処理する設計になっている。
この設計は 8 件の修正・改善（TASK-2, 5, 8, 9, 14, 15, 16, 17）を経て
6 件の新バグ（TASK-20〜25）を生む連鎖を引き起こした。

| 修正タスク | 導入した退行 |
|-----------|------------|
| TASK-9（二重保持解消 → contentRevision） | TASK-21（追記後に全文render）, TASK-23（同一内容で再描画） |
| TASK-17（検索で全チャンク読込） | TASK-20（検索フリーズ）, TASK-24（検索入力が無効化のまま） |
| TASK-14（チャンク境界ハイライト） | TASK-22（境界の改行消失が露呈） |
| TASK-2（エンコーディング単一情報源化） | TASK-26（二重デコード） |

根本原因は、`LineChunkReader` がバイトレベルで以下の責務を同時に担っていること:

- FileHandle 管理と I/O
- BOM 検出・スキップ
- エンコーディング判定
- バイトレベル改行走査（0x0A/0x0D）
- マルチバイト文字境界保護（trimIncompleteTail）
- 1MB 強制分割
- RFC 4180 引用符状態追跡
- remainder バッファ管理

個別パッチでは問題が別の箇所に移るだけで、構造的な解決にならない。

## 決定事項（要件）

- **エンコーディング・改行コードの問題をチャンク処理から完全に分離する**。
  デコード＋改行正規化した String をメモリにキャッシュし、
  チャンク切り出しは String スライスで行う。
- 行指向ファイルの**サイズ上限を 100MB** に設定する。
  現行は上限なし（OOM リスクあり）。100MB のテキストファイルは
  SSD からの読み込み＋デコードが 1 秒未満で完了する。
- **UTF-16 / UTF-32 の行指向ファイルにも対応する**。
  現行は `unsupportedForChunking` で拒否しているが、
  全量デコード後は String なのでチャンク分割に制約がない。
- 先読み 1,000 行＋明示アクションで追記する UI 動作は
  前設計（2026-07-14-line-chunked-loading-design.md）を踏襲する。
- **検索を Swift 側の String 検索に移行する**。
  DOM 全量構築による検索フリーズ（TASK-20）を設計で解消する。

## 全体アーキテクチャ

### 現行フロー

```
File (bytes)
  → LineChunkReader
      BOM検出 + encoding判定 + 改行バイト走査 + quote追跡
      + 文字境界保護 + チャンク分割 (すべてバイトレベルで一体処理)
  → String chunks
  → ViewerStore.content (逐次蓄積)
  → JS render / appendChunk
```

### 新フロー

```
File (bytes)
  → NormalizedTextCache
      全量読み込み + encoding判定 + デコード + CRLF/CR→LF 正規化
      + 行インデックス構築 (1回きり)
  → StringChunkReader
      行インデックスから String スライス (純粋な文字列操作)
  → ViewerStore.content (逐次蓄積、キャッシュも保持)
  → JS render / appendChunk
```

## コンポーネント設計

### NormalizedTextCache

BefoldKit に追加する新しい構造体。
ファイル読み込み・デコード・正規化の責務を一箇所に集約する。

```swift
public struct NormalizedTextCache: Sendable {
    public static let maxFileSizeBytes = 100 * 1024 * 1024

    /// デコード＋正規化済みの全文（CRLF/CR → LF 済み）
    public let text: String

    /// 各行の先頭オフセット（text 内の String.Index）。
    /// lineStartIndices[0] = text.startIndex,
    /// lineStartIndices[n] = n 行目の先頭。
    public let lineStartIndices: [String.Index]

    /// 総行数
    public var lineCount: Int { lineStartIndices.count }
}
```

**責務**:

1. `Data(contentsOf:)` で全量読み込み
2. `TextEncoding.detectEncoding` でエンコーディング判定（1 回のみ）
3. BOM を除去してデコード（1 回のみ）
4. CRLF / CR → LF に正規化
5. 行頭インデックスの配列を構築

**エラー処理**: ファイルサイズ超過・デコード失敗は
キャッシュ生成時に確定する。キャッシュ生成後のチャンク操作ではエラーが発生しない。

**UTF-16/UTF-32 対応**: `isChunkableEncoding` チェックが不要。
全量デコード後は String なので、どのエンコーディングでも同じように扱える。

### StringChunkReader

`LineChunkReader` を置き換える。`ChunkedTextReading` プロトコルを実装する。

```swift
public actor StringChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000

    private let cache: NormalizedTextCache
    private let respectsCSVQuotes: Bool
    private var currentLine: Int = 0
}
```

**責務**: キャッシュの `lineStartIndices` を使い、
`currentLine` から `linesPerChunk` 行分の String スライスを返す。

CSV の `respectsCSVQuotes` が true の場合、引用符内の改行を
行としてカウントしない。ただし対象は正規化済み String の文字走査であり、
バイト境界・マルチバイト保護は一切不要。

**`readNextChunk()` は実質的に失敗しない**:
I/O もデコードもないため。`ChunkedTextReading` プロトコルの
`throws` 宣言はそのまま維持し、`LineChunkReader` 削除後にプロトコルを整理する。

### LineChunkReader との比較

| 現行 LineChunkReader の責務 | StringChunkReader |
|---|---|
| FileHandle 管理 | 不要（キャッシュ参照のみ） |
| BOM 検出・スキップ | 不要（キャッシュ生成時に完了） |
| エンコーディング判定 | 不要 |
| バイトレベル改行走査 (0x0A/0x0D) | 不要（LF 正規化済み、行インデックス構築済み） |
| マルチバイト文字境界保護 | 不要（String スライスなので文字が割れない） |
| 1MB 強制分割 | 不要（行インデックスから直接スライス） |
| RFC 4180 引用符バイト走査 | String の文字走査に簡略化 |
| remainder バッファ管理 | 不要 |

## ViewerStore 統合

### computeLoad の変更

```
computeLoad
  ├─ binary (image/pdf) → ContentLoader.load (変更なし)
  └─ text (全種別)
       ├─ isBinary 判定 → .full(unsupportedFormat)
       ├─ fileSize > 100MB → .full(fileTooLarge)
       ├─ NormalizedTextCache(url:) デコード失敗 → .full(unsupportedFormat)
       └─ 成功
            ├─ isLineOriented → StringChunkReader(cache)
            │     → .chunked(session, firstChunk, isAtEnd)
            └─ else
                  ├─ cache.text.utf8.count > 10MB → .full(fileTooLarge)
                  └─ → .full(content: cache.text)
```

### キャッシュの保持

`NormalizedTextCache` を `ViewerStore` のプロパティとして保持する。
`LoadOutcome.chunked` にキャッシュを含め、`apply()` で保存する。
非行指向テキストの `.full` パスでもキャッシュを保持する
（検索や同一内容スキップで使う）。

- 検索（後述）でキャッシュの全文テキストを直接使うため
- 同一内容スキップでキャッシュのハッシュを比較するため
- ファイル再読込時にキャッシュを差し替える
- `close()` でキャッシュを解放する

### 同一内容スキップ（TASK-23 対応）

キャッシュ生成時にファイル `Data` のハッシュを計算して保持する。
`apply()` 時に前回のハッシュと比較し、同一なら `contentRevision` を増分しない。
全文の String 比較より軽量で確実。

### ContentLoader の役割縮小

テキストのデコードは `NormalizedTextCache` に移る。
`ContentLoader` はバイナリファイル（image/pdf）の base64 エンコードと
サイズチェック＋ `isBinary` 判定のみに責務が限定される。

### サイズ制限の整理

| ファイル種別 | 上限 | 判定場所 |
|------------|------|---------|
| バイナリ (image/pdf) | 50MB | ContentLoader（現行通り） |
| 非行指向テキスト (mmd/md/svg/html) | 10MB | computeLoad（現行通り） |
| 行指向テキスト (csv/code) | 100MB | NormalizedTextCache（新設） |

## 検索の改善（TASK-20 対応）

### 方針

DOM 全量構築による検索を廃止し、
キャッシュの String を Swift 側で検索する。

### 新フロー

```
Cmd+F → JS: postMessage("findInText", {query, options})
  → Swift: cache.text 上で String 検索
  → マッチ位置（行番号 + オフセット）の配列を JS に返す
  → JS: 表示済み DOM 内のマッチのみハイライト、
        未表示マッチは件数表示
```

### 設計判断

- **検索は Swift 側で実行する**: `cache.text` は正規化済み String。
  `NSRegularExpression` で高速に検索可能。DOM 構築が不要。
- **DOM への全量追記をやめる**: 表示済みチャンク内のマッチのみハイライトし、
  未表示部分は件数だけ報告する。
- **マッチ間ナビゲーション**: 未表示領域のマッチへの移動時は、
  その周辺チャンクのみを DOM に追記してスクロールする。

### スコープ

検索の Swift 側移行は JS 側の大幅な書き換えを伴う。
初期実装では「表示済み範囲のみ検索 + 件数表示」で出し、
マッチ間ナビゲーションの最適化は後続タスクとする。

## 既存 backlog タスクへの影響

| タスク | 影響 | 理由 |
|--------|------|------|
| TASK-20 (検索フリーズ) | **設計で解消** | Swift 側 String 検索に移行。DOM 全量構築が不要 |
| TASK-21 (追記後に全文render) | **残存** | Coordinator の revision 未更新が原因。キャッシュ設計とは独立。ただし修正容易 |
| TASK-22 (チャンク境界の改行消失) | **Swift 側は解消、JS 側は残存** | LF 正規化＋行インデックス分割で Swift 側は解消。viewer.js の末尾改行消失は別途修正 |
| TASK-23 (同一内容で再描画) | **設計で解消** | ハッシュ比較で同一内容なら contentRevision を増分しない |
| TASK-24 (検索入力が無効化のまま) | **設計で解消** | 検索が Swift 側 String 操作になり、チャンク読み込みとの競合が消える |
| TASK-25 (エラーの偽装) | **設計で解消** | チャンク切り出しは String スライスで失敗しない。エラーはキャッシュ生成時に確定 |
| TASK-26 (二重デコード) | **設計で解消** | デコードは NormalizedTextCache 生成時の 1 回のみ |

## 削除対象のコード

- `LineChunkReader`（`StringChunkReader` に置き換え）
- `TextEncoding.trimIncompleteTail` / `trimIncompleteUTF8Tail`（マルチバイト境界保護が不要）
- `TextEncoding.isChunkableEncoding`（UTF-16/UTF-32 も対応するため不要）
- `TextEncodingError.unsupportedForChunking`（上記に伴い不要）
- viewer.js の `loadAllLinesForSearch` / `_mmdOnAllLinesLoaded`（Swift 側検索に移行）

## 維持するコード

- `TextEncoding.detectEncoding` / `detectBOM`（NormalizedTextCache が使う）
- `TextEncoding.decodeText`（NormalizedTextCache 内部で使用、呼び出しは 1 箇所に集約）
- `ChunkedTextReading` プロトコル（StringChunkReader が実装）
- `ContentLoader`（バイナリファイル用に縮小して維持）
- viewer.js の `render` / `appendChunk`（チャンク追記の DOM 操作は維持）

## テスト方針

- **NormalizedTextCache**: 各エンコーディング（UTF-8, UTF-8 BOM, UTF-16 LE/BE,
  UTF-32 LE/BE, Shift_JIS, EUC-JP）× 各改行コード（LF, CRLF, CR）の
  組み合わせで正規化結果を検証。行インデックスの正確性。サイズ超過の拒否。
- **StringChunkReader**: 行数ベースのチャンク分割。CSV 引用符内改行の扱い。
  最終チャンクの isAtEnd。空ファイル。
- **ViewerStore 統合**: 既存の ViewerStore テストを NormalizedTextCache ベースに移行。
  同一内容スキップ。キャッシュの生成エラー時の LoadOutcome。
- **既存テストの移行**: LineChunkReader のテストを StringChunkReader 用に書き換え。
  テストの意図（エンコーディング対応、チャンク境界）は維持し、
  バイトレベルの実装詳細に依存するテストは削除。
