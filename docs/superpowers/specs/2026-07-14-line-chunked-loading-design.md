# 行指向テキストのチャンク読み込み設計

<!-- supersedes ../plans/2026-07-14-large-text-deferred-loading.md -->
<!-- constrained-by ../plans/2026-07-11-quicklook-prep-refactor.md -->

## 背景

22.1MB / 35,510 行 / CP932 エンコードの CSV
（`R06_chitankouhi_240401.csv`）が表示できなかった。原因は 2 つ:

1. **DOM の爆発**: CSV は全行を HTML `<table>` に変換して一括 `innerHTML`
   する実装で、このファイルでは約 170 万セルの table を一度に構築する。
   これは WKWebView に限らずどのブラウザでも固まるサイズであり、
   ボトルネックはファイル読み込みではなく DOM 構築にある。
2. **初期実装の段階読み込みの欠陥**:
   コードレビューで、`fullLoadTask` の MainActor 隔離継承（全量読み込みが
   実際にはメインスレッドで走る）、キャンセル競合による古い内容の上書き、
   10–50MB バイナリの二重読み込み、マルチバイト文字の途中切断による
   mojibake の 4 件が CONFIRMED となった。
   さらに、レガシーエンコーディング（Shift_JIS 等）を全量デコード経由で
   処理する設計に 10MB 上限があり、きっかけとなった 22MB CP932 CSV が
   依然として表示できない矛盾があった。

## 決定事項（要件）

- 先読み（約 1,000 行）で表示は完結する。続きは**明示アクション**
  （「続きを読み込む」ボタン）で 1,000 行ずつ DOM に追記する。
  暗黙のバックグラウンド全量読み込みは行わない。
- 段階読み込みの対象は**行指向形式のみ**: CSV/TSV・コード・プレーンテキスト。
  Markdown/Mermaid/HTML は途中切断で描画が壊れるため対象外。
- 行指向形式は**エンコーディングに関わらずファイルサイズ上限を撤廃**する。
  プレビューコストがファイル全体のサイズに依存しなくなるため。
- 非行指向テキスト（Markdown/Mermaid/HTML）は 10MB 上限を維持する。
  DOM 構築がボトルネックとなりブラウザが固まるため。
- 将来の QuickLook 拡張は初回チャンク（先読み分）のみを表示する。

## 全体アーキテクチャ

```
ViewerStore
  │
  ├─ FileType(拡張子)─── isLineOriented? ───┐
  │                                          │
  ├─(行指向)─> LineChunkReader(url)          │
  │              ├─ プローブ(8KB): バイナリ判定・エンコーディング・改行検出
  │              ├─ readNextChunk() → (text, isAtEnd)
  │              └─ min(1000行, 1MB) でストリーム読み
  │     ├──> render(content, type)
  │     └──> バナー「続きを読み込む」ボタン
  │               └─ JS → ViewerStore.loadMoreLines()
  │                         └─> 次チャンク → evaluateJavaScript("appendChunk(...)")
  │
  └─(非行指向)─> Task { contentLoader.load() }  ← キャンセル可能
```

**行指向チャンクは同期実行。** 1 チャンク＝1,000 行は数百 KB 程度で、
読み込み＋デコードは数 ms のためメインスレッドで同期実行する。
非行指向の全量読み込みはバックグラウンド Task で実行し、キャンセル可能とする。

## 処理フロー

1. **FileType 判定**（拡張子、I/O なし）
   - バイナリ形式（image/pdf）→ 既存経路（変更なし）
   - テキスト形式 → 2 へ
2. **行指向判定**（`FileType.isLineOriented`、拡張子で即決）
   - **行指向** → 3a へ
   - **非行指向** → 3b へ
3a. **LineChunkReader 生成**（プローブ 8KB を 1 回読み）
   - バイナリ内容検出（NUL）→ リジェクト
   - エンコーディング確定（BOM → UTF-8 → ヒューリスティック）
   - UTF-16/UTF-32 → リジェクト（改行バイトが多バイト列に出現するため）
   - それ以外（UTF-8/ASCII/Shift_JIS/EUC-JP 等）→ チャンク読み開始
3b. **非行指向テキスト**
   - `Task` でバックグラウンド一括読み込み（10MB 上限、キャンセル可能）

## 読み込みポリシー

| 形式 | 経路 | サイズ上限 |
|---|---|---|
| 行指向テキスト（全エンコーディング） | チャンク読み | なし |
| Markdown・Mermaid・HTML（非行指向） | バックグラウンド一括読み | 10MB |
| 画像・PDF（バイナリ） | 従来の一括読み | 50MB |

- 定数: `linesPerChunk = 1000`、`maxChunkBytes = 1MB`
  （改行のない病的ファイル対策の安全弁。超過時はバイト上限で
  強制切断し 1 行として扱う）
- 行指向は**小さいファイルも同じチャンク経路を通す**。1,000 行未満なら
  初回チャンクで `isAtEnd = true` となり `isTruncated = false` で完結する。
  「truncated かどうか」の判定源が reader ひとつに一本化される。

## コンポーネント詳細

### BefoldKit / `LineChunkReader`

- `FileHandle` で読み込みオフセットを保持し、
  `readNextChunk()` が改行境界で切った `String` と `isAtEnd` を返す。
- エンコーディングは**先頭プローブ（8KB）で一度だけ確定**する
  （BOM → UTF-8 → `TextEncoding.detectEncoding` のヒューリスティック）。
  以降のチャンクには確定したデコーダを固定適用する。
- **UTF-16/UTF-32 のみ対象外**（改行バイト 0x0A/0x0D が多バイト列中に
  出現し、バイト走査で行境界を確定できないため）。
  UTF-8/ASCII/Shift_JIS/EUC-JP 等はすべてチャンク読みの対象とする。
  Shift_JIS/EUC-JP では 0x0A/0x0D がトレイルバイト範囲外のため、
  バイト走査による行分割がそのまま正しく動作する。
- **バイト境界保護**: チャンク末尾がマルチバイト文字の途中で切れた場合、
  UTF-8 は既存の `trimIncompleteUTF8Tail` で文字境界まで戻す。
  レガシーエンコーディングはデコード試行＋末尾バイト切り詰めリトライで
  汎用的に対処する（最大 3 バイトのリトライで解決し、1MB チャンクに対して
  無視できるコスト）。

### `ContentLoader`

- `load`（既存・非行指向テキスト＋バイナリ用）のみ。
  `loadDecodedText` は削除する（全量デコードフォールバック経路の廃止）。

### `DecodedTextChunkReader`

- **削除**。全エンコーディングが `LineChunkReader` を直接通るため不要。

### `ViewerStore`

- `loadMoreLines()`（`@MainActor`）: 次チャンクを読み、`content` に
  蓄積した上で `appendChunk` を JS へ送る。全文を `content` に蓄積するため
  ソースモード切替や再描画は既読分の一括 render で成立する。
- `isTruncated` は `reader.isAtEnd` の否定から導出する（独自状態を持たない）。
- `computeLoad` の行指向パス: `chunkedReaderFactory` のみ。
  `TextEncodingError` 時の `loadDecodedText` フォールバックを削除し、
  リジェクトとする。
- FileWatcher 発火時はセッションを破棄し先頭チャンクから再表示する。

### viewer.html / JS

- `appendChunk(text)`: CSV は `<tbody>` に行を追加、コード/テキストは
  `<pre>` 末尾に追記する（コードはチャンク単体で highlight する）。
- バナー刷新: 「N 行を表示中・続きあり」＋「続きを読み込む」ボタン。
  文言は `ViewerBridge` 経由でローカライズ済み文字列（xcstrings, en+ja）を
  渡す。HTML への日本語ハードコードはしない。
- ボタン → script message handler → `ViewerStore.loadMoreLines()`。

## エラー処理

- エンコーディング推定失敗・デコード不能チャンク →
  既存 `RejectReason.unsupportedFormat` を表示する。
- UTF-16/UTF-32 テキスト → `unsupportedForChunking` → リジェクト。
- 読み込み途中のファイル削除・縮小 → `readNextChunk` がエラーを返し、
  既存の削除ハンドリング（ウィンドウ側）に委譲する。

## 既知の制限

- **`maxQuotedFieldBytes`（500 バイト）を超える引用符付き CSV フィールド**:
  `StringChunkReader` は行内の `"` 出現を走査して `inQuotes` 状態を
  チャンクをまたいで維持するが、開いたクォートが 500 バイト
  （`maxQuotedFieldBytes`）を超えても閉じられない場合は不均衡クォートとみなし、
  `inQuotes` を強制的に `false` へリセットして通常の行ベース分割に復帰する
  （`StringChunkReader.swift` の `advanceRespectingQuotes` 内、
  `quotedRunLength` 判定を参照）。この閾値はチャンク境界（`maxChunkBytes`
  = 1MiB）とは無関係に、CSV セルの実長に基づいて判定する。
  そのため 500 バイトを超える正当な複数行クォートフィールドは、
  対のない引用符と区別できず途中で `inQuotes` が失われ、
  JS 側 `parseCsv`/`tokenizeCsvRows`（viewer.js）はチャンクをまたぐ
  引用符状態を持たないため、当該論理行は不正な複数行として描画される。
  RFC 4180 の引用フィールドが 500 バイトを超えるケースは現実的にまれであり、
  対応する場合は Swift→JS 間に新しい継続状態フラグを追加し、
  `appendChunk` の CSV 分岐に直前チャンク最終行とのマージ処理
  （コード分岐が強制分割継続に対して持つ処理と同様のもの）を追加する必要がある。
  現時点では対応せず既知の制限とする。

## テスト

- `LineChunkReader`: 行数境界・**CP932 実データのチャンク読み**・
  UTF-8 途中切断の繰り越し・レガシーエンコーディングの
  バイト境界保護（デコードリトライ）・
  改行なし巨大行（`maxChunkBytes` 切断）・`isAtEnd` 判定
  （実ファイル + Swift Testing）。
- `ContentLoader`: 行指向/非行指向の経路分岐。
- `ViewerStore`: `loadMoreLines` の状態遷移、FileWatcher 発火時のリセット。
  10–50MB 帯のバイナリ表示のカバレッジを維持する。
- テストダブル（`InMemoryFileReader`）の行切断ロジックは本体と共有
  ヘルパー化し、再実装によるドリフトを防ぐ。
- JS 側は `/webview-smoke` での手動確認（既存規約どおり）。

## 期待される効果

- **全エンコーディングの大容量 CSV**: 初回 1,000 行が瞬時に表示され、
  以降はボタンを押した分だけ DOM が増える。
  22MB CP932 CSV（本機能のきっかけ）も表示可能になる。
- レビューで CONFIRMED となった正確性バグ 4 件（MainActor 継承・
  キャンセル競合・バイナリ二重読み込み・mojibake）がすべて構造的に解消。
- `DecodedTextChunkReader` / `loadDecodedText` の削除により、
  読み込み経路が行指向チャンク or 非行指向一括の 2 本に単純化される。
