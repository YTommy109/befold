# テキスト読み込みデータフロー

<!-- constrained-by ./../../docs/superpowers/specs/2026-07-16-normalized-text-cache-design.md -->

本文書はテキストファイルの読み込みから表示までのデータフローを記録する。
現行フロー（LineChunkReader ベース）と新フロー（NormalizedTextCache + StringChunkReader ベース）の
両方を図示し、サイズ制限・エンコーディング対応の比較を含める。

## 用語

| 用語 | 意味 |
|------|------|
| 行指向 (line-oriented) | csv / tsv / code。行番号付きチャンク読み込みの対象 |
| 非行指向 | mermaid / markdown / svg / html / plaintext。全量を一括で読み込む |
| バイナリ | image / pdf。Base64 エンコードして表示する |

## 現行フロー（LineChunkReader ベース）

### 全体図

```
ViewerStore.reload()
  └─ computeLoad(url, fileType, ...)
       ├─ ファイル不在 → .missing
       ├─ バイナリ (image/pdf)
       │    └─ ContentLoader.load()
       │         サイズチェック(50MB) → Data読込 → base64エンコード
       │         → .full(base64)
       ├─ isBinary判定(NULバイト検出) → .full(unsupportedFormat)
       ├─ 行指向 (csv/tsv/code)
       │    └─ LineChunkReader(url, encoding)
       │         → readNextChunk()
       │         → .chunked(session, firstChunk, isAtEnd)
       └─ 非行指向テキスト (mermaid/md/svg/html/plaintext)
            └─ ContentLoader.load()
                 サイズチェック(10MB) → Data読込
                 → detectEncoding → BOM除去 → decodeText
                 → .full(text)
```

### LineChunkReader の内部フロー

```
init(url, encoding)
  ├─ FileHandle.init(forReadingFrom:)
  ├─ 先頭4バイト読込 → TextEncoding.detectBOM()
  ├─ encoding 引数 nil → 検出結果を使用 (UTF-8 フォールバック)
  ├─ TextEncoding.isChunkableEncoding() → UTF-8 以外は unsupportedForChunking エラー
  └─ BOM の後ろへシーク

readNextChunk()
  ├─ FileHandle から 1MB 読込
  ├─ 前回の remainder を先頭に結合
  ├─ 末尾から逆走査して最後の 0x0A (LF) を探す
  │    └─ LF なし → remainder に蓄積して次の 1MB 読込へ
  ├─ バイト列を走査して 0x22 (") を数え CSV 引用符状態を追跡
  ├─ 改行を数えて linesPerChunk (1000行) に達したら分割
  ├─ TextEncoding.trimIncompleteTail() でマルチバイト文字境界を保護
  ├─ 分割後のバイト列を remainder に保存
  └─ TextEncoding.decodeText(chunk, encoding) → (text, isAtEnd)
```

**責務の集中**: LineChunkReader は以下の 8 つの責務を一体処理する:

1. FileHandle 管理と I/O（1MB 単位の読み込み）
2. BOM 検出・スキップ
3. エンコーディング判定
4. バイトレベル改行走査（0x0A / 0x0D）
5. マルチバイト文字境界保護（trimIncompleteTail）
6. 1MB 強制分割
7. RFC 4180 引用符状態追跡（CSV のクォート内改行）
8. remainder バッファ管理

### 検索フロー（現行）

```
Cmd+F → _mmdOpenFind()
  ├─ _mmdIsTruncated == false
  │    └─ _mmdFindRun() → DOM TreeWalker で全文検索
  └─ _mmdIsTruncated == true
       ├─ postMessage("loadAllLinesForSearch")
       ├─ _mmdSetFindLoading(true) → 検索入力を無効化・"Loading…" 表示
       └─ Swift 側: 残チャンクをすべて読込
            ├─ readNextChunk() をループ
            ├─ 各チャンクを appendChunk() で DOM に追記
            └─ _mmdOnAllLinesLoaded() → _mmdSetFindLoading(false) → _mmdFindRun()
```

**問題**: 大きなファイルで Cmd+F すると全チャンクの DOM 構築が走り、UI がフリーズする (TASK-20)。
チャンク読み込み中に Cmd+F すると検索入力が "Loading…" のまま無効化される (TASK-24)。

### apply のフロー

```
apply(outcome)
  ├─ .missing → scheduleFileGone()
  ├─ .chunked(session, firstChunk, isAtEnd)
  │    ├─ chunkSession = session
  │    ├─ content = firstChunk
  │    ├─ isTruncated = !isAtEnd
  │    ├─ contentRevision += 1
  │    └─ newlineCount / displayedLineCount 更新
  └─ .full(loaded)
       ├─ chunkSession = nil
       ├─ content = loaded.content
       ├─ isTruncated = false
       └─ contentRevision += 1
```

## 新フロー（NormalizedTextCache + StringChunkReader ベース）

### 全体図

```
ViewerStore.reload()
  └─ computeLoad(url, fileType, ...)
       ├─ ファイル不在 → .missing
       ├─ バイナリ (image/pdf)
       │    └─ ContentLoader.load()
       │         サイズチェック(50MB) → Data読込 → base64エンコード
       │         → .full(base64, cache: nil)
       ├─ isBinary判定(NULバイト検出) → .full(unsupportedFormat, cache: nil)
       ├─ サイズチェック(100MB超) → .full(fileTooLarge, cache: nil)
       └─ テキスト (全種別)
            └─ NormalizedTextCache(data:)
                 Data全量読込 → detectEncoding → BOM除去
                 → デコード(1回) → CRLF/CR→LF正規化
                 → 行インデックス構築 → dataHash 計算
                 ├─ 行指向 (csv/tsv/code)
                 │    └─ StringChunkReader(cache, respectsCSVQuotes)
                 │         → readNextChunk()
                 │         → .chunked(session, cache, firstChunk, isAtEnd)
                 ├─ 非行指向テキスト
                 │    ├─ cache.text.utf8.count > 10MB → .full(fileTooLarge, cache: nil)
                 │    └─ → .full(content: cache.text, cache: cache)
                 └─ デコード失敗 → .full(unsupportedFormat, cache: nil)
```

### NormalizedTextCache の内部フロー

```
init(data:)
  ├─ data.isEmpty → text="", lineStartIndices=[], return
  ├─ dataHash = data のハッシュ値
  ├─ TextEncoding.detectEncoding(data)
  │    └─ 失敗 → throw decodeFailed
  ├─ BOM 除去 (data.dropFirst(bomLength))
  ├─ String(data:encoding:) でデコード (1回きり)
  │    └─ 失敗 → throw decodeFailed
  ├─ CRLF → LF, CR → LF に正規化
  └─ 行頭インデックス配列を構築
       text を走査し、各 LF の次の位置を記録
```

**特徴**: I/O・デコード・正規化がすべて init で完了する。
生成後はエラーが発生しない。UTF-16 / UTF-32 も含めすべてのエンコーディングに対応する。

### StringChunkReader の内部フロー

```
readNextChunk()
  ├─ currentLine >= lineCount → ("", true)
  ├─ startIndex = lineStartIndices[currentLine]
  ├─ respectsCSVQuotes == true
  │    └─ advanceRespectingQuotes()
  │         文字レベルで " を数え、引用符内の改行を行としてカウントしない
  │         linesPerChunk (1000) 論理行分を進める
  ├─ respectsCSVQuotes == false
  │    └─ endLine = currentLine + linesPerChunk
  ├─ endIndex = lineStartIndices[endLine] or text.endIndex
  ├─ chunk = text[startIndex ..< endIndex]
  └─ return (chunk, currentLine >= lineCount)
```

**特徴**: String スライスのみで I/O なし。バイト境界・マルチバイト保護が不要。
`readNextChunk()` は実質的に失敗しない。

### 検索フロー（新）

```
Cmd+F → _mmdOpenFind()
  └─ _mmdFindRun()
       DOM TreeWalker で表示済み範囲のみ検索
       _mmdIsTruncated == true の場合
         → 件数表示に "(表示範囲内)" を付加
```

**改善**: 全チャンク読み込みが不要。フリーズしない。
検索入力の無効化状態が発生しない。

### apply のフロー（新）

```
apply(outcome)
  ├─ .missing → scheduleFileGone()
  ├─ .chunked(session, cache, firstChunk, isAtEnd)
  │    ├─ cache.dataHash == contentHash → return (同一内容スキップ)
  │    ├─ textCache = cache
  │    ├─ contentHash = cache.dataHash
  │    ├─ chunkSession = session
  │    ├─ content = firstChunk
  │    ├─ isTruncated = !isAtEnd
  │    └─ contentRevision += 1
  └─ .full(loaded, cache)
       ├─ cache?.dataHash == contentHash → return (同一内容スキップ)
       ├─ textCache = cache
       ├─ contentHash = cache?.dataHash
       └─ (以降は現行と同じ)
```

**改善**: dataHash 比較による同一内容スキップで、
ファイル再保存のたびの無駄な再描画を防止する (TASK-23 対応)。

## 責務の比較

| 現行 LineChunkReader の責務 | 新アーキテクチャでの担当 |
|---|---|
| FileHandle 管理と I/O | NormalizedTextCache (init 時に全量読込) |
| BOM 検出・スキップ | NormalizedTextCache (init 時に 1 回) |
| エンコーディング判定 | NormalizedTextCache (init 時に 1 回) |
| バイトレベル改行走査 | 不要 (LF 正規化済み、行インデックス構築済み) |
| マルチバイト文字境界保護 | 不要 (String スライスなので文字が割れない) |
| 1MB 強制分割 | 不要 (行インデックスから直接スライス) |
| RFC 4180 引用符バイト走査 | StringChunkReader (文字レベル走査に簡略化) |
| remainder バッファ管理 | 不要 |

## サイズ制限

| ファイル種別 | 現行上限 | 新上限 | 判定場所 |
|------------|---------|--------|---------|
| バイナリ (image/pdf) | 50MB | 50MB (変更なし) | ContentLoader |
| 非行指向テキスト (mermaid/md/svg/html/plaintext) | 10MB | 10MB (変更なし) | computeLoad (ContentLoader.maxTextFileSizeBytes 参照) |
| 行指向テキスト (csv/tsv/code) | 上限なし | **100MB** | computeLoad (NormalizedTextCache.maxFileSizeBytes) |

行指向テキストに 100MB 上限を設ける理由: 現行は上限がなく OOM リスクがある。
100MB のテキストファイルは SSD からの読み込み＋デコードが 1 秒未満で完了する。

## エンコーディング対応

| エンコーディング | 現行フロー | 新フロー |
|----------------|-----------|---------|
| UTF-8 (BOM なし) | ✅ チャンク読み込み対応 | ✅ チャンク読み込み対応 |
| UTF-8 (BOM 付き) | ✅ チャンク読み込み対応 | ✅ チャンク読み込み対応 |
| UTF-16 LE (BOM 付き) | ❌ `unsupportedForChunking` エラー | ✅ チャンク読み込み対応 |
| UTF-16 BE (BOM 付き) | ❌ `unsupportedForChunking` エラー | ✅ チャンク読み込み対応 |
| UTF-32 LE (BOM 付き) | ❌ `unsupportedForChunking` エラー | ✅ チャンク読み込み対応 |
| UTF-32 BE (BOM 付き) | ❌ `unsupportedForChunking` エラー | ✅ チャンク読み込み対応 |
| Shift_JIS | ✅ 全量読み込み (非行指向パス) | ✅ チャンク読み込み対応 |
| EUC-JP | ✅ 全量読み込み (非行指向パス) | ✅ チャンク読み込み対応 |
| ISO-8859-1 (フォールバック) | ✅ デコードフォールバック | ✅ デコードフォールバック |

現行フローでは `isChunkableEncoding` が UTF-8 のみを許可するため、
UTF-16 / UTF-32 の行指向ファイルはチャンク読み込みに対応できない。
新フローでは全量デコード後に String スライスするため、エンコーディングによる制約がない。

## 既存バグへの影響

| タスク | 現行の問題 | 新フローでの状態 |
|--------|-----------|----------------|
| TASK-20 | 検索で全チャンク DOM 構築 → フリーズ | 設計で解消 (表示範囲のみ検索) |
| TASK-21 | 追記後に contentRevision 未同期で全文 render | 残存 (キャッシュ設計とは独立。修正容易) |
| TASK-22 | チャンク境界で改行消失 | Swift 側は解消 (LF 正規化＋行インデックス)。JS 側は別途修正 |
| TASK-23 | 同一内容でも再描画 | 設計で解消 (dataHash 比較でスキップ) |
| TASK-24 | 検索入力が "Loading…" のまま | 設計で解消 (全量読み込みが不要) |
| TASK-25 | チャンクエラーが偽装される | 設計で解消 (String スライスは失敗しない) |
| TASK-26 | detectEncoding 委譲で二重デコード | 設計で解消 (デコードは 1 回のみ) |
