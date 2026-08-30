# ADR 0009: PDF を WebKit 内蔵プラグインではなく PDFKit で描き、描画面を 2 枚にする

- ステータス: Accepted
- 日付: 2026-08-29
- backlog decision: decision-9
- 関連タスク: TASK-564, TASK-564.1, TASK-564.6

<!-- constrained-by ./0002-presentation-state-and-capabilities.md -->

## Context

### これまでの描き方（TASK-564.1 着手前）

PDF は他の種別と同じく viewer.html の中で描いていた。読み込みは
`ContentLoader.load` が Data を base64 文字列にし、`ViewerLoadPipeline.load` が
`FileType.isBinaryContent` で分岐してその経路へ流す。viewer 側は
`renderers.ts` の `_renderPdf` が base64 をバイト列へ戻して `Blob` を作り、
その blob URL を `<iframe>` の `src` に入れる。実際に描くのは WebKit 内蔵の
PDF プラグインで、befold からは中が見えない。

この構造には、TASK-564 が並べた 4 つの機能（1 ページのフィット表示、
ページ単位のスクロール、表示位置の記憶、90 度単位の回転）のどれも載らない。
`<iframe>` の中の描画は同一オリジンではなく、ページ・倍率・スクロール位置に
触る API が無い。倍率でさえ CSS zoom が効かず、`zoom.ts` は
`pdf-body` クラスを見て「iframe 自体の width/height を倍率で変える」という
特例で代用していた（幅フィット描画なので幅を広げると拡大されるという間接的な効果）。

### プラグインから何が触れるか（実測 / 2026-08-30 時点）

上の「触る API が無い」は、TASK-567 の途中で改めて実測して確かめた。`WKWebView` に
PDF を `loadFileURL` で読ませ、JavaScript から見えるものを数えた結果は次のとおり。

| 式 | 結果 | 意味 |
| --- | --- | --- |
| `document.body` | 存在する | プラグインを載せるために合成された HTML |
| `document.embeds.length` | 1 | PDF は `<embed>` として 1 個ぶら下がる |
| `window.scrollY` | 0 | 中でスクロールしても host 側は動かない |
| `document.title` | 空 | 文書の情報は出てこない |

**中身はスクリプトから見えない。** ページ番号・スクロール位置・倍率・回転のいずれも
読めず、書けない。したがって TASK-564 の 4 機能のうち**表示位置の記憶**（現在位置を
読む必要がある）と**90 度回転**（回転させる手段が無い）は、プラグイン経由では原理的に
実装できない。ページ送りだけは `#page=N` のフラグメントで一方向に指示できる可能性が
あるが、読み戻せないので位置の記憶には使えない。

### 選択肢

1. **PDFKit（`PDFView`）で描く。** ページ・倍率・スクロール位置・回転が
   すべて公開 API にある。macOS 標準の PDF 表示そのもので、追加の同梱物は無い。
2. **pdf.js を同梱し、viewer.html の中で描く。** 描画面は 1 枚のままで、
   ズーム・検索・スクロールが既存の JS 経路に載る。
3. **`<iframe>` のまま、できることだけ諦める。**

## Decision

**PDFKit の `PDFView` で描く。** viewer.html 側の PDF 専用コードは撤去する。

pdf.js を採らなかった理由は 2 つある。

- **同梱物が増える。** viewer のバンドルは既に 816KB（`viewer-bundle.js`）で、
  mermaid・markdown-it・highlight.js・DOMPurify を抱えている。pdf.js は
  本体に加えてワーカーとフォントを持ち、`check-third-party-licenses` と
  `check-vendored-deps` の監査対象がもう 1 つ増える。macOS が同じ品質の
  描画エンジンを標準で持っているのに、同じものを 2 つ抱えることになる。
- **CSP を緩める必要がある。** pdf.js はワーカーを起動し、フォントと画像を
  自前で組み立てる。viewer.html の CSP は `default-src 'none'` から始めて
  必要なものだけを開けており、`worker-src` と `blob:` を足すのは
  この方針を逆に進めることになる。今回はむしろ `frame-src blob:` を
  **削れた**（PDF のためだけに開けていた唯一の穴だった）。

**代償は、描画面が 2 枚になること。** WKWebView と `PDFView` が同じ窓に並び、
どちらを見せるか・どちらへ命令を届けるかの判断が生まれる。この判断が
メニュー・ツールバー・コマンドへ散ると ADR 0002 段 2 の「条件は 1 箇所」が
崩れるため、次の形に閉じた。

- **宛先の決定は `DocumentSurfaces` の 2 メソッドだけが持つ。**
  `operating(on:)` が「いま描いている 1 枚」を返し、`syncingAll` が
  「すべての面」を返す。`DocumentCommandController` は種別を見ない。
- **`DocumentRendering`（ADR 0002 段 4 の port）を 2 群に分けた**（TASK-564.6）。
  ユーザー操作（ズーム・印刷・検索・ジャンプ・スクロール位置）は 1 枚へ振り分け、
  追随（フォント・CSV 数値表示・ジャンプ可否・リネーム）は全部へ配る。
  追随を振り分けると、PDF を見ている間の設定変更が WebView へ入らない形と、
  対応形式が変わるリネームで旧側の面が追随しない形（TASK-401 / TASK-393）が戻る。
- **振り分けの真実の源は `ViewerContentState.fileType`。**
  提示予定の URL（`ViewerStore.pendingURL`）から導くと、`openFile` の入口で
  URL だけが先に進むため、切替直後に「画面には旧ファイルが出ているのに
  命令は新しい面へ飛ぶ」区間ができ、命令が無言で捨てられる。
- **面は破棄・再生成しない。** 種別が変わっても両方を階層に残し、重ね順で
  出し分ける（差し替えると白フラッシュと stale な初期倍率が出る / TASK-266）。

読み込み経路も分けた。**PDF だけ `Data` のまま運ぶ**（`ViewerLoadPipeline.Outcome`
の `.binary`）。`PDFView` は `Data` を直接受けられ、base64 は約 1.33 倍に膨らむ。
画像は `data:` URI として JS へ渡すため base64 のままにする。サイズ上限（50MB）・
拒否理由・hash の作り方は `ContentLoader.loadData` を共有し、経路が分かれても
同じファイルが種別によって違う扱いを受けないようにした。

**PDF として開けないデータは `RejectReason.damagedDocument` で拒否する。**
読み込み自体は成功しているため、これを見ないと `rejectReason` が nil のまま
`PDFView` が黙って空白を出す（バナーも出ない）。判定は `PDFDataProbe` に置き、
表示側が `PDFDocument` を作る条件と 1 つの事実を共有する。

## Consequences

- **PDF ではジャンプができなくなる。** `<iframe>` の頃も viewer の検索・ジャンプは
  PDF の中身に届いておらず、`canFind` / `canJump` が true のまま何も起きない状態
  だった。これは ADR 0002 が排した「押せるのに反応が無い」形なので、両方に
  `!isBinaryContent` を足して塞いだ（画像でも同じく dead だった穴が同時に閉じる）。

  **このうち検索は TASK-570 で開いた。** PDFKit の `beginFindString` で実体を入れ、
  可否は `!isBinaryContent` ではなく `FileType.supportsFind`（画像 false / PDF true）
  で決めるようにした。読み込み方法で判定したままだと、PDF を開けた瞬間に画像まで
  一緒に開いてしまうため。ジャンプは見出し構造の抽出という別の問題を含むので
  塞いだままで、`canJump` は `!isBinaryContent` のまま。
- **キーボードスクロールの 6 件（Space / Shift+Space / j / k / Shift+↓ / Shift+↑）が
  PDF では効かない。** これらは `viewer-src/keyboard.ts` にしか入口が無い。
  Help の一覧（`ViewerShortcutCatalog`）は種別非依存なので、PDF では説明と
  実態が食い違う。`PDFView` が標準で処理するキーの実測と合わせて別タスクで扱う。
- **描画の速さについて、言えることと言えないこと。** 231 ページの PDF で最初の
  1 フレームまでを測ると PDFKit 7〜8ms・WebKit 内蔵プラグイン 49〜122ms だった
  （2026-08-30）。ただしこの比較は厳密ではない——WebKit 側は `takeSnapshot`
  （プロセス間通信を含む）、PDFKit 側は `cacheDisplay`（直接描画）で測り方が違う。
  **「WebKit は GPU 合成で速い」は検証していない。** macOS の WebKit が PDF 表示に
  内部で PDFKit を使う構成（`PDFPlugin` が `PDFLayerController` を使う）は一般に
  知られているが、ここでは確かめていない。もしそうなら違いは「WebKit 対 PDFKit」では
  なく「レイヤベースの描画経路 対 `PDFView` の `drawRect` 描画」である。描画経路が
  遅さの本体だと分かった場合は、`PDFPage.draw` で自前にタイルレイヤーへ描く案が
  残っている（規模は大きい）。判断は実測が出てから行う（TASK-569）。
- **ページ単位のスクロールは後に撤回した。** 当初は `.singlePage` にして
  ホイールをページ送りへ振り替えていた（TASK-564.2）。「2 ページの端が同時に
  見える位置で止まらない」ことを構造で守れるのが理由だったが、その代償として
  スクロールでページが瞬時に切り替わり、滑らかに読めなかった。体感を優先して
  この不変条件を捨て、`.singlePageContinuous` へ改めた（TASK-567）。スナップや
  遷移アニメーションのような代わりの仕掛けは足していない。連続スクロールでは
  `scaleFactorForSizeToFit` が幅基準になるため、`autoScales` に任せると倍率 1.0 が
  「ページの幅が収まる」に変わってしまう（`scaleFactorForSizeToFit` を override しても
  自動追従はその値を読まない / 実測）。倍率 1.0 の意味を「ページ全体が収まる」の
  ままにするため、`autoScales` を使わず `ZoomingPDFView` が倍率を覚えて
  `layout` で入れ直す。
- **ピンチは自前で受ける。** `PDFView` の内側の `PDFScrollView` は
  `allowsMagnification` が既定で true で、ピンチを消費して `PDFView` の
  サブクラスへ渡さない。その状態では `autoScales` がフィットへ戻すため、
  拡大は一瞬効くだけ、縮小は無視される。`ZoomingPDFView` がレイアウトのたびに
  この設定を切り、倍率の入口を `applyZoom` へ一本化している（TASK-568）。
- **ズームの意味を面ごとに合わせる必要がある。** `PDFView.scaleFactor` は絶対倍率
  なので、倍率 1.0 が「ページ幅がビューに収まる状態」になるよう
  `scaleFactorForSizeToFit` を基準に掛け直している。これをしないと、同じ 1.0 が
  WebView 側では等倍・PDF 側ではページの一部という別の意味になる。
- **QuickLook 拡張は影響を受けない。** `FileType.quickLookSupportedExtensions` が
  `isBinaryContent` を除くため、PDF はもともと対象外
  （`QuickLookInfoPlistTests` が担保）。
- viewer 側からは `_renderPdf` / `_createPdfBlobHolder` / `_mmdPdfBlob` /
  `shape === 'pdf'` 分岐 / `pdf-body` の CSS / `zoom.ts` の特例 /
  `encoding.ts` の `base64ToBytes` / CSP の `frame-src blob:` が消えた。
  復活していないことは `ViewerBridgeContractTests` が走査で固定する。
