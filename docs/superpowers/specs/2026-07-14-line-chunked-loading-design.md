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
2. **現行の段階読み込み（10MB バイト先読み + バックグラウンド全量読み込み）の欠陥**:
   コードレビューで、`fullLoadTask` の MainActor 隔離継承（全量読み込みが
   実際にはメインスレッドで走る）、キャンセル競合による古い内容の上書き、
   10–50MB バイナリの二重読み込み、マルチバイト文字の途中切断による
   mojibake の 4 件が CONFIRMED となった。

10MB のバイト先読みは「数ページ分のテキストが見えれば十分」という要件に
対して 2 桁過剰（約 16,000 行）でもあった。

## 決定事項（要件）

- 先読み（約 1,000 行）で表示は完結する。続きは**明示アクション**
  （「続きを読み込む」ボタン）で 1,000 行ずつ DOM に追記する。
  暗黙のバックグラウンド全量読み込みは行わない。
- 段階読み込みの対象は**行指向形式のみ**: CSV/TSV・コード・プレーンテキスト。
  Markdown/Mermaid/HTML は途中切断で描画が壊れるため対象外。
- 行指向形式は**ファイルサイズ上限を撤廃**する。プレビューコストが
  ファイル全体のサイズに依存しなくなるため。
- 将来の QuickLook 拡張は初回チャンク（先読み分）のみを表示する。

## 全体アーキテクチャ

```
ViewerStore ──(初回)──> ContentLoader.openChunked(url, fileType)
    │                        └─> ChunkedTextSession（LineChunkReader を保持）
    │                              ・先頭チャンクでエンコーディング確定
    │                              ・readNext(maxLines:maxBytes:) → (text, isAtEnd)
    ├──> render(content, type)          … 既存経路そのまま
    └──> バナー「続きを読み込む」ボタン
              └─ JS → script message handler → ViewerStore.loadMoreLines()
                        └─> 次チャンク読み → evaluateJavaScript("appendChunk(...)")
```

**非同期タスクを一切持たない。** 1 チャンク＝1,000 行は数百 KB 程度で、
読み込み＋デコードは数 ms のためメインスレッドで同期実行する。
これにより現行の `fullLoadTask` は実装ごと削除され、キャンセル管理・
actor 境界の問題（レビュー指摘のバグ 3 件）が構造的に消える。

## 読み込みポリシー

| 形式 | 経路 | サイズ上限 |
|---|---|---|
| CSV/TSV・コード・プレーンテキスト（行指向・UTF-8/ASCII） | チャンク読み（常時） | なし |
| 行指向・レガシーエンコーディング（Shift_JIS 等） | 全量デコード→DecodedTextChunkReader | 10MB |
| Markdown・Mermaid・HTML | 従来の一括読み | 10MB（main の挙動に戻す） |
| 画像・PDF（バイナリ） | 従来の一括読み | 50MB |

- 定数: `previewLineCount = 1000`、`chunkLineCount = 1000`、
  `maxChunkBytes = 4MB`（改行のない病的ファイル対策の安全弁。
  超過時はバイト上限で強制切断し 1 行として扱う）
- 行指向は**小さいファイルも同じチャンク経路を通す**。1,000 行未満なら
  初回チャンクで `isAtEnd = true` となり `isTruncated = false` で完結する。
  「truncated かどうか」の判定源が reader ひとつに一本化され、
  現行の `needsDeferred`（ViewerStore 側の二重判定）と `loadPreview`
  （`load` の分岐カスケードのコピペ）は両方削除される。

## コンポーネント詳細

### BefoldKit / `LineChunkReader`（新規）

- `FileHandle` で読み込みオフセットを保持し、
  `readNext(maxLines:maxBytes:)` が改行境界で切った `String` と
  `isAtEnd` を返す。
- エンコーディングは**先頭チャンクで一度だけ確定**する
  （BOM → UTF-8 → `TextEncoding.detectEncoding` のヒューリスティック）。
  以降のチャンクには確定したデコーダを固定適用する。
- **チャンク対象は UTF-8/ASCII のみ**。強制分割時に文字境界を保証できない
  レガシーエンコーディング（Shift_JIS / EUC-JP 等）および UTF-16/UTF-32 は
  `TextEncodingError.unsupportedForChunking` を投げ、
  `ContentLoader.loadDecodedText` で全量デコード（10MB 上限）した文字列を
  `DecodedTextChunkReader` で行チャンク配信するフォールバック経路に委ねる。
- UTF-8 チャンクの末尾がマルチバイト文字の途中で切れた場合は
  文字境界まで戻して残りを次チャンクに繰り越す（mojibake 指摘の解消）。

### `ContentLoader`

- `load`（既存・非行指向用）と `openChunked`（新設）の 2 経路。
  `loadPreview` は削除する。
- 将来の QuickLook 拡張は `openChunked` の初回チャンクのみ使用する。

### `ViewerStore`

- `loadMoreLines()`（`@MainActor` 同期）: 次チャンクを読み、`content` に
  蓄積した上で `appendChunk` を JS へ送る。全文を `content` に蓄積するため
  ソースモード切替や再描画は既読分の一括 render で成立する。
- `isTruncated` は `reader.isAtEnd` の否定から導出する（独自状態を持たない）。
- FileWatcher 発火時はセッションを破棄し先頭チャンクから再表示する。
  追記読み込み位置とファイル変更の整合は取らない（最もシンプルな整合性担保）。

### viewer.html / JS

- `appendChunk(text)`: CSV は `<tbody>` に行を追加、コード/テキストは
  `<pre>` 末尾に追記する（コードはチャンク単体で highlight する）。
- バナー刷新: 「N 行を表示中・続きあり」＋「続きを読み込む」ボタン。
  文言は `ViewerBridge` 経由でローカライズ済み文字列（xcstrings, en+ja）を
  渡す。HTML への日本語ハードコードはしない。
- ボタン → script message handler（パス参照クリック等の既存パターンを踏襲）
  → `ViewerStore.loadMoreLines()`。

## エラー処理

- エンコーディング推定失敗・デコード不能チャンク →
  既存 `RejectReason.unsupportedFormat` を表示する。
- 読み込み途中のファイル削除・縮小 → `readNext` がエラーを返し、
  既存の削除ハンドリング（ウィンドウ側）に委譲する。

## テスト

- `LineChunkReader`: 行数境界・CP932 実データ・UTF-8 途中切断の繰り越し・
  改行なし巨大行（`maxChunkBytes` 切断）・`isAtEnd` 判定
  （実ファイル + Swift Testing）。
- `ContentLoader`: 行指向/非行指向の経路分岐と、読み込みポリシー表の全セル
  （各形式 × 上限内/上限超過）。
- `ViewerStore`: `loadMoreLines` の状態遷移、FileWatcher 発火時のリセット。
  10–50MB 帯のバイナリ表示のカバレッジ（レビューで喪失が指摘された
  `imageOverTextSizeLimitStillLoads` 相当）を復活させる。
- テストダブル（`InMemoryFileReader`）の行切断ロジックは本体と共有
  ヘルパー化し、再実装によるドリフトを防ぐ。
- JS 側は `/webview-smoke` での手動確認（既存規約どおり）。

## 期待される効果

- UTF-8 の大容量 CSV: 初回 1,000 行が瞬時に表示され、
  以降はボタンを押した分だけ DOM が増える。
  レガシーエンコーディングは 10MB 以下なら全量デコード後にチャンク配信される。
- レビューで CONFIRMED となった正確性バグ 4 件（MainActor 継承・
  キャンセル競合・バイナリ二重読み込み・mojibake）がすべて構造的に解消。
- `needsDeferred` / `loadPreview` / `fullLoadTask` の削除により、
  読み込み判定の情報源が一本化される。
