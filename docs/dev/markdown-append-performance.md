# Markdown の追記性能を測る

<!-- derived-from ./rules/testing.md -->

`scripts/benchmark-markdown-append.swift` は本番 Resources を独立した WKWebView で読み、
`appendChunk()` の処理と直後の強制レイアウトを測る任意実行ハーネス。
新しい依存や CI の時間閾値は追加しない。正しさの回帰は既存の Jest で検証する。

## Mermaid

初めに図を 1 個描き、125% に拡大してから、図を 1 個含む小さい Markdown を 19 回追記する。
既存の図が追記ごとに再ラップされる負荷を切り分けるための入力で、アプリの
1,000 行チャンクやファイル読み込みを再現するものではない。

`appendChunk()` は同期 API なので、新しい図に SVG とズームラッパーが揃うまで
MutationObserver で待つ。本番 bundle に計測フックは挿入しない。
図の数・既存ラッパーの同一性・保存された倍率が変われば失敗する。ラッパー数と入れ子の数は
変更前の不具合も比較できるよう記録値とし、修正後はそれぞれ 20 と 0 を確認する。

## パス参照

`paths` はパス参照・太字・インラインコードを含む段落を 15,000 個描画した後、
500 段落ずつ 10 回追記する。読み込み済み本文が多い状態での追加処理を切り分ける。
最後の 20,000 段落の本文と参照数を独立した期待値と照合し、元の DOM の同一性も確認する。
最終 HTML と本文の SHA-256 を出力するため、新旧の同一性は時間とは別に確認できる。

最適化の対象はパスを注釈する走査。参照解決の対象収集や Mermaid の要素検索など、
蓄積済み DOM を調べる別の処理もあるため、追記全体が追記量だけに比例するとは限らない。

## 実行と比較

```sh
mkdir -p .tmp/markdown-append
swiftc scripts/benchmark-markdown-append.swift -o .tmp/markdown-append/benchmark
git archive origin/main BefoldApp/BefoldKit/Resources | tar -x -C .tmp/markdown-append
.tmp/markdown-append/benchmark .tmp/markdown-append/BefoldApp/BefoldKit/Resources mermaid > .tmp/markdown-append/before.jsonl
.tmp/markdown-append/benchmark BefoldApp/BefoldKit/Resources mermaid > .tmp/markdown-append/after.jsonl
```

パス参照は末尾の `mermaid` を `paths` に替えて実行する。2 つの修正の寄与を分けるには、
Mermaid 修正の親とそのコミットを `mermaid` で、パス参照修正の親とそのコミットを `paths` で比較する。

比較元の ref は測定対象に合わせて選ぶ。前後を交互に各 3 回以上測り、中央値と最大値を報告する。
別のビルドや性能計測を並走させない。入力・Resources の SHA-256、OS、WebKit user agent、
viewport、visibility は JSONL に記録される。入力はハーネス内の固定文字列から生成する。

所要時間は各追記の開始から完了確認・強制レイアウトまでの合計。
初回描画・ファイル I/O・Swift 側の参照解決・フレーム提示時間は含まない。
180 秒のタイムアウト、WebKit 終了、読み込み失敗、描画エラーは非ゼロ終了する。
